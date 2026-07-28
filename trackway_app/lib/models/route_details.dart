import 'route_stop.dart';

class RouteDetails {
  final String routeName;
  final String startLocation;
  final String endLocation;
  final double totalDistance;
  final List<RouteStop> stops;

  RouteDetails({
    required this.routeName,
    required this.startLocation,
    required this.endLocation,
    required this.totalDistance,
    required this.stops,
  });

  factory RouteDetails.fromJson(Map<String, dynamic> json) {
    return RouteDetails(
      routeName: json["route_name"],
      startLocation: json["start_location"],
      endLocation: json["end_location"],
      totalDistance: json["total_distance"].toDouble(),
      stops: (json["stops"] as List).map((e) => RouteStop.fromJson(e)).toList(),
    );
  }
}
