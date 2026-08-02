import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/route_details.dart';
import '../../services/api_service.dart';
import '../tracking/tracking_screen.dart';

class RouteDetailsScreen extends StatefulWidget {
  final int busId;
  final String busName;
  final String busNumber;
  final int routeId;
  final String status;
  final int capacity;

  const RouteDetailsScreen({
    super.key,
    required this.busId,
    this.busName = "",
    required this.busNumber,
    required this.routeId,
    required this.status,
    required this.capacity,
  });

  @override
  State<RouteDetailsScreen> createState() => _RouteDetailsScreenState();
}

class _RouteDetailsScreenState extends State<RouteDetailsScreen> {
  final ApiService apiService = ApiService();

  RouteDetails? routeDetails;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadRouteDetails();
  }

  Future<void> loadRouteDetails() async {
    try {
      final data = await apiService.getRouteDetails(widget.routeId);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          isLoading = false;
          errorMessage = "Could not load route details. Please check your connection and try again.";
        });
        return;
      }
      setState(() {
        routeDetails = data;
        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      debugPrint("Route Details Load Error: $e");
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = "Could not load route details. Please check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.bgMint,
        appBar: AppBar(title: const Text("Route Details")),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primaryEmerald)),
      );
    }

    if (errorMessage != null || routeDetails == null) {
      return Scaffold(
        backgroundColor: AppTheme.bgMint,
        appBar: AppBar(title: const Text("Route Details")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 54, color: AppTheme.warningAmber),
                const SizedBox(height: 16),
                Text(
                  errorMessage ?? "Route details are unavailable.",
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
                  label: const Text("Retry"),
                  onPressed: () {
                    setState(() => isLoading = true);
                    loadRouteDetails();
                  },
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
        title: Text(
          "Route: ${routeDetails?.routeName ?? ''}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Executive Commuter Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE6F4ED)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.06),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.mintContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.directions_bus_rounded, color: AppTheme.primaryEmerald, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.busName.isNotEmpty ? "${widget.busName} (${widget.busNumber})" : widget.busNumber,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              "Route ID #${widget.routeId} • Cap ${widget.capacity}",
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.successBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.status.isNotEmpty ? widget.status : "Active",
                          style: const TextStyle(
                            color: AppTheme.successGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Divider(height: 1, color: Color(0xFFE6F4ED)),
                  ),

                  Row(
                    children: [
                      const Icon(Icons.alt_route_rounded, color: AppTheme.primaryEmerald, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "${routeDetails!.startLocation}  →  ${routeDetails!.endLocation}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                        ),
                      ),
                      Text(
                        "${routeDetails!.totalDistance} km",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryEmerald, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "Route Station Sequence",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),

            const SizedBox(height: 12),

            ...routeDetails!.stops.map(
              (stop) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE6F4ED)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.mintContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_on_rounded, color: AppTheme.primaryEmerald, size: 18),
                  ),
                  title: Text(
                    stop.stopName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                  ),
                  subtitle: Text(
                    "Coordinates: ${stop.latitude.toStringAsFixed(4)}, ${stop.longitude.toStringAsFixed(4)}",
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryEmerald,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.my_location_rounded),
                label: const Text("TRACK LIVE BUS POSITION", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrackingScreen(busId: widget.busId),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
