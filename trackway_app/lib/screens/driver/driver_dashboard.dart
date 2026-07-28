import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_theme.dart';
import '../../services/api_service.dart';
import '../home/home_screen.dart';
import '../login/login_screen.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool tripStarted = false;
  int? activeJourneyId;
  String username = "Driver";
  String busNumber = "KL59J1234";

  final ApiService apiService = ApiService();
  Timer? timer;
  Position? currentPosition;

  @override
  void initState() {
    super.initState();
    _loadDriverInfo();
  }

  Future<void> _loadDriverInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString("username") ?? "Driver";
      busNumber = prefs.getString("bus_number") ?? "KL59J1234";
    });
  }

  Future<void> sendGps() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location services are disabled on device")),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Location permissions are denied")),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permissions permanently denied")),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition();

      if (!mounted) return;
      setState(() {
        currentPosition = position;
      });

      // Convert speed from m/s to km/h (multiply by 3.6)
      final speedKmh = position.speed * 3.6;

      await apiService.uploadGps(
        latitude: position.latitude,
        longitude: position.longitude,
        speed: double.parse(speedKmh.toStringAsFixed(1)),
      );
    } catch (e) {
      debugPrint("sendGps Error: $e");
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMint,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMint,
        title: const Text("Driver Control Hub", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: AppTheme.primaryEmerald),
            tooltip: "Passenger View",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: "Log Out",
            onPressed: () async {
              timer?.cancel();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Driver Profile Header Card
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryEmerald, Color(0xFF047857), Color(0xFF064E3B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.badge_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.directions_bus_rounded, color: Color(0xFFD1FAE5), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                "Assigned: $busNumber",
                                style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: tripStarted ? Colors.white : Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tripStarted ? "ON DUTY" : "OFF DUTY",
                        style: TextStyle(
                          color: tripStarted ? AppTheme.primaryEmeraldDark : Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Live Duty Toggle Button
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tripStarted ? Colors.redAccent : AppTheme.primaryEmerald,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: Icon(tripStarted ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded, size: 28),
                label: Text(
                  tripStarted ? "END TRIP BROADCAST" : "START TRIP BROADCAST",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (!tripStarted) {
                    final result = await apiService.startJourney();

                    if (result["success"] != true) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(result["error"] ?? "Could not start journey session"),
                        ),
                      );
                      return;
                    }

                    activeJourneyId = result["id"] as int?;
                    await sendGps();

                    timer = Timer.periodic(
                      const Duration(seconds: 4),
                      (_) => sendGps(),
                    );
                  } else {
                    final stopped = await apiService.stopJourney();
                    if (!stopped) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text("Could not stop journey session")),
                      );
                      return;
                    }

                    timer?.cancel();
                    timer = null;
                    activeJourneyId = null;
                  }

                  if (!mounted) return;
                  setState(() {
                    tripStarted = !tripStarted;
                  });
                },
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "Live Telemetry Stream",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),

            const SizedBox(height: 12),

            // Telemetry Cards Grid
            Row(
              children: [
                Expanded(
                  child: TelemetryCard(
                    icon: Icons.wifi_tethering_rounded,
                    title: "Broadcast Signal",
                    value: tripStarted ? "Streaming" : "Paused",
                    subtitle: tripStarted ? "Interval 4 sec" : "GPS Inactive",
                    valueColor: tripStarted ? AppTheme.successGreen : AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TelemetryCard(
                    icon: Icons.speed_rounded,
                    title: "Vehicle Speed",
                    value: currentPosition == null
                        ? "0.0 km/h"
                        : "${(currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h",
                    subtitle: "Satellite GPS",
                    valueColor: AppTheme.primaryEmerald,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE6F4ED)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.mintContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.my_location_rounded, color: AppTheme.primaryEmerald),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "GPS Coordinates",
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentPosition == null
                              ? "Acquiring satellite signal..."
                              : "${currentPosition!.latitude.toStringAsFixed(5)}, ${currentPosition!.longitude.toStringAsFixed(5)}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TelemetryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color valueColor;

  const TelemetryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6F4ED)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryEmerald.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: AppTheme.primaryEmerald, size: 22),
              CircleAvatar(radius: 4, backgroundColor: valueColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: valueColor),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
