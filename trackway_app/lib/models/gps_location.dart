import '../config/app_config.dart';

class GpsLocation {
  final double latitude;
  final double longitude;
  final double speed;
  final double bearing;
  final String timestamp;
  final double? snappedLatitude;
  final double? snappedLongitude;
  final bool activeJourney;
  final int? journeyId;
  final String status;

  GpsLocation({
    required this.latitude,
    required this.longitude,
    required this.speed,
    this.bearing = 0.0,
    required this.timestamp,
    this.snappedLatitude,
    this.snappedLongitude,
    this.activeJourney = true,
    this.journeyId,
    this.status = "live",
  });

  factory GpsLocation.fromJson(Map<String, dynamic> json) {
    // If the backend explicitly sends active_journey, use it directly (new backend format).
    // If absent (old cloud backend), infer from GPS timestamp freshness:
    //   - GPS < 10 minutes old  → bus is actively broadcasting → treat as ACTIVE
    //   - GPS ≥ 10 minutes old  → driver stopped broadcasting → treat as INACTIVE
    // The driver GPS broadcast service uploads every 2-3 seconds while running.
    // A 10-minute-stale GPS means the bus definitely stopped its journey.
    final bool? explicitActiveJourney = json["active_journey"] as bool?;
    final bool activeJourney;
    if (explicitActiveJourney != null) {
      activeJourney = explicitActiveJourney;
    } else {
      final ts = (json["timestamp"] as String?) ?? "";
      bool inferred = false; // mutable local to avoid final-in-try-catch error
      if (ts.isNotEmpty) {
        try {
          final dt = DateTime.parse(ts).toUtc();
          final elapsedSec = DateTime.now().toUtc().difference(dt).inSeconds;
          // If GPS is within the "lost" threshold (default 45s), the driver's broadcast
          // service is still (or was just recently) running — treat as ACTIVE.
          // When the driver stops a journey, stopBroadcast() cancels the GPS upload timer
          // immediately. After signalLostThresholdSec seconds with no new upload, this
          // correctly transitions the passenger screen to INACTIVE.
          inferred = elapsedSec <= AppConfig.signalLostThresholdSec;
        } catch (_) {
          inferred = false;
        }
      }
      activeJourney = inferred;
    }

    return GpsLocation(
      latitude: (json["latitude"] as num? ?? 0.0).toDouble(),
      longitude: (json["longitude"] as num? ?? 0.0).toDouble(),
      speed: (json["speed"] as num? ?? 0.0).toDouble(),
      bearing: (json["bearing"] as num? ?? 0.0).toDouble(),
      timestamp: (json["timestamp"] as String?) ?? "",
      snappedLatitude: (json["snapped_latitude"] as num?)?.toDouble(),
      snappedLongitude: (json["snapped_longitude"] as num?)?.toDouble(),
      activeJourney: activeJourney,
      journeyId: (json["journey_id"] as num?)?.toInt(),
      status: (json["status"] as String?) ?? "live",
    );
  }

  String get signalStatus {
    if (timestamp.isEmpty) return "lost";
    try {
      final dt = DateTime.parse(timestamp).toUtc();
      final elapsed = DateTime.now().toUtc().difference(dt).inSeconds;
      if (elapsed <= AppConfig.signalStaleThresholdSec) return "live";
      if (elapsed <= AppConfig.signalLostThresholdSec) return "stale";
      return "lost";
    } catch (_) {
      return "live";
    }
  }
}
