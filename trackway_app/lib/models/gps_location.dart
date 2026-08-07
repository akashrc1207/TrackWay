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
    return GpsLocation(
      latitude: (json["latitude"] as num? ?? 0.0).toDouble(),
      longitude: (json["longitude"] as num? ?? 0.0).toDouble(),
      speed: (json["speed"] as num? ?? 0.0).toDouble(),
      bearing: (json["bearing"] as num? ?? 0.0).toDouble(),
      timestamp: (json["timestamp"] as String?) ?? "",
      snappedLatitude: (json["snapped_latitude"] as num?)?.toDouble(),
      snappedLongitude: (json["snapped_longitude"] as num?)?.toDouble(),
      activeJourney: (json["active_journey"] as bool?) ?? false,
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
