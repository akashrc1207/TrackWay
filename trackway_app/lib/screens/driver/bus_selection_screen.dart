import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_theme.dart';
import '../../models/bus.dart';
import '../../services/api_service.dart';
import '../../services/gps_broadcast_service.dart';
import 'driver_dashboard.dart';
import '../login/login_screen.dart';

class BusSelectionScreen extends StatefulWidget {
  const BusSelectionScreen({super.key});

  @override
  State<BusSelectionScreen> createState() => _BusSelectionScreenState();
}

class _BusSelectionScreenState extends State<BusSelectionScreen> {
  final ApiService _apiService = ApiService();
  List<Bus> _buses = [];
  bool _isLoading = true;
  int? _selectedBusId;
  String _driverUsername = "Driver";

  @override
  void initState() {
    super.initState();
    _loadDriverAndBuses();
  }

  Future<void> _loadDriverAndBuses() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    final activeJourney = await _apiService.getActiveJourney();
    if (activeJourney != null && activeJourney["has_active_journey"] == true) {
      final journeyId = int.tryParse(activeJourney["journey_id"].toString());
      final busId = int.tryParse(activeJourney["bus_id"].toString());
      if (journeyId != null && busId != null) {
        await GpsBroadcastService.instance.restoreActiveSession(
          activeJourneyId: journeyId,
          busId: busId,
          busName: activeJourney["bus_name"]?.toString(),
          busNumber: activeJourney["bus_number"]?.toString(),
          routeName: activeJourney["route_name"]?.toString(),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverDashboard()),
        );
        return;
      }
    }

    final savedUsername = prefs.getString("username") ?? "Driver";
    final savedBusId = prefs.getInt("selected_bus_id");

    final buses = await _apiService.getAvailableBuses();

    if (!mounted) return;
    setState(() {
      _driverUsername = savedUsername;
      _buses = buses;
      _selectedBusId = savedBusId ?? (buses.isNotEmpty ? buses.first.id : null);
      _isLoading = false;
    });
  }

  Future<void> _confirmSelection(Bus bus) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("selected_bus_id", bus.id);
    await prefs.setString("bus_name", bus.busName);
    await prefs.setString("bus_number", bus.busNumber);
    await prefs.setString("route_name", bus.routeName);

    // Pre-fetch and cache route terminal details for instant 0ms validation
    try {
      final details = await _apiService.getRouteDetails(bus.routeId);
      if (details != null) {
        GpsBroadcastService.instance.setCachedRouteDetails(details);
      }
    } catch (e) {
      debugPrint("Pre-cache route details error: $e");
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DriverDashboard()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMint,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMint,
        elevation: 0,
        title: const Text("Select Bus", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryEmerald),
            tooltip: "Refresh Available Buses",
            onPressed: _loadDriverAndBuses,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: "Log Out",
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Driver Welcome Banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryEmerald, Color(0xFF047857), Color(0xFF064E3B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.badge_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome, $_driverUsername!",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Select an available bus for your active shift:",
                          style: TextStyle(color: Color(0xFFD1FAE5), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Available Buses List Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.directions_bus_filled_rounded, size: 20, color: AppTheme.primaryEmerald),
                  const SizedBox(width: 8),
                  Text(
                    "AVAILABLE FLEET (${_buses.length})",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),

            // Buses List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryEmerald))
                  : _buses.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.directions_bus_outlined, size: 56, color: AppTheme.warningAmber),
                                const SizedBox(height: 16),
                                const Text(
                                  "No buses currently available for assignment.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _loadDriverAndBuses,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text("Refresh List"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryEmerald,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadDriverAndBuses,
                          color: AppTheme.primaryEmerald,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            itemCount: _buses.length,
                            itemBuilder: (context, index) {
                              final bus = _buses[index];
                              final isSelected = bus.id == _selectedBusId;

                              return InkWell(
                                onTap: () {
                                  setState(() => _selectedBusId = bus.id);
                                },
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: isSelected ? AppTheme.primaryEmerald : Colors.transparent,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isSelected
                                            ? AppTheme.primaryEmerald.withValues(alpha: 0.15)
                                            : Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: isSelected ? AppTheme.mintContainer : AppTheme.bgMint,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.directions_bus_rounded,
                                              color: isSelected ? AppTheme.primaryEmerald : AppTheme.textSecondary,
                                              size: 26,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  bus.busName.isNotEmpty ? bus.busName : bus.busNumber,
                                                  style: const TextStyle(
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  bus.busNumber,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: AppTheme.textSecondary,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Selection Radio / Badge
                                          Radio<int>(
                                            value: bus.id,
                                            groupValue: _selectedBusId,
                                            activeColor: AppTheme.primaryEmerald,
                                            onChanged: (val) {
                                              setState(() => _selectedBusId = val);
                                            },
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 20),
                                      Row(
                                        children: [
                                          const Icon(Icons.alt_route_rounded, size: 16, color: AppTheme.primaryEmerald),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              bus.routeName,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.mintContainer,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              "Cap: ${bus.capacity}",
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryEmerald),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      ElevatedButton(
                                        onPressed: () => _confirmSelection(bus),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isSelected ? AppTheme.primaryEmerald : const Color(0xFFE2E8F0),
                                          foregroundColor: isSelected ? Colors.white : AppTheme.textPrimary,
                                          minimumSize: const Size(double.infinity, 44),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: isSelected ? 2 : 0,
                                        ),
                                        child: Text(
                                          isSelected ? "Confirm & Continue with ${bus.busName.isNotEmpty ? bus.busName : bus.busNumber}" : "Select Bus",
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
