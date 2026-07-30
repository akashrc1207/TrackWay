import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class GpsBroadcastService extends ChangeNotifier {
  static final GpsBroadcastService _instance = GpsBroadcastService._internal();
  static GpsBroadcastService get instance => _instance;

  GpsBroadcastService._internal();

  final ApiService _apiService = ApiService();

  bool _isBroadcasting = false;
  int? _activeJourneyId;
  Position? _currentPosition;
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
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (e) {
        debugPrint("Geolocator position check error: $e");
      }

      if (position == null) {
        debugPrint("No real GPS position available. Skipping upload.");
        return;
      }

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
