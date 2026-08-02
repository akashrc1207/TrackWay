import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_theme.dart';
import '../../services/api_service.dart';
import '../driver/bus_selection_screen.dart';

class DriverLogin extends StatefulWidget {
  const DriverLogin({super.key});

  @override
  State<DriverLogin> createState() => _DriverLoginState();
}

class _DriverLoginState extends State<DriverLogin> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _isCheckingAutoLogin = true;
  String? _savedUsername;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedUsername = prefs.getString("username");
      if (_savedUsername != null && _savedUsername!.isNotEmpty) {
        _usernameController.text = _savedUsername!;
      }
    } catch (e) {
      debugPrint("Error loading saved credentials: $e");
    }

    if (mounted) {
      setState(() {
        _isCheckingAutoLogin = false;
      });
    }
  }

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
            },
            child: const Text("Save & Connect"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your username and password")),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _apiService.login(username, password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result != null && result.containsKey("token")) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("remember_driver", _rememberMe);
      await prefs.setString("username", username);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const BusSelectionScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Login failed. Check your username and password or server IP."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _fillPreset(String user, String pass) {
    setState(() {
      _usernameController.text = user;
      _passwordController.text = pass;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAutoLogin) {
      return Scaffold(
        backgroundColor: AppTheme.bgMint,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryEmerald),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgMint,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMint,
        elevation: 0,
        title: const Text("Driver Portal Login", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: AppTheme.primaryEmerald),
            tooltip: "Configure Server IP",
            onPressed: () => _showServerConfigDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.mintContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.directions_bus_rounded, size: 64, color: AppTheme.primaryEmerald),
            ),
            const SizedBox(height: 16),
            const Text(
              "Driver Portal Sign In",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              "Enter your account credentials to start your trip and broadcast GPS telemetry.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),

            // Username TextField
            TextField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: "Username",
                hintText: "Enter your username",
                prefixIcon: const Icon(Icons.person_rounded, color: AppTheme.primaryEmerald),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.primaryEmerald, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Password TextField
            TextField(
              controller: _passwordController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleLogin(),
              decoration: InputDecoration(
                labelText: "Password",
                hintText: "Enter your password",
                prefixIcon: const Icon(Icons.lock_rounded, color: AppTheme.primaryEmerald),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.primaryEmerald, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Remember Me Option
            Row(
              children: [
                Checkbox(
                  value: _rememberMe,
                  activeColor: AppTheme.primaryEmerald,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: (val) {
                    setState(() => _rememberMe = val ?? true);
                  },
                ),
                const Text(
                  "Remember username",
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                ),
              ],
            ),

            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryEmerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isLoading ? null : _handleLogin,
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        "Sign In as Driver",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            // Quick Preset Chips for testing
            const Text(
              "Quick Demo Accounts (Tap to fill):",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.badge, size: 16, color: AppTheme.primaryEmerald),
                  label: const Text("driver1", style: TextStyle(fontSize: 12)),
                  onPressed: () => _fillPreset("driver1", "driver123"),
                ),
                ActionChip(
                  avatar: const Icon(Icons.badge, size: 16, color: AppTheme.primaryEmerald),
                  label: const Text("driver2", style: TextStyle(fontSize: 12)),
                  onPressed: () => _fillPreset("driver2", "driver123"),
                ),
                ActionChip(
                  avatar: const Icon(Icons.badge, size: 16, color: AppTheme.primaryEmerald),
                  label: const Text("driver3", style: TextStyle(fontSize: 12)),
                  onPressed: () => _fillPreset("driver3", "driver123"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
