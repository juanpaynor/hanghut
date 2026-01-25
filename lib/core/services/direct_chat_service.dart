import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for handling direct 1:1 chat conversations
class DirectChatService {
  static final DirectChatService _instance = DirectChatService._internal();
  factory DirectChatService() => _instance;
  DirectChatService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  /// Find existing conversation or create a new one between current user and target user
  Future<String> startConversation(String targetUserId) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in');
    }

    // Use the secure RPC function to get or create the chat
    // This handles the logic atomically and bypasses RLS for creation via SECURITY DEFINER
    final chatId = await _client.rpc<String>(
      'get_or_create_dm_chat',
      params: {'target_user_id': targetUserId},
    );

    return chatId;
  }

  /// Get all conversations for the current user
  Future<List<Map<String, dynamic>>> getConversations() async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return [];

    try {
      final conversations = await _client
          .from('direct_chat_participants')
          .select('''
            chat_id,
            direct_chats!inner(
              id,
              updated_at,
              created_at
            )
          ''')
          .eq('user_id', currentUserId)
          .order('direct_chats(updated_at)', ascending: false);

      // For each conversation, get the other participant and last message
      final enrichedConversations = <Map<String, dynamic>>[];

      for (var conv in conversations) {
        final chatId = conv['chat_id'];

        // Get other participant
        final otherParticipant = await _client
            .from('direct_chat_participants')
            .select('user_id, users!inner(id, display_name, avatar_url)')
            .eq('chat_id', chatId)
            .neq('user_id', currentUserId)
            .single();

        // Get last message
        final lastMessage = await _client
            .from('direct_messages')
            .select('content, created_at, sender_id')
            .eq('chat_id', chatId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        enrichedConversations.add({
          'chat_id': chatId,
          'other_user': otherParticipant['users'],
          'last_message': lastMessage,
          'updated_at': conv['direct_chats']['updated_at'],
        });
      }

      return enrichedConversations;
    } catch (e) {
      print('Error getting conversations: $e');
      return [];
    }
  }

  /// Get messages for a specific conversation
  Future<List<Map<String, dynamic>>> getMessages(String chatId) async {
    try {
      final messages = await _client
          .from('direct_messages')
          .select('''
            id,
            content,
            sender_id,
            created_at,
            message_type,
            users!sender_id(id, display_name, avatar_url)
          ''')
          .eq('chat_id', chatId)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(messages);
    } catch (e) {
      print('Error getting messages: $e');
      return [];
    }
  }

  /// Send a message in a conversation
  Future<Map<String, dynamic>?> sendMessage({
    required String chatId,
    required String content,
    String messageType = 'text',
  }) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null) return null;

      final message = await _client
          .from('direct_messages')
          .insert({
            'chat_id': chatId,
            'sender_id': currentUserId,
            'content': content,
            'message_type': messageType,
          })
          .select('''
            id,
            content,
            sender_id,
            created_at,
            message_type,
            users!sender_id(id, display_name, avatar_url)
          ''')
          .single();

      // Update the chat's updated_at timestamp
      await _client
          .from('direct_chats')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', chatId);

      return message;
    } catch (e) {
      print('Error sending message: $e');
      return null;
    }
  }

  /// Mark messages as read
  Future<void> markAsRead(String chatId) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null) return;

      await _client
          .from('direct_chat_participants')
          .update({'last_read_at': DateTime.now().toIso8601String()})
          .eq('chat_id', chatId)
          .eq('user_id', currentUserId);
    } catch (e) {
      print('Error marking as read: $e');
    }
  }
}
