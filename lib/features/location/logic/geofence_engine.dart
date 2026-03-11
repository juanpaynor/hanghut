import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'package:bitemates/core/services/location_service.dart';
import 'package:bitemates/core/services/notification_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeofenceEngine {
  static final GeofenceEngine _instance = GeofenceEngine._internal();
  factory GeofenceEngine() => _instance;
  GeofenceEngine._internal();

  final LocationService _locationService = LocationService();

  // Cache: List of Table Locations {id, lat, lng, title, datetime, current_capacity, max_guests}
  List<Map<String, dynamic>> _activeGeofences = [];

  // State: Currently "Inside" zones to prevent double firing
  final Set<String> _insideZones = {};

  // Debounce Timers: {tableId: Timer}
  final Map<String, Timer> _dwellTimers = {};

  // PHASE 1: Per-zone cooldown tracking
  final Map<String, DateTime> _lastNotificationTime = {};

  // PHASE 1: Global rate limit tracking
  final Queue<DateTime> _recentNotifications = Queue();

  // Config
  static const double kGeofenceRadiusMeters = 200.0;
  static const int kDwellTimeSeconds = 20; // Production value (was 5 for testing)

  // PHASE 1: Rate limiting config
  static const Duration kNotificationCooldown = Duration(hours: 6);
  static const int kMaxNotificationsPerHour = 3;

  // Stream for UI (Foreground) — carries full event data for the modal
  final StreamController<Map<String, dynamic>> _eventStreamController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventStreamController.stream;

  // Muted Zones (Persisted)
  Set<String> _mutedZones = {};

  StreamSubscription<Position>? _positionSubscription;
  bool _isGhostMode = false;

  bool get isGhostMode => _isGhostMode;

  /// Initialize Engine
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isGhostMode = prefs.getBool('ghost_mode') ?? false;

    if (_isGhostMode) {
      print('👻 GEOFENCE: Ghost Mode is ON. Engine sleeping.');
      return;
    }

    await _loadGeofencesFromCache();
    await _loadMutedZones(); // Load Ignore List
    await _loadNotificationHistory(); // PHASE 1: Load cooldown data

    // Start Listening to Foreground Location
    _locationService.startTracking(); // Ensure service is tracking
    _positionSubscription?.cancel();
    _positionSubscription = _locationService.locationStream.listen((position) {
      checkProximity(position.latitude, position.longitude);
    });

    print(
      '📍 GEOFENCE: Engine Initialized. ${_activeGeofences.length} fences loaded. Monitoring...',
    );
  }

  Future<void> setGhostMode(bool enable) async {
    _isGhostMode = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ghost_mode', enable);

    if (enable) {
      // Stop Everything
      _positionSubscription?.cancel();
      print('👻 GEOFENCE: Ghost Mode ENABLED. Stopping monitoring.');
    } else {
      // Restart
      print('📍 GEOFENCE: Ghost Mode DISABLED. Restarting...');
      await init();
    }
  }

  // PHASE 1: Load notification history
  Future<void> _loadNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString('notification_history');

      if (jsonString != null) {
        final Map<String, dynamic> decoded = jsonDecode(jsonString);

        // Load per-zone cooldowns
        final Map<String, dynamic>? lastTimes = decoded['last_times'];
        if (lastTimes != null) {
          _lastNotificationTime.clear();
          lastTimes.forEach((key, value) {
            _lastNotificationTime[key] = DateTime.parse(value as String);
          });
        }
      }
    } catch (e) {
      print('❌ GEOFENCE: Load history error - $e');
    }
  }

  // PHASE 1: Save notification history
  Future<void> _saveNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, dynamic> data = {
        'last_times': _lastNotificationTime.map(
          (key, value) => MapEntry(key, value.toIso8601String()),
        ),
      };

      await prefs.setString('notification_history', jsonEncode(data));
    } catch (e) {
      print('❌ GEOFENCE: Save history error - $e');
    }
  }

  Future<void> _loadMutedZones() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? muted = prefs.getStringList('muted_geofences');
    if (muted != null) {
      _mutedZones = muted.toSet();
    }
  }

  Future<void> muteGeofence(String id) async {
    _mutedZones.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('muted_geofences', _mutedZones.toList());
    print('🔇 GEOFENCE: Muted $id');
  }

  /// Temporarily snooze a geofence for 1 hour (sets cooldown without permanent mute)
  void snoozeGeofence(String id) {
    _lastNotificationTime[id] = DateTime.now();
    _saveNotificationHistory();
    print('💤 GEOFENCE: Snoozed $id for 1 hour');
  }

  // PHASE 1: Check rate limit
  bool _canSendNotification() {
    final now = DateTime.now();
    final oneHourAgo = now.subtract(const Duration(hours: 1));

    // Remove old entries
    _recentNotifications.removeWhere((time) => time.isBefore(oneHourAgo));

    // Check limit
    if (_recentNotifications.length >= kMaxNotificationsPerHour) {
      print(
        '🚦 GEOFENCE: Rate limit reached (${_recentNotifications.length}/hr)',
      );
      return false;
    }

    return true;
  }

  // PHASE 2: Check if event is relevant
  bool _shouldNotify(Map<String, dynamic> event) {
    try {
      // 1. Event starts within next 4 hours (if datetime is available)
      final datetimeStr = event['datetime'] ?? event['start_datetime'];
      if (datetimeStr != null) {
        final eventTime = DateTime.parse(datetimeStr);
        final timeUntilEvent = eventTime.difference(DateTime.now());

        if (timeUntilEvent > const Duration(hours: 4)) {
          return false; // Too far in future
        }

        if (timeUntilEvent.isNegative &&
            timeUntilEvent < const Duration(minutes: -30)) {
          return false; // Event ended
        }
      }
      // If no datetime (e.g. a table), it's always relevant

      // 2. Event not full
      final currentCapacity = (event['current_capacity'] ?? event['member_count'] ?? 0) as num;
      final maxGuests = (event['max_guests'] ?? event['capacity'] ?? 99) as num;

      if (currentCapacity >= maxGuests) {
        return false;
      }

      return true;
    } catch (e) {
      print('❌ Error checking event relevance: $e');
      return true; // Default to notifying if we can't validate
    }
  }

  // PHASE 2: Calculate event priority
  int _calculateEventPriority(Map<String, dynamic> event, double distance) {
    int score = 0;

    try {
      // Time relevance (starts soon = higher priority)
      final eventTime = DateTime.parse(event['datetime']);
      final minutesUntil = eventTime.difference(DateTime.now()).inMinutes;

      if (minutesUntil < 60) {
        score += 50;
      } else if (minutesUntil < 120) {
        score += 30;
      } else {
        score += 10;
      }

      // Capacity (nearly full = FOMO = higher priority)
      final currentCapacity = event['current_capacity'] ?? 0;
      final maxGuests = event['max_guests'] ?? 4;
      final fillRate = maxGuests > 0 ? currentCapacity / maxGuests : 0;

      if (fillRate > 0.75) {
        score += 30; // 75%+ full
      } else if (fillRate > 0.5) {
        score += 15;
      }

      // Distance (closer = more relevant)
      if (distance < 100) {
        score += 20;
      } else if (distance < 200) {
        score += 10;
      }

      // User has muted this zone (lower priority)
      if (_mutedZones.contains(event['id'])) {
        score -= 50;
      }
    } catch (e) {
      print('❌ Error calculating priority: $e');
    }

    return score;
  }

  void _triggerEvent(String id, String title, Map<String, dynamic> event) {
    // Check 1: User muted?
    if (_mutedZones.contains(id)) {
      print('🔇 GEOFENCE: $id is muted. Skipping.');
      return;
    }

    // PHASE 1: Check 2: Notified recently?
    final lastTime = _lastNotificationTime[id];
    if (lastTime != null) {
      final elapsed = DateTime.now().difference(lastTime);
      if (elapsed < kNotificationCooldown) {
        print(
          '🔇 GEOFENCE: $id cooldown active (${elapsed.inMinutes}m/${kNotificationCooldown.inHours}h)',
        );
        return;
      }
    }

    // PHASE 2: Check 3: Event relevant?
    if (!_shouldNotify(event)) {
      print('⏭️ GEOFENCE: $id not relevant. Skipping.');
      return;
    }

    // PHASE 1: Check 4: Global rate limit?
    if (!_canSendNotification()) {
      print('🚦 GEOFENCE: Rate limit - skipping $id');
      return;
    }

    // All checks passed - trigger event
    _insideZones.add(id);
    _dwellTimers.remove(id);

    print('✅ GEOFENCE TRIGGERED: $id');

    // Record notification time
    _lastNotificationTime[id] = DateTime.now();
    _recentNotifications.add(DateTime.now());
    _saveNotificationHistory(); // Persist

    // 1. Notify UI (if App is Open) — include full event data for rich modal
    _eventStreamController.add({
      'id': id,
      'title': title,
      'datetime': event['datetime'] ?? event['start_datetime'],
      'current_capacity': event['current_capacity'] ?? event['member_count'] ?? 0,
      'max_guests': event['max_guests'] ?? event['capacity'] ?? 0,
      'location_name': event['location_name'] ?? event['venue_name'] ?? event['title'],
      'ticket_price': event['ticket_price'] ?? event['price_per_person'] ?? 0,
    });

    // 2. Show Notification (Smart Copy)
    String notifTitle = 'You are near $title!';
    String notifBody = 'Open app to check in.';

    try {
      final bool isTicketHolder = event['is_user_ticket_holder'] ?? false;
      final bool isJoined = event['is_user_joined'] ?? false;
      final num price = event['ticket_price'] ?? 0;

      if (isTicketHolder) {
        notifTitle = "Welcome Back! 🎟️";
        notifBody = "Show your ticket for $title at the entrance.";
      } else if (isJoined) {
        notifTitle = "You've Arrived! 👋";
        notifBody = "Join your table at $title.";
      } else if (price > 0) {
        notifTitle = "Nearby Event! 🎫";
        notifBody = "Tickets available from \$${price}. Tap to view.";
      } else {
        notifTitle = "Nearby Event! 🎉";
        notifBody = "Check out $title happening now.";
      }
    } catch (e) {
      print('⚠️ Error generating smart copy: $e');
    }

    _showGeofenceNotification(notifTitle, notifBody);
  }

  /// Call this when app opens or background fetch runs
  Future<void> syncGeofences() async {
    try {
      final location = await _locationService.getCurrentLocation();
      if (location == null) return;

      final response = await Supabase.instance.client.rpc(
        'get_nearby_tables',
        params: {
          'lat': location.latitude,
          'lng': location.longitude,
          'radius_meters': 5000, // 5km cache radius
        },
      );

      // Save to List (now includes datetime, capacity for smart filtering)
      _activeGeofences = List<Map<String, dynamic>>.from(response);

      // Persist to Disk
      await _saveGeofencesToCache();

      print('📍 GEOFENCE: Synced ${_activeGeofences.length} tables.');
    } catch (e) {
      print('❌ GEOFENCE: Sync error - $e');
    }
  }

  Future<void> _saveGeofencesToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String jsonString = jsonEncode(_activeGeofences);
      await prefs.setString('geofence_cache', jsonString);
    } catch (e) {
      print('❌ GEOFENCE: Save cache error - $e');
    }
  }

  Future<void> _loadGeofencesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString('geofence_cache');

      if (jsonString != null) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _activeGeofences = List<Map<String, dynamic>>.from(decoded);
      }
    } catch (e) {
      print('❌ GEOFENCE: Load cache error - $e');
    }
  }

  /// Core Check Loop - PHASE 2: Priority-based filtering
  void checkProximity(double userLat, double userLng) {
    final List<Map<String, dynamic>> nearbyEvents = [];
    final Map<String, double> distanceMap = {};

    // First pass: collect all nearby events with distances
    for (final fence in _activeGeofences) {
      // Support both table (location_lat/lng) and event (latitude/longitude) schemas
      final double fenceLat = ((fence['latitude'] ?? fence['location_lat']) as num).toDouble();
      final double fenceLng = ((fence['longitude'] ?? fence['location_lng']) as num).toDouble();

      final double distance = _locationService.distanceBetween(
        userLat,
        userLng,
        fenceLat,
        fenceLng,
      );

      final String fenceId = fence['id'];
      final bool isInside = distance < kGeofenceRadiusMeters;

      if (isInside) {
        nearbyEvents.add(fence);
        distanceMap[fenceId] = distance;
      } else {
        _handleExit(fenceId);
      }
    }

    // PHASE 2: Sort by priority if multiple events
    if (nearbyEvents.length > 1) {
      nearbyEvents.sort((a, b) {
        final aPriority = _calculateEventPriority(
          a,
          distanceMap[a['id']] ?? 999,
        );
        final bPriority = _calculateEventPriority(
          b,
          distanceMap[b['id']] ?? 999,
        );
        return bPriority.compareTo(aPriority); // Descending
      });

      print('📊 GEOFENCE: ${nearbyEvents.length} nearby, sorted by priority');
    }

    // Process events (rate limits will naturally cap notifications)
    for (final event in nearbyEvents) {
      _handleEnter(event['id'], event['title'] ?? 'Unknown Event', event);
    }
  }

  // --- State Machine ---

  void _handleEnter(String id, String title, Map<String, dynamic> event) {
    // If already inside, do nothing
    if (_insideZones.contains(id)) return;

    // If timer already running, let it run
    if (_dwellTimers.containsKey(id)) return;

    print('📍 Entering Zone: $title (Starting Dwell Timer)');

    // Start Timer
    _dwellTimers[id] = Timer(Duration(seconds: kDwellTimeSeconds), () {
      _triggerEvent(id, title, event);
    });
  }

  void _handleExit(String id) {
    // Cancel any pending timer
    if (_dwellTimers.containsKey(id)) {
      _dwellTimers[id]?.cancel();
      _dwellTimers.remove(id);
      print('📍 Exited Zone: $id before dwell time.');
    }

    // Mark as outside
    if (_insideZones.contains(id)) {
      _insideZones.remove(id);
      print('📍 Left Zone: $id');
    }
  }

  Future<void> _showGeofenceNotification(String title, String body) async {
    await NotificationService().showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      body: body,
      channelId: 'bitemates_geofence',
      channelName: 'Nearby Events',
    );
  }
}
