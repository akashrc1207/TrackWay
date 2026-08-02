import time
import logging
from typing import Dict, Any
from django.core.cache import cache

logger = logging.getLogger("trackway.telemetry")

CACHE_PREFIX = "trackway:metrics"
METRICS_CACHE_TIMEOUT = 86400  # 24 hours persistence


class TelemetryTracker:
    """
    Production-Grade Telemetry & Structured Monitoring Tracker.
    Tracks GPS packet stats, rejection counts, ETA prediction latency,
    API request latency, and active journey metrics in persistent Django cache.
    """

    @classmethod
    def _increment(cls, key: str, amount: int = 1):
        cache_key = f"{CACHE_PREFIX}:{key}"
        try:
            val = cache.get(cache_key, 0)
            cache.set(cache_key, val + amount, timeout=METRICS_CACHE_TIMEOUT)
        except Exception as e:
            logger.error(f"Telemetry increment error for {key}: {e}")

    @classmethod
    def _get(cls, key: str, default: int = 0) -> int:
        return cache.get(f"{CACHE_PREFIX}:{key}", default)

    @classmethod
    def record_gps_received(cls):
        cls._increment("gps_packets_received")

    @classmethod
    def record_gps_rejected(cls, reason: str = "unknown"):
        cls._increment("gps_packets_rejected")
        cls._increment(f"gps_rejection_reason:{reason}")

    @classmethod
    def record_eta_prediction(cls, latency_ms: float):
        cls._increment("eta_predictions_count")
        cache_key = f"{CACHE_PREFIX}:eta_total_latency_ms"
        total_lat = cache.get(cache_key, 0.0)
        cache.set(cache_key, total_lat + latency_ms, timeout=METRICS_CACHE_TIMEOUT)

    @classmethod
    def record_api_request(cls, endpoint: str, latency_ms: float, status_code: int):
        cls._increment("api_requests_total")
        if status_code >= 400:
            cls._increment("api_errors_total")

        cache_key = f"{CACHE_PREFIX}:api_total_latency_ms"
        total_lat = cache.get(cache_key, 0.0)
        cache.set(cache_key, total_lat + latency_ms, timeout=METRICS_CACHE_TIMEOUT)

    @classmethod
    def get_metrics_summary(cls, active_journeys_count: int = 0, active_buses_count: int = 0) -> Dict[str, Any]:
        received = cls._get("gps_packets_received")
        rejected = cls._get("gps_packets_rejected")
        eta_count = cls._get("eta_predictions_count")
        eta_total_lat = cache.get(f"{CACHE_PREFIX}:eta_total_latency_ms", 0.0)

        api_count = cls._get("api_requests_total")
        api_errors = cls._get("api_errors_total")
        api_total_lat = cache.get(f"{CACHE_PREFIX}:api_total_latency_ms", 0.0)

        avg_eta_latency = round(eta_total_lat / eta_count, 2) if eta_count > 0 else 0.0
        avg_api_latency = round(api_total_lat / api_count, 2) if api_count > 0 else 0.0
        rejection_rate = round((rejected / received * 100.0), 2) if received > 0 else 0.0

        return {
            "status": "healthy",
            "telemetry": {
                "active_journeys": active_journeys_count,
                "active_buses": active_buses_count,
                "gps_packets": {
                    "received": received,
                    "rejected": rejected,
                    "rejection_rate_percent": rejection_rate,
                    "reasons": {
                        "accuracy_low": cls._get("gps_rejection_reason:accuracy_low"),
                        "implied_speed_impossible": cls._get("gps_rejection_reason:implied_speed_impossible"),
                        "jump_impossible": cls._get("gps_rejection_reason:jump_impossible"),
                    },
                },
                "eta_engine": {
                    "predictions_count": eta_count,
                    "avg_prediction_latency_ms": avg_eta_latency,
                },
                "api_performance": {
                    "total_requests": api_count,
                    "total_errors": api_errors,
                    "avg_response_time_ms": avg_api_latency,
                },
            },
        }
