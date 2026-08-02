import 'package:flutter/material.dart';
import 'config/app_theme.dart';
import 'screens/login/login_screen.dart';

import 'services/gps_broadcast_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await GpsBroadcastService.instance.init();
  } catch (e) {
    debugPrint("Startup initialization error: $e");
  }
  runApp(const TrackWayApp());
}

class TrackWayApp extends StatelessWidget {
  const TrackWayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TrackWay',
      themeMode: ThemeMode.light,
      theme: AppTheme.lightTheme,
      home: const LoginScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.directions_bus, color: Colors.white, size: 100),
            SizedBox(height: 20),
            Text(
              "TrackWay",
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              "AI Powered Bus Tracking",
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
