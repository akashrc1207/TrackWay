import 'route_stop.dart';

class RouteDetails {
  final String routeName;
  final String startLocation;
  final String endLocation;
  final double totalDistance;
  final List<RouteStop> stops;
  final List<RouteStop> roadPolyline;

  RouteDetails({
    required this.routeName,
    required this.startLocation,
    required this.endLocation,
    required this.totalDistance,
    required this.stops,
    required this.roadPolyline,
  });

  factory RouteDetails.fromJson(Map<String, dynamic> json) {
    final List<RouteStop> stopsList = (json["stops"] as List? ?? [])
        .map<RouteStop>((e) => RouteStop.fromJson(e as Map<String, dynamic>))
        .toList();

    final List<RouteStop> polylineList = (json["road_polyline"] as List? ?? [])
        .map<RouteStop>((e) => RouteStop.fromJson(e as Map<String, dynamic>))
        .toList();

    return RouteDetails(
      routeName: (json["route_name"] as String?) ?? "",
      startLocation: (json["start_location"] as String?) ?? "",
      endLocation: (json["end_location"] as String?) ?? "",
      totalDistance: (json["total_distance"] as num? ?? 0).toDouble(),
      stops: stopsList,
      roadPolyline: polylineList.isNotEmpty ? polylineList : stopsList,
    );
  }
}
