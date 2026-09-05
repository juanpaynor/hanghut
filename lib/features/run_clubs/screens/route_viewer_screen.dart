import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:bitemates/core/services/club_route_service.dart';
import 'package:bitemates/features/run_clubs/screens/route_creator_screen.dart'
    show kMapStyleLight, kMapStyleDark;
import 'package:bitemates/providers/theme_provider.dart';

/// Read-only render of a saved club route: the polyline, start/finish dots,
/// framed to fit. Reused later for GPX-imported routes. All Mapbox annotations
/// (no image icons) → patch-safe.
class RouteViewerScreen extends StatefulWidget {
  final ClubRoute route;

  const RouteViewerScreen({super.key, required this.route});

  @override
  State<RouteViewerScreen> createState() => _RouteViewerScreenState();
}

class _RouteViewerScreenState extends State<RouteViewerScreen> {
  static const int _line = 0xFFF04E2E;
  static const int _start = 0xFF16A34A; // green
  static const int _finish = 0xFFEF4444; // red

  MapboxMap? _map;

  /// Parses the stored GeoJSON LineString into map coordinates.
  List<Position> get _coords {
    final raw = widget.route.path?['coordinates'];
    if (raw is! List) return const [];
    return raw
        .whereType<List>()
        .where((c) => c.length >= 2 && c[0] is num && c[1] is num)
        .map((c) => Position((c[0] as num).toDouble(), (c[1] as num).toDouble()))
        .toList();
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    final coords = _coords;
    if (coords.length < 2) return;

    // Line
    final lineMgr = await map.annotations.createPolylineAnnotationManager();
    await lineMgr.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: coords),
        lineColor: _line,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
      ),
    );

    // Start + finish dots
    final dotMgr = await map.annotations.createCircleAnnotationManager();
    await dotMgr.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: coords.first),
        circleRadius: 7.0,
        circleColor: _start,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2.0,
      ),
    );
    await dotMgr.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: coords.last),
        circleRadius: 7.0,
        circleColor: _finish,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2.0,
      ),
    );

    _frame(coords);
  }

  /// Fits the camera to the route's bounding box (center + estimated zoom).
  void _frame(List<Position> coords) {
    double minLng = coords.first.lng.toDouble(), maxLng = minLng;
    double minLat = coords.first.lat.toDouble(), maxLat = minLat;
    for (final p in coords) {
      final lng = p.lng.toDouble(), lat = p.lat.toDouble();
      minLng = math.min(minLng, lng);
      maxLng = math.max(maxLng, lng);
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
    }
    final centerLng = (minLng + maxLng) / 2;
    final centerLat = (minLat + maxLat) / 2;
    final span = math.max(maxLng - minLng, maxLat - minLat);

    double zoom;
    if (span <= 0) {
      zoom = 15;
    } else {
      // World spans 360° at zoom 0; each zoom level halves the visible span.
      zoom = (math.log(360 / span) / math.ln2) - 0.6; // -0.6 = padding
      zoom = zoom.clamp(3.0, 16.0);
    }

    _map?.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(centerLng, centerLat)),
        zoom: zoom,
      ),
    );
  }

  String get _distanceLabel {
    final m = widget.route.distanceM;
    if (m == null || m <= 0) return '';
    final km = m / 1000;
    return km >= 1 ? '${km.toStringAsFixed(2)} km' : '${m.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final coords = _coords;
    final center = coords.isNotEmpty
        ? Point(coordinates: coords.first)
        : Point(coordinates: Position(121.0509, 14.5507));

    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: ValueKey('routeViewerMap_${isDark ? 'd' : 'l'}'),
            styleUri: isDark ? kMapStyleDark : kMapStyleLight,
            cameraOptions: CameraOptions(center: center, zoom: 13.0),
            onMapCreated: _onMapCreated,
          ),

          // Top bar: back + name/distance
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Material(
                    color: theme.cardColor,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.arrow_back_ios_new, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.route.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          if (_distanceLabel.isNotEmpty)
                            Text(
                              _distanceLabel,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.hintColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (coords.length < 2)
            const Center(
              child: Text('This route has no path data.'),
            ),
        ],
      ),
    );
  }
}
