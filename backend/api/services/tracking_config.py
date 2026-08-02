"""
Centralized Backend Configuration Constants for TrackWay GPS Engine & ETA Pipeline
"""

# Maximum allowable GPS accuracy in meters (worse accuracy rejected)
MAX_GPS_ACCURACY_METERS = 50.0

# Maximum physical speed limit for bus in km/h
MAX_SPEED_KMH = 130.0

# Maximum position jump allowed within 3 seconds (in meters)
MAX_JUMP_METERS_3SEC = 200.0

# Signal status thresholds (in seconds)
SIGNAL_STALE_SEC = 15
SIGNAL_LOST_SEC = 45

# Exponential Moving Average (EMA) alpha factor for ETA smoothing (0.0 < alpha <= 1.0)
EMA_ALPHA = 0.35

# Cache timeout for smoothed ETA store (seconds)
ETA_CACHE_TIMEOUT_SEC = 3600
