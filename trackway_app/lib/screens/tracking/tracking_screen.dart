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

class _TrackingScreenState extends State<TrackingScreen> {
  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();

  GpsLocation? _gpsLocation;
  Map<String, dynamic>? _etaData;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final gps = await _apiService.getLatestGps(widget.busId);
      final eta = await _apiService.fetchBusEta(widget.busId);

      if (!mounted) return;

      setState(() {
        _gpsLocation = gps;
        _etaData = eta;
        _isLoading = false;
        _errorMessage = null;
      });

      _mapController.move(LatLng(gps.latitude, gps.longitude), 14.5);
    } catch (e) {
      debugPrint("Tracking Load Error: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_gpsLocation == null) {
          _errorMessage = "Waiting for live location signal from Bus ${widget.busId}";
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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
                  child: const Icon(Icons.location_off_rounded, size: 54, color: AppTheme.warningAmber),
                ),
                const SizedBox(height: 20),
                Text(
                  _errorMessage ?? "No GPS location signal available yet.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
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

    final busPos = LatLng(_gpsLocation!.latitude, _gpsLocation!.longitude);
    final stops = (_etaData?["stops_eta"] as List?) ?? [];

    List<Marker> mapMarkers = [
      Marker(
        point: busPos,
        width: 58,
        height: 58,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.primaryEmerald,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryEmerald.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 28),
        ),
      ),
    ];

    for (var stop in stops) {
      final stopLat = stop["latitude"] as double?;
      final stopLng = stop["longitude"] as double?;
      final stopName = stop["stop_name"] as String? ?? "Stop";
      final etaText = stop["eta_text"] as String? ?? "";

      if (stopLat != null && stopLng != null) {
        mapMarkers.add(
          Marker(
            point: LatLng(stopLat, stopLng),
            width: 100,
            height: 65,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryEmerald,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Text(
                    "ETA $etaText",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(Icons.location_on, color: AppTheme.primaryEmerald, size: 26),
                Text(
                  stopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
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
          "Live Bus #${widget.busId}",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryEmerald),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: busPos,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: "com.trackway.app",
              ),
              MarkerLayer(markers: mapMarkers),
            ],
          ),

          // Bottom Sheet Card Overlay - Concept 1 Mint & Emerald
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
                          child: const Icon(Icons.speed_rounded, color: AppTheme.primaryEmerald, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${_gpsLocation!.speed} km/h",
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              _etaData?['route_name'] ?? 'Active Journey',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.successBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              CircleAvatar(radius: 3.5, backgroundColor: AppTheme.successGreen),
                              SizedBox(width: 6),
                              Text(
                                "LIVE GPS",
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
                      SizedBox(
                        height: 68,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: stops.length,
                          itemBuilder: (context, index) {
                            final s = stops[index];
                            return Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.bgMint,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE6F4ED)),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s["stop_name"] ?? "",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "ETA: ${s['eta_text']} • ${s['distance_km']} km",
                                    style: const TextStyle(
                                      color: AppTheme.primaryEmerald,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
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
