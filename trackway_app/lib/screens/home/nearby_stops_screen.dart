import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/app_theme.dart';
import '../../models/route_details.dart';
import '../../models/route_stop.dart';
import '../../services/api_service.dart';
import '../tracking/tracking_screen.dart';

class NearbyStopsScreen extends StatefulWidget {
  final int routeId;
  const NearbyStopsScreen({super.key, this.routeId = 1});

  @override
  State<NearbyStopsScreen> createState() => _NearbyStopsScreenState();
}

class NearbyStopsItem {
  final RouteStop stop;
  final int stopOrder;
  final double distanceKm;
  final String? etaText;
  final double? etaMinutes;

  NearbyStopsItem({
    required this.stop,
    required this.stopOrder,
    required this.distanceKm,
    this.etaText,
    this.etaMinutes,
  });
}

class _NearbyStopsScreenState extends State<NearbyStopsScreen> {
  final ApiService apiService = ApiService();
  bool isLoading = true;
  RouteDetails? routeDetails;
  List<NearbyStopsItem> nearbyStops = [];
  Map<int, Map<String, dynamic>> etaMap = {};

  // User location or default central route coordinate (Oduvallythattu)
  double userLat = 12.1353962;
  double userLng = 75.4408002;
  String locationStatus = "GPS Active";

  String activeFilter = "Nearest 5";

  @override
  void initState() {
    super.initState();
    initLocationAndLoadStops();
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * (pi / 180.0);
    final dLon = (lon2 - lon1) * (pi / 180.0);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180.0)) * cos(lat2 * (pi / 180.0)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  Future<void> initLocationAndLoadStops() async {
    try {
      Position? pos = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2));
      if (pos != null) {
        userLat = pos.latitude;
        userLng = pos.longitude;
        locationStatus = "Live GPS";
      } else {
        locationStatus = "Route Center";
      }
    } catch (_) {
      locationStatus = "Route Center";
    }

    try {
      final data = await apiService.getRouteDetails(widget.routeId);
      final busesData = await apiService.searchBus("");

      int activeBusId = 7;
      if (busesData.isNotEmpty) {
        activeBusId = busesData.first.id;
      }

      final busEtaData = await apiService.fetchBusEta(activeBusId);

      if (busEtaData != null && busEtaData["stops_eta"] != null) {
        List stopsEtaList = busEtaData["stops_eta"];
        for (var item in stopsEtaList) {
          int order = item["stop_order"] ?? 0;
          etaMap[order] = item;
        }
      }

      List<NearbyStopsItem> items = [];
      for (int i = 0; i < data.stops.length; i++) {
        final stop = data.stops[i];
        final stopOrder = i + 1;
        final dist = _haversine(userLat, userLng, stop.latitude, stop.longitude);

        String? etaText;
        double? etaMinutes;
        if (etaMap.containsKey(stopOrder)) {
          etaText = etaMap[stopOrder]!["eta_text"];
          etaMinutes = (etaMap[stopOrder]!["eta_minutes"] as num?)?.toDouble();
        }

        items.add(NearbyStopsItem(
          stop: stop,
          stopOrder: stopOrder,
          distanceKm: dist,
          etaText: etaText,
          etaMinutes: etaMinutes,
        ));
      }

      // Sort by proximity to user
      items.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

      if (!mounted) return;
      setState(() {
        routeDetails = data;
        nearbyStops = items;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Load Nearby Stops Error: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  List<NearbyStopsItem> get filteredStops {
    if (activeFilter == "Nearest 5") {
      return nearbyStops.take(5).toList();
    } else if (activeFilter == "Nearest 10") {
      return nearbyStops.take(10).toList();
    } else {
      return nearbyStops;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMint,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMint,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Nearby Route Stops",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textPrimary),
            ),
            Text(
              routeDetails != null
                  ? "${routeDetails!.routeName} (${routeDetails!.stops.length} Stops)"
                  : "Thaliparamba ➔ Cherupuzha",
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.successBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gps_fixed_rounded, color: AppTheme.successGreen, size: 14),
                const SizedBox(width: 4),
                Text(
                  locationStatus,
                  style: const TextStyle(color: AppTheme.successGreen, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryEmerald))
          : Column(
              children: [
                // Filter Chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: ["Nearest 5", "Nearest 10", "All Stops"].map((filter) {
                      final isSelected = activeFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryEmerald,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isSelected ? AppTheme.primaryEmerald : const Color(0xFFE6F4ED),
                            ),
                          ),
                          onSelected: (_) => setState(() => activeFilter = filter),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Stops List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredStops.length,
                    itemBuilder: (context, index) {
                      final item = filteredStops[index];
                      final distFormatted = item.distanceKm < 1.0
                          ? "${(item.distanceKm * 1000).round()} m"
                          : "${item.distanceKm.toStringAsFixed(1)} km";

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: index == 0 ? AppTheme.primaryEmerald : const Color(0xFFE6F4ED)),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryEmerald.withValues(alpha: index == 0 ? 0.08 : 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: index == 0 ? AppTheme.primaryEmerald : AppTheme.mintContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    color: index == 0 ? Colors.white : AppTheme.primaryEmerald,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            item.stop.stopName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          if (index == 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryEmerald,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                "CLOSEST",
                                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Stop #${item.stopOrder} on route",
                                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.mintContainer,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    distFormatted,
                                    style: const TextStyle(
                                      color: AppTheme.primaryEmerald,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(height: 1, color: Color(0xFFE6F4ED)),
                            ),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryEmerald, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      item.etaText != null ? "AI ETA: ${item.etaText}" : "AI ETA: Calculating...",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: AppTheme.primaryEmerald,
                                      ),
                                    ),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryEmerald,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.my_location_rounded, size: 14),
                                  label: const Text("Track Bus", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const TrackingScreen(busId: 1)),
                                    );
                                  },
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
            ),
    );
  }
}
