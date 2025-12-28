import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:bitemates/core/config/ably_config.dart';

class AblyService {
  static final AblyService _instance = AblyService._internal();
  factory AblyService() => _instance;
  AblyService._internal();

  ably.Realtime? _realtime;

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

  Future<void> publishMessage({
    required String channelName,
    required String content,
    required String senderId,
    required String senderName,
    String? senderPhotoUrl,
    String contentType = 'text',
  }) async {
    if (_realtime == null) await init();

    try {
      final channel = _realtime!.channels.get(channelName);
      await channel.publish(
        name: 'chat_message',
        data: {
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

  void dispose() {
    _realtime?.close();
    _realtime = null;
  }
}
