/// Centralized Configuration Constants for TrackWay Flutter App
class AppConfig {
  /// GPS position polling interval for passenger tracking screen (milliseconds)
  static const int gpsPollIntervalMs = 2500;

  /// ETA recalculation polling interval for passenger tracking screen (milliseconds)
  static const int etaRefreshIntervalMs = 25000;

  /// Maximum acceptable GPS accuracy in meters.
  /// Readings with accuracy worse than this will be rejected.
  static const double maxGpsAccuracyMeters = 50.0;

  /// Maximum physically possible speed for a bus in km/h.
  static const double maxSpeedKmh = 130.0;

  /// Maximum allowable position jump in meters within 3 seconds.
  static const double maxJumpMetersPer3Sec = 200.0;

  /// Seconds before a GPS signal is flagged as "stale" (weak)
  static const int signalStaleThresholdSec = 15;

  /// Seconds before a GPS signal is flagged as "lost" (offline)
  static const int signalLostThresholdSec = 45;

  /// Rolling position queue max capacity for smooth map animation
  static const int positionQueueCapacity = 5;
}
