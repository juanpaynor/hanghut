import 'package:bitemates/core/config/supabase_config.dart';

/// Provides GeoJSON point data for rendering a heatmap layer on the map.
class HeatmapService {
  static final HeatmapService _instance = HeatmapService._internal();
  factory HeatmapService() => _instance;
  HeatmapService._internal();

  // Simple in-memory cache
  Map<String, dynamic>? _cachedGeoJson;
  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Fetch all table/event points for heatmap rendering.
  ///
  /// Returns a GeoJSON FeatureCollection of Point features with a `weight`
  /// property based on member count / popularity.
  Future<Map<String, dynamic>> fetchHeatmapData({
    double? minLat,
    double? maxLat,
    double? minLng,
    double? maxLng,
  }) async {
    // Return cache if valid
    if (_cachedGeoJson != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      print('🔥 Heatmap: Using cached data');
      return _cachedGeoJson!;
    }

    try {
      print('🔥 Heatmap: Fetching fresh data from Supabase');

      // Fetch tables with location + member count for weight
      var query = SupabaseConfig.client
          .from('tables')
          .select('id, latitude, longitude, max_guests, status')
          .eq('status', 'open');

      // Apply viewport bounds if provided (wider area for heatmap)
      if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
        // Expand bounds by 50% for smoother edges
        final latPad = (maxLat - minLat) * 0.5;
        final lngPad = (maxLng - minLng) * 0.5;
        query = query
            .gte('latitude', minLat - latPad)
            .lte('latitude', maxLat + latPad)
            .gte('longitude', minLng - lngPad)
            .lte('longitude', maxLng + lngPad);
      }

      final tables = await query.limit(500);

      // Also fetch events
      var eventQuery = SupabaseConfig.client
          .from('events')
          .select('id, latitude, longitude, tickets_sold, capacity');

      if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
        final latPad = (maxLat - minLat) * 0.5;
        final lngPad = (maxLng - minLng) * 0.5;
        eventQuery = eventQuery
            .gte('latitude', minLat - latPad)
            .lte('latitude', maxLat + latPad)
            .gte('longitude', minLng - lngPad)
            .lte('longitude', maxLng + lngPad);
      }

      final events = await eventQuery.limit(200);

      // Build GeoJSON features
      final features = <Map<String, dynamic>>[];

      for (final table in tables) {
        final lat = table['latitude'];
        final lng = table['longitude'];
        if (lat == null || lng == null) continue;

        // Weight based on max capacity (min 1)
        final guests = (table['max_guests'] as num?) ?? 1;
        final weight = guests.toDouble().clamp(1.0, 10.0);

        features.add({
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [lng, lat],
          },
          'properties': {
            'weight': weight,
            'source_type': 'table',
          },
        });
      }

      for (final event in events) {
        final lat = event['latitude'];
        final lng = event['longitude'];
        if (lat == null || lng == null) continue;

        // Events have higher weight based on tickets sold
        final ticketsSold = (event['tickets_sold'] as num?) ?? 5;
        final weight = (ticketsSold.toDouble() / 5).clamp(2.0, 10.0);

        features.add({
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [lng, lat],
          },
          'properties': {
            'weight': weight,
            'source_type': 'event',
          },
        });
      }

      final geoJson = {
        'type': 'FeatureCollection',
        'features': features,
      };

      // Cache it
      _cachedGeoJson = geoJson;
      _lastFetchTime = DateTime.now();

      print('🔥 Heatmap: Generated ${features.length} points (${tables.length} tables, ${events.length} events)');
      return geoJson;
    } catch (e) {
      print('❌ Heatmap fetch error: $e');
      // Return empty collection on error
      return {
        'type': 'FeatureCollection',
        'features': [],
      };
    }
  }

  /// Invalidate the cache (call after data changes)
  void invalidateCache() {
    _cachedGeoJson = null;
    _lastFetchTime = null;
  }
}
