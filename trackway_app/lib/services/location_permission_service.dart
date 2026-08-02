import 'package:geolocator/geolocator.dart';

/// Centralised location permission handling.
///
/// Nothing in the app was previously requesting runtime location
/// permission, so `Geolocator` calls would silently fail (return null /
/// throw) on any device where the permission dialog hadn't already been
/// granted through some other means. Screens that need the device's
/// location should call [ensureLocationPermission] before calling into
/// `Geolocator`.
class LocationPermissionResult {
  final bool granted;
  final String? errorMessage;

  const LocationPermissionResult({required this.granted, this.errorMessage});
}

Future<LocationPermissionResult> ensureLocationPermission() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return const LocationPermissionResult(
      granted: false,
      errorMessage: "Location services are turned off. Please enable GPS/location on your device.",
    );
  }

  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    return const LocationPermissionResult(
      granted: false,
      errorMessage: "Location permission was denied. Please allow location access to continue.",
    );
  }

  if (permission == LocationPermission.deniedForever) {
    return const LocationPermissionResult(
      granted: false,
      errorMessage:
          "Location permission is permanently denied. Please enable it from your device's app settings.",
    );
  }

  return const LocationPermissionResult(granted: true);
}
