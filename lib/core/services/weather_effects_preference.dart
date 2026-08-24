import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User toggle for the map's live weather visuals (currently the rain effect).
///
/// Client-side only and defaults ON. Backed by SharedPreferences so it persists
/// and can be read from both the Settings screen and the map without wiring up
/// a provider. [enabled] is a synchronous best-effort mirror of the stored
/// value; call [load] to refresh it.
///
/// [changes] fires whenever the value is flipped so open screens (the map) can
/// react immediately instead of only picking the change up on the next load.
class WeatherEffectsPreference {
  static const String _key = 'map_weather_effects_enabled';
  static bool _cached = true;

  /// Broadcasts the new value the moment [setEnabled] runs. Listen from the map
  /// to apply/remove the rain effect live (no app restart needed).
  static final ValueNotifier<bool> changes = ValueNotifier<bool>(_cached);

  /// Last known value (defaults to true until [load] runs).
  static bool get enabled => _cached;

  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    _cached = prefs.getBool(_key) ?? true;
    changes.value = _cached;
    return _cached;
  }

  static Future<void> setEnabled(bool value) async {
    _cached = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    changes.value = value;
  }
}
