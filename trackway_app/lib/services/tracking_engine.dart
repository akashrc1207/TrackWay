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
  final ValueNotifier<String> signalStatusNotifier = ValueNotifier<String>("inactive");
  final ValueNotifier<GpsLocation?> gpsLocationNotifier = ValueNotifier<GpsLocation?>(null);
  final ValueNotifier<Map<String, dynamic>?> etaDataNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<List<LatLng>> travelledPolylineNotifier = ValueNotifier<List<LatLng>>([]);
  final ValueNotifier<List<LatLng>> remainingPolylineNotifier = ValueNotifier<List<LatLng>>([]);
  final ValueNotifier<bool> activeJourneyNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int?> journeyIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<String?> errorMessageNotifier = ValueNotifier<String?>(null);

  // Position Queue & Animation state
  final List<LatLng> _positionQueue = [];
  LatLng? _oldPos;
  LatLng? _targetPos;
  double _oldBearing = 0.0;
  double _targetBearing = 0.0;
  int? _currentJourneyId;

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

  void clearJourneyState() {
    debugPrint("[TRACK_RUNTIME] clearJourneyState() called for Bus #$busId — erasing all polylines, markers, ETAs, GPS position.");
    _positionQueue.clear();
    _oldPos = null;
    _targetPos = null;
    _oldBearing = 0.0;
    _targetBearing = 0.0;
    _currentJourneyId = null;

    animatedPosNotifier.value = null;
    bearingNotifier.value = 0.0;
    signalStatusNotifier.value = "inactive";
    gpsLocationNotifier.value = null;
    etaDataNotifier.value = null;
    travelledPolylineNotifier.value = [];
    remainingPolylineNotifier.value = [];
    activeJourneyNotifier.value = false;
    journeyIdNotifier.value = null;
    debugPrint("[TRACK_RUNTIME] clearJourneyState() DONE — activeJourneyNotifier=${activeJourneyNotifier.value}");
  }

  void _startTimers() {
    _gpsTimer?.cancel();
    _etaTimer?.cancel();

    // Fast 2.5s poll for position & bearing stream
    _gpsTimer = Timer.periodic(
      const Duration(milliseconds: AppConfig.gpsPollIntervalMs),
      (_) => pollGpsUpdate(),
    );

    // Decoupled slower 3s poll for heavy ML ETA recalculation
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

      // GPS poll is the master authority on active journey state.
      // activeJourney defaults to false when key is missing (old backend compatibility).
      if (gps == null || !gps.activeJourney) {
        debugPrint(
          "[TRACK_RUNTIME] pollGpsUpdate Bus #$busId => "
          "activeJourney=${gps?.activeJourney}, status=${gps?.status} -> INACTIVE. Clearing state."
        );
        clearJourneyState();
        signalStatusNotifier.value = "inactive";
        activeJourneyNotifier.value = false;
        journeyIdNotifier.value = null;
        return;
      }

      if (gps.journeyId != null && gps.journeyId != _currentJourneyId) {
        debugPrint("[TRACK_RUNTIME] pollGpsUpdate Bus #$busId => NEW journey_id=${gps.journeyId} (was $_currentJourneyId). Clearing old state.");
        clearJourneyState();
        _currentJourneyId = gps.journeyId;
        journeyIdNotifier.value = gps.journeyId;
      }

      activeJourneyNotifier.value = true;
      gpsLocationNotifier.value = gps;
      signalStatusNotifier.value = gps.status.isNotEmpty ? gps.status : gps.signalStatus;

      final displayLat = gps.snappedLatitude ?? gps.latitude;
      final displayLng = gps.snappedLongitude ?? gps.longitude;
      final newPos = LatLng(displayLat, displayLng);

      debugPrint(
        "[TRACK_RUNTIME] pollGpsUpdate Bus #$busId => activeJourney=true, journey_id=$_currentJourneyId, "
        "raw=(${gps.latitude}, ${gps.longitude}), snapped=($displayLat, $displayLng), "
        "speed=${gps.speed}km/h, status=${gps.signalStatus}"
      );

      // Queue position
      _positionQueue.add(newPos);
      if (_positionQueue.length > AppConfig.positionQueueCapacity) {
        _positionQueue.removeAt(0);
      }

      if (_targetPos == null) {
        _oldPos = newPos;
        _targetPos = newPos;
        animatedPosNotifier.value = newPos;
        if (gps.bearing != 0.0) bearingNotifier.value = gps.bearing;
      } else if (_targetPos != newPos) {
        _oldPos = animatedPosNotifier.value ?? _targetPos;
        _targetPos = newPos;

        _oldBearing = bearingNotifier.value;
        // Calculate target bearing if moving sufficiently
        if (gps.speed >= 1.5 || BearingCalculator.calculateBearing(_oldPos!, _targetPos!).abs() > 0.1) {
          _targetBearing = BearingCalculator.calculateBearing(_oldPos!, _targetPos!);
        } else {
          _targetBearing = _oldBearing;
        }

        _animController?.forward(from: 0.0);
      }
    } catch (e) {
      debugPrint("[TRACK_RUNTIME] TrackingEngine GPS Poll Error: $e");
    }
  }

  Future<void> pollEtaUpdate() async {
    try {
      final Map<String, dynamic>? etaNullable = await _apiService.fetchBusEta(busId);

      // Guard: null response = inactive
      if (etaNullable == null) {
        etaDataNotifier.value = null;
        travelledPolylineNotifier.value = [];
        remainingPolylineNotifier.value = [];
        if (gpsLocationNotifier.value?.activeJourney != true) {
          activeJourneyNotifier.value = false;
          signalStatusNotifier.value = "inactive";
        }
        debugPrint("[TRACK_RUNTIME] pollEtaUpdate Bus #$busId => ETA response null -> inactive");
        return;
      }

      // eta is now guaranteed non-null for the rest of this function
      final eta = etaNullable;

      // Determine if this ETA response represents an active journey.
      // New backend: explicit active_journey field present → use it directly.
      // Old backend: no active_journey field → defer to GPS poll verdict.
      //   The GPS poll uses GPS timestamp freshness to infer active state,
      //   so we trust it as the authority rather than guessing from ETA data alone.
      final bool? explicitActive = eta["active_journey"] as bool?;
      final bool etaActiveJourney;
      if (explicitActive != null) {
        // New backend: use the explicit field
        etaActiveJourney = explicitActive;
        debugPrint("[TRACK_RUNTIME] pollEtaUpdate Bus #$busId => active_journey=$etaActiveJourney (explicit from backend)");
      } else {
        // Old backend: no active_journey key → follow the GPS poll's decision
        etaActiveJourney = activeJourneyNotifier.value;
        debugPrint("[TRACK_RUNTIME] pollEtaUpdate Bus #$busId => active_journey absent, deferring to GPS: $etaActiveJourney");
      }

      if (!etaActiveJourney) {
        etaDataNotifier.value = null;
        travelledPolylineNotifier.value = [];
        remainingPolylineNotifier.value = [];
        // Only set inactive signal if GPS also confirms inactive
        if (gpsLocationNotifier.value?.activeJourney != true) {
          activeJourneyNotifier.value = false;
          signalStatusNotifier.value = "inactive";
        }
        debugPrint("[TRACK_RUNTIME] pollEtaUpdate Bus #$busId => inactive -> cleared ETA/polyline state");
        return;
      }

      final respJourneyId = (eta["journey_id"] as num?)?.toInt();
      if (_currentJourneyId != null && respJourneyId != null && respJourneyId != _currentJourneyId) {
        debugPrint("[TRACK_RUNTIME] ETA response journey_id ($respJourneyId) mismatch with current ($_currentJourneyId) -> DISCARDING");
        return;
      }

      if (respJourneyId != null && _currentJourneyId == null) {
        _currentJourneyId = respJourneyId;
        journeyIdNotifier.value = respJourneyId;
      }

      activeJourneyNotifier.value = true;
      etaDataNotifier.value = eta;
      if (eta["signal_status"] != null) {
        signalStatusNotifier.value = eta["signal_status"] as String;
      }
      _updatePolylineFromState(eta);

      final nextStopName = eta["next_stop"]?["stop_name"] ?? "Unknown";
      final nextStopStatus = eta["next_stop"]?["status"] ?? "unknown";
      debugPrint(
        "[TRACK_RUNTIME] pollEtaUpdate Bus #$busId: active_journey=true, journey_id=$respJourneyId, "
        "progress=${eta['journey_progress_percent']}%, next_stop=$nextStopName ($nextStopStatus)"
      );
    } catch (e) {
      debugPrint("[TRACK_RUNTIME] TrackingEngine ETA Poll Error: $e");
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

    travelledPolylineNotifier.value = travelled;
    remainingPolylineNotifier.value = remaining;
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
    activeJourneyNotifier.dispose();
    journeyIdNotifier.dispose();
    isLoadingNotifier.dispose();
    errorMessageNotifier.dispose();
  }
}
