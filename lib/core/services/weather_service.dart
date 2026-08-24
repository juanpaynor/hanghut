import 'package:flutter/foundation.dart';
import 'package:bitemates/core/config/supabase_config.dart';

/// Thin client for the `get-weather` edge function that answers a single
/// question: "is it raining at this location right now?"
///
/// Result is cached ~20 minutes per rough location so the map never hammers
/// the weather API (and the check feels instant on repeat opens). Fails soft —
/// any error resolves to "not raining" so the map is never blocked.
class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  static const Duration _ttl = Duration(minutes: 20);
  // ~0.1° ≈ 11 km — plenty granular for "is it raining here".
  static const double _locEpsilon = 0.1;

  bool? _cachedRaining;
  DateTime? _cachedAt;
  double? _cachedLat;
  double? _cachedLng;

  Future<bool> isRainingAt(double lat, double lng) async {
    final now = DateTime.now();
    if (_cachedRaining != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _ttl &&
        _cachedLat != null &&
        _cachedLng != null &&
        (_cachedLat! - lat).abs() < _locEpsilon &&
        (_cachedLng! - lng).abs() < _locEpsilon) {
      return _cachedRaining!;
    }

    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'get-weather',
        body: {'lat': lat, 'lng': lng},
      );
      final data = response.data;
      final raining = data is Map && data['raining'] == true;

      _cachedRaining = raining;
      _cachedAt = now;
      _cachedLat = lat;
      _cachedLng = lng;

      debugPrint(
        '🌦️ Weather @ ($lat,$lng): '
        '${data is Map ? data['condition'] : 'unknown'} → raining=$raining',
      );
      return raining;
    } catch (e) {
      debugPrint('🌦️ Weather check failed (soft): $e');
      return false;
    }
  }
}
