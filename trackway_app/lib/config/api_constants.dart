class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: "http://34.14.132.119",
  );

  static const String routes = "$baseUrl/api/routes/";
  static const String buses = "$baseUrl/api/buses/";
  static const String search = "$baseUrl/api/search/";
  static const String busStops = "$baseUrl/api/bus-stops/";
  static const String gps = "$baseUrl/api/gps/";
  static const String login = "$baseUrl/api/token/";
}
