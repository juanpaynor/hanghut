import 'dart:async';

/// Utility class for debouncing function calls
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  /// Call the function after the delay, canceling any previous pending calls
  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancel any pending calls
  void cancel() {
    _timer?.cancel();
  }

  /// Dispose of the debouncer
  void dispose() {
    _timer?.cancel();
  }
}

/// Utility class for throttling function calls
class Throttler {
  final Duration duration;
  DateTime? _lastCallTime;

  Throttler({required this.duration});

  /// Call the function only if enough time has passed since the last call
  void call(void Function() action) {
    final now = DateTime.now();

    if (_lastCallTime == null || now.difference(_lastCallTime!) >= duration) {
      _lastCallTime = now;
      action();
    }
  }

  /// Reset the throttler
  void reset() {
    _lastCallTime = null;
  }
}
