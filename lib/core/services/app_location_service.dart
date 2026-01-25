import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppLocationService {
  static const _updateInterval = Duration(hours: 24);
  static const _lastUpdateKey = 'last_location_update';

  /// Update user location if 24 hours have passed since last update
  Future<void> updateLocationIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateString = prefs.getString(_lastUpdateKey);

      // Check if 24h passed
      if (lastUpdateString != null) {
        final lastUpdate = DateTime.parse(lastUpdateString);
        final elapsed = DateTime.now().difference(lastUpdate);

        if (elapsed < _updateInterval) {
          print('✅ LOCATION: Fresh - updated ${elapsed.inHours}h ago (skip)');
          return; // Skip update
        }
      }

      // Check location permissions
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          print('❌ LOCATION: Permission denied');
          return;
        }
      }

      // Get current location (coarse accuracy for privacy/battery)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      // Update in database
      await Supabase.instance.client.rpc(
        'update_user_location',
        params: {'lat': position.latitude, 'lng': position.longitude},
      );

      // Save timestamp
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());

      print(
        '📍 LOCATION: Updated (${position.latitude}, ${position.longitude})',
      );
    } catch (e) {
      print('❌ LOCATION: Update failed - $e');
      // Don't throw - location update is non-critical
    }
  }

  /// Manually trigger location update (for testing or user action)
  Future<void> forceUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastUpdateKey); // Clear timestamp
    await updateLocationIfNeeded();
  }
}
