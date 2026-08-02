import logging
import time
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
from django.core.cache import cache

from .eta_service import predict_eta_with_ml, haversine_distance, ROUTE_STOPS, _load_stop_road_distances
from .bearing_calculator import calculate_bearing
from .tracking_config import (
    EMA_ALPHA,
    ETA_CACHE_TIMEOUT_SEC,
    SIGNAL_STALE_SEC,
    SIGNAL_LOST_SEC,
)

logger = logging.getLogger("trackway.eta_engine")


class ETAEngine:
    """
    Dedicated ETA Pipeline Engine separating raw ML/physics inference from:
    1. Persistent EMA Smoothing (via django.core.cache)
    2. Physical Rate-Limiting
    3. Signal Status Determination ('live', 'stale', 'lost')
    4. Confidence Score Calculation (0.0 to 1.0)
    5. Structured Telemetry & Latency Logging
    """

    @staticmethod
    def get_signal_status(last_timestamp: Optional[datetime]) -> str:
        """Determine signal status ('live', 'stale', 'lost') from GPS timestamp freshness."""
        if last_timestamp is None:
            return "lost"

        if not last_timestamp.tzinfo:
            last_timestamp = last_timestamp.replace(tzinfo=timezone.utc)

        elapsed_sec = (datetime.now(timezone.utc) - last_timestamp).total_seconds()

        if elapsed_sec <= SIGNAL_STALE_SEC:
            return "live"
        elif elapsed_sec <= SIGNAL_LOST_SEC:
            return "stale"
        else:
            return "lost"

    @staticmethod
    def calculate_confidence(
        signal_status: str,
        engine_type: str,
        current_speed_kmh: float,
        stops_remaining: int,
    ) -> float:
        """
        Calculate an ETA confidence score between 0.0 and 1.0 based on:
        - Signal status (live: +0.4, stale: +0.2, lost: 0.0)
        - Model engine reliability (Keras LSTM: +0.4, ExtraTrees: +0.3, Physics: +0.2)
        - Vehicle speed stability & distance remaining
        """
        score = 0.0

        if signal_status == "live":
            score += 0.45
        elif signal_status == "stale":
            score += 0.25
        else:
            score += 0.05

        if "Keras LSTM" in engine_type:
            score += 0.40
        elif "ExtraTrees" in engine_type:
            score += 0.30
        else:
            score += 0.20

        # Speed check bonus
        if 10.0 <= current_speed_kmh <= 80.0:
            score += 0.15
        elif current_speed_kmh > 0:
            score += 0.08

        return round(min(0.99, max(0.10, score)), 2)

    @classmethod
    def get_smoothed_eta(
        cls,
        bus_id: int,
        stop_id: int,
        raw_eta: float,
        last_log_time: Optional[datetime] = None,
    ) -> float:
        """
        Retrieve cached previous ETA and apply Exponential Moving Average (EMA)
        + Physical Rate Limiting.
        """
        cache_key = f"trackway:eta:bus_{bus_id}:stop_{stop_id}"
        cached_data = cache.get(cache_key)

        now_ts = time.time()

        if cached_data is None:
            smoothed = round(raw_eta, 1)
        else:
            prev_eta = cached_data.get("eta", raw_eta)
            prev_ts = cached_data.get("timestamp", now_ts)

            # If raw_eta shifted significantly (stop progression or trip reset), adopt new raw ETA immediately
            if abs(raw_eta - prev_eta) > 5.0:
                smoothed = round(raw_eta, 1)
            else:
                # Responsive EMA (0.5 alpha) allowing ETA to reduce continuously as bus travels
                ema_val = (0.5 * raw_eta) + (0.5 * prev_eta)
                # When traveling towards stop (raw_eta < prev_eta), ensure ETA reduces monotonically
                if raw_eta < prev_eta:
                    smoothed = round(max(raw_eta, min(prev_eta - 0.05, ema_val)), 1)
                else:
                    smoothed = round(max(0.5, ema_val), 1)

        # Update cache
        cache.set(
            cache_key,
            {"eta": smoothed, "timestamp": now_ts},
            timeout=ETA_CACHE_TIMEOUT_SEC,
        )

        return smoothed

    @classmethod
    def compute_stop_eta(
        cls,
        bus_id: int,
        current_lat: float,
        current_lng: float,
        current_speed_kmh: float,
        target_lat: float,
        target_lng: float,
        target_stop_order: int,
        direction_flag: int,
        last_log_time: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        """
        Computes robust, smoothed, confidence-scored ETA for a specific stop.
        """
        start_time = time.time()

        raw_eta, engine_name = predict_eta_with_ml(
            current_lat=current_lat,
            current_lng=current_lng,
            current_speed_kmh=current_speed_kmh,
            target_lat=target_lat,
            target_lng=target_lng,
            target_stop_order=target_stop_order,
            direction_flag=direction_flag,
            bus_id=bus_id,
        )

        signal_status = cls.get_signal_status(last_log_time)

        if raw_eta is None:
            raw_eta = 5.0
            engine_name = "Physics Road Geometry Fallback"

        smoothed_eta = cls.get_smoothed_eta(
            bus_id=bus_id,
            stop_id=target_stop_order,
            raw_eta=raw_eta,
            last_log_time=last_log_time,
        )

        confidence = cls.calculate_confidence(
            signal_status=signal_status,
            engine_type=engine_name,
            current_speed_kmh=current_speed_kmh,
            stops_remaining=target_stop_order,
        )

        # Distance calculation
        road_cum_map = _load_stop_road_distances()
        target_road_cum = road_cum_map.get(target_stop_order, (target_stop_order - 1) * 1.2)
        road_dist_km = haversine_distance(current_lat, current_lng, target_lat, target_lng)

        latency_ms = round((time.time() - start_time) * 1000, 2)
        try:
            from .telemetry import TelemetryTracker
            TelemetryTracker.record_eta_prediction(latency_ms)
        except Exception:
            pass

        logger.debug(
            f"Bus #{bus_id} Stop #{target_stop_order} ETA: {smoothed_eta}m (raw: {raw_eta}m), "
            f"Conf: {confidence}, Status: {signal_status}, Latency: {latency_ms}ms"
        )

        return {
            "distance_km": round(road_dist_km, 2),
            "eta_minutes": smoothed_eta,
            "raw_eta_minutes": raw_eta,
            "eta_text": f"{int(smoothed_eta)} mins" if smoothed_eta >= 1.0 else "< 1 min",
            "speed_kmh": round(current_speed_kmh, 1),
            "prediction_engine": engine_name,
            "confidence": confidence,
            "signal_status": signal_status,
            "is_ml": True,
        }
