import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_theme.dart';
import '../../models/gps_location.dart';
import '../../services/api_service.dart';

class TrackingScreen extends StatefulWidget {
  final int busId;

  const TrackingScreen({super.key, required this.busId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();

  late AnimationController _animController;
  final ValueNotifier<LatLng?> _animatedPosNotifier = ValueNotifier<LatLng?>(
    null,
  );
  LatLng? _oldBusPos;
  LatLng? _targetBusPos;

  GpsLocation? _gpsLocation;
  Map<String, dynamic>? _etaData;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _animController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2000),
        )..addListener(() {
          if (_oldBusPos != null && _targetBusPos != null) {
            final lat =
                _oldBusPos!.latitude +
                (_targetBusPos!.latitude - _oldBusPos!.latitude) *
                    _animController.value;
            final lng =
                _oldBusPos!.longitude +
                (_targetBusPos!.longitude - _oldBusPos!.longitude) *
                    _animController.value;
            final currentAnimatedPos = LatLng(lat, lng);
            _animatedPosNotifier.value = currentAnimatedPos;
            try {
              _mapController.move(
                currentAnimatedPos,
                _mapController.camera.zoom,
              );
            } catch (_) {}
          }
        });

    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final gps = await _apiService.getLatestGps(widget.busId);
      final eta = await _apiService.fetchBusEta(widget.busId);

      if (!mounted) return;

      if (gps == null) {
        setState(() {
          _isLoading = false;
          if (_gpsLocation == null) {
            _errorMessage =
                "Waiting for live GPS location signal from Bus #${widget.busId}";
          }
        });
        return;
      }

      final newPos = LatLng(gps.latitude, gps.longitude);

      setState(() {
        _gpsLocation = gps;
        _etaData = eta;
        _isLoading = false;
        _errorMessage = null;
      });

      if (_targetBusPos == null) {
        _oldBusPos = newPos;
        _targetBusPos = newPos;
        _animatedPosNotifier.value = newPos;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              _mapController.move(newPos, 14.5);
            } catch (_) {}
          }
        });
      } else if (_targetBusPos != newPos) {
        _oldBusPos = _animatedPosNotifier.value ?? _targetBusPos;
        _targetBusPos = newPos;
        _animController.forward(from: 0.0);
      }
    } catch (e) {
      debugPrint("Tracking Load Error: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_gpsLocation == null) {
          _errorMessage =
              "Waiting for live location signal from Bus ${widget.busId}";
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    _animatedPosNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _gpsLocation == null) {
      return Scaffold(
        backgroundColor: AppTheme.bgMint,
        appBar: AppBar(title: Text("Tracking Bus #${widget.busId}")),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryEmerald),
        ),
      );
    }

    if (_gpsLocation == null) {
      return Scaffold(
        backgroundColor: AppTheme.bgMint,
        appBar: AppBar(title: Text("Tracking Bus #${widget.busId}")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: AppTheme.warningBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_off_rounded,
                    size: 54,
                    color: AppTheme.warningAmber,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _errorMessage ?? "No GPS location signal available yet.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryEmerald,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text("Retry Connection"),
                  onPressed: () {
                    setState(() => _isLoading = true);
                    _loadData();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    final stops = (_etaData?["stops_eta"] as List?) ?? [];

    // Find immediate next stop index
    int nextStopIndex = -1;
    for (int i = 0; i < stops.length; i++) {
      if (stops[i]["eta_text"] != "Passed") {
        nextStopIndex = i;
        break;
      }
    }

    List<Marker> stopMarkers = [];
    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      final stopLat = stop["latitude"] as double?;
      final stopLng = stop["longitude"] as double?;
      final stopName = stop["stop_name"] as String? ?? "Stop";
      final etaText = stop["eta_text"] as String? ?? "";
      final isPassed = etaText == "Passed";
      final isNext = i == nextStopIndex;

      if (stopLat != null && stopLng != null) {
        stopMarkers.add(
          Marker(
            point: LatLng(stopLat, stopLng),
            width: 105,
            height: 65,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isPassed
                        ? Colors.grey.shade600
                        : (isNext
                              ? Colors.amber.shade800
                              : AppTheme.primaryEmerald),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    isPassed
                        ? "Passed"
                        : (isNext ? "NEXT: $etaText" : "ETA $etaText"),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  isPassed ? Icons.check_circle_rounded : Icons.location_on,
                  color: isPassed
                      ? Colors.grey.shade500
                      : (isNext
                            ? Colors.amber.shade800
                            : AppTheme.primaryEmerald),
                  size: isNext ? 28 : 22,
                ),
                Text(
                  stopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isNext ? FontWeight.w900 : FontWeight.bold,
                    color: isPassed
                        ? Colors.grey.shade600
                        : AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.bgMint,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMint,
        title: Text(
          _etaData?["bus_name"] != null
              ? "${_etaData!['bus_name']} (${_etaData!['bus_number']})"
              : "Live Bus #${widget.busId}",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppTheme.primaryEmerald,
            ),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _animatedPosNotifier.value ??
                  LatLng(_gpsLocation!.latitude, _gpsLocation!.longitude),
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: "com.trackway.app",
              ),
              ValueListenableBuilder<LatLng?>(
                valueListenable: _animatedPosNotifier,
                builder: (context, pos, _) {
                  final busPos =
                      pos ??
                      LatLng(_gpsLocation!.latitude, _gpsLocation!.longitude);
                  return MarkerLayer(
                    markers: [
                      Marker(
                        point: busPos,
                        width: 62,
                        height: 62,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.primaryEmerald,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryEmerald.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.directions_bus_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      ...stopMarkers,
                    ],
                  );
                },
              ),
            ],
          ),

          // "Where Is My Train" Style Live Timeline Bottom Overlay
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE6F4ED)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.mintContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.speed_rounded,
                            color: AppTheme.primaryEmerald,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${_gpsLocation!.speed} km/h",
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              _etaData?['route_name'] ??
                                  'Thaliparamba - Cherupuzha',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.successGreen.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 3.5,
                                backgroundColor: AppTheme.successGreen,
                              ),
                              SizedBox(width: 6),
                              Text(
                                "SMOOTH LIVE",
                                style: TextStyle(
                                  color: AppTheme.successGreen,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (stops.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Divider(height: 1, color: Color(0xFFE6F4ED)),
                      ),

                      // "Where is my Train" Style Station Timeline
                      SizedBox(
                        height: 72,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: stops.length,
                          itemBuilder: (context, index) {
                            final s = stops[index];
                            final etaText = s["eta_text"] ?? "";
                            final isPassed = etaText == "Passed";
                            final isNext = index == nextStopIndex;

                            return Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isNext
                                    ? AppTheme.mintContainer
                                    : (isPassed
                                          ? Colors.grey.shade100
                                          : Colors.white),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isNext
                                      ? AppTheme.primaryEmerald
                                      : const Color(0xFFE6F4ED),
                                  width: isNext ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isPassed
                                        ? Icons.check_circle_rounded
                                        : (isNext
                                              ? Icons.directions_bus_rounded
                                              : Icons
                                                    .radio_button_checked_rounded),
                                    color: isPassed
                                        ? Colors.grey.shade400
                                        : (isNext
                                              ? AppTheme.primaryEmerald
                                              : AppTheme.primaryEmeraldDark),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            s["stop_name"] ?? "",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: isPassed
                                                  ? Colors.grey.shade600
                                                  : AppTheme.textPrimary,
                                            ),
                                          ),
                                          if (isNext) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryEmerald,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                "NEXT STOP",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isPassed
                                            ? "Departed"
                                            : "ETA: ${s['eta_text']} (${s['distance_km']} km)",
                                        style: TextStyle(
                                          color: isPassed
                                              ? Colors.grey.shade500
                                              : AppTheme.primaryEmeraldDark,
                                          fontSize: 11,
                                          fontWeight: isNext
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
