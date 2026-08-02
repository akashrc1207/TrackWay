import '../config/app_config.dart';

class GpsLocation {
  final double latitude;
  final double longitude;
  final double speed;
  final double bearing;
  final String timestamp;

  GpsLocation({
    required this.latitude,
    required this.longitude,
    required this.speed,
    this.bearing = 0.0,
    required this.timestamp,
  });

  factory GpsLocation.fromJson(Map<String, dynamic> json) {
    return GpsLocation(
      latitude: (json["latitude"] as num? ?? 0.0).toDouble(),
      longitude: (json["longitude"] as num? ?? 0.0).toDouble(),
      speed: (json["speed"] as num? ?? 0.0).toDouble(),
      bearing: (json["bearing"] as num? ?? 0.0).toDouble(),
      timestamp: (json["timestamp"] as String?) ?? "",
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
