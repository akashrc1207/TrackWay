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
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
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
        debugPrint("[TRACK_RUNTIME] getLatestGps Bus #$busId RAW: active_journey=${response.data['active_journey']}, journey_id=${response.data['journey_id']}, status=${response.data['status']}");
        return GpsLocation.fromJson(response.data);
      }
      return null;
    } catch (e) {
      debugPrint("[TRACK_RUNTIME] getLatestGps Bus #$busId Error: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchBusEta(int busId) async {
    try {
      final response = await _dio.get("/api/buses/$busId/eta/");
      final data = response.data as Map<String, dynamic>;
      debugPrint("[TRACK_RUNTIME] fetchBusEta Bus #$busId RAW: active_journey=${data['active_journey']}, journey_id=${data['journey_id']}, status=${data['status']}, stops=${(data['stops_eta'] as List?)?.length ?? 0}, polyline=${(data['travelled_polyline'] as List?)?.length ?? 0}");
      return data;
    } catch (e) {
      debugPrint("[TRACK_RUNTIME] fetchBusEta Bus #$busId Error: $e");
      return null;
    }
  }

  Future<void> uploadGps({
    required double latitude,
    required double longitude,
    required double speed,
    double? accuracy,
    double? heading,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("token");

    if (token == null || token.isEmpty) {
      debugPrint("GPS Upload Error: Authentication token missing. Skipping upload.");
      return;
    }

    try {
      final data = <String, dynamic>{
        "latitude": latitude,
        "longitude": longitude,
        "speed": speed,
      };
      if (accuracy != null) data["accuracy"] = accuracy;
      if (heading != null) data["heading"] = heading;

      final response = await _dio.post(
        "/api/gps/update/",
        data: data,
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

  Future<Map<String, dynamic>> startJourney({
    int? busId,
    double? latitude,
    double? longitude,
    String? direction,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("token");

    if (token == null || token.isEmpty) {
      return {"success": false, "error": "Authentication required. Please log in as a driver."};
    }

    final int? targetBusId = busId ?? prefs.getInt("selected_bus_id");
    final Map<String, dynamic> payload = {};
    if (targetBusId != null) payload["bus_id"] = targetBusId;
    if (latitude != null) payload["latitude"] = latitude;
    if (longitude != null) payload["longitude"] = longitude;
    if (direction != null) payload["direction"] = direction;

    try {
      final response = await _dio.post(
        "/api/journey/start/",
        data: payload,
        options: Options(headers: {"Authorization": "Token $token"}),
      );

      if (response.data != null && response.data["start_time"] != null) {
        await prefs.setString("journey_start_time", response.data["start_time"].toString());
      }

      return {
        "success": true,
        "id": response.data["id"],
        "data": response.data,
      };
    } on DioException catch (e) {
      final resData = e.response?.data;
      String errorMsg = "Server error (${e.response?.statusCode ?? 'unknown'})";
      if (resData is Map) {
        errorMsg = resData["error"]?.toString() ?? resData["detail"]?.toString() ?? errorMsg;
      } else if (resData is String && resData.isNotEmpty) {
        errorMsg = resData;
      }
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

      if (response.statusCode == 200) {
        await prefs.remove("journey_start_time");
        return true;
      }
      return false;
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

      return data;
    } catch (e) {
      debugPrint("Login Error: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> getActiveJourney() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString("token");
    debugPrint("[DEBUG_LOG] getActiveJourney using token: $token");
    if (token == null || token.isEmpty) return null;

    try {
      final response = await _dio.get(
        "/api/journey/active/",
        options: Options(headers: {"Authorization": "Token $token"}),
      );
      debugPrint("[DEBUG_LOG] GET /api/journey/active/ HTTP Status: ${response.statusCode}");
      debugPrint("[DEBUG_LOG] GET /api/journey/active/ Response Data: ${response.data}");
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data["has_active_journey"] == true) {
          if (data["bus_name"] != null) await prefs.setString("bus_name", data["bus_name"].toString());
          if (data["bus_number"] != null) await prefs.setString("bus_number", data["bus_number"].toString());
          if (data["route_name"] != null) await prefs.setString("route_name", data["route_name"].toString());
          if (data["bus_id"] != null) await prefs.setInt("selected_bus_id", int.parse(data["bus_id"].toString()));
          if (data["journey_id"] != null) await prefs.setInt("active_journey_id", int.parse(data["journey_id"].toString()));
          if (data["start_time"] != null) await prefs.setString("journey_start_time", data["start_time"].toString());
          await prefs.setBool("is_broadcasting", true);
        }
        return data;
      }
    } catch (e) {
      debugPrint("[DEBUG_LOG] Get Active Journey Exception: $e");
    }
    return null;
  }
}
