import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// Service to handle device location
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _trackingSubscription;

  Position? _cachedPosition;
  DateTime? _lastUpdate;
  static const _cacheValidityMinutes = 5;

  /// Get current device location with caching
  Future<Position?> getCurrentLocation() async {
    // Return cached position if still valid
    if (_cachedPosition != null && _lastUpdate != null) {
      final age = DateTime.now().difference(_lastUpdate!);
      if (age.inMinutes < _cacheValidityMinutes) {
        return _cachedPosition;
      }
    }

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Location services are disabled');
        return null;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️ Location permission denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('⚠️ Location permission denied forever');
        return null;
      }

      // Try to get last known position first (fast)
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        // Optional: Check if it's recent enough? For now, just use it to be fast.
        _cachedPosition = lastKnown;
        _lastUpdate = DateTime.now();
        // Don't return yet, try to get fresh, but use this as fallback?
        // Actually, for the feed, we want speed. Return this if available?
        // Let's use it if we can.
        print(
          '✅ Using last known location: ${lastKnown.latitude}, ${lastKnown.longitude}',
        );
        return lastKnown;
      }

      // Get current position (fresh)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );

      _cachedPosition = position;
      _lastUpdate = DateTime.now();

      print('✅ Location: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('❌ Error getting location: $e');
      return null;
    }
  }

  /// Stream controller for location updates
  final StreamController<Position> _locationController =
      StreamController<Position>.broadcast();

  Stream<Position> get locationStream => _locationController.stream;

  /// Start Foreground Stream
  void startTracking() {
    // Cancel any existing subscription before starting a new one
    _trackingSubscription?.cancel();
    _trackingSubscription = null;

    print('📍 Location Tracking Started');
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _trackingSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position position) {
        _cachedPosition = position;
        _lastUpdate = DateTime.now();
        _locationController.add(position);
      },
      onError: (e) {
        // kCLErrorDomain error 1 = kCLErrorLocationUnknown — transient iOS error,
        // location will resume automatically. Just log and keep the stream alive.
        // kCLErrorDomain error 0 = kCLErrorLocationDenied — user revoked permission.
        final msg = e.toString();
        if (msg.contains('kCLErrorDomain error 1') ||
            msg.contains('kCLErrorLocationUnknown')) {
          // Transient — iOS couldn't determine location momentarily; safe to ignore
          print(
            '⚠️ LOCATION: Temporary location unknown (kCLErrorDomain 1) — will retry automatically',
          );
        } else if (msg.contains('kCLErrorDomain error 0') ||
            msg.contains('kCLErrorDenied')) {
          print('⚠️ LOCATION: Permission revoked — stopping tracking');
          stopTracking();
        } else {
          print('⚠️ LOCATION: Stream error (non-fatal) — $e');
        }
        // Reschedule tracking after a brief delay so the stream recovers
        Future.delayed(const Duration(seconds: 5), () {
          if (_trackingSubscription == null) startTracking();
        });
      },
      cancelOnError: false, // Keep subscription alive on errors
    );
  }

  /// Stop location tracking and release resources
  void stopTracking() {
    _trackingSubscription?.cancel();
    _trackingSubscription = null;
    print('📍 Location Tracking Stopped');
  }

  /// Calculate distance between two points (in meters)
  double distanceBetween(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  /// Clear cached location
  void clearCache() {
    _cachedPosition = null;
    _lastUpdate = null;
  }
}
