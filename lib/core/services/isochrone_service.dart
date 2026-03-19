import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Fetches isochrone (walkability) polygons from the Mapbox Isochrone API.
class IsochroneService {
  static final IsochroneService _instance = IsochroneService._internal();
  factory IsochroneService() => _instance;
  IsochroneService._internal();

  static const String _baseUrl =
      'https://api.mapbox.com/isochrone/v1/mapbox/walking';

  /// Fetch isochrone polygon(s) for the given location.
  ///
  /// [lat], [lng] — center point (user location).
  /// [minutes] — list of contour durations in minutes, e.g. [5, 10, 15].
  /// Returns a GeoJSON FeatureCollection with polygon features, or null on error.
  Future<Map<String, dynamic>?> fetchIsochrone({
    required double lat,
    required double lng,
    List<int> minutes = const [5, 10, 15],
  }) async {
    final token = dotenv.env['MAPBOX_PUBLIC_TOKEN'];
    if (token == null || token.isEmpty) {
      print('❌ IsochroneService: MAPBOX_PUBLIC_TOKEN not found in .env');
      return null;
    }

    try {
      final contoursParam = minutes.join(',');
      // Colors for each contour (green → yellow → red)
      final colors = <String>[];
      for (var i = 0; i < minutes.length; i++) {
        switch (i) {
          case 0:
            colors.add('4CAF50'); // green
            break;
          case 1:
            colors.add('FFC107'); // yellow/amber
            break;
          case 2:
            colors.add('FF5722'); // deep orange
            break;
          default:
            colors.add('9C27B0'); // purple fallback
        }
      }
      final colorsParam = colors.join(',');

      final url = Uri.parse(
        '$_baseUrl/$lng,$lat'
        '?contours_minutes=$contoursParam'
        '&contours_colors=$colorsParam'
        '&polygons=true'
        '&denoise=1'
        '&generalize=500'
        '&access_token=$token',
      );

      print('🗺️ Isochrone: Fetching for ($lat, $lng) at $contoursParam min');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        print('✅ Isochrone: Got ${(data['features'] as List?)?.length ?? 0} contour(s)');
        return data;
      } else {
        print('❌ Isochrone API error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Isochrone fetch error: $e');
      return null;
    }
  }
}
