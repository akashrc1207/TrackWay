class Bus {
  final int id;
  final String busName;
  final String busNumber;
  final int capacity;
  final String status;
  final int route;

  Bus({
    required this.id,
    required this.busName,
    required this.busNumber,
    required this.capacity,
    required this.status,
    required this.route,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: json["id"],
      busName: json["bus_name"] ?? "",
      busNumber: json["bus_number"] ?? "",
      capacity: json["capacity"] ?? 50,
      status: json["status"] ?? "Active",
      route: json["route"] ?? 1,
    );
  }

  String get displayName =>
      busName.isNotEmpty ? "$busName ($busNumber)" : busNumber;
}
