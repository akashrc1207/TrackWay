import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_theme.dart';
import '../../services/tracking_engine.dart';

class TrackingScreen extends StatefulWidget {
  final int busId;

  const TrackingScreen({super.key, required this.busId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> with SingleTickerProviderStateMixin {
  late TrackingEngine _engine;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _engine = TrackingEngine(busId: widget.busId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _engine.initialize(this, _mapController);
    });
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _engine.isLoadingNotifier,
      builder: (context, isLoading, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: _engine.errorMessageNotifier,
          builder: (context, errorMsg, _) {
            if (isLoading || _engine.gpsLocationNotifier.value == null || _engine.etaDataNotifier.value == null) {
              return Scaffold(
                backgroundColor: AppTheme.bgMint,
                appBar: AppBar(title: Text("Tracking Bus #${widget.busId}")),
                body: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppTheme.primaryEmerald),
                      SizedBox(height: 16),
                      Text(
                        "Connecting to live bus telemetry & route ETAs...",
                        style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (_engine.gpsLocationNotifier.value == null) {
              return Scaffold(
                backgroundColor: AppTheme.bgMint,
                appBar: AppBar(title: Text("Tracking Bus #${widget.busId}")),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: AppTheme.warningBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_off_rounded, size: 54, color: AppTheme.warningAmber),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          errorMsg ?? "No GPS location signal available yet.",
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
                          label: const Text("Retry Connection"),
                          onPressed: () => _engine.loadInitialData(_mapController),
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
                title: ValueListenableBuilder<Map<String, dynamic>?>(
                  valueListenable: _engine.etaDataNotifier,
                  builder: (context, etaData, _) {
                    final busName = etaData?['bus_name'];
                    final busNum = etaData?['bus_number'];
                    final titleText = (busName != null && busNum != null)
                        ? "$busName ($busNum)"
                        : "Live Bus #${widget.busId}";
                    return Text(
                      titleText,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    );
                  },
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryEmerald),
                    onPressed: () => _engine.loadInitialData(_mapController),
                  ),
                ],
              ),
              body: Stack(
                children: [
                  // Interactive Map Layer
                  ValueListenableBuilder<LatLng?>(
                    valueListenable: _engine.animatedPosNotifier,
                    builder: (context, initialPos, _) {
                      final centerPos = initialPos ?? LatLng(12.0369964, 75.3600476);
                      return FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: centerPos,
                          initialZoom: 14.5,
                          onMapEvent: (event) {
                            if (event is MapEventMoveStart) {
                              _engine.onUserMapGesture();
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                            userAgentPackageName: "com.trackway.app",
                          ),

                          // Traveled vs Remaining Polyline Segment Layer
                          ValueListenableBuilder<List<LatLng>>(
                            valueListenable: _engine.travelledPolylineNotifier,
                            builder: (context, travelled, _) {
                              return ValueListenableBuilder<List<LatLng>>(
                                valueListenable: _engine.remainingPolylineNotifier,
                                builder: (context, remaining, _) {
                                  return PolylineLayer(
                                    polylines: [
                                      if (travelled.isNotEmpty)
                                        Polyline(
                                          points: travelled,
                                          strokeWidth: 4.5,
                                          color: Colors.grey.shade500,
                                        ),
                                      if (remaining.isNotEmpty)
                                        Polyline(
                                          points: remaining,
                                          strokeWidth: 6.0,
                                          color: AppTheme.primaryEmerald,
                                        ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),

                          // Bus & Stop Markers Layer
                          ValueListenableBuilder<Map<String, dynamic>?>(
                            valueListenable: _engine.etaDataNotifier,
                            builder: (context, etaData, _) {
                              final stops = (etaData?["stops_eta"] as List?) ?? [];
                               int nextStopIndex = -1;
                              for (int i = 0; i < stops.length; i++) {
                                final sStatus = stops[i]["status"] as String? ?? "";
                                final sEtaText = stops[i]["eta_text"] as String? ?? "";
                                final isDep = sStatus == "departed" || sEtaText.contains("Departed") || sEtaText.contains("Passed");
                                if (!isDep) {
                                  nextStopIndex = i;
                                  break;
                                }
                              }

                              List<Marker> stopMarkers = [];
                              for (int i = 0; i < stops.length; i++) {
                                final stop = stops[i];
                                final stopLat = stop["latitude"] as double?;
                                final stopLng = stop["longitude"] as double?;
                                final stopName = stop["stop_name"] as String? ?? "Stop";
                                final etaText = stop["eta_text"] as String? ?? "";
                                final status = stop["status"] as String? ?? "";
                                final isDeparted = status == "departed" || etaText.contains("Departed") || etaText.contains("Passed");
                                final isArriving = status == "arriving" || etaText == "At Stop";
                                final isNext = i == nextStopIndex;

                                final arrivalTime = stop["arrival_time"] as String? ?? "";

                                Color badgeBg = AppTheme.primaryEmerald;
                                String badgeLabel = arrivalTime.isNotEmpty && arrivalTime != "Passed" && arrivalTime != "Now"
                                    ? "ETA $etaText • $arrivalTime"
                                    : "ETA $etaText";
                                IconData markerIcon = Icons.location_on_outlined;
                                Color iconColor = AppTheme.primaryEmerald;

                                if (isDeparted) {
                                  badgeBg = Colors.grey.shade600;
                                  badgeLabel = "Departed";
                                  markerIcon = Icons.check_circle_rounded;
                                  iconColor = Colors.grey.shade500;
                                } else if (isArriving) {
                                  badgeBg = Colors.amber.shade800;
                                  badgeLabel = "AT STOP";
                                  markerIcon = Icons.directions_bus_rounded;
                                  iconColor = Colors.amber.shade800;
                                } else if (isNext) {
                                  badgeBg = AppTheme.primaryEmerald;
                                  badgeLabel = arrivalTime.isNotEmpty && arrivalTime != "Passed" && arrivalTime != "Now"
                                      ? "NEXT: $etaText ($arrivalTime)"
                                      : "NEXT: $etaText";
                                  markerIcon = Icons.location_on;
                                  iconColor = AppTheme.primaryEmerald;
                                }

                                if (stopLat != null && stopLng != null) {
                                  stopMarkers.add(
                                    Marker(
                                      point: LatLng(stopLat, stopLng),
                                      width: (isNext || isArriving) ? 145 : 125,
                                      height: (isNext || isArriving) ? 92 : 82,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: (isNext || isArriving) ? 8 : 6,
                                              vertical: (isNext || isArriving) ? 4 : 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badgeBg,
                                              borderRadius: BorderRadius.circular(10),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (isNext || isArriving) ? Colors.amber.withValues(alpha: 0.4) : Colors.black26,
                                                  blurRadius: (isNext || isArriving) ? 6 : 3,
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              badgeLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: (isNext || isArriving) ? 10.5 : 9.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            markerIcon,
                                            color: iconColor,
                                            size: (isNext || isArriving) ? 26 : 20,
                                          ),
                                          Text(
                                            stopName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: (isNext || isArriving) ? 10.5 : 9.5,
                                              fontWeight: (isNext || isArriving) ? FontWeight.w900 : FontWeight.bold,
                                              color: isDeparted ? Colors.grey.shade600 : AppTheme.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              }

                              return ValueListenableBuilder<LatLng?>(
                                valueListenable: _engine.animatedPosNotifier,
                                builder: (context, busPos, _) {
                                  return ValueListenableBuilder<double>(
                                    valueListenable: _engine.bearingNotifier,
                                    builder: (context, bearing, _) {
                                      final currentBusPos = busPos ?? LatLng(12.0369964, 75.3600476);
                                      return MarkerLayer(
                                        markers: [
                                          // Rotated Directional Bus Marker
                                          Marker(
                                            point: currentBusPos,
                                            width: 66,
                                            height: 66,
                                            child: Transform.rotate(
                                              angle: bearing * (math.pi / 180.0),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primaryEmerald,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 3.5),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppTheme.primaryEmerald.withValues(alpha: 0.5),
                                                      blurRadius: 14,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.navigation_rounded,
                                                  color: Colors.white,
                                                  size: 32,
                                                ),
                                              ),
                                            ),
                                          ),
                                          ...stopMarkers,
                                        ],
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  // Floating Map Controls Column (Zoom In, Zoom Out, Auto-Follow)
                  Positioned(
                    right: 16,
                    bottom: 215,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: "zoom_in_fab",
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.textPrimary,
                          elevation: 4,
                          onPressed: () {
                            final center = _mapController.camera.center;
                            final zoom = _mapController.camera.zoom;
                            _mapController.move(center, (zoom + 0.75).clamp(3.0, 19.0));
                          },
                          child: const Icon(Icons.add_rounded, size: 22),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: "zoom_out_fab",
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.textPrimary,
                          elevation: 4,
                          onPressed: () {
                            final center = _mapController.camera.center;
                            final zoom = _mapController.camera.zoom;
                            _mapController.move(center, (zoom - 0.75).clamp(3.0, 19.0));
                          },
                          child: const Icon(Icons.remove_rounded, size: 22),
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: _engine.autoFollowNotifier,
                          builder: (context, autoFollow, _) {
                            return FloatingActionButton.small(
                              heroTag: "auto_follow_fab",
                              backgroundColor: autoFollow ? AppTheme.primaryEmerald : Colors.white,
                              foregroundColor: autoFollow ? Colors.white : AppTheme.textPrimary,
                              elevation: 4,
                              onPressed: _engine.toggleAutoFollow,
                              child: Icon(
                                autoFollow ? Icons.my_location_rounded : Icons.location_disabled_rounded,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Bottom Timeline Card
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: ValueListenableBuilder<Map<String, dynamic>?>(
                      valueListenable: _engine.etaDataNotifier,
                      builder: (context, etaData, _) {
                        final stops = (etaData?["stops_eta"] as List?) ?? [];
                        int nextStopIndex = -1;
                        for (int i = 0; i < stops.length; i++) {
                          final sStatus = stops[i]["status"] as String? ?? "";
                          final sEtaText = stops[i]["eta_text"] as String? ?? "";
                          final isDep = sStatus == "departed" || sEtaText.contains("Departed") || sEtaText.contains("Passed");
                          if (!isDep) {
                            nextStopIndex = i;
                            break;
                          }
                        }

                        final confidence = nextStopIndex >= 0 ? stops[nextStopIndex]["confidence"] as num? : null;
                        final confidenceText = confidence != null ? "${(confidence * 100).toInt()}% Confident" : "AI Predicted";

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFE6F4ED)),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryEmerald.withValues(alpha: 0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.mintContainer,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(Icons.speed_rounded, color: AppTheme.primaryEmerald, size: 26),
                                    ),
                                    const SizedBox(width: 14),
                                    ValueListenableBuilder(
                                      valueListenable: _engine.gpsLocationNotifier,
                                      builder: (context, gps, _) {
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "${gps?.speed ?? 0.0} km/h",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 20,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              etaData?['direction_name'] ?? etaData?['route_name'] ?? 'Thaliparamba to Cherupuzha',
                                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    const Spacer(),

                                    // Signal Status Badge
                                    ValueListenableBuilder<String>(
                                      valueListenable: _engine.signalStatusNotifier,
                                      builder: (context, signalStatus, _) {
                                        final isLive = signalStatus == "live";
                                        final isStale = signalStatus == "stale";
                                        final badgeColor = isLive
                                            ? AppTheme.successGreen
                                            : (isStale ? Colors.amber.shade800 : Colors.red.shade700);

                                        final badgeText = isLive
                                            ? "SMOOTH LIVE"
                                            : (isStale ? "SIGNAL WEAK" : "GPS LOST");

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: badgeColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircleAvatar(radius: 3.5, backgroundColor: badgeColor),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    badgeText,
                                                    style: TextStyle(
                                                      color: badgeColor,
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              confidenceText,
                                              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),

                                if (stops.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12.0),
                                    child: Divider(height: 1, color: Color(0xFFE6F4ED)),
                                  ),

                                  // Station Timeline
                                  SizedBox(
                                    height: 72,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: stops.length,
                                      itemBuilder: (context, index) {
                                        final s = stops[index];
                                        final etaText = s["eta_text"] ?? "";
                                        final status = s["status"] ?? "";
                                        final isDeparted = status == "departed" || etaText.contains("Departed") || etaText.contains("Passed");
                                        final isArriving = status == "arriving" || etaText == "At Stop";
                                        final isNext = index == nextStopIndex;

                                        Color cardBg = Colors.white;
                                        Color borderColor = const Color(0xFFE6F4ED);
                                        IconData iconData = Icons.radio_button_checked_rounded;
                                        Color iconColor = AppTheme.primaryEmeraldDark;

                                        if (isDeparted) {
                                          cardBg = Colors.grey.shade100;
                                          borderColor = Colors.grey.shade300;
                                          iconData = Icons.check_circle_rounded;
                                          iconColor = Colors.grey.shade400;
                                        } else if (isArriving) {
                                          cardBg = Colors.amber.shade50;
                                          borderColor = Colors.amber.shade400;
                                          iconData = Icons.directions_bus_rounded;
                                          iconColor = Colors.amber.shade900;
                                        } else if (isNext) {
                                          cardBg = AppTheme.mintContainer;
                                          borderColor = AppTheme.primaryEmerald;
                                          iconData = Icons.directions_bus_rounded;
                                          iconColor = AppTheme.primaryEmerald;
                                        }

                                        return Container(
                                          margin: const EdgeInsets.only(right: 10),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: cardBg,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: borderColor,
                                              width: (isNext || isArriving) ? 1.5 : 1.0,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                iconData,
                                                color: iconColor,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        s["stop_name"] ?? "",
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                          color: isDeparted ? Colors.grey.shade600 : AppTheme.textPrimary,
                                                        ),
                                                      ),
                                                      if (isArriving) ...[
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.amber.shade800,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: const Text(
                                                            "AT STOP",
                                                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                      ] else if (isNext) ...[
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: AppTheme.primaryEmerald,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: const Text(
                                                            "NEXT STOP",
                                                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Builder(builder: (context) {
                                                    final arrivalTime = s["arrival_time"] as String? ?? "";
                                                    String subtitleText = "ETA: $etaText";
                                                    if (isDeparted) {
                                                      subtitleText = "Departed";
                                                    } else if (isArriving) {
                                                      subtitleText = "Arriving Now";
                                                    } else if (arrivalTime.isNotEmpty && arrivalTime != "Passed" && arrivalTime != "Now") {
                                                      subtitleText = "ETA: $etaText ($arrivalTime)";
                                                    }

                                                    return Text(
                                                      subtitleText,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: (isNext || isArriving) ? FontWeight.bold : FontWeight.normal,
                                                        color: isDeparted
                                                            ? Colors.grey.shade500
                                                            : (isArriving
                                                                ? Colors.amber.shade900
                                                                : (isNext ? AppTheme.primaryEmerald : AppTheme.textSecondary)),
                                                      ),
                                                    );
                                                  }),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
