import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_theme.dart';
import '../../services/gps_broadcast_service.dart';
import '../home/home_screen.dart';
import '../login/login_screen.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  String username = "driver1";
  String busName = "Nayana";
  String busNumber = "KL 59 N 4005";

  @override
  void initState() {
    super.initState();
    GpsBroadcastService.instance.addListener(_onServiceUpdate);
    _loadDriverInfo();
  }

  @override
  void dispose() {
    GpsBroadcastService.instance.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadDriverInfo() async {
    await GpsBroadcastService.instance.init();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      username = prefs.getString("username") ?? "driver1";
      busName = prefs.getString("bus_name") ?? "Nayana";
      busNumber = prefs.getString("bus_number") ?? "KL 59 N 4005";
    });
  }

  @override
  Widget build(BuildContext context) {
    final broadcastService = GpsBroadcastService.instance;
    final tripStarted = broadcastService.isBroadcasting;
    final currentPosition = broadcastService.currentPosition;

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
              await GpsBroadcastService.instance.stopBroadcast();
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
                              Expanded(
                                child: Text(
                                  busName.isNotEmpty ? "Assigned: $busName ($busNumber)" : "Assigned: $busNumber",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 13, fontWeight: FontWeight.w600),
                                ),
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
                    final result = await broadcastService.startBroadcast();

                    if (result["success"] != true) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(result["error"] ?? "Could not start journey session"),
                        ),
                      );
                      return;
                    }
                  } else {
                    final stopped = await broadcastService.stopBroadcast();
                    if (!stopped) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text("Could not stop journey session")),
                      );
                      return;
                    }
                  }
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
                        : "${(currentPosition.speed * 3.6).toStringAsFixed(1)} km/h",
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
                              : "${currentPosition.latitude.toStringAsFixed(5)}, ${currentPosition.longitude.toStringAsFixed(5)}",
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
