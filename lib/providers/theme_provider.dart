import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  /// Minimum spacing between theme switches. Flipping light/dark rebuilds the
  /// whole tree (and re-sets the Mapbox style JSON on the map), so hammering the
  /// toggle can interleave those heavy operations and glitch the UI. We throttle
  /// switches to at most one per this window; taps that arrive sooner are
  /// ignored (listeners rebuild back to the current, unchanged state).
  static const Duration _switchCooldown = Duration(milliseconds: 700);
  DateTime? _lastSwitchAt;

  ThemeProvider() {
    _loadTheme();
  }

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  /// Whether a switch is currently allowed (false during the cooldown window).
  /// Exposed so UI can optionally disable the control while it settles.
  bool get canSwitch {
    final last = _lastSwitchAt;
    return last == null ||
        DateTime.now().difference(last) >= _switchCooldown;
  }

  void toggleTheme(bool isDark) {
    final target = isDark ? ThemeMode.dark : ThemeMode.light;
    // No-op if already there — avoids a needless full rebuild.
    if (target == _themeMode) return;

    // Throttle rapid flips so the heavy re-theme/re-style work can't overlap.
    if (!canSwitch) {
      // Nudge listeners so bound switches snap back to the real state.
      notifyListeners();
      return;
    }

    _lastSwitchAt = DateTime.now();
    _themeMode = target;
    _saveTheme();
    notifyListeners();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode');
    if (isDark != null) {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      notifyListeners();
    }
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _themeMode == ThemeMode.dark);
  }
}
