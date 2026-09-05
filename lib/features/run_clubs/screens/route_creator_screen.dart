import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:bitemates/core/services/route_directions_service.dart';
import 'package:bitemates/core/services/club_route_service.dart';
import 'package:bitemates/providers/theme_provider.dart';

/// Custom branded Mapbox styles — must match map_screen.dart.
const String kMapStyleLight = 'mapbox://styles/swiftdash/cmjwvnoqp001v01rdeseu6fz1';
const String kMapStyleDark = 'mapbox://styles/swiftdash/cmjyv1kco003m01rd6nkjcd27';

/// In-app snap-to-roads route creator for run clubs.
///
/// Tap the map to drop waypoints; each add re-snaps the whole path to walkable
/// roads via [RouteDirectionsService] and redraws. Undo / clear, live distance.
/// On save it pops a map: { name, waypoints, path (GeoJSON LineString),
/// distance_m } — persistence to `club_routes` is wired by the caller once that
/// table lands. All Mapbox + HTTP → Shorebird-patchable.
class RouteCreatorScreen extends StatefulWidget {
  final String groupId;
  final double? initialLat;
  final double? initialLng;

  const RouteCreatorScreen({
    super.key,
    required this.groupId,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<RouteCreatorScreen> createState() => _RouteCreatorScreenState();
}

class _RouteCreatorScreenState extends State<RouteCreatorScreen> {
  static const int _accent = 0xFFF04E2E; // route line + waypoint dots

  MapboxMap? _map;
  PolylineAnnotationManager? _lineMgr;
  CircleAnnotationManager? _dotMgr;

  final List<Position> _waypoints = [];
  List<Position> _snapped = [];
  double _distanceM = 0;
  bool _snapping = false;

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    _lineMgr = await map.annotations.createPolylineAnnotationManager();
    _dotMgr = await map.annotations.createCircleAnnotationManager();
  }

  Future<void> _onTap(MapContentGestureContext context) async {
    final map = _map;
    if (map == null) return;
    // Convert the tapped screen pixel to a geographic coordinate.
    final point = await map.coordinateForPixel(context.touchPosition);
    _waypoints.add(point.coordinates);
    await _redrawDots();
    await _resnap();
  }

  Future<void> _undo() async {
    if (_waypoints.isEmpty) return;
    _waypoints.removeLast();
    await _redrawDots();
    await _resnap();
  }

  Future<void> _clear() async {
    _waypoints.clear();
    _snapped = [];
    _distanceM = 0;
    await _lineMgr?.deleteAll();
    await _dotMgr?.deleteAll();
    if (mounted) setState(() {});
  }

  Future<void> _redrawDots() async {
    await _dotMgr?.deleteAll();
    for (final p in _waypoints) {
      await _dotMgr?.create(
        CircleAnnotationOptions(
          geometry: Point(coordinates: p),
          circleRadius: 6.0,
          circleColor: _accent,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 2.0,
        ),
      );
    }
  }

  Future<void> _resnap() async {
    if (_waypoints.length < 2) {
      await _lineMgr?.deleteAll();
      _snapped = [];
      _distanceM = 0;
      if (mounted) setState(() {});
      return;
    }

    setState(() => _snapping = true);
    final result = await RouteDirectionsService().snap(List.of(_waypoints));
    if (!mounted) return;
    setState(() => _snapping = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't snap that segment — try again")),
      );
      return;
    }

    _snapped = result.coordinates;
    _distanceM = result.distanceM;
    await _lineMgr?.deleteAll();
    await _lineMgr?.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: _snapped),
        lineColor: _accent,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_snapped.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least 2 points to make a route')),
      );
      return;
    }
    final name = await _promptName();
    if (name == null || !mounted) return;

    final path = <String, dynamic>{
      'type': 'LineString',
      'coordinates': _snapped.map((p) => [p.lng, p.lat]).toList(),
    };

    setState(() => _snapping = true);
    final saved = await ClubRouteService().createRoute(
      groupId: widget.groupId,
      name: name,
      path: path,
      waypoints: _waypoints.map((p) => [p.lng, p.lat]).toList(),
      distanceM: _distanceM,
    );
    if (!mounted) return;
    setState(() => _snapping = false);

    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save route — try again')),
      );
      return;
    }
    Navigator.of(context).pop(saved);
  }

  Future<String?> _promptName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this route'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. BGC Loop, Riverside 5K',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.of(ctx).pop(v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String get _distanceLabel {
    if (_distanceM <= 0) return '—';
    final km = _distanceM / 1000;
    return km >= 1
        ? '${km.toStringAsFixed(2)} km'
        : '${_distanceM.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final center = Point(
      coordinates: Position(
        widget.initialLng ?? 121.0509, // Metro Manila fallback (BGC)
        widget.initialLat ?? 14.5507,
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: ValueKey('routeCreatorMap_${isDark ? 'd' : 'l'}'),
            styleUri: isDark ? kMapStyleDark : kMapStyleLight,
            cameraOptions: CameraOptions(center: center, zoom: 14.0),
            onMapCreated: _onMapCreated,
            onTapListener: _onTap,
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _roundBtn(
                    icon: Icons.close,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                      child: Text(
                        _waypoints.isEmpty
                            ? 'Tap the map to drop points'
                            : '$_distanceLabel  ·  ${_waypoints.length} points',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_snapping)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _pillBtn(
                      icon: Icons.undo,
                      label: 'Undo',
                      onTap: _waypoints.isEmpty ? null : _undo,
                    ),
                    const SizedBox(width: 10),
                    _pillBtn(
                      icon: Icons.clear_all,
                      label: 'Clear',
                      onTap: _waypoints.isEmpty ? null : _clear,
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _snapped.length < 2 ? null : _save,
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Save route'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(_accent),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22)),
      ),
    );
  }

  Widget _pillBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
