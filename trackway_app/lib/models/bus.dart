class Bus {
  final int id;
  final String busName;
  final String busNumber;
  final int capacity;
  final String status;
  final int routeId;
  final String routeName;

  Bus({
    required this.id,
    required this.busName,
    required this.busNumber,
    required this.capacity,
    required this.status,
    required this.routeId,
    required this.routeName,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    String routeStr = "Thaliparamba - Cherupuzha";
    int rId = 1;
    if (json["route"] is String) {
      routeStr = json["route"];
    } else if (json["route"] is int) {
      rId = json["route"];
    }

    return Bus(
      id: json["id"],
      busName: json["bus_name"] ?? "",
      busNumber: json["bus_number"] ?? "",
      capacity: json["capacity"] ?? 50,
      status: json["status"] ?? "Active",
      routeId: rId,
      routeName: routeStr,
    );
  }

  String get displayName => busName.isNotEmpty ? "$busName ($busNumber)" : busNumber;
  int get route => routeId;
}
