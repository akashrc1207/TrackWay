import math
from typing import Dict, Any

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great circle distance in kilometers between two points 
    on the earth specified in decimal degrees.
    """
    R = 6371.0  # Earth radius in kilometers

    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    a = (math.sin(dlat / 2.0) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         (math.sin(dlon / 2.0) ** 2))
    
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    distance = R * c
    return distance

def predict_eta_with_ml(bus_id: int, stop_id: int, current_lat: float, current_lng: float, speed_kmh: float) -> Dict[str, Any]:
    """
    Placeholder service function for ML Model Integration.
    Your friend can plug their trained ML model (e.g. PyTorch, Scikit-Learn, or ONNX) here.
    """
    return None

def calculate_eta(current_lat: float, current_lng: float, current_speed_kmh: float, target_lat: float, target_lng: float) -> Dict[str, Any]:
    """
    Calculates ETA and distance to a target bus stop.
    Uses current bus speed with a reasonable fallback average speed (e.g. 25-30 km/h in urban areas).
    """
    distance_km = haversine_distance(current_lat, current_lng, target_lat, target_lng)
    
    # Effective speed (if bus is stopped or speed is very low, use 25 km/h urban average speed)
    effective_speed = current_speed_kmh if current_speed_kmh > 5.0 else 25.0
    
    # Time in hours -> convert to minutes
    eta_minutes = (distance_km / effective_speed) * 60.0

    # Add 1 minute dwell time per stop buffer if distance > 0.5km
    if distance_km > 0.5:
        eta_minutes += 1.5

    eta_minutes_rounded = round(max(1.0, eta_minutes), 1)

    return {
        "distance_km": round(distance_km, 2),
        "eta_minutes": eta_minutes_rounded,
        "eta_text": f"{int(eta_minutes_rounded)} mins" if eta_minutes_rounded >= 1 else "< 1 min",
        "speed_kmh": round(effective_speed, 1),
    }
