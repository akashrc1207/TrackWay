class Bus {
  final int id;
  final String busNumber;
  final int capacity;
  final String status;
  final int route;

  Bus({
    required this.id,
    required this.busNumber,
    required this.capacity,
    required this.status,
    required this.route,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: json["id"],
      busNumber: json["bus_number"],
      capacity: json["capacity"],
      status: json["status"],
      route: json["route"],
    );
  }
}
