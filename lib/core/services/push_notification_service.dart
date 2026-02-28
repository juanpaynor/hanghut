import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/notification_service.dart';
import 'package:bitemates/main.dart'; // For navigatorKey
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();

  factory PushNotificationService() => _instance;

  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    try {
      // 1. Request Permission
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('🔔 FCM: Authorized (${settings.authorizationStatus})');

        // 2. Set Foreground Presentation Options (iOS)
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // 3. Get & Save Token
        String? token = await _fcm.getToken();
        if (token != null) {
          print('🔔 FCM Token: $token');
          await _saveTokenToSupabase(token);
        }

        // 4. Listen for Token Refresh
        _fcm.onTokenRefresh.listen(_saveTokenToSupabase);

        // 5. Message Listeners
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('🔔 FCM Foreground Message: ${message.notification?.title}');

          if (message.notification != null) {
            NotificationService().showNotification(
              id: message.hashCode,
              title: message.notification!.title ?? 'New Notification',
              body: message.notification!.body ?? '',
              payload: message.data.toString(), // Pass data for routing on tap
            );
          } else if (message.data.isNotEmpty) {
            // Data-only message
            NotificationService().showNotification(
              id: message.hashCode,
              title: 'Bitemates',
              body: 'You have a new message', // Generic fallback
              payload: message.data.toString(),
            );
          }
        });

        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          print('🔔 FCM Notification Tapped: ${message.data}');
          handleNotificationTap(message.data);
        });

        // Check if app was opened from a terminated state
        RemoteMessage? initialMessage = await _fcm.getInitialMessage();
        if (initialMessage != null) {
          print('🔔 FCM Initial Message: ${initialMessage.data}');
          handleNotificationTap(initialMessage.data);
        }
      } else {
        print('🔔 FCM: Permission Declined');
      }
    } catch (e) {
      print('❌ FCM Error: $e');
    }
  }

  void handleNotificationTap(Map<String, dynamic> data) {
    print('🔔 Handling Tap: $data');
    if (data['type'] == 'chat_message') {
      final tableId = data['table_id']?.toString();
      if (tableId != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              channelId: 'table_$tableId',
              tableId: tableId,
              tableTitle: 'Chat',
              chatType: 'table',
            ),
          ),
        );
      }
    } else if (data['type'] == 'table_join') {
      final tableId = data['table_id']?.toString();
      if (tableId != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MainNavigationScreen(
              initialIndex: 1, // Map Tab
              initialTableId: tableId,
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        await SupabaseConfig.client
            .from('users')
            .update({'fcm_token': token})
            .eq('id', user.id);
        print('✅ FCM: Token saved to Supabase');
      }
    } catch (e) {
      print('❌ FCM: Error saving token: $e');
    }
  }
}
