import 'dart:io';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/core/config/supabase_config.dart';

// Top-level function for Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Background Task Executing: $task");
    return Future.value(true);
  });
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // Android Config
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        ); // Ensure icon exists

    // iOS Config
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        print('Notification tapped: ${details.payload}');
      },
    );
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // --- Local Notifications ---

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'bitemates_channel_main',
          'Bitemates Notifications',
          channelDescription: 'Main channel for app notifications',
          importance: Importance.max,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _notificationsPlugin.show(id, title, body, details, payload: payload);
  }

  // --- Database (Supabase) Integration ---

  /// Fetch notifications with pagination for the 'Bell' feed.
  /// [limit] defaults to 20.
  /// [before] (created_at) for cursor-based pagination.
  Future<List<Map<String, dynamic>>> fetchNotifications({
    int limit = 20,
    DateTime? before,
  }) async {
    final client = SupabaseConfig.client;
    final userId = client.auth.currentUser?.id;

    if (userId == null) return [];

    // Start building query
    PostgrestFilterBuilder query = client
        .from('notifications')
        // actor:users(...) joins public.users on notifications.actor_id = users.id
        // user_photos(...) nested join on users.id = user_photos.user_id
        .select('*, actor:users(display_name, user_photos(photo_url))')
        .eq('user_id', userId);

    // Apply cursor filter if present
    if (before != null) {
      query = query.lt('created_at', before.toIso8601String());
    }

    // Execute with sort and limit
    final response = await query
        .order('created_at', ascending: false)
        .limit(limit);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> markAsRead(String notificationId) async {
    await SupabaseConfig.client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  // --- Realtime Updates (Smart Ping) ---
  final StreamController<int> _unreadCountController =
      StreamController<int>.broadcast();
  Stream<int> get unreadCountStream => _unreadCountController.stream;
  RealtimeChannel? _notificationChannel;

  /// Subscribes to realtime INSERT events for the current user's notifications.
  /// This is lightweight: it just triggers a refresh of the count.
  void subscribeToNotifications() {
    final client = SupabaseConfig.client;
    final userId = client.auth.currentUser?.id;

    if (userId == null) return;
    if (_notificationChannel != null) return; // Already subscribed

    print('🔔 Subscribing to notification channel for user: $userId');

    _notificationChannel = client
        .channel('public:notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            print('🔔 New notification received! Refreshing count...');
            _refreshUnreadCount();

            // Optional: Show local notification snackbar or toast here if app is in foreground
          },
        )
        .subscribe();

    // Initial fetch
    _refreshUnreadCount();
  }

  void unsubscribeNotifications() {
    if (_notificationChannel != null) {
      SupabaseConfig.client.removeChannel(_notificationChannel!);
      _notificationChannel = null;
    }
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final count = await getUnreadCount();
      _unreadCountController.add(count);
    } catch (e) {
      print('❌ Error refreshing unread count: $e');
    }
  }

  Future<int> getUnreadCount() async {
    final client = SupabaseConfig.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return 0;

    final count = await client
        .from('notifications')
        .count(CountOption.exact)
        .eq('user_id', userId)
        .eq('is_read', false);

    return count;
    // Note: count() returns int directly in recent versions, or PostgrestResponse.
    // Supabase Flutter v2 .count() returns `Future<int>` directly.
  }
}
