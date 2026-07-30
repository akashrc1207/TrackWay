import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_theme.dart';
import '../../models/bus.dart';
import '../../models/route_details.dart';
import '../../services/api_service.dart';
import '../tracking/tracking_screen.dart';

class SavedRoutesScreen extends StatefulWidget {
  final int routeId;
  const SavedRoutesScreen({super.key, this.routeId = 1});

  @override
  State<SavedRoutesScreen> createState() => _SavedRoutesScreenState();
}

class _SavedRoutesScreenState extends State<SavedRoutesScreen> {
  final ApiService apiService = ApiService();
  final MapController _mapController = MapController();

  bool isLoading = true;
  RouteDetails? routeDetails;
  List<Bus> activeBuses = [];
  Map<int, Map<String, dynamic>> etaMap = {};
  Map<int, LatLng> busPositions = {};
  Timer? _refreshTimer;
  int? selectedBusId;

  @override
  void initState() {
    super.initState();
    loadRouteMapData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => loadRouteMapData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadRouteMapData() async {
    final routeData = await apiService.getRouteDetails(widget.routeId);
    final busesData = await apiService.searchBus("");

    Map<int, LatLng> positions = {};
    for (var b in busesData) {
      final gps = await apiService.getLatestGps(b.id);
      if (gps != null) {
        positions[b.id] = LatLng(gps.latitude, gps.longitude);
      }
    }

    int activeBusId = selectedBusId ?? (busesData.isNotEmpty ? busesData.first.id : 7);
    final busEtaData = await apiService.fetchBusEta(activeBusId);

    if (busEtaData != null && busEtaData["stops_eta"] != null) {
      List stopsEtaList = busEtaData["stops_eta"];
      for (var item in stopsEtaList) {
        int order = item["stop_order"] ?? 0;
        etaMap[order] = item;
      }
    }

    if (!mounted) return;

    setState(() {
      routeDetails = routeData;
      activeBuses = busesData;
      busPositions = positions;
      isLoading = false;
    });
  }

  void _zoomIn() {
    try {
      final currentZoom = _mapController.camera.zoom;
      _mapController.move(_mapController.camera.center, currentZoom + 1.0);
    } catch (_) {}
  }

  void _zoomOut() {
    try {
      final currentZoom = _mapController.camera.zoom;
      _mapController.move(_mapController.camera.center, currentZoom - 1.0);
    } catch (_) {}
  }

  void _recenterRoute() {
    try {
      final mapCenter = LatLng(12.1680284, 75.4628332);
      _mapController.move(mapCenter, 11.2);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || routeDetails == null) {
      return Scaffold(
        backgroundColor: AppTheme.bgMint,
        appBar: AppBar(
          backgroundColor: AppTheme.bgMint,
          title: const Text("Saved Route Map"),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryEmerald),
        ),
      );
    }

    List<LatLng> polylinePoints = routeDetails!.roadPolyline
        .map((s) => LatLng(s.latitude, s.longitude))
        .toList();

    final mapCenter = LatLng(12.1680284, 75.4628332);

    // 1. Build Markers for All 38 Bus Stops with Bus Stop Icon & Name Badge
    List<Marker> markers = [];
    for (int i = 0; i < routeDetails!.stops.length; i++) {
      final stop = routeDetails!.stops[i];
      final stopOrder = i + 1;
      final isTerminal = stopOrder == 1 || stopOrder == 38;

      markers.add(
        Marker(
          point: LatLng(stop.latitude, stop.longitude),
          width: 110,
          height: 65,
          child: GestureDetector(
            onTap: () {
              _mapController.move(LatLng(stop.latitude, stop.longitude), 15.0);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stop Name Label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isTerminal ? AppTheme.primaryEmerald : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryEmerald, width: 1.5),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Text(
                    "#$stopOrder ${stop.stopName}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isTerminal ? Colors.white : AppTheme.primaryEmeraldDark,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // Dedicated Bus Stop Sign Icon
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isTerminal ? AppTheme.primaryEmerald : AppTheme.mintContainer,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: Icon(
                    Icons.hail_rounded, // Bus stop sign icon
                    color: isTerminal ? Colors.white : AppTheme.primaryEmerald,
                    size: isTerminal ? 18 : 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Build Markers for Active Buses (Nayana, Holy Angel, Big Show)
    for (var bus in activeBuses) {
      final livePos = busPositions[bus.id];
      double bLat = livePos?.latitude ?? 12.1353962;
      double bLng = livePos?.longitude ?? 75.4408002;

      final isSelected = selectedBusId == bus.id;

      markers.add(
        Marker(
          point: LatLng(bLat, bLng),
          width: 95,
          height: 72,
          child: GestureDetector(
            onTap: () {
              setState(() => selectedBusId = bus.id);
              _mapController.move(LatLng(bLat, bLng), 14.5);
            },
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.amber.shade800 : AppTheme.primaryEmerald,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  ),
                  child: Text(
                    bus.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.amber : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryEmerald, width: 2),
                  ),
                  child: const Icon(Icons.directions_bus_rounded, color: AppTheme.primaryEmerald, size: 20),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgMint,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMint,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              routeDetails!.routeName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
            ),
            Text(
              "${routeDetails!.stops.length} Bus Stops • ${activeBuses.length} Active Buses",
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.center_focus_strong_rounded, color: AppTheme.primaryEmerald),
            onPressed: _recenterRoute,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Interactive Full Map View
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 11.2,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: "com.trackway.app",
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 4.5,
                    color: AppTheme.primaryEmerald,
                  ),
                ],
              ),
              MarkerLayer(markers: markers),
            ],
          ),

          // Zoom Controls (Floating Zoom In, Zoom Out, Recenter)
          Positioned(
            top: 20,
            right: 16,
            child: Column(
              children: [
                // Zoom In (+)
                FloatingActionButton.small(
                  heroTag: "btn_zoom_in",
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryEmerald,
                  elevation: 4,
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add_rounded, size: 24),
                ),
                const SizedBox(height: 8),
                // Zoom Out (-)
                FloatingActionButton.small(
                  heroTag: "btn_zoom_out",
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryEmerald,
                  elevation: 4,
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove_rounded, size: 24),
                ),
                const SizedBox(height: 8),
                // Recenter Route
                FloatingActionButton.small(
                  heroTag: "btn_recenter",
                  backgroundColor: AppTheme.primaryEmerald,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  onPressed: _recenterRoute,
                  child: const Icon(Icons.my_location_rounded, size: 18),
                ),
              ],
            ),
          ),

          // Floating Glassmorphic Commuter Sheet
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.15,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${routeDetails!.startLocation} ➔ ${routeDetails!.endLocation}",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                "Route Distance: ${routeDetails!.totalDistance} km | 38 Bus Stops",
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.successBg,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              children: [
                                CircleAvatar(radius: 3.5, backgroundColor: AppTheme.successGreen),
                                SizedBox(width: 5),
                                Text(
                                  "LIVE MAP",
                                  style: TextStyle(color: AppTheme.successGreen, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Active Buses Selector
                      const Text(
                        "Active Route Buses on Map",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: activeBuses.map((b) {
                          final isSelected = selectedBusId == b.id;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSelected ? AppTheme.primaryEmerald : Colors.white,
                                  foregroundColor: isSelected ? Colors.white : AppTheme.textPrimary,
                                  elevation: 0,
                                  side: BorderSide(
                                    color: isSelected ? AppTheme.primaryEmerald : const Color(0xFFE6F4ED),
                                  ),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => TrackingScreen(busId: b.id)),
                                  );
                                },
                                child: Column(
                                  children: [
                                    Text(
                                      b.busName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: isSelected ? Colors.white : AppTheme.primaryEmerald,
                                      ),
                                    ),
                                    Text(
                                      b.busNumber,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isSelected ? Colors.white70 : AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // 38 Complete Bus Stops List
                      Text(
                        "Route Station Sequence (${routeDetails!.stops.length} Stops)",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 12),

                      ...List.generate(routeDetails!.stops.length, (index) {
                        final stop = routeDetails!.stops[index];
                        final stopOrder = index + 1;
                        String? etaText;
                        if (etaMap.containsKey(stopOrder)) {
                          etaText = etaMap[stopOrder]!["eta_text"];
                        }
                        final isPassed = etaText == "Passed";

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isPassed ? Colors.grey.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isPassed ? Colors.grey.shade200 : const Color(0xFFE6F4ED)),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isPassed ? Colors.grey.shade200 : AppTheme.mintContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPassed ? Icons.check_circle_rounded : Icons.hail_rounded,
                                color: isPassed ? Colors.grey.shade400 : AppTheme.primaryEmerald,
                                size: 14,
                              ),
                            ),
                            title: Text(
                              "#$stopOrder ${stop.stopName}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isPassed ? Colors.grey.shade600 : AppTheme.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              "Lat: ${stop.latitude.toStringAsFixed(4)}, Lon: ${stop.longitude.toStringAsFixed(4)}",
                              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                            trailing: Text(
                              isPassed ? "Departed" : (etaText ?? "AI ETA"),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isPassed ? Colors.grey.shade500 : AppTheme.primaryEmerald,
                              ),
                            ),
                            onTap: () {
                              _mapController.move(LatLng(stop.latitude, stop.longitude), 15.0);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
