import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/gps_location.dart';
import '../utils/bearing_calculator.dart';
import 'api_service.dart';

/// Dedicated Tracking Engine Layer separating map animation, position queuing,
/// bearing calculation, camera control, and signal monitoring from UI presentation.
class TrackingEngine {
  final int busId;
  final ApiService _apiService = ApiService();

  // Reactive State Notifiers
  final ValueNotifier<LatLng?> animatedPosNotifier = ValueNotifier<LatLng?>(null);
  final ValueNotifier<double> bearingNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> autoFollowNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<String> signalStatusNotifier = ValueNotifier<String>("live");
  final ValueNotifier<GpsLocation?> gpsLocationNotifier = ValueNotifier<GpsLocation?>(null);
  final ValueNotifier<Map<String, dynamic>?> etaDataNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<List<LatLng>> travelledPolylineNotifier = ValueNotifier<List<LatLng>>([]);
  final ValueNotifier<List<LatLng>> remainingPolylineNotifier = ValueNotifier<List<LatLng>>([]);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<String?> errorMessageNotifier = ValueNotifier<String?>(null);

  // Position Queue & Animation state
  final List<LatLng> _positionQueue = [];
  LatLng? _oldPos;
  LatLng? _targetPos;
  double _oldBearing = 0.0;
  double _targetBearing = 0.0;

  Timer? _gpsTimer;
  Timer? _etaTimer;
  AnimationController? _animController;

  TrackingEngine({required this.busId});

  void initialize(TickerProvider vsync, MapController mapController) {
    _animController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: AppConfig.gpsPollIntervalMs - 200),
    )..addListener(() {
        if (_oldPos != null && _targetPos != null) {
          final t = _animController!.value;
          final lat = _oldPos!.latitude + (_targetPos!.latitude - _oldPos!.latitude) * t;
          final lng = _oldPos!.longitude + (_targetPos!.longitude - _oldPos!.longitude) * t;
          final currentPos = LatLng(lat, lng);
          animatedPosNotifier.value = currentPos;

          // Bearing interpolation
          bearingNotifier.value = BearingCalculator.lerpAngle(_oldBearing, _targetBearing, t);

          // Auto-follow map camera
          if (autoFollowNotifier.value) {
            try {
              mapController.move(currentPos, mapController.camera.zoom);
            } catch (_) {}
          }
        }
      });

    loadInitialData(mapController);
    _startTimers();
  }

  void _startTimers() {
    _gpsTimer?.cancel();
    _etaTimer?.cancel();

    // Fast 2.5s poll for position & bearing stream
    _gpsTimer = Timer.periodic(
      const Duration(milliseconds: AppConfig.gpsPollIntervalMs),
      (_) => pollGpsUpdate(),
    );

    // Decoupled slower 25s poll for heavy ML ETA recalculation
    _etaTimer = Timer.periodic(
      const Duration(milliseconds: AppConfig.etaRefreshIntervalMs),
      (_) => pollEtaUpdate(),
    );
  }

  Future<void> loadInitialData(MapController mapController) async {
    isLoadingNotifier.value = true;
    errorMessageNotifier.value = null;

    await Future.wait([
      pollGpsUpdate(),
      pollEtaUpdate(),
    ]);

    isLoadingNotifier.value = false;

    if (animatedPosNotifier.value != null && autoFollowNotifier.value) {
      try {
        mapController.move(animatedPosNotifier.value!, 14.5);
      } catch (_) {}
    }
  }

  Future<void> pollGpsUpdate() async {
    try {
      final gps = await _apiService.getLatestGps(busId);
      if (gps == null) {
        signalStatusNotifier.value = "lost";
        if (gpsLocationNotifier.value == null) {
          errorMessageNotifier.value = "Waiting for live GPS location signal from Bus #$busId";
        }
        return;
      }

      gpsLocationNotifier.value = gps;
      signalStatusNotifier.value = gps.signalStatus;

      final newPos = LatLng(gps.latitude, gps.longitude);

      // Queue position
      _positionQueue.add(newPos);
      if (_positionQueue.length > AppConfig.positionQueueCapacity) {
        _positionQueue.removeAt(0);
      }

      if (_targetPos == null) {
        _oldPos = newPos;
        _targetPos = newPos;
        animatedPosNotifier.value = newPos;
      } else if (_targetPos != newPos) {
        _oldPos = animatedPosNotifier.value ?? _targetPos;
        _targetPos = newPos;

        // Calculate target bearing
        _oldBearing = bearingNotifier.value;
        _targetBearing = BearingCalculator.calculateBearing(_oldPos!, _targetPos!);

        _animController?.forward(from: 0.0);
      }
    } catch (e) {
      debugPrint("TrackingEngine GPS Poll Error: $e");
    }
  }

  Future<void> pollEtaUpdate() async {
    try {
      final eta = await _apiService.fetchBusEta(busId);
      if (eta != null) {
        etaDataNotifier.value = eta;
        if (eta["signal_status"] != null) {
          signalStatusNotifier.value = eta["signal_status"];
        }
        _updatePolylineFromState(eta);
      }
    } catch (e) {
      debugPrint("TrackingEngine ETA Poll Error: $e");
    }
  }

  void _updatePolylineFromState(Map<String, dynamic> state) {
    final travelledRaw = (state["travelled_polyline"] as List?) ?? [];
    final remainingRaw = (state["remaining_polyline"] as List?) ?? [];

    List<LatLng> travelled = [];
    for (var p in travelledRaw) {
      final lat = (p["latitude"] as num?)?.toDouble();
      final lng = (p["longitude"] as num?)?.toDouble();
      if (lat != null && lng != null) travelled.add(LatLng(lat, lng));
    }

    List<LatLng> remaining = [];
    for (var p in remainingRaw) {
      final lat = (p["latitude"] as num?)?.toDouble();
      final lng = (p["longitude"] as num?)?.toDouble();
      if (lat != null && lng != null) remaining.add(LatLng(lat, lng));
    }

    if (travelled.isNotEmpty) travelledPolylineNotifier.value = travelled;
    if (remaining.isNotEmpty) remainingPolylineNotifier.value = remaining;
  }

  void toggleAutoFollow() {
    autoFollowNotifier.value = !autoFollowNotifier.value;
  }

  void onUserMapGesture() {
    // Automatically pause auto-follow when user manually drags map
    if (autoFollowNotifier.value) {
      autoFollowNotifier.value = false;
    }
  }

  void dispose() {
    _gpsTimer?.cancel();
    _etaTimer?.cancel();
    _animController?.dispose();
    animatedPosNotifier.dispose();
    bearingNotifier.dispose();
    autoFollowNotifier.dispose();
    signalStatusNotifier.dispose();
    gpsLocationNotifier.dispose();
    etaDataNotifier.dispose();
    travelledPolylineNotifier.dispose();
    remainingPolylineNotifier.dispose();
    isLoadingNotifier.dispose();
    errorMessageNotifier.dispose();
  }
}
