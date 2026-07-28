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
      latitude: double.parse(json["latitude"].toString()),
      longitude: double.parse(json["longitude"].toString()),
      speed: double.parse(json["speed"].toString()),
      timestamp: json["timestamp"],
    );
  }
}
