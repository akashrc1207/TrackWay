import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_constants.dart';
import '../models/bus.dart';
import '../models/gps_location.dart';
import '../models/route_details.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final customUrl = prefs.getString("custom_backend_url");
          if (customUrl != null && customUrl.trim().isNotEmpty) {
            final trimmed = customUrl.trim();
            options.baseUrl = trimmed.endsWith('/')
                ? trimmed.substring(0, trimmed.length - 1)
                : trimmed;
          }
          return handler.next(options);
        },
      ),
    );
  }

  Future<List<Bus>> getBuses() async {
    try {
      final response = await _dio.get("/api/buses/");
      List data = response.data;
      return data.map((e) => Bus.fromJson(e)).toList();
    } catch (e) {
      debugPrint("Get Buses Error: $e");
      return searchBus("");
    }
  }

  Future<List<Bus>> searchBus(String query) async {
    try {
      final response = await _dio.get(
        "/api/search/",
        queryParameters: {"q": query},
      );

      List data = response.data;
      return data.map((e) => Bus.fromJson(e)).toList();
    } catch (e) {
      debugPrint("Search Error: $e");
      return [];
    }
  }

  Future<RouteDetails?> getRouteDetails(int routeId) async {
    try {
      final response = await _dio.get("/api/routes/$routeId/details/");
      return RouteDetails.fromJson(response.data);
    } catch (e) {
      debugPrint("Get Route Details Error: $e");
      return null;
    }
  }

  Future<GpsLocation?> getLatestGps(int busId) async {
    try {
      final response = await _dio.get("/api/gps/latest/$busId/");
      if (response.data != null) {
        return GpsLocation.fromJson(response.data);
      }
      return null;
    } catch (e) {
      debugPrint("Get Latest GPS Error: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchBusEta(int busId) async {
    try {
      final response = await _dio.get("/api/buses/$busId/eta/");
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint("Fetch Bus ETA Error: $e");
      return null;
    }
  }

  Future<void> uploadGps({
    required double latitude,
    required double longitude,
    required double speed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("token");

    if (token == null || token.isEmpty) {
      debugPrint("No auth token found, attempting auto-login as driver1...");
      final loginData = await login("driver1", "driver123");
      token = loginData?["token"];
      if (token == null) return;
    }

    try {
      final response = await _dio.post(
        "/api/gps/update/",
        data: {"latitude": latitude, "longitude": longitude, "speed": speed},
        options: Options(headers: {"Authorization": "Token $token"}),
      );

      debugPrint("GPS Upload Success: ${response.statusCode}");
    } on DioException catch (e) {
      debugPrint("GPS Upload Error: ${e.response?.statusCode} - ${e.response?.data}");
    }
  }

  Future<List<Bus>> getAvailableBuses() async {
    try {
      final response = await _dio.get("/api/buses/available/");
      List data = response.data;
      return data.map((e) => Bus.fromJson(e)).toList();
    } catch (e) {
      debugPrint("Get Available Buses Error: $e");
      return getBuses();
    }
  }

  Future<Map<String, dynamic>> startJourney({int? busId}) async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("token");

    if (token == null || token.isEmpty) {
      debugPrint("No token for startJourney, auto-authenticating driver1...");
      final loginData = await login("driver1", "driver123");
      token = loginData?["token"];
    }

    if (token == null || token.isEmpty) {
      return {"success": false, "error": "Authentication required. Please log in."};
    }

    final int? targetBusId = busId ?? prefs.getInt("selected_bus_id");

    try {
      final response = await _dio.post(
        "/api/journey/start/",
        data: targetBusId != null ? {"bus_id": targetBusId} : {},
        options: Options(headers: {"Authorization": "Token $token"}),
      );

      return {
        "success": true,
        "id": response.data["id"],
        "data": response.data,
      };
    } on DioException catch (e) {
      final errorMsg = e.response?.data?["error"] ?? e.response?.data?["detail"] ?? "Server error (${e.response?.statusCode})";
      debugPrint("Start Journey Error: $errorMsg");
      return {"success": false, "error": errorMsg};
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  Future<bool> stopJourney() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("token");

    if (token == null || token.isEmpty) {
      return false;
    }

    try {
      final response = await _dio.post(
        "/api/journey/stop/",
        options: Options(headers: {"Authorization": "Token $token"}),
      );

      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint("Stop Journey Error: ${e.response?.data}");
      return false;
    }
  }

  Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      final response = await _dio.post(
        "/api/auth/login/",
        data: {"username": username, "password": password},
      );

      final data = response.data;
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString("token", data["token"] ?? "");
      await prefs.setString("username", data["username"] ?? "");
      if (data["bus_name"] != null) {
        await prefs.setString("bus_name", data["bus_name"]);
      }
      if (data["bus_number"] != null) {
        await prefs.setString("bus_number", data["bus_number"]);
      }

      return data;
    } catch (e) {
      debugPrint("Login Error: $e");
      return null;
    }
  }
}
