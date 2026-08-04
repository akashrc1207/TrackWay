import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/route_details.dart';
import 'api_service.dart';
import 'location_permission_service.dart';

class GpsBroadcastService extends ChangeNotifier {
  static final GpsBroadcastService _instance = GpsBroadcastService._internal();
  static GpsBroadcastService get instance => _instance;

  GpsBroadcastService._internal();

  final ApiService _apiService = ApiService();

  bool _isBroadcasting = false;
  int? _activeJourneyId;
  Position? _currentPosition;
  Position? _lastValidPosition;
  Timer? _timer;

  bool get isBroadcasting => _isBroadcasting;
  int? get activeJourneyId => _activeJourneyId;
  Position? get currentPosition => _currentPosition;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");

      if (token != null && token.isNotEmpty) {
        final activeJourney = await _apiService.getActiveJourney();
        if (activeJourney != null) {
          if (activeJourney["has_active_journey"] == true) {
            _isBroadcasting = true;
            _activeJourneyId = int.tryParse(activeJourney["journey_id"].toString());
            await prefs.setBool("is_broadcasting", true);
            if (_activeJourneyId != null) {
              await prefs.setInt("active_journey_id", _activeJourneyId!);
            }
          } else {
            _isBroadcasting = false;
            _activeJourneyId = null;
            await prefs.setBool("is_broadcasting", false);
            await prefs.remove("active_journey_id");
          }
        } else {
          // Network error/timeout: retain cached broadcasting session state
          _isBroadcasting = prefs.getBool("is_broadcasting") ?? _isBroadcasting;
          _activeJourneyId = prefs.getInt("active_journey_id") ?? _activeJourneyId;
        }
      } else {
        _isBroadcasting = prefs.getBool("is_broadcasting") ?? false;
        _activeJourneyId = prefs.getInt("active_journey_id");
      }

      if (_isBroadcasting && _timer == null) {
        debugPrint("Restoring active GPS broadcast session (Journey #$_activeJourneyId)...");
        _startTimer();
        sendGps();
      }
    } catch (e) {
      debugPrint("GpsBroadcastService init error: $e");
    }
  }

  Future<void> restoreActiveSession({
    required int activeJourneyId,
    required int busId,
    String? busName,
    String? busNumber,
    String? routeName,
  }) async {
    debugPrint("[DEBUG_LOG] restoreActiveSession ENTERED: activeJourneyId=$activeJourneyId, busId=$busId");
    _activeJourneyId = activeJourneyId;
    _isBroadcasting = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("is_broadcasting", true);
    await prefs.setInt("active_journey_id", activeJourneyId);
    await prefs.setInt("selected_bus_id", busId);
    if (busName != null) await prefs.setString("bus_name", busName);
    if (busNumber != null) await prefs.setString("bus_number", busNumber);
    if (routeName != null) await prefs.setString("route_name", routeName);

    _startTimer();
    sendGps();
    notifyListeners();
    debugPrint("[DEBUG_LOG] restoreActiveSession FINISHED");
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      sendGps();
    });
  }

  Future<void> sendGps() async {
    if (!_isBroadcasting) return;

    try {
      final permissionResult = await ensureLocationPermission();
      if (!permissionResult.granted) {
        debugPrint("Location permission unavailable: ${permissionResult.errorMessage}. Skipping upload.");
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (e) {
        debugPrint("getCurrentPosition failed ($e), falling back to last known position.");
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (e2) {
          debugPrint("Geolocator last-known position check error: $e2");
        }
      }

      if (position == null) {
        debugPrint("No real GPS position available. Skipping upload.");
        return;
      }

      debugPrint(
        "GPS: lat=${position.latitude}, "
        "lng=${position.longitude}, "
        "accuracy=${position.accuracy}"
      );

      // 1. Accuracy Check
      if (position.accuracy > AppConfig.maxGpsAccuracyMeters) {
        debugPrint("Rejecting GPS log: Low accuracy (${position.accuracy.toStringAsFixed(1)}m > ${AppConfig.maxGpsAccuracyMeters}m)");
        return;
      }

      // 2. Jump and Implied Speed Check against last valid upload
      if (_lastValidPosition != null) {
        final distMeters = Geolocator.distanceBetween(
          _lastValidPosition!.latitude,
          _lastValidPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        final dtSec = position.timestamp.difference(_lastValidPosition!.timestamp).inMilliseconds / 1000.0;

        if (dtSec > 0 && dtSec <= 120.0 && distMeters <= 10000.0) {
          final impliedSpeedKmh = (distMeters / dtSec) * 3.6;
          if (impliedSpeedKmh > AppConfig.maxSpeedKmh) {
            debugPrint("Rejecting GPS log: Implied speed impossible (${impliedSpeedKmh.toStringAsFixed(1)} km/h > ${AppConfig.maxSpeedKmh} km/h)");
            return;
          }
          if (dtSec <= 3.5 && distMeters > AppConfig.maxJumpMetersPer3Sec) {
            debugPrint("Rejecting GPS log: Distance jump impossible (${distMeters.toStringAsFixed(1)}m > ${AppConfig.maxJumpMetersPer3Sec}m in ${dtSec.toStringAsFixed(1)}s)");
            return;
          }
        }
      }

      _lastValidPosition = position;
      _currentPosition = position;
      double rawSpeed = (position.speed.isNaN || position.speed.isInfinite || position.speed < 0) ? 0.0 : position.speed;
      final speedKmh = rawSpeed * 3.6;

      await _apiService.uploadGps(
        latitude: position.latitude,
        longitude: position.longitude,
        speed: double.parse(speedKmh.toStringAsFixed(1)),
      );

      notifyListeners();
    } catch (e) {
      debugPrint("sendGps Error in service: $e");
    }
  }

  RouteDetails? _cachedRouteDetails;
  RouteDetails? get cachedRouteDetails => _cachedRouteDetails;
  void setCachedRouteDetails(RouteDetails details) {
    _cachedRouteDetails = details;
  }

  Future<Map<String, dynamic>> validateTerminalProximity({int? busId, int? routeId}) async {
    if (_isBroadcasting) {
      return {
        "valid": false,
        "reason": "already_broadcasting",
        "error": "An active journey is already running. Please end your current trip first.",
      };
    }

    final permissionResult = await ensureLocationPermission();
    if (!permissionResult.granted) {
      return {
        "valid": false,
        "reason": "permission_denied",
        "error": permissionResult.errorMessage ?? "Location permission is required to verify terminal proximity.",
      };
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    if (position == null) {
      return {
        "valid": false,
        "reason": "no_gps",
        "error": "Acquiring satellite GPS signal... Please try again in a few seconds.",
      };
    }

    RouteDetails? routeDetails = _cachedRouteDetails;
    if (routeDetails == null) {
      final targetRouteId = routeId ?? 1;
      routeDetails = await _apiService.getRouteDetails(targetRouteId);
      if (routeDetails != null) {
        _cachedRouteDetails = routeDetails;
      }
    }

    if (routeDetails == null || routeDetails.stops.isEmpty) {
      return {
        "valid": false,
        "reason": "no_route_details",
        "error": "Could not retrieve route terminal information from server.",
      };
    }

    final firstStop = routeDetails.stops.first;
    final lastStop = routeDetails.stops.last;

    final double distToFirstExact = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      firstStop.latitude,
      firstStop.longitude,
    );

    final double distToLastExact = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lastStop.latitude,
      lastStop.longitude,
    );

    final int distToFirst = distToFirstExact.round();
    final int distToLast = distToLastExact.round();
    final int accuracyRounded = position.accuracy.round();

    final bool isNearFirst = distToFirstExact <= AppConfig.startRadiusMeters;
    final bool isNearLast = distToLastExact <= AppConfig.startRadiusMeters;

    if (!isNearFirst && !isNearLast) {
      return {
        "valid": false,
        "reason": "out_of_bounds",
        "distToFirst": distToFirst,
        "distToLast": distToLast,
        "firstStop": firstStop.stopName,
        "lastStop": lastStop.stopName,
        "accuracy": accuracyRounded,
        "requiredRadius": AppConfig.startRadiusMeters.round(),
      };
    }

    final String direction = isNearFirst ? "forward" : "reverse";
    final String directionLabel = isNearFirst
        ? "Forward (${firstStop.stopName} ➔ ${lastStop.stopName})"
        : "Reverse (${lastStop.stopName} ➔ ${firstStop.stopName})";
    final String terminalName = isNearFirst ? firstStop.stopName : lastStop.stopName;
    final int distMeters = isNearFirst ? distToFirst : distToLast;

    return {
      "valid": true,
      "direction": direction,
      "directionLabel": directionLabel,
      "terminalName": terminalName,
      "distMeters": distMeters,
      "accuracy": accuracyRounded,
      "currentPosition": position,
    };
  }

  Future<Map<String, dynamic>> startBroadcast({
    int? busId,
    Position? position,
    String? direction,
  }) async {
    try {
      final permissionResult = await ensureLocationPermission();
      if (!permissionResult.granted) {
        return {
          "success": false,
          "error": permissionResult.errorMessage ?? "Location permission is required to start broadcasting.",
        };
      }

      Position? pos = position;
      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
        } catch (_) {
          try {
            pos = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }
      }

      final result = await _apiService.startJourney(
        busId: busId,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
        direction: direction,
      );

      if (result["success"] == true) {
        _activeJourneyId = result["id"] != null ? int.tryParse(result["id"].toString()) : null;
        _isBroadcasting = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool("is_broadcasting", true);
        if (_activeJourneyId != null) {
          await prefs.setInt("active_journey_id", _activeJourneyId!);
        }

        _startTimer();
        await sendGps();
        notifyListeners();
      }

      return result;
    } catch (e, stack) {
      debugPrint("startBroadcast Exception: $e\n$stack");
      return {
        "success": false,
        "error": "Failed to start broadcast: ${e.toString()}",
      };
    }
  }

  Future<bool> stopBroadcast() async {
    final stopped = await _apiService.stopJourney();

    if (stopped) {
      _timer?.cancel();
      _timer = null;
      _isBroadcasting = false;
      _activeJourneyId = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("is_broadcasting", false);
      await prefs.remove("active_journey_id");

      notifyListeners();
    }

    return stopped;
  }
}
