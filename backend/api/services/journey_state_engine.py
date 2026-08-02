import os
import json
import time
import math
import logging
from typing import Dict, Any, List, Tuple, Optional
from datetime import datetime, timedelta
from django.core.cache import cache

from .eta_service import haversine_distance, ROUTE_STOPS, closest_stop_id
from .bearing_calculator import calculate_bearing
from .tracking_config import (
    EMA_ALPHA,
    ETA_CACHE_TIMEOUT_SEC,
    SIGNAL_STALE_SEC,
    SIGNAL_LOST_SEC,
)

logger = logging.getLogger("trackway.journey_state")

_ROAD_POLYLINE_CACHE: Optional[List[Dict[str, float]]] = None
_STOP_SEGMENT_INDEX_CACHE: Optional[Dict[int, int]] = None


def load_road_polyline() -> List[Dict[str, float]]:
    global _ROAD_POLYLINE_CACHE
    if _ROAD_POLYLINE_CACHE is not None:
        return _ROAD_POLYLINE_CACHE

    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    poly_path = os.path.join(base_dir, "ml_models", "road_polyline.json")
    if os.path.exists(poly_path):
        try:
            with open(poly_path, "r") as f:
                _ROAD_POLYLINE_CACHE = json.load(f)
                return _ROAD_POLYLINE_CACHE
        except Exception as e:
            logger.error(f"Error loading road_polyline.json: {e}")

    # Fallback to ROUTE_STOPS coordinates
    _ROAD_POLYLINE_CACHE = [{"latitude": s[2], "longitude": s[3]} for s in ROUTE_STOPS]
    return _ROAD_POLYLINE_CACHE


def map_stops_to_polyline_segments(polyline: List[Dict[str, float]]) -> Dict[int, int]:
    """Map each stop_order (1..38) to its nearest polyline segment index."""
    global _STOP_SEGMENT_INDEX_CACHE
    if _STOP_SEGMENT_INDEX_CACHE is not None:
        return _STOP_SEGMENT_INDEX_CACHE

    mapping = {}
    for seq, name, slat, slon in ROUTE_STOPS:
        min_d = float("inf")
        best_seg = 0
        for i, p in enumerate(polyline):
            d = haversine_distance(slat, slon, p["latitude"], p["longitude"])
            if d < min_d:
                min_d = d
                best_seg = i
        mapping[seq] = best_seg

    _STOP_SEGMENT_INDEX_CACHE = mapping
    return mapping


def snap_point_to_polyline(
    lat: float, lng: float, polyline: List[Dict[str, float]]
) -> Tuple[float, float, int, float]:
    """
    Project (lat, lng) onto the nearest line segment of polyline.
    Returns: (snapped_lat, snapped_lng, segment_index, min_dist_meters)
    """
    if not polyline:
        return lat, lng, 0, 0.0

    min_dist_m = float("inf")
    best_lat, best_lng = lat, lng
    best_seg_idx = 0

    for i in range(len(polyline) - 1):
        p1 = polyline[i]
        p2 = polyline[i + 1]

        x1, y1 = p1["latitude"], p1["longitude"]
        x2, y2 = p2["latitude"], p2["longitude"]

        dx = x2 - x1
        dy = y2 - y1

        if dx == 0 and dy == 0:
            d = haversine_distance(lat, lng, x1, y1) * 1000.0
            if d < min_dist_m:
                min_dist_m = d
                best_lat, best_lng = x1, y1
                best_seg_idx = i
            continue

        t = ((lat - x1) * dx + (lng - y1) * dy) / (dx * dx + dy * dy)
        t = max(0.0, min(1.0, t))

        proj_lat = x1 + t * dx
        proj_lng = y1 + t * dy

        dist_m = haversine_distance(lat, lng, proj_lat, proj_lng) * 1000.0
        if dist_m < min_dist_m:
            min_dist_m = dist_m
            best_lat, best_lng = proj_lat, proj_lng
            best_seg_idx = i

    if min_dist_m <= 75.0:
        return round(best_lat, 6), round(best_lng, 6), best_seg_idx, round(min_dist_m, 1)

    return lat, lng, best_seg_idx, round(min_dist_m, 1)


class SynchronizedJourneyEngine:
    """
    Single Source of Truth Journey Engine.
    Handles polyline map snapping, direction locking with hysteresis,
    stop status lifecycle (departed -> arriving -> upcoming),
    and automatic terminus direction switching.
    """

    TERMINUS_ARRIVAL_RADIUS_METERS = 250.0
    TERMINUS_DWELL_SECONDS = 8.0

    @classmethod
    def check_terminus_switch(
        cls,
        bus_id: int,
        current_dir: int,
        current_lat: float,
        current_lng: float,
        seg_idx: int,
        total_segs: int,
    ) -> int:
        """
        Detects when a bus arrives at the terminus stop and dwells.
        Switches direction automatically (0 -> 1 or 1 -> 0).
        """
        polyline = load_road_polyline()
        if not polyline:
            return current_dir

        # Determine active terminus coordinate
        if current_dir == 0:
            # Forward leg: Terminus is Cherupuzha (end of polyline)
            term_pt = polyline[-1]
            at_terminus_by_index = seg_idx >= (total_segs - 15)
        else:
            # Return leg: Terminus is Thaliparamba (start of polyline)
            term_pt = polyline[0]
            at_terminus_by_index = seg_idx <= 15

        dist_to_term_m = (
            haversine_distance(current_lat, current_lng, term_pt["latitude"], term_pt["longitude"])
            * 1000.0
        )

        is_near_terminus = (
            dist_to_term_m <= cls.TERMINUS_ARRIVAL_RADIUS_METERS or at_terminus_by_index
        )

        dwell_cache_key = f"trackway:terminus_dwell:bus_{bus_id}"
        dwell_state = cache.get(dwell_cache_key)

        now_ts = time.time()

        if is_near_terminus:
            if dwell_state is None:
                cache.set(
                    dwell_cache_key,
                    {"start_time": now_ts, "direction": current_dir},
                    timeout=300,
                )
            else:
                start_time = dwell_state.get("start_time", now_ts)
                dwell_sec = now_ts - start_time
                if dwell_sec >= 2.0:
                    new_dir = 1 if current_dir == 0 else 0
                    logger.info(
                        f"Bus #{bus_id} arrived at terminus. Auto-switching direction from {current_dir} to {new_dir}."
                    )
                    # Reset locked direction and clear dwell state
                    cache.set(
                        f"trackway:direction:bus_{bus_id}",
                        {"direction": new_dir, "last_seg": seg_idx, "consecutive_flips": 0},
                        timeout=ETA_CACHE_TIMEOUT_SEC,
                    )
                    cache.delete(dwell_cache_key)

                    # Clear cached ETAs for previous route
                    for seq in range(1, 40):
                        cache.delete(f"trackway:eta:bus_{bus_id}:stop_{seq}")

                    return new_dir
        else:
            if dwell_state is not None:
                # If bus was dwelling at terminus and now moved away in reverse direction, switch direction immediately
                start_time = dwell_state.get("start_time", now_ts)
                cache.delete(dwell_cache_key)
                if (now_ts - start_time) >= 1.0:
                    new_dir = 1 if current_dir == 0 else 0
                    cache.set(
                        f"trackway:direction:bus_{bus_id}",
                        {"direction": new_dir, "last_seg": seg_idx, "consecutive_flips": 0},
                        timeout=ETA_CACHE_TIMEOUT_SEC,
                    )
                    for seq in range(1, 40):
                        cache.delete(f"trackway:eta:bus_{bus_id}:stop_{seq}")
                    return new_dir

        return current_dir

    @classmethod
    def get_locked_direction(
        cls, bus_id: int, raw_direction: int, closest_seg_idx: int, total_segs: int
    ) -> int:
        """
        Direction locking with hysteresis.
        """
        cache_key = f"trackway:direction:bus_{bus_id}"
        state = cache.get(cache_key)

        if state is None:
            locked_dir = raw_direction
            cache.set(
                cache_key,
                {"direction": locked_dir, "last_seg": closest_seg_idx, "consecutive_flips": 0},
                timeout=ETA_CACHE_TIMEOUT_SEC,
            )
            return locked_dir

        prev_dir = state.get("direction", raw_direction)
        last_seg = state.get("last_seg", closest_seg_idx)

        if prev_dir == 0 and closest_seg_idx > last_seg + 2:
            locked_dir = 0
            flips = 0
        elif prev_dir == 1 and closest_seg_idx < last_seg - 2:
            locked_dir = 1
            flips = 0
        elif raw_direction != prev_dir:
            flips = state.get("consecutive_flips", 0) + 1
            if flips >= 4:
                locked_dir = raw_direction
                flips = 0
            else:
                locked_dir = prev_dir
        else:
            locked_dir = prev_dir
            flips = 0

        cache.set(
            cache_key,
            {"direction": locked_dir, "last_seg": closest_seg_idx, "consecutive_flips": flips},
            timeout=ETA_CACHE_TIMEOUT_SEC,
        )

        return locked_dir

    @classmethod
    def compute_synchronized_state(
        cls,
        bus_id: int,
        bus_name: str,
        bus_number: str,
        route_id: int,
        route_name: str,
        current_lat: float,
        current_lng: float,
        speed_kmh: float,
        timestamp: Optional[datetime],
        raw_direction: int,
        stops: List[Any],
        recent_logs: List[Any],
    ) -> Dict[str, Any]:
        """
        Builds the unified Synchronized Journey State object with explicit Stop Lifecycles.
        """
        polyline = load_road_polyline()
        total_segs = len(polyline)
        stop_seg_map = map_stops_to_polyline_segments(polyline)

        # 1. Snap location to road polyline
        snapped_lat, snapped_lng, seg_idx, snap_error_m = snap_point_to_polyline(
            current_lat, current_lng, polyline
        )

        # 2. Lock direction & check automatic terminus switch
        init_direction = cls.get_locked_direction(bus_id, raw_direction, seg_idx, total_segs)
        direction_flag = cls.check_terminus_switch(
            bus_id, init_direction, snapped_lat, snapped_lng, seg_idx, total_segs
        )

        # 3. Slice travelled vs remaining polyline & compute progress
        if direction_flag == 1:
            # Return leg: Cherupuzha -> Thaliparamba
            travelled_poly = polyline[seg_idx:]
            remaining_poly = polyline[: seg_idx + 1]
            progress_pct = round(((total_segs - seg_idx) / float(total_segs)) * 100.0, 1)
            direction_name = "Cherupuzha to Thaliparamba"
        else:
            # Forward leg: Thaliparamba -> Cherupuzha
            travelled_poly = polyline[: seg_idx + 1]
            remaining_poly = polyline[seg_idx:]
            progress_pct = round((seg_idx / float(total_segs)) * 100.0, 1)
            direction_name = "Thaliparamba to Cherupuzha"

        # 4. Calculate bearing
        bearing = 0.0
        if len(recent_logs) >= 2:
            bearing = calculate_bearing(
                recent_logs[1].latitude,
                recent_logs[1].longitude,
                recent_logs[0].latitude,
                recent_logs[0].longitude,
            )

        # 5. Stop Progression & Lifecycle Classification
        from .eta_engine import ETAEngine

        ordered_stops = list(stops)
        if direction_flag == 1:
            ordered_stops.sort(key=lambda s: s.stop_order, reverse=True)
        else:
            ordered_stops.sort(key=lambda s: s.stop_order)

        eta_results = []
        next_stop_info = None

        # Find closest stop_order for current snapped position
        closest_stop, _ = closest_stop_id(snapped_lat, snapped_lng)

        for stop in ordered_stops:
            s_order = stop.stop_order
            s_seg = stop_seg_map.get(s_order, 0)
            dist_to_stop_m = (
                haversine_distance(snapped_lat, snapped_lng, stop.latitude, stop.longitude)
                * 1000.0
            )

            # Dynamic stop status along direction of travel
            is_departed = False
            if direction_flag == 0:
                # Forward leg (Thaliparamba -> Cherupuzha):
                if s_order < (closest_stop - 1):
                    is_departed = True
                elif s_order == (closest_stop - 1):
                    is_departed = dist_to_stop_m > 200.0 or seg_idx > s_seg
                elif s_order == closest_stop:
                    is_departed = seg_idx > (s_seg + 2) and dist_to_stop_m > 200.0
            else:
                # Return leg (Cherupuzha -> Thaliparamba):
                if s_order > (closest_stop + 1):
                    is_departed = True
                elif s_order == (closest_stop + 1):
                    is_departed = dist_to_stop_m > 200.0 or seg_idx < s_seg
                elif s_order == closest_stop:
                    is_departed = seg_idx < (s_seg - 2) and dist_to_stop_m > 200.0

            if is_departed:
                status_str = "departed"
                eta_text_str = "Departed"
                eta_min = 0.0
                raw_min = 0.0
                dist_km = 0.0
                prediction_engine = "Journey Engine"
                confidence = 1.0
            elif dist_to_stop_m <= 150.0:
                status_str = "arriving"
                eta_text_str = "At Stop"
                eta_min = 0.0
                raw_min = 0.0
                dist_km = round(dist_to_stop_m / 1000.0, 2)
                prediction_engine = "Journey Engine"
                confidence = 0.98
            else:
                status_str = "upcoming"
                eta_info = ETAEngine.compute_stop_eta(
                    bus_id=bus_id,
                    current_lat=snapped_lat,
                    current_lng=snapped_lng,
                    current_speed_kmh=speed_kmh,
                    target_lat=stop.latitude,
                    target_lng=stop.longitude,
                    target_stop_order=stop.stop_order,
                    direction_flag=direction_flag,
                    last_log_time=timestamp,
                )
                eta_min = eta_info["eta_minutes"]
                raw_min = eta_info["raw_eta_minutes"]
                # Guarantee clean positive ETA text for upcoming stops
                if eta_info["eta_text"] in ("Passed", "Departed"):
                    eta_text_str = "< 1 min"
                    eta_min = 0.5
                else:
                    eta_text_str = eta_info["eta_text"]

                dist_km = eta_info["distance_km"]
                prediction_engine = eta_info["prediction_engine"]
                confidence = eta_info["confidence"]

            # Calculate clock time of arrival
            if is_departed:
                arrival_time_str = "Passed"
            elif status_str == "arriving":
                arrival_time_str = "Now"
            else:
                arrival_dt = datetime.now() + timedelta(minutes=eta_min)
                arrival_time_str = arrival_dt.strftime("%I:%M %p").lstrip("0")

            stop_dict = {
                "stop_id": stop.id,
                "stop_name": stop.stop_name,
                "stop_order": stop.stop_order,
                "latitude": stop.latitude,
                "longitude": stop.longitude,
                "status": status_str,
                "distance_km": dist_km,
                "eta_minutes": eta_min,
                "raw_eta_minutes": raw_min,
                "eta_text": eta_text_str,
                "arrival_time": arrival_time_str,
                "speed_kmh": round(speed_kmh, 1),
                "prediction_engine": prediction_engine,
                "confidence": confidence,
                "signal_status": ETAEngine.get_signal_status(timestamp),
                "is_ml": True,
            }
            eta_results.append(stop_dict)

            if next_stop_info is None and status_str in ("arriving", "upcoming"):
                next_stop_info = stop_dict

        signal_status = ETAEngine.get_signal_status(timestamp)

        return {
            "bus_id": bus_id,
            "bus_name": bus_name,
            "bus_number": bus_number,
            "route_id": route_id,
            "route_name": route_name,
            "direction_flag": direction_flag,
            "direction_name": direction_name,
            "signal_status": signal_status,
            "journey_progress_percent": progress_pct,
            "current_segment_index": seg_idx,
            "snap_error_meters": snap_error_m,
            "latest_position": {
                "latitude": snapped_lat,
                "longitude": snapped_lng,
                "raw_latitude": current_lat,
                "raw_longitude": current_lng,
                "speed": speed_kmh,
                "bearing": bearing,
                "timestamp": timestamp,
            },
            "next_stop": next_stop_info,
            "travelled_polyline": travelled_poly,
            "remaining_polyline": remaining_poly,
            "stops_eta": eta_results,
        }
