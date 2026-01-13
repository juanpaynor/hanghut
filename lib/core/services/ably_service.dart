import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:bitemates/core/config/ably_config.dart';

class AblyService {
  static final AblyService _instance = AblyService._internal();
  factory AblyService() => _instance;
  AblyService._internal();

  ably.Realtime? _realtime;
  bool _isConnected = false;

  Future<void> init() async {
    if (_realtime != null) return;

    try {
      _realtime = ably.Realtime(
        options: ably.ClientOptions(
          key: AblyConfig.apiKey,
          autoConnect: true,
          // Optional: Add clientId for presence features
          // clientId: user.id,
        ),
      );

      _realtime!.connection.on().listen((stateChange) {
        print('🔄 ABLY: Connection state changed: ${stateChange.current}');
        _isConnected = stateChange.current == ably.ConnectionState.connected;

        // Auto-reconnect on disconnect
        if (stateChange.current == ably.ConnectionState.disconnected ||
            stateChange.current == ably.ConnectionState.suspended) {
          print('⚠️ ABLY: Connection lost, will auto-reconnect');
        }
      });

      print('✅ ABLY: Initialized');
    } catch (e) {
      print('❌ ABLY: Error initializing - $e');
    }
  }

  Stream<ably.Message>? getChannelStream(String channelName) {
    if (_realtime == null) return null;
    final channel = _realtime!.channels.get(channelName);
    return channel.subscribe();
  }

  ably.RealtimeChannel? getChannel(String channelName) {
    if (_realtime == null) return null;
    return _realtime!.channels.get(channelName);
  }

  Future<void> publishMessage({
    required String channelName,
    required String content,
    required String senderId,
    required String senderName,
    String? senderPhotoUrl,
    String contentType = 'text',
    String? messageId, // Add message ID
  }) async {
    if (_realtime == null) await init();

    try {
      final channel = _realtime!.channels.get(channelName);
      await channel.publish(
        name: 'chat_message',
        data: {
          'id': messageId, // Include message ID
          'content': content,
          'contentType': contentType,
          'senderId': senderId,
          'senderName': senderName,
          'senderPhotoUrl': senderPhotoUrl,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      print('✅ ABLY: Message published to $channelName');
    } catch (e) {
      print('❌ ABLY: Error publishing message - $e');
      rethrow;
    }
  }

  Future<void> leaveChannel(String channelName) async {
    if (_realtime == null) return;
    try {
      final channel = _realtime!.channels.get(channelName);
      await channel.detach();
      print('✅ ABLY: Detached from $channelName');
    } catch (e) {
      print('❌ ABLY: Error detaching - $e');
    }
  }

  // -----------------------------------------------------------------------------
  // Social Feed Real-Time Methods
  // -----------------------------------------------------------------------------

  /// Subscribe to city-specific social feed channel
  Stream<ably.Message>? subscribeToCityFeed(String city) {
    if (_realtime == null) return null;
    final channelName = 'feed:${city.toLowerCase()}';
    final channel = _realtime!.channels.get(channelName);
    print('✅ ABLY: Subscribed to $channelName');
    return channel.subscribe();
  }

  /// Publish post created event
  Future<void> publishPostCreated({
    required String city,
    required Map<String, dynamic> postData,
  }) async {
    if (_realtime == null) await init();

    try {
      final channelName = 'feed:${city.toLowerCase()}';
      final channel = _realtime!.channels.get(channelName);
      await channel.publish(name: 'post_created', data: postData);
      print('✅ ABLY: Published post_created to $channelName');
    } catch (e) {
      print('❌ ABLY: Error publishing post_created - $e');
    }
  }

  /// Publish post deleted event
  Future<void> publishPostDeleted({
    required String city,
    required String postId,
  }) async {
    if (_realtime == null) await init();

    try {
      final channelName = 'feed:${city.toLowerCase()}';
      final channel = _realtime!.channels.get(channelName);
      await channel.publish(name: 'post_deleted', data: {'post_id': postId});
      print('✅ ABLY: Published post_deleted to $channelName');
    } catch (e) {
      print('❌ ABLY: Error publishing post_deleted - $e');
    }
  }

  /// Publish comment added event
  Future<void> publishCommentAdded({
    required String city,
    required String postId,
    required Map<String, dynamic> commentData,
  }) async {
    if (_realtime == null) await init();

    try {
      final channelName = 'feed:${city.toLowerCase()}';
      final channel = _realtime!.channels.get(channelName);
      await channel.publish(
        name: 'comment_added',
        data: {'post_id': postId, 'comment': commentData},
      );
      print('✅ ABLY: Published comment_added to $channelName');
    } catch (e) {
      print('❌ ABLY: Error publishing comment_added - $e');
    }
  }

  /// Unsubscribe from city feed
  Future<void> unsubscribeFromCityFeed(String city) async {
    if (_realtime == null) return;
    try {
      final channelName = 'feed:${city.toLowerCase()}';
      final channel = _realtime!.channels.get(channelName);
      await channel.detach();
      print('✅ ABLY: Unsubscribed from $channelName');
    } catch (e) {
      print('❌ ABLY: Error unsubscribing - $e');
    }
  }

  /// Get connection status
  bool get isConnected => _isConnected;

  /// Get connection state stream
  Stream<ably.ConnectionStateChange>? getConnectionStateStream() {
    return _realtime?.connection.on();
  }

  /// Manual reconnect
  Future<void> reconnect() async {
    if (_realtime == null) return;
    try {
      await _realtime!.connection.close();
      await Future.delayed(Duration(seconds: 1));
      await _realtime!.connection.connect();
      print('🔄 ABLY: Manual reconnect triggered');
    } catch (e) {
      print('❌ ABLY: Reconnect failed - $e');
    }
  }

  void dispose() {
    _realtime?.close();
    _realtime = null;
    _isConnected = false;
  }
}
