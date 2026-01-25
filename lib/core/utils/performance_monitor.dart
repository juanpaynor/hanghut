import 'dart:async';

/// Performance monitoring utility for tracking slow operations
class PerformanceMonitor {
  /// Track execution time of an async operation
  static Future<T> track<T>(
    String operationName,
    Future<T> Function() operation, {
    int slowThresholdMs = 1000,
  }) async {
    final start = DateTime.now();

    try {
      final result = await operation();
      final duration = DateTime.now().difference(start);

      _logPerformance(operationName, duration, slowThresholdMs);

      return result;
    } catch (e) {
      final duration = DateTime.now().difference(start);
      print('❌ $operationName FAILED after ${duration.inMilliseconds}ms: $e');
      rethrow;
    }
  }

  /// Track execution time of a synchronous operation
  static T trackSync<T>(
    String operationName,
    T Function() operation, {
    int slowThresholdMs = 500,
  }) {
    final start = DateTime.now();

    try {
      final result = operation();
      final duration = DateTime.now().difference(start);

      _logPerformance(operationName, duration, slowThresholdMs);

      return result;
    } catch (e) {
      final duration = DateTime.now().difference(start);
      print('❌ $operationName FAILED after ${duration.inMilliseconds}ms: $e');
      rethrow;
    }
  }

  static void _logPerformance(
    String operationName,
    Duration duration,
    int slowThresholdMs,
  ) {
    final ms = duration.inMilliseconds;

    if (ms > slowThresholdMs) {
      print(
        '🐌 SLOW: $operationName took ${ms}ms (threshold: ${slowThresholdMs}ms)',
      );

      // TODO: Send to analytics/monitoring service
      // Analytics.logSlowOperation(operationName, duration);
    } else if (ms > 100) {
      print('⏱️  $operationName: ${ms}ms');
    } else {
      print('⚡ $operationName: ${ms}ms');
    }
  }

  /// Start a timer for manual tracking
  static PerformanceTimer startTimer(String operationName) {
    return PerformanceTimer(operationName);
  }
}

/// Manual performance timer for complex operations
class PerformanceTimer {
  final String operationName;
  final DateTime _startTime;
  final Map<String, Duration> _checkpoints = {};

  PerformanceTimer(this.operationName) : _startTime = DateTime.now();

  /// Add a checkpoint
  void checkpoint(String name) {
    _checkpoints[name] = DateTime.now().difference(_startTime);
  }

  /// Stop timer and log results
  void stop() {
    final totalDuration = DateTime.now().difference(_startTime);

    print('⏱️  $operationName: ${totalDuration.inMilliseconds}ms');

    if (_checkpoints.isNotEmpty) {
      print('   Checkpoints:');
      _checkpoints.forEach((name, duration) {
        print('   - $name: ${duration.inMilliseconds}ms');
      });
    }
  }
}
