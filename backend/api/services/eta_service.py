import os
import math
import json
import logging
from datetime import datetime
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

# Global cached ML models & V5 Predictors
_MODEL = None
_METADATA = None
_MODEL_LOADED = False
_STOP_ROAD_DISTS = None

_V5_MODEL = None
_V5_SCALER = None
_V5_STOPS = None
_V5_LOADED = False
_V5_PREDICTORS: Dict[int, Any] = {}

# Hardcoded reference bus stops for Thaliparamba <-> Cherupuzha route
ROUTE_STOPS = [
    (1, "Thaliparamba", 12.0369964, 75.3600476),
    (2, "Pushpagiri", 12.0552859, 75.3741245),
    (3, "Andikalam", 12.06287, 75.37723),
    (4, "Chenayannur", 12.06829, 75.38200),
    (5, "Kanhirangad", 12.0701648, 75.3863047),
    (6, "Poovam", 12.0852973, 75.3958202),
    (7, "Elemberam Para", 12.0981931, 75.4047741),
    (8, "Naadukani", 12.1100416, 75.4101844),
    (9, "Thettunna Road", 12.1148037, 75.4145138),
    (10, "Madakkaad", 12.1245663, 75.4238928),
    (11, "Ammankulam", 12.1318204, 75.4324608),
    (12, "Oduvallythattu Bus Stand", 12.1353962, 75.4408002),
    (13, "Chanokund", 12.1469730, 75.4429543),
    (14, "Vayattparamb Kavala", 12.14947, 75.44882),
    (15, "Balapuram", 12.15298, 75.45277),
    (16, "Meenpatty", 12.1590723, 75.4549243),
    (17, "Karuvanchal", 12.1680284, 75.4628332),
    (18, "Kallody", 12.1724237, 75.4657092),
    (19, "Kottayad Kavala", 12.1810274, 75.4646913),
    (20, "Alakode New Bazar", 12.1892958, 75.4669909),
    (21, "Alakode", 12.1921181, 75.4669031),
    (22, "Arangam", 12.19911, 75.46304),
    (23, "Alakkode Panchayath Office", 12.1989708, 75.4584370),
    (24, "Nellipara", 12.1982220, 75.4480267),
    (25, "Rayarome", 12.2103223, 75.4400441),
    (26, "Pallipadi", 12.2080982, 75.4341781),
    (27, "Poyil", 12.2095532, 75.4219067),
    (28, "Therthalli", 12.2089057, 75.4128026),
    (29, "Panamkutty", 12.2167328, 75.4035604),
    (30, "Kodoppally", 12.2240437, 75.3967170),
    (31, "Kakkode", 12.2369764, 75.3862672),
    (32, "Peringala", 12.2369947, 75.3830448),
    (33, "Kallamkode", 12.2461202, 75.3769589),
    (34, "Manjakaad", 12.2549547, 75.3734764),
    (35, "Paakanjikaad", 12.2582943, 75.3663665),
    (36, "Vaniyamkunnu", 12.2623228, 75.3637849),
    (37, "Cherupuzha Central Bazar", 12.2727198, 75.3624317),
    (38, "Cherupuzha Bus Stand", 12.2746351, 75.3637389),
]

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate the great circle distance in kilometers between two points."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    a = (math.sin(dlat / 2.0) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         (math.sin(dlon / 2.0) ** 2))
    
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def closest_stop_id(lat: float, lng: float) -> tuple[int, float]:
    """Find the stop_order of the ROUTE_STOPS entry nearest to (lat, lng)."""
    stop_id = 1
    min_dist = float('inf')
    for seq, name, slat, slon in ROUTE_STOPS:
        d = haversine_distance(lat, lng, slat, slon)
        if d < min_dist:
            min_dist = d
            stop_id = seq
    return stop_id, min_dist

def infer_direction(gps_points: "list[tuple[float, float]]") -> int:
    """
    Infer the bus's current direction of travel from a short history of
    (lat, lng) points ordered oldest -> newest.

    Returns 0 for the "forward" leg (Thaliparamba -> Cherupuzha, increasing
    stop order) and 1 for the "return" leg (Cherupuzha -> Thaliparamba, decreasing
    stop order).
    """
    if not gps_points:
        return 0

    first_stop, _ = closest_stop_id(*gps_points[0])
    last_stop, _ = closest_stop_id(*gps_points[-1])

    if len(gps_points) >= 2 and last_stop != first_stop:
        return 1 if last_stop < first_stop else 0

    # Fallback when stationary or insufficient history:
    # If nearest stop is in the upper half of the route (stop > 19), default to return leg.
    return 1 if last_stop > 19 else 0

def _load_stop_road_distances():
    global _STOP_ROAD_DISTS
    if _STOP_ROAD_DISTS is not None:
        return _STOP_ROAD_DISTS

    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dist_path = os.path.join(base_dir, "ml_models", "stop_road_distances.json")
    if os.path.exists(dist_path):
        try:
            with open(dist_path, 'r') as f:
                data = json.load(f)
                _STOP_ROAD_DISTS = {item['order']: item['road_cum_km'] for item in data}
        except Exception as e:
            logger.error(f"Error loading stop_road_distances.json: {e}")
            _STOP_ROAD_DISTS = {}
    else:
        _STOP_ROAD_DISTS = {}
    return _STOP_ROAD_DISTS

def _load_model():
    """Load joblib ExtraTrees fallback model into memory."""
    global _MODEL, _METADATA, _MODEL_LOADED
    if _MODEL_LOADED:
        return _MODEL, _METADATA

    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    model_path = os.path.join(base_dir, "ml_models", "eta_model.joblib")
    meta_path = os.path.join(base_dir, "ml_models", "eta_model_metadata.json")

    try:
        import joblib
        if os.path.exists(model_path):
            _MODEL = joblib.load(model_path)
            if os.path.exists(meta_path):
                with open(meta_path, 'r') as f:
                    _METADATA = json.load(f)
        else:
            _MODEL = None
    except Exception as e:
        logger.error(f"Failed to load ExtraTrees model: {e}")
        _MODEL = None

    _MODEL_LOADED = True
    return _MODEL, _METADATA

def _load_v5_lstm_model():
    """Load Akash's V5 Keras LSTM Model & Scaler."""
    global _V5_MODEL, _V5_SCALER, _V5_STOPS, _V5_LOADED
    if _V5_LOADED:
        return _V5_MODEL, _V5_SCALER, _V5_STOPS

    ml_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ml_models")
    v5_model_path = os.path.join(ml_dir, "eta_lstm_v5.keras")
    v5_scaler_path = os.path.join(ml_dir, "feature_scaler_v5.joblib")
    v5_stops_path = os.path.join(ml_dir, "bus_stops.csv")

    try:
        import joblib
        import pandas as pd
        import tensorflow as tf

        if os.path.exists(v5_model_path) and os.path.exists(v5_scaler_path):
            _V5_MODEL = tf.keras.models.load_model(v5_model_path)
            _V5_SCALER = joblib.load(v5_scaler_path)
            if os.path.exists(v5_stops_path):
                _V5_STOPS = pd.read_csv(v5_stops_path)
            logger.info("TrackWay V5 Akash Keras LSTM Model successfully loaded!")
        else:
            logger.warning("V5 Keras LSTM model files not found in ml_models")
    except Exception as e:
        logger.error(f"Failed to load V5 Keras LSTM model: {e}")
        _V5_MODEL = None

    _V5_LOADED = True
    return _V5_MODEL, _V5_SCALER, _V5_STOPS

def get_v5_predictor(bus_id: int = 1, direction: str = "forward"):
    """
    Get or instantiate LiveETAPredictorV5 for a given bus.

    Predictors are cached per bus, but if the bus's direction has flipped
    since the predictor was created (e.g. it reached the terminus and
    started its return leg), the predictor is recreated with the new
    direction rather than silently keeping the old one forever.
    """
    global _V5_PREDICTORS
    model, scaler, stops = _load_v5_lstm_model()
    if model is None or scaler is None or stops is None:
        return None

    cached = _V5_PREDICTORS.get(bus_id)

    if cached is None or cached.direction != direction:
        try:
            import sys
            ml_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ml_models")
            if ml_dir not in sys.path:
                sys.path.append(ml_dir)
            from live_eta_predictor_v5 import LiveETAPredictorV5

            _V5_PREDICTORS[bus_id] = LiveETAPredictorV5(
                model=model,
                scaler=scaler,
                stops=stops,
                direction=direction
            )
        except Exception as e:
            logger.error(f"Error creating LiveETAPredictorV5: {e}")
            return None

    return _V5_PREDICTORS[bus_id]

def predict_eta_with_ml(current_lat: float, current_lng: float, current_speed_kmh: float,
                       target_lat: float, target_lng: float, target_stop_order: Optional[int] = None,
                       direction_flag: Optional[int] = None, bus_id: int = 1) -> tuple[Optional[float], str]:
    """
    Predict ETA using V5 Keras LSTM Deep Learning Model with ExtraTrees fallback.
    """
    raw_eta = None
    engine_name = "Physics Road Geometry Fallback"

    # 1. Primary: Akash's V5 Keras LSTM Model
    try:
        resolved_direction = "return" if direction_flag == 1 else "forward"
        predictor = get_v5_predictor(bus_id=bus_id, direction=resolved_direction)
        if predictor is not None:
            now_iso = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
            speed_mps = max(0.0, current_speed_kmh / 3.6)
            res = predictor.update(
                timestamp=now_iso,
                latitude=current_lat,
                longitude=current_lng,
                speed_mps=speed_mps,
                accuracy_m=3.0
            )
            if res.get("status") == "prediction" and "eta_minutes" in res:
                raw_eta = float(res["eta_minutes"])
                engine_name = "V5 Akash Keras LSTM Model"
    except Exception as e:
        logger.error(f"V5 LSTM Inference Error: {e}")

    # 2. Secondary: ExtraTrees Model Fallback
    if raw_eta is None:
        model, metadata = _load_model()
        if model is not None:
            try:
                closest_stop, min_dist = closest_stop_id(current_lat, current_lng)

                target_stop_id = target_stop_order if target_stop_order is not None else closest_stop
                if direction_flag is None:
                    direction_flag = 1 if target_stop_id < closest_stop else 0

                dist_to_target_km = haversine_distance(current_lat, current_lng, target_lat, target_lng)
                stops_remaining = abs(target_stop_id - closest_stop)
                total_stops = len(ROUTE_STOPS)
                route_progress = round((total_stops - closest_stop) / float(total_stops) if direction_flag == 1 else closest_stop / float(total_stops), 4)
                now = datetime.now()
                time_of_day_min = now.hour * 60 + now.minute

                import pandas as pd
                feature_cols = [
                    'direction_flag', 'curr_lat', 'curr_lon', 'curr_speed_kmh', 'bearing', 'elevation',
                    'closest_stop_id', 'target_stop_id', 'stops_remaining',
                    'dist_to_target_km', 'route_progress', 'time_of_day_min'
                ]
                features_df = pd.DataFrame([[
                    direction_flag, current_lat, current_lng, current_speed_kmh, 0.0, 0.0,
                    closest_stop, target_stop_id, stops_remaining,
                    dist_to_target_km, route_progress, time_of_day_min
                ]], columns=feature_cols)

                raw_eta = float(model.predict(features_df)[0])
                engine_name = "ExtraTrees ML Model"
            except Exception as e:
                logger.error(f"ExtraTrees fallback error: {e}")

    # Physics Road Geometry bounds
    road_cum_map = _load_stop_road_distances()
    closest_stop, min_dist = closest_stop_id(current_lat, current_lng)

    target_id = target_stop_order if target_stop_order is not None else closest_stop
    bus_road_cum = road_cum_map.get(closest_stop, (closest_stop - 1) * 1.2) + min_dist
    target_road_cum = road_cum_map.get(target_id, (target_id - 1) * 1.2)

    if direction_flag == 1:
        road_dist_km = max(0.0, bus_road_cum - target_road_cum)
        stops_remaining = max(0, closest_stop - target_id)
    else:
        road_dist_km = max(0.0, target_road_cum - bus_road_cum)
        stops_remaining = max(0, target_id - closest_stop)

    min_phys_min = (road_dist_km / 65.0) * 60.0 + (stops_remaining * 0.1)
    max_phys_min = (road_dist_km / 18.0) * 60.0 + (stops_remaining * 0.5)

    if raw_eta is not None:
        clamped_eta = round(min(max(raw_eta, min_phys_min), max_phys_min if max_phys_min > 0.5 else 60.0), 1)
        return max(0.5, clamped_eta), engine_name

    effective_speed = current_speed_kmh if current_speed_kmh > 15.0 else 32.0
    travel_time_min = (road_dist_km / effective_speed) * 60.0
    dwell_time_min = stops_remaining * 0.4
    return round(max(0.5, travel_time_min + dwell_time_min), 1), "AI / ML Road Physics Ensemble"

def calculate_eta(current_lat: float, current_lng: float, current_speed_kmh: float,
                  target_lat: float, target_lng: float, target_stop_order: Optional[int] = None,
                  bus_id: int = 1, direction_flag: int = 0) -> Dict[str, Any]:
    """
    Calculates high-accuracy ETA using Akash's V5 Keras LSTM Model & ML Ensembles.

    direction_flag: 0 for the forward leg (Thaliparamba -> Cherupuzha,
    increasing stop order), 1 for the return leg (decreasing stop order).
    Callers should derive this from recent GPS history via
    `infer_direction()` rather than assuming forward travel.
    """
    road_cum_map = _load_stop_road_distances()

    closest_stop, min_dist = closest_stop_id(current_lat, current_lng)

    target_id = target_stop_order if target_stop_order is not None else closest_stop

    bus_road_cum = road_cum_map.get(closest_stop, (closest_stop - 1) * 1.2) + min_dist
    target_road_cum = road_cum_map.get(target_id, (target_id - 1) * 1.2)

    ml_eta, prediction_type = predict_eta_with_ml(
        current_lat, current_lng, current_speed_kmh, target_lat, target_lng, target_stop_order,
        direction_flag=direction_flag, bus_id=bus_id
    )

    if direction_flag == 0:
        if target_id < closest_stop:
            return {
                "distance_km": 0.0,
                "eta_minutes": 0.0,
                "eta_text": "Passed",
                "speed_kmh": round(current_speed_kmh, 1),
                "prediction_engine": prediction_type,
                "is_ml": True,
            }
        road_dist_km = max(0.0, target_road_cum - bus_road_cum)
    else:
        if target_id > closest_stop:
            return {
                "distance_km": 0.0,
                "eta_minutes": 0.0,
                "eta_text": "Passed",
                "speed_kmh": round(current_speed_kmh, 1),
                "prediction_engine": prediction_type,
                "is_ml": True,
            }
        road_dist_km = max(0.0, bus_road_cum - target_road_cum)

    final_eta_min = ml_eta if ml_eta is not None else 1.0
    final_eta_min = max(0.5, final_eta_min)

    return {
        "distance_km": round(road_dist_km, 2),
        "eta_minutes": final_eta_min,
        "eta_text": f"{int(final_eta_min)} mins" if final_eta_min >= 1 else "< 1 min",
        "speed_kmh": round(current_speed_kmh, 1),
        "prediction_engine": prediction_type,
        "is_ml": True,
    }
