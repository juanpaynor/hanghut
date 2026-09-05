import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Result of snapping user-placed waypoints to walkable roads/paths.
class SnappedRoute {
  /// Full-resolution snapped path (many points), ready to draw as a polyline.
  final List<Position> coordinates;

  /// Total route distance in metres, computed server-side by Mapbox.
  final double distanceM;

  const SnappedRoute({required this.coordinates, required this.distanceM});
}

/// Wraps the Mapbox Directions API (walking profile) to turn a handful of
/// tapped waypoints into a clean, road-following route + real distance.
///
/// Uses the same MAPBOX_PUBLIC_TOKEN as [IsochroneService]. All HTTP, no native
/// code — safe to ship in a Shorebird patch. Low call volume (a few requests per
/// route *created*, not per view), so it sits comfortably in the Mapbox free tier.
class RouteDirectionsService {
  static final RouteDirectionsService _instance =
      RouteDirectionsService._internal();
  factory RouteDirectionsService() => _instance;
  RouteDirectionsService._internal();

  static const String _baseUrl =
      'https://api.mapbox.com/directions/v5/mapbox/walking';

  /// Snaps [waypoints] (2–25 points, in tap order) to the walking network.
  /// Returns the snapped path + distance, or null on any failure.
  Future<SnappedRoute?> snap(List<Position> waypoints) async {
    if (waypoints.length < 2) return null;
    // Directions caps a single request at 25 coordinates.
    if (waypoints.length > 25) {
      print('⚠️ RouteDirectionsService: >25 waypoints, truncating to 25');
      waypoints = waypoints.sublist(0, 25);
    }

    final token = dotenv.env['MAPBOX_PUBLIC_TOKEN'];
    if (token == null || token.isEmpty) {
      print('❌ RouteDirectionsService: MAPBOX_PUBLIC_TOKEN not found in .env');
      return null;
    }

    try {
      final coordsPath = waypoints.map((p) => '${p.lng},${p.lat}').join(';');
      final url = Uri.parse(
        '$_baseUrl/$coordsPath'
        '?geometries=geojson'
        '&overview=full'
        '&steps=false'
        '&access_token=$token',
      );

      final response = await http.get(url);
      if (response.statusCode != 200) {
        print('❌ Directions API ${response.statusCode}: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final distance = (route['distance'] as num?)?.toDouble() ?? 0;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coords = (geometry?['coordinates'] as List?) ?? const [];

      final positions = coords
          .map<Position>(
            (c) => Position((c[0] as num).toDouble(), (c[1] as num).toDouble()),
          )
          .toList();

      if (positions.length < 2) return null;
      return SnappedRoute(coordinates: positions, distanceM: distance);
    } catch (e) {
      print('❌ Directions fetch error: $e');
      return null;
    }
  }
}
