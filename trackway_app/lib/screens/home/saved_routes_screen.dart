import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_theme.dart';
import '../../models/bus.dart';
import '../../models/route_details.dart';
import '../../services/api_service.dart';

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
  String? errorMessage;

  void _showServerConfigDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUrl = prefs.getString("custom_backend_url") ?? "http://10.0.2.2:8000";
    final controller = TextEditingController(text: currentUrl);

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.dns_rounded, color: AppTheme.primaryEmerald),
            SizedBox(width: 10),
            Text("Server Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Enter your server URL or PC IP address for physical phone testing:",
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: "Backend Server URL",
                hintText: "e.g. http://192.168.1.50:8000",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.link_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.remove("custom_backend_url");
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Reset Default"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryEmerald, foregroundColor: Colors.white),
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await prefs.setString("custom_backend_url", url);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() => isLoading = true);
              loadRouteMapData();
            },
            child: const Text("Save & Connect"),
          ),
        ],
      ),
    );
  }

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
    try {
      final routeData = await apiService.getRouteDetails(widget.routeId);
      if (routeData == null) {
        if (!mounted) return;
        setState(() {
          isLoading = false;
          errorMessage ??= "Could not load the route map. Please check your server connection.";
        });
        return;
      }

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
        errorMessage = null;
      });
    } catch (e) {
      debugPrint("Saved Routes Map Load Error: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = "Error connecting to backend server: $e";
      });
    }
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
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_rounded, color: AppTheme.primaryEmerald),
              tooltip: "Configure Server IP",
              onPressed: () => _showServerConfigDialog(context),
            ),
          ],
        ),
        body: Center(
          child: isLoading
              ? const CircularProgressIndicator(color: AppTheme.primaryEmerald)
              : Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 54, color: AppTheme.warningAmber),
                      const SizedBox(height: 16),
                      Text(
                        errorMessage ?? "Could not connect to backend server.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.primaryEmerald, width: 1.5),
                              foregroundColor: AppTheme.primaryEmerald,
                            ),
                            icon: const Icon(Icons.settings_rounded),
                            label: const Text("Server Settings"),
                            onPressed: () => _showServerConfigDialog(context),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryEmerald,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text("Retry"),
                            onPressed: () {
                              setState(() => isLoading = true);
                              loadRouteMapData();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
          height: 75,
          child: GestureDetector(
            onTap: () {
              _mapController.move(LatLng(stop.latitude, stop.longitude), 15.0);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isTerminal ? AppTheme.primaryEmerald : AppTheme.mintContainer,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: Icon(
                    Icons.hail_rounded,
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

    int activeCount = 0;
    for (var bus in activeBuses) {
      if (bus.status != "Active") continue;
      activeCount++;

      final livePos = busPositions[bus.id];
      double bLat = livePos?.latitude ?? 12.1353962;
      double bLng = livePos?.longitude ?? 75.4408002;

      final isSelected = selectedBusId == bus.id;

      markers.add(
        Marker(
          point: LatLng(bLat, bLng),
          width: 95,
          height: 75,
          child: GestureDetector(
            onTap: () {
              setState(() => selectedBusId = bus.id);
              _mapController.move(LatLng(bLat, bLng), 14.5);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            Text(
              "${routeDetails!.stops.length} Bus Stops • $activeCount Active Buses",
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded, color: AppTheme.primaryEmerald),
            tooltip: "Recenter Route",
            onPressed: _recenterRoute,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 11.2,
              minZoom: 9.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.trackway.app',
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

          Positioned(
            right: 16,
            top: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: "zoom_in_btn",
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryEmeraldDark,
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: "zoom_out_btn",
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryEmeraldDark,
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: "recenter_btn",
                  backgroundColor: AppTheme.primaryEmerald,
                  foregroundColor: Colors.white,
                  onPressed: _recenterRoute,
                  child: const Icon(Icons.center_focus_strong_rounded),
                ),
              ],
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.38,
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

                      const Text(
                        "Route Fleet Status",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: activeBuses.map((b) {
                          final isSelected = selectedBusId == b.id;
                          final isActive = b.status == "Active";

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
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                ),
                                onPressed: () {
                                  if (isActive) {
                                    setState(() => selectedBusId = b.id);
                                    final livePos = busPositions[b.id];
                                    if (livePos != null) {
                                      _mapController.move(livePos, 14.5);
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("${b.busName} is currently off-duty / inactive."),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                child: Column(
                                  children: [
                                    Text(
                                      b.busName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: isSelected ? Colors.white : AppTheme.primaryEmerald,
                                      ),
                                    ),
                                    Text(
                                      b.busNumber,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isSelected ? Colors.white70 : AppTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? (isSelected ? Colors.white24 : AppTheme.successBg)
                                            : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isActive ? "Active" : "Inactive",
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isActive
                                              ? (isSelected ? Colors.white : AppTheme.successGreen)
                                              : Colors.grey.shade700,
                                        ),
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
