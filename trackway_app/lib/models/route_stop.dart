class RouteStop {
  final int id;
  final String stopName;
  final double latitude;
  final double longitude;

  RouteStop({
    required this.id,
    required this.stopName,
    required this.latitude,
    required this.longitude,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      id: json["id"],
      stopName: json["stop_name"],
      latitude: json["latitude"].toDouble(),
      longitude: json["longitude"].toDouble(),
    );
  }
}
