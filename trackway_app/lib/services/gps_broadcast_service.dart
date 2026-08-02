import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
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
      _isBroadcasting = prefs.getBool("is_broadcasting") ?? false;
      _activeJourneyId = prefs.getInt("active_journey_id");

      if (_isBroadcasting && _timer == null) {
        debugPrint("Restoring active GPS broadcast session (Journey #$_activeJourneyId)...");
        _startTimer();
        sendGps();
      }
    } catch (e) {
      debugPrint("GpsBroadcastService init error: $e");
    }
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
      final speedKmh = position.speed * 3.6;

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

  Future<Map<String, dynamic>> startBroadcast() async {
    final permissionResult = await ensureLocationPermission();
    if (!permissionResult.granted) {
      return {
        "success": false,
        "error": permissionResult.errorMessage ?? "Location permission is required to start broadcasting.",
      };
    }

    final result = await _apiService.startJourney();

    if (result["success"] == true) {
      _activeJourneyId = result["id"] as int?;
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
