import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/notification_service.dart';
import 'package:bitemates/main.dart'; // For navigatorKey
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/features/home/screens/post_detail_screen.dart';
import 'package:bitemates/features/ticketing/screens/my_tickets_screen.dart';
import 'package:bitemates/features/profile/screens/my_memberships_screen.dart';
import 'package:bitemates/features/groups/screens/group_detail_screen.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();

  factory PushNotificationService() => _instance;

  PushNotificationService._internal();

  /// Set to true during payment flow to prevent FCM notifications from
  /// blocking the main thread during app resume (Mapbox re-render window).
  static bool suppressNotifications = false;

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
        String? token;

        if (Platform.isIOS) {
          // On iOS, we must get the APNs token first before FCM token
          String? apnsToken = await _fcm.getAPNSToken();
          print('🔔 APNs Token: $apnsToken');
          if (apnsToken != null) {
            token = await _fcm.getToken();
          } else {
            // Wait a bit and try again, it sometimes takes a moment
            await Future.delayed(const Duration(seconds: 2));
            apnsToken = await _fcm.getAPNSToken();
            print('🔔 APNs Token (Retry): $apnsToken');
            if (apnsToken != null) {
              token = await _fcm.getToken();
            }
          }
        } else {
          token = await _fcm.getToken();
        }

        if (token != null) {
          print('🔔 FCM Token: $token');
          await _saveTokenToSupabase(token);
        }

        // 4. Listen for Token Refresh
        _fcm.onTokenRefresh.listen(_saveTokenToSupabase);

        // 5. Message Listeners
        // Defer notification display to avoid competing with
        // Mapbox re-render and other services during app resume.
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('🔔 FCM Foreground Message: ${message.notification?.title}');

          // During payment flow, skip showing notifications entirely
          // to prevent ANR from main thread contention with Mapbox re-render.
          if (suppressNotifications) {
            print('🔔 FCM: Notification suppressed (payment in progress)');
            return;
          }

          // Defer by 2 seconds for non-payment notifications
          Future.delayed(const Duration(seconds: 2), () {
            if (message.notification != null) {
              NotificationService().showNotification(
                id: message.hashCode,
                title: message.notification!.title ?? 'New Notification',
                body: message.notification!.body ?? '',
                payload: jsonEncode(message.data),
              );
            } else if (message.data.isNotEmpty) {
              NotificationService().showNotification(
                id: message.hashCode,
                title: 'Bitemates',
                body: 'You have a new message',
                payload: jsonEncode(message.data),
              );
            }
          });
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

  Future<void> handleNotificationTap(Map<String, dynamic> data) async {
    print('🔔 Handling Tap: $data');
    if (data['type'] == 'chat_message' ||
        data['type'] == 'chat' ||
        // Chat mentions carry a chat_type → route into the chat, not a post.
        (data['type'] == 'mention' && data['chat_type'] != null)) {
      final String chatType = data['chat_type'] ?? 'table';
      // Support both push data keys (table_id, chat_id) and bell data keys (entity_id)
      var entityId =
          data['table_id']?.toString() ??
          data['chat_id']?.toString() ??
          data['entity_id']?.toString();

      if (entityId != null) {
        String channelId = '${chatType}_$entityId';
        String tableTitle = data['sender_name'] ?? 'Chat';

        try {
          if (chatType == 'trip') {
            // Fetch Trip Chat Details (same as bell handler)
            final chat = await SupabaseConfig.client
                .from('trip_group_chats')
                .select('ably_channel_id, destination_city')
                .eq('id', entityId)
                .maybeSingle();

            if (chat != null) {
              channelId = chat['ably_channel_id'] ?? channelId;
              tableTitle = '${chat['destination_city']} Group';
            }
          } else if (chatType == 'dm' || chatType == 'direct') {
            var chatId = data['chat_id']?.toString() ?? entityId;
            channelId = chatId.startsWith('direct_')
                ? chatId
                : 'direct_$chatId';
            tableTitle =
                data['sender_name'] ?? data['actor_name'] ?? 'Direct Message';
            entityId = chatId;
          } else if (chatType == 'group') {
            // Group chat — channel is group_<id>; look up the group name.
            channelId = 'group_$entityId';
            final group = await SupabaseConfig.client
                .from('groups')
                .select('name')
                .eq('id', entityId)
                .maybeSingle();
            if (group != null) {
              tableTitle = group['name'] ?? tableTitle;
            }
          } else {
            // Table / Hangout — look up title from DB
            final table = await SupabaseConfig.client
                .from('tables')
                .select('title')
                .eq('id', entityId)
                .maybeSingle();
            if (table != null) {
              tableTitle = table['title'] ?? tableTitle;
            }
          }
        } catch (e) {
          print('⚠️ Push chat nav: fallback to raw data: $e');
        }

        // Normalize 'direct' -> 'dm' so ChatScreen queries the right tables
        final normalizedChatType = (chatType == 'direct') ? 'dm' : chatType;

        final navContext = navigatorKey.currentContext;
        if (navContext != null) {
          showModalBottomSheet(
            context: navContext,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            enableDrag: true,
            builder: (context) => ChatScreen(
              channelId: channelId,
              tableId: entityId!,
              tableTitle: tableTitle,
              chatType: normalizedChatType,
            ),
          );
        }
      }
    } else if (data['type'] == 'group_join_request' ||
        data['type'] == 'group_approved' ||
        data['type'] == 'group_invite' ||
        data['type'] == 'group_invite_suggestion' ||
        data['type'] == 'group_admin_promoted' ||
        data['type'] == 'group_detail') {
      // Group membership notifications — open the group detail screen.
      // entity_id (or explicit group_id) carries the group id.
      final groupId =
          data['group_id']?.toString() ?? data['entity_id']?.toString();
      if (groupId != null) {
        final navContext = navigatorKey.currentContext;
        if (navContext != null) {
          Navigator.of(navContext).push(
            MaterialPageRoute(
              builder: (_) => GroupDetailScreen(groupId: groupId),
            ),
          );
        }
      }
    } else if (data['type'] == 'follower_event' || data['type'] == 'new_event') {
      // new_event: fired by notify_followers_new_event + notify_past_buyers_new_event
      final eventId =
          data['event_id']?.toString() ?? data['entity_id']?.toString();
      if (eventId != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MainNavigationScreen(
              initialIndex: 0,
              initialEventId: eventId,
            ),
          ),
          (route) => false,
        );
      }
    } else if (data['type'] == 'table_join' ||
        data['type'] == 'join_request' ||
        data['type'] == 'approved' ||
        data['type'] == 'declined' ||
        data['type'] == 'hangout_invite' ||
        data['type'] == 'follower_hangout' ||
        data['type'] == 'friend_joined' ||
        data['type'] == 'event_reminder' ||
        data['type'] == 'ticket_purchase' ||
        data['type'] == 'host_status_update') {
      // All table-related notifications — open map with table detail
      final tableId =
          data['table_id']?.toString() ?? data['entity_id']?.toString();
      if (tableId != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MainNavigationScreen(
              initialIndex: 0, // Map Tab
              initialTableId: tableId,
            ),
          ),
          (route) => false,
        );
      }
    } else if (data['type'] == 'like' ||
        data['type'] == 'comment' ||
        data['type'] == 'mention') {
      // Social notifications (incl. post/comment mentions) — open the post detail.
      // Chat mentions are handled above (they carry a chat_type).
      final postId =
          data['post_id']?.toString() ?? data['entity_id']?.toString();
      if (postId != null) {
        final navContext = navigatorKey.currentContext;
        if (navContext != null) {
          Navigator.of(navContext).push(
            MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
          );
        }
      }
    } else if (data['type'] == 'ticket_approved') {
      // Registration approved — open My Tickets so they can see and pay/view
      final navContext = navigatorKey.currentContext;
      if (navContext != null) {
        Navigator.of(navContext).push(
          MaterialPageRoute(builder: (_) => const MyTicketsScreen()),
        );
      }
    } else if (data['type'] == 'ticket_rejected') {
      // Registration rejected — open My Tickets to see rejection reason
      final navContext = navigatorKey.currentContext;
      if (navContext != null) {
        Navigator.of(navContext).push(
          MaterialPageRoute(builder: (_) => const MyTicketsScreen()),
        );
      }
    } else if (data['type'] == 'subscription_confirmed' ||
        data['type'] == 'subscription_expired' ||
        data['type'] == 'subscription_renewal_reminder' ||
        data['type'] == 'claim_fulfilled') {
      // Fan subscription events → open My Memberships
      final navContext = navigatorKey.currentContext;
      if (navContext != null) {
        Navigator.of(navContext).push(
          MaterialPageRoute(builder: (_) => const MyMembershipsScreen()),
        );
      }
    } else if (data['type'] == 'new_follower') {
      // Someone followed you → open their profile.
      // notify_new_follower sets entity_id + metadata.follower_id to the follower.
      final followerId =
          data['follower_id']?.toString() ?? data['entity_id']?.toString();
      if (followerId != null) {
        final navContext = navigatorKey.currentContext;
        if (navContext != null) {
          Navigator.of(navContext).push(
            MaterialPageRoute(
              builder: (_) => UserProfileScreen(userId: followerId),
            ),
          );
        }
      }
    } else if (data['type'] == 'new_subscriber_post') {
      // New members-only post → open Feed tab
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const MainNavigationScreen(initialIndex: 1),
        ),
        (route) => false,
      );
    } else if (data['type'] == 'new_claim_received') {
      // Organizer: new claim received → open Profile tab (host dashboard)
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const MainNavigationScreen(initialIndex: 3),
        ),
        (route) => false,
      );
    } else if (data['type'] == 'broadcast') {
      // Admin broadcast — route to target tab
      // Tab indices: Map=0, Feed=1, Explore=2, Profile=3
      final target = data['target']?.toString();
      int tabIndex = 1; // Default: Feed

      switch (target) {
        case 'map':
          tabIndex = 0;
          break;
        case 'feed':
          tabIndex = 1;
          break;
        case 'tickets':
          tabIndex = 2;
          break;
        case 'profile':
          tabIndex = 3;
          break;
        default:
          tabIndex = 1;
          break;
      }

      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MainNavigationScreen(initialIndex: tabIndex),
        ),
        (route) => false,
      );
    } else {
      // Unknown type — fallback to Feed tab
      print('⚠️ Unknown notification type: ${data['type']}, opening feed');
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const MainNavigationScreen(initialIndex: 1),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      User? user = SupabaseConfig.client.auth.currentUser;

      // If no user yet, wait for auth state and retry (handles cold start race condition)
      if (user == null) {
        print('⏳ FCM: No user yet, waiting for auth...');
        await Future.delayed(const Duration(seconds: 3));
        user = SupabaseConfig.client.auth.currentUser;
      }

      if (user != null) {
        await SupabaseConfig.client
            .from('users')
            .update({'fcm_token': token})
            .eq('id', user.id);
        print('✅ FCM: Token saved to Supabase for ${user.email}');
      } else {
        print('⚠️ FCM: Still no user after wait — token not saved');
      }
    } catch (e) {
      print('❌ FCM: Error saving token: $e');
    }
  }

  /// Call this after login to ensure the FCM token is saved for the new session
  Future<void> saveTokenOnLogin() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToSupabase(token);
      }
    } catch (e) {
      print('❌ FCM: Error saving token on login: $e');
    }
  }

  /// Clear this device's FCM token from the current user's row on logout so the
  /// account stops receiving pushes on this device. MUST run BEFORE
  /// auth.signOut() — afterwards currentUser is null and RLS blocks the update.
  /// (A DB trigger also enforces one-user-per-token, but clearing here closes
  /// the window immediately and handles the case where the next login is on a
  /// different device.)
  Future<void> clearTokenOnLogout() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      await SupabaseConfig.client
          .from('users')
          .update({'fcm_token': null})
          .eq('id', user.id);
      print('✅ FCM: Token cleared on logout for ${user.email}');
    } catch (e) {
      print('❌ FCM: Error clearing token on logout: $e');
    }
  }
}
