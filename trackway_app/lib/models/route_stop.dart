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
      id: (json["id"] as int?) ?? 0,
      stopName: (json["stop_name"] as String?) ?? "",
      latitude: (json["latitude"] as num? ?? 0).toDouble(),
      longitude: (json["longitude"] as num? ?? 0).toDouble(),
    );
  }
}
