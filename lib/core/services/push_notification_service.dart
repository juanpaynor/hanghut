import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:bitemates/core/config/supabase_config.dart';

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
          // TODO: Integrate local notifications for robust foreground UI if needed
        });

        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          print('🔔 FCM Notification Tapped: ${message.data}');
          // TODO: Handle navigation based on data
        });

        // Check if app was opened from a terminated state
        RemoteMessage? initialMessage = await _fcm.getInitialMessage();
        if (initialMessage != null) {
          print('🔔 FCM Initial Message: ${initialMessage.data}');
          // TODO: Handle navigation
        }
      } else {
        print('🔔 FCM: Permission Declined');
      }
    } catch (e) {
      print('❌ FCM Error: $e');
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
