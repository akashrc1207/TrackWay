import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/bus.dart';
import '../../services/api_service.dart';
import '../tracking/tracking_screen.dart';

class ActiveBusesScreen extends StatefulWidget {
  const ActiveBusesScreen({super.key});

  @override
  State<ActiveBusesScreen> createState() => _ActiveBusesScreenState();
}

class _ActiveBusesScreenState extends State<ActiveBusesScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Bus> _buses = [];

  @override
  void initState() {
    super.initState();
    _loadActiveBuses();
  }

  Future<void> _loadActiveBuses() async {
    setState(() => _loading = true);
    final buses = await _api.getBuses();
    final active = buses.where((b) => b.status.toLowerCase() == 'active').toList();
    if (!mounted) return;
    setState(() {
      _buses = active;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgMint,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMint,
        title: const Text('Live Buses', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryEmerald),
            onPressed: _loadActiveBuses,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryEmerald))
          : _buses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.directions_bus_filled_rounded, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No active buses available', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _buses.length,
                  itemBuilder: (context, index) {
                    final bus = _buses[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TrackingScreen(busId: bus.id),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                height: 56,
                                width: 56,
                                decoration: BoxDecoration(
                                  color: AppTheme.mintContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.directions_bus_rounded, color: AppTheme.primaryEmerald, size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(bus.displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                    const SizedBox(height: 6),
                                    Text('Route ${bus.route} • ${bus.status}', style: const TextStyle(color: AppTheme.textSecondary)),
                                    const SizedBox(height: 6),
                                    Text('Tap to view stops', style: TextStyle(color: AppTheme.primaryEmerald.withValues(alpha: 0.9), fontSize: 12)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: AppTheme.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
