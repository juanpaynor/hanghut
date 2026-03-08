import 'dart:io';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/push_notification_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'dart:convert';

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
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS Config — MUST be true to show alerts
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        print('Notification tapped: ${details.payload}');
        if (details.payload != null) {
          try {
            final dynamic parsed = jsonDecode(details.payload!);
            if (parsed is Map<String, dynamic>) {
              PushNotificationService().handleNotificationTap(parsed);
            }
          } catch (e) {
            print('Error parsing local notification payload: $e');
          }
        }
      },
    );

    // Create Android notification channels
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'bitemates_push',
          'Push Notifications',
          description: 'Remote push notifications from FCM',
          importance: Importance.max,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'bitemates_events',
          'Event Reminders',
          description: 'Scheduled reminders for upcoming events',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'bitemates_geofence',
          'Nearby Events',
          description: 'Alerts when you are near an event',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'bitemates_social',
          'Social Activity',
          description: 'Likes, comments, and join requests',
          importance: Importance.defaultImportance,
        ),
      );
    }

    print('✅ NotificationService initialized');

    // Initialize timezone data for scheduled notifications
    tz_data.initializeTimeZones();
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
    String channelId = 'bitemates_push',
    String channelName = 'Push Notifications',
  }) async {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.max,
          priority: Priority.high,
        );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(id, title, body, details, payload: payload);
  }

  // --- Scheduled Event Reminders ---

  /// Schedule a reminder notification 30 minutes before the event.
  /// Uses `tableId.hashCode` as the notification ID for deterministic cancellation.
  Future<void> scheduleEventReminder({
    required String tableId,
    required String title,
    required String venueName,
    required DateTime eventTime,
  }) async {
    final reminderTime = eventTime.subtract(const Duration(minutes: 30));

    // Don't schedule if the reminder time is already in the past
    if (reminderTime.isBefore(DateTime.now())) {
      print('⏰ Reminder time already passed for $title, skipping.');
      return;
    }

    final int notifId = tableId.hashCode.abs() % 100000; // Deterministic ID
    final scheduledDate = tz.TZDateTime.from(reminderTime, tz.local);

    final AndroidNotificationDetails androidDetails =
        const AndroidNotificationDetails(
          'bitemates_events',
          'Event Reminders',
          importance: Importance.high,
          priority: Priority.high,
        );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _notificationsPlugin.zonedSchedule(
        notifId,
        'Starting Soon! ⏰',
        '$title at $venueName starts in 30 minutes!',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: jsonEncode({'type': 'event_reminder', 'table_id': tableId}),
      );
      print('⏰ Scheduled reminder for "$title" at $reminderTime');
    } catch (e) {
      print('❌ Error scheduling reminder: $e');
    }
  }

  /// Cancel a previously scheduled event reminder.
  Future<void> cancelEventReminder(String tableId) async {
    final int notifId = tableId.hashCode.abs() % 100000;
    await _notificationsPlugin.cancel(notifId);
    print('❌ Cancelled reminder for table $tableId (notif ID: $notifId)');
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

    // Refresh count after marking as read
    _refreshUnreadCount();
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

            // Show a local notification toast for social activity
            try {
              final newRecord = payload.newRecord;
              if (newRecord != null) {
                final title = newRecord['title'] as String? ?? 'Bitemates';
                final body =
                    newRecord['body'] as String? ??
                    'You have a new notification';
                showNotification(
                  id: DateTime.now().millisecondsSinceEpoch % 100000,
                  title: title,
                  body: body,
                  channelId: 'bitemates_social',
                  channelName: 'Social Activity',
                );
              }
            } catch (e) {
              print('⚠️ Error showing social toast: $e');
            }
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
