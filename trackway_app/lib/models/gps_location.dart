class GpsLocation {
  final double latitude;
  final double longitude;
  final double speed;
  final String timestamp;

  GpsLocation({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.timestamp,
  });

  factory GpsLocation.fromJson(Map<String, dynamic> json) {
    return GpsLocation(
      latitude: (json["latitude"] as num? ?? 0.0).toDouble(),
      longitude: (json["longitude"] as num? ?? 0.0).toDouble(),
      speed: (json["speed"] as num? ?? 0.0).toDouble(),
      timestamp: (json["timestamp"] as String?) ?? "",
    );
  }
}
