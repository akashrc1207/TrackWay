import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Calculates initial spherical bearing (in degrees, 0..360) from point A to point B.
class BearingCalculator {
  /// Calculate initial bearing between two [LatLng] points in degrees (0..360)
  static double calculateBearing(LatLng start, LatLng end) {
    return calculateBearingRaw(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  /// Calculate initial bearing between coordinates in degrees (0..360)
  static double calculateBearingRaw(
    double lat1Deg,
    double lon1Deg,
    double lat2Deg,
    double lon2Deg,
  ) {
    if (lat1Deg == lat2Deg && lon1Deg == lon2Deg) {
      return 0.0;
    }

    final lat1 = _toRadians(lat1Deg);
    final lon1 = _toRadians(lon1Deg);
    final lat2 = _toRadians(lat2Deg);
    final lon2 = _toRadians(lon2Deg);

    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    final degrees = _toDegrees(radians);

    return (degrees + 360) % 360;
  }

  /// Smoothly interpolates angle from [from] to [to] handling the 0-360 degree wrap.
  static double lerpAngle(double from, double to, double t) {
    final diff = (to - from + 540) % 360 - 180;
    return (from + diff * t + 360) % 360;
  }

  static double _toRadians(double degree) => degree * (math.pi / 180.0);
  static double _toDegrees(double rad) => rad * (180.0 / math.pi);
}
