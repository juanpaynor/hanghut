import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:bitemates/core/services/chat_database.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ChatScreen extends StatefulWidget {
  final String tableId;
  final String tableTitle;
  final String channelId;
  final String chatType; // 'table' or 'trip'

  const ChatScreen({
    super.key,
    required this.tableId,
    required this.tableTitle,
    required this.channelId,
    this.chatType = 'table',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ablyService = AblyService();
  final _chatDatabase = ChatDatabase();
  final _memberService = TableMemberService();
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;
  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserPhoto;
  Map<String, dynamic>? _replyingTo;
  bool _isHost = false;
  Map<String, List<Map<String, dynamic>>> _messageReactions = {};
  bool _useTelegramMode = false; // Feature flag for chat storage type
  Timer? _batchSyncTimer; // Periodic sync timer for Telegram mode

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    await _getCurrentUser();
    await _checkIfHost();
    await _loadParticipants();
    await _loadMessageHistory();
    _subscribeToAbly();
    _subscribeToReactions();

    // Start batch sync timer for Telegram mode
    if (_useTelegramMode) {
      _startBatchSyncTimer();
    }
  }

  Future<void> _checkIfHost() async {
    if (widget.chatType == 'trip') {
      // Trip chats now also use Telegram mode (Local First) 🚀
      setState(() {
        _isHost = false;
        _useTelegramMode = true;
      });
      return;
    }

    try {
      final table = await SupabaseConfig.client
          .from('tables')
          .select('host_id, chat_storage_type')
          .eq('id', widget.tableId)
          .single();

      setState(() {
        _isHost = table['host_id'] == _currentUserId;
        _useTelegramMode = table['chat_storage_type'] == 'telegram';
      });

      if (_useTelegramMode) {
        print('📱 Using Telegram mode (local-first) for this table');
      } else {
        print('💾 Using legacy mode (database-first) for this table');
      }
    } catch (e) {
      print('❌ CHAT: Error checking host status - $e');
    }
  }

  void _subscribeToReactions() {
    SupabaseConfig.client
        .channel('message_reactions:${widget.tableId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: widget.chatType == 'trip'
              ? 'trip_messages'
              : 'message_reactions', // Trip reactions not yet supported
          callback: (payload) {
            if (widget.chatType != 'trip') _loadReactions();
          },
        )
        .subscribe();
  }

  Future<void> _loadReactions() async {
    try {
      final messageIds = _messages
          .map((m) => m['id'])
          .where((id) => id != null)
          .toList();
      if (messageIds.isEmpty) return;

      final reactions = await SupabaseConfig.client
          .from('message_reactions')
          .select('*')
          .inFilter('message_id', messageIds);

      // Fetch user display names for reactions
      final userIds = List<Map<String, dynamic>>.from(
        reactions,
      ).map((r) => r['user_id'] as String).toSet().toList();

      final users = userIds.isEmpty
          ? []
          : await SupabaseConfig.client
                .from('users')
                .select('id, display_name')
                .inFilter('id', userIds);

      final userMap = {for (var u in users) u['id']: u['display_name']};

      final reactionMap = <String, List<Map<String, dynamic>>>{};
      for (var reaction in reactions) {
        final msgId = reaction['message_id'];
        reactionMap.putIfAbsent(msgId, () => []);
        reactionMap[msgId]!.add({
          ...reaction,
          'displayName': userMap[reaction['user_id']] ?? 'Unknown',
        });
      }

      if (mounted) {
        setState(() {
          _messageReactions = reactionMap;
        });
      }
    } catch (e) {
      print('❌ Error loading reactions: $e');
    }
  }

  Future<void> _loadParticipants() async {
    try {
      final query = widget.chatType == 'trip'
          ? SupabaseConfig.client
                .from('trip_chat_participants')
                .select('user_id')
                .eq(
                  'chat_id',
                  widget.tableId,
                ) // tableId holds chat_id for trips
          : SupabaseConfig.client
                .from('table_members')
                .select('user_id')
                .eq('table_id', widget.tableId)
                .inFilter('status', [
                  'approved',
                  'joined',
                  'attended',
                ]); // Only show active members

      final response = await query;

      final userIds = List<Map<String, dynamic>>.from(
        response,
      ).map((p) => p['user_id'] as String).toList();

      if (userIds.isEmpty) {
        if (mounted) setState(() => _participants = []);
        return;
      }

      // Fetch user details
      final users = await SupabaseConfig.client
          .from('users')
          .select('id, display_name')
          .inFilter('id', userIds);

      // Fetch user photos
      final photos = await SupabaseConfig.client
          .from('user_photos')
          .select('user_id, photo_url')
          .inFilter('user_id', userIds)
          .eq('is_primary', true);

      final photoMap = {for (var p in photos) p['user_id']: p['photo_url']};

      if (mounted) {
        setState(() {
          _participants = List<Map<String, dynamic>>.from(users).map((u) {
            return {
              'userId': u['id'],
              'displayName': u['display_name'],
              'photoUrl': photoMap[u['id']],
            };
          }).toList();
        });
      }
    } catch (e) {
      print('❌ CHAT: Error loading participants - $e');
    }
  }

  Future<void> _getCurrentUser() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null) {
      _currentUserId = user.id;

      // Fetch user details
      final userData = await SupabaseConfig.client
          .from('users')
          .select('display_name')
          .eq('id', user.id)
          .single();

      // Fetch user photo
      final photoData = await SupabaseConfig.client
          .from('user_photos')
          .select('photo_url')
          .eq('user_id', user.id)
          .eq('is_primary', true)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _currentUserName = userData['display_name'];
          _currentUserPhoto = photoData?['photo_url'];
        });
      }
    }
  }

  Future<void> _loadMessageHistory() async {
    if (_useTelegramMode) {
      await _loadMessageHistory_Telegram();
    } else {
      await _loadMessageHistory_Legacy();
    }
  }

  /// Telegram mode: Load from local SQLite first
  Future<void> _loadMessageHistory_Telegram() async {
    try {
      final localMessages = await _chatDatabase.getMessages(widget.tableId);

      if (localMessages.isNotEmpty) {
        await _enrichAndDisplayMessages(localMessages);
      } else {
        print('📥 First time - syncing from cloud...');
        await _chatDatabase.initialSyncFromCloud(
          widget.tableId,
          chatType: widget.chatType,
        );
        final syncedMessages = await _chatDatabase.getMessages(widget.tableId);
        await _enrichAndDisplayMessages(syncedMessages);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ CHAT: Error loading messages (Telegram mode) - $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Legacy mode: Load from Supabase
  Future<void> _loadMessageHistory_Legacy() async {
    try {
      final tableName = widget.chatType == 'trip'
          ? 'trip_messages'
          : 'messages';
      final idColumn = widget.chatType == 'trip' ? 'chat_id' : 'table_id';

      // Note: trip_messages has 'message_type', messages has 'content_type'.
      // We handle this mismatch in the map below.

      final messages = await SupabaseConfig.client
          .from(tableName)
          .select('*')
          .eq(idColumn, widget.tableId)
          .order(
            widget.chatType == 'trip' ? 'sent_at' : 'timestamp',
            ascending: true,
          )
          .limit(50);

      final messageList = List<Map<String, dynamic>>.from(messages);

      // Collect all sender IDs and reply_to IDs
      final senderIds = messageList
          .map((m) => m['sender_id'] as String)
          .toSet();
      final replyToIds = messageList
          .where((m) => m['reply_to_id'] != null)
          .map((m) => m['reply_to_id'] as String)
          .toSet();

      // Fetch users data
      final users = senderIds.isEmpty
          ? []
          : await SupabaseConfig.client
                .from('users')
                .select('id, display_name')
                .inFilter('id', senderIds.toList());

      final photos = senderIds.isEmpty
          ? []
          : await SupabaseConfig.client
                .from('user_photos')
                .select('user_id, photo_url')
                .inFilter('user_id', senderIds.toList())
                .eq('is_primary', true);

      // Fetch reply messages if any
      final replyMessages = replyToIds.isEmpty
          ? []
          : await SupabaseConfig.client
                .from('messages')
                .select('id, content, sender_id')
                .inFilter('id', replyToIds.toList());

      final userMap = {for (var u in users) u['id']: u['display_name']};
      final photoMap = {for (var p in photos) p['user_id']: p['photo_url']};
      final replyMap = {
        for (var r in replyMessages)
          r['id']: {
            'id': r['id'],
            'content': r['content'],
            'sender_id': r['sender_id'],
            'senderName': userMap[r['sender_id']] ?? 'Unknown',
          },
      };

      if (mounted) {
        setState(() {
          _messages = messageList.map((msg) {
            final senderId = msg['sender_id'];
            final replyToId =
                msg['reply_to_id']; // Likely null for trips initially
            final timestamp =
                msg['sent_at'] ?? msg['timestamp']; // Handle col name diff

            return {
              'id': msg['id'],
              'content': msg['content'],
              'contentType':
                  msg['message_type'] ?? msg['content_type'] ?? 'text',
              'senderId': senderId,
              'senderName': userMap[senderId] ?? 'Unknown',
              'senderPhotoUrl': photoMap[senderId],
              'timestamp': timestamp,
              'isMe': senderId == _currentUserId,
              'deletedAt': msg['deleted_at'],
              'deletedForEveryone': msg['deleted_for_everyone'] ?? false,
              'replyTo': replyToId != null ? replyMap[replyToId] : null,
            };
          }).toList();
          _isLoading = false;
        });
        _scrollToBottom();
        _loadReactions();
      }
    } catch (e) {
      print('❌ CHAT: Error loading history - $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Enrich messages with user data (shared by Telegram & Legacy modes)
  Future<void> _enrichAndDisplayMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    if (messages.isEmpty) return;

    try {
      final senderIds = messages.map((m) => m['sender_id'] as String).toSet();

      final users = await SupabaseConfig.client
          .from('users')
          .select('id, display_name')
          .inFilter('id', senderIds.toList());

      final photos = await SupabaseConfig.client
          .from('user_photos')
          .select('user_id, photo_url')
          .inFilter('user_id', senderIds.toList())
          .eq('is_primary', true);

      final userMap = {for (var u in users) u['id']: u['display_name']};
      final photoMap = {for (var p in photos) p['user_id']: p['photo_url']};

      if (mounted) {
        setState(() {
          _messages = messages.map((msg) {
            final timestamp = msg['timestamp'];
            final timestampStr = timestamp is int
                ? DateTime.fromMillisecondsSinceEpoch(
                    timestamp,
                  ).toIso8601String()
                : timestamp;

            return {
              'id': msg['id'],
              'content': msg['content'],
              'contentType':
                  msg['message_type'] ?? msg['content_type'] ?? 'text',
              'senderId': msg['sender_id'],
              'senderName': userMap[msg['sender_id']] ?? 'Unknown',
              'senderPhotoUrl': photoMap[msg['sender_id']],
              'timestamp': timestampStr,
              'isMe': msg['sender_id'] == _currentUserId,
            };
          }).toList();
        });
        _scrollToBottom();
        _loadReactions();
      }
    } catch (e) {
      print('❌ Error enriching messages: $e');
    }
  }

  void _subscribeToAbly() async {
    await _ablyService.init();
    final stream = _ablyService.getChannelStream(widget.channelId);

    stream?.listen((ably.Message message) {
      if (message.data != null) {
        final data = Map<String, dynamic>.from(message.data as Map);

        // In Telegram mode, skip our own messages (already added locally)
        if (_useTelegramMode && data['senderId'] == _currentUserId) {
          return;
        }

        if (mounted) {
          setState(() {
            _messages.add({
              'content': data['content'],
              'contentType': data['contentType'] ?? 'text',
              'senderId': data['senderId'],
              'senderName': data['senderName'],
              'senderPhotoUrl': data['senderPhotoUrl'],
              'timestamp': data['timestamp'],
              'isMe': data['senderId'] == _currentUserId,
            });
          });
          _scrollToBottom();
        }
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({String? gifUrl}) async {
    if (_useTelegramMode) {
      await _sendMessage_Telegram(gifUrl: gifUrl);
    } else {
      await _sendMessage_Legacy(gifUrl: gifUrl);
    }
  }

  /// Telegram mode: Save to local DB first, then sync
  Future<void> _sendMessage_Telegram({String? gifUrl}) async {
    final content = gifUrl ?? _messageController.text.trim();
    final contentType = gifUrl != null ? 'gif' : 'text';

    if (content.isEmpty || _currentUserId == null) return;

    _messageController.clear();
    final replyToId = _replyingTo?['id'];
    setState(() {
      _replyingTo = null;
    });

    try {
      const uuid = Uuid();
      final messageId = uuid.v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final message = {
        'id': messageId,
        'table_id': widget.tableId,
        'sender_id': _currentUserId!,
        'sender_name': _currentUserName,
        'content': content,
        'timestamp': timestamp,
        'message_type': contentType,
        if (gifUrl != null) 'gif_url': gifUrl,
        if (replyToId != null) 'reply_to_id': replyToId,
        'chat_type': widget.chatType,
        'synced': 0,
      };

      // 1. Save locally
      await _chatDatabase.saveMessage(message);

      // Update UI immediately
      if (mounted) {
        setState(() {
          _messages.add({
            ...message,
            'timestamp': DateTime.fromMillisecondsSinceEpoch(
              timestamp,
            ).toIso8601String(),
            'contentType': contentType,
            'isMe': true,
            'senderName': _currentUserName ?? 'You',
            'senderPhotoUrl': _currentUserPhoto,
            'senderId': _currentUserId!,
          });
        });
        _scrollToBottom();
      }

      // 2. Publish to Ably
      await _ablyService.publishMessage(
        channelName: widget.channelId,
        content: content,
        contentType: contentType,
        senderId: _currentUserId!,
        senderName: _currentUserName ?? 'Unknown',
        senderPhotoUrl: _currentUserPhoto,
      );

      // Note: Sync happens in 60-second batches (see _startBatchSyncTimer)
    } catch (e) {
      print('❌ CHAT: Error sending message (Telegram) - $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    }
  }

  /// Legacy mode: Save to Supabase first
  Future<void> _sendMessage_Legacy({String? gifUrl}) async {
    final content = gifUrl ?? _messageController.text.trim();
    final contentType = gifUrl != null ? 'gif' : 'text';

    if (content.isEmpty || _currentUserId == null) return;

    _messageController.clear();
    final replyToId = _replyingTo?['id'];
    setState(() {
      _replyingTo = null;
    });

    try {
      // 1. Save to Supabase
      if (widget.chatType == 'trip') {
        await SupabaseConfig.client.from('trip_messages').insert({
          'chat_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': content,
          'message_type': contentType,
          // 'reply_to_id': replyToId, // Schema update needed if we want replies in trips
        });
      } else {
        await SupabaseConfig.client.from('messages').insert({
          'table_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': content,
          'content_type': contentType,
          if (replyToId != null) 'reply_to_id': replyToId,
        });
      }

      // 2. Publish to Ably
      await _ablyService.publishMessage(
        channelName: widget.channelId,
        content: content,
        contentType: contentType,
        senderId: _currentUserId!,
        senderName: _currentUserName ?? 'Unknown',
        senderPhotoUrl: _currentUserPhoto,
      );
    } catch (e) {
      print('❌ CHAT: Error sending message - $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    }
  }

  void _handleReply(Map<String, dynamic> message) {
    setState(() {
      _replyingTo = message;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  Future<void> _handleReaction(String messageId, String emoji) async {
    try {
      // Check if user already reacted with this emoji
      final existing = await SupabaseConfig.client
          .from('message_reactions')
          .select('id')
          .eq('message_id', messageId)
          .eq('user_id', _currentUserId!)
          .eq('emoji', emoji)
          .maybeSingle();

      if (existing != null) {
        // Remove reaction
        await SupabaseConfig.client
            .from('message_reactions')
            .delete()
            .eq('id', existing['id']);
      } else {
        // Add reaction
        await SupabaseConfig.client.from('message_reactions').insert({
          'message_id': messageId,
          'user_id': _currentUserId,
          'emoji': emoji,
        });
      }
    } catch (e) {
      print('❌ Error handling reaction: $e');
    }
  }

  Future<void> _handleDelete(
    Map<String, dynamic> message,
    bool deleteForEveryone,
  ) async {
    try {
      await SupabaseConfig.client
          .from('messages')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_for_everyone': deleteForEveryone,
          })
          .eq('id', message['id']);

      await _loadMessageHistory();
    } catch (e) {
      print('❌ Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete message')),
        );
      }
    }
  }

  void _showGifPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TenorGifPicker(
        onGifSelected: (gifUrl) {
          _sendMessage(gifUrl: gifUrl);
        },
      ),
    );
  }

  Future<void> _leaveTable() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Chat?'),
        content: const Text(
          'You will be removed from this activity and its chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) setState(() => _isLoading = true);

    await _memberService.leaveTable(widget.tableId);

    if (mounted) {
      Navigator.pop(context, true); // Close chat with change signal
    }
  }

  @override
  void dispose() {
    _batchSyncTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _ablyService.leaveChannel(widget.channelId);
    super.dispose();
  }

  /// Start periodic batch sync timer (Telegram mode only)
  void _startBatchSyncTimer() {
    _batchSyncTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _syncPendingMessages(),
    );
    print('⏰ Batch sync timer started (60s intervals)');
  }

  /// Sync all unsynced messages to cloud
  Future<void> _syncPendingMessages() async {
    if (!_useTelegramMode) return;

    try {
      final unsyncedMessages = await _chatDatabase.getUnsyncedMessages(
        widget.tableId,
      );

      if (unsyncedMessages.isEmpty) {
        return;
      }

      print('📤 Syncing ${unsyncedMessages.length} pending messages...');

      for (var msg in unsyncedMessages) {
        await _chatDatabase.syncToCloud(msg);
      }

      print('✅ Batch sync complete');
    } catch (e) {
      print('⚠️ Batch sync failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Set a fixed height for the sheet (e.g., 90% of screen)
    // or let it adapt if we prefer. Given it's a chat, taking most of the screen is good.
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag Handle & Header
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.tableTitle,
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: () => _showParticipantsSheet(),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_participants.length} Active',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions Menu
                  PopupMenuButton<String>(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: Colors.black54,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) {
                      if (value == 'leave') {
                        _leaveTable();
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'leave',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.exit_to_app,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Leave Chat',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                  ),
                  const SizedBox(width: 8),
                  // Close Button
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.black54,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.black12),

            // Messages Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.grey[300],
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start the conversation!',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg['isMe'] as bool;
                        final showHeader =
                            index == 0 ||
                            _messages[index - 1]['senderId'] != msg['senderId'];

                        return Padding(
                          padding: EdgeInsets.only(
                            top: showHeader ? 16 : 4,
                            bottom: 4,
                          ),
                          child: Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe && showHeader)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    bottom: 4,
                                  ),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              UserProfileScreen(
                                                userId: msg['senderId'],
                                              ),
                                        ),
                                      );
                                    },
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.grey[300],
                                      backgroundImage:
                                          msg['senderPhotoUrl'] != null
                                          ? NetworkImage(msg['senderPhotoUrl'])
                                          : null,
                                      child: msg['senderPhotoUrl'] == null
                                          ? Icon(
                                              Icons.person,
                                              size: 16,
                                              color: Colors.grey[600],
                                            )
                                          : null,
                                    ),
                                  ),
                                )
                              else if (!isMe)
                                const SizedBox(width: 40),

                              Flexible(
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (showHeader && !isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 12,
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          msg['senderName'] ?? 'Unknown',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),

                                    // Message Bubble & Actions Wrapper
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        // Left Actions (for Other)
                                        if (!isMe) ...[
                                          // Hidden actions that appear on swipe?
                                          // For simplicity, keeping actions logic but maybe simplified UI
                                          // Or just tap bubble to act
                                        ],

                                        Flexible(
                                          child: GestureDetector(
                                            onLongPress: () =>
                                                _showMessageActions(msg),
                                            child: Container(
                                              padding:
                                                  msg['contentType'] == 'gif'
                                                  ? EdgeInsets.zero
                                                  : const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                              decoration: BoxDecoration(
                                                color:
                                                    msg['contentType'] == 'gif'
                                                    ? Colors.transparent
                                                    : (isMe
                                                          ? Colors
                                                                .black // My Bubble
                                                          : Colors
                                                                .grey[100]), // Other Bubble
                                                borderRadius: BorderRadius.only(
                                                  topLeft:
                                                      const Radius.circular(20),
                                                  topRight:
                                                      const Radius.circular(20),
                                                  bottomLeft: Radius.circular(
                                                    isMe ? 20 : 4,
                                                  ),
                                                  bottomRight: Radius.circular(
                                                    isMe ? 4 : 20,
                                                  ),
                                                ),
                                                // Add shadow to mine for pop
                                                boxShadow:
                                                    isMe &&
                                                        msg['contentType'] !=
                                                            'gif'
                                                    ? [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                alpha: 0.1,
                                                              ),
                                                          blurRadius: 4,
                                                          offset: Offset(0, 2),
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // Reply Preview Inside Bubble
                                                  if (msg['replyTo'] != null)
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                            bottom: 6,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: isMe
                                                            ? Colors.white
                                                                  .withValues(
                                                                    alpha: 0.2,
                                                                  )
                                                            : Colors.black
                                                                  .withValues(
                                                                    alpha: 0.05,
                                                                  ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border(
                                                          left: BorderSide(
                                                            color: isMe
                                                                ? Colors.white
                                                                : Colors
                                                                      .black54,
                                                            width: 2,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            msg['replyTo']['senderName'] ??
                                                                'Unknown',
                                                            style: TextStyle(
                                                              color: isMe
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .black87,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                          Text(
                                                            msg['replyTo']['content'] ??
                                                                '',
                                                            style: TextStyle(
                                                              color: isMe
                                                                  ? Colors
                                                                        .white70
                                                                  : Colors
                                                                        .black54,
                                                              fontSize: 12,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ],
                                                      ),
                                                    ),

                                                  // Content
                                                  if (msg['contentType'] ==
                                                      'gif')
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      child: CachedNetworkImage(
                                                        imageUrl:
                                                            msg['content'],
                                                        width: 200,
                                                        fit: BoxFit.cover,
                                                        placeholder:
                                                            (
                                                              context,
                                                              url,
                                                            ) => Container(
                                                              width: 200,
                                                              height: 200,
                                                              color: Colors
                                                                  .grey[200],
                                                              child: const Center(
                                                                child:
                                                                    CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                              ),
                                                            ),
                                                        errorWidget:
                                                            (
                                                              context,
                                                              url,
                                                              error,
                                                            ) => const Icon(
                                                              Icons.error,
                                                            ),
                                                      ),
                                                    )
                                                  else
                                                    Text(
                                                      msg['deletedAt'] !=
                                                                  null &&
                                                              (msg['deletedForEveryone'] ||
                                                                  !isMe)
                                                          ? '[Message deleted]'
                                                          : msg['content'],
                                                      style: TextStyle(
                                                        color: isMe
                                                            ? Colors.white
                                                            : Colors.black87,
                                                        fontSize: 16,
                                                        fontStyle:
                                                            (msg['deletedAt'] !=
                                                                null)
                                                            ? FontStyle.italic
                                                            : FontStyle.normal,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Reactions & Timestamp
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                        left: 4,
                                        right: 4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_messageReactions[msg['id']]
                                                  ?.isNotEmpty ==
                                              true)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              child: Wrap(
                                                spacing: 4,
                                                children: _buildReactionChips(
                                                  msg['id'],
                                                ),
                                              ),
                                            ),
                                          Text(
                                            DateFormat('h:mm a').format(
                                              DateTime.parse(
                                                msg['timestamp'],
                                              ).toLocal(),
                                            ),
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Input Area
            Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (_replyingTo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Replying to ${_replyingTo!['senderName']}',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _replyingTo!['content'],
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 20,
                              color: Colors.black54,
                            ),
                            onPressed: _cancelReply,
                          ),
                        ],
                      ),
                    ),

                  Row(
                    children: [
                      // GIF Button
                      IconButton(
                        icon: const Icon(
                          Icons.gif_box_outlined,
                          color: Colors.black54,
                        ),
                        onPressed: _showGifPicker,
                      ),
                      const SizedBox(width: 8),
                      // Text Input
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TextField(
                            controller: _messageController,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              hintStyle: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.color,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Send Button
                      GestureDetector(
                        onTap: () => _sendMessage(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor, // Bright indigo
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Methods (Updated for Light Theme) ---

  void _showParticipantsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.people_outline, color: Colors.black87),
                  const SizedBox(width: 12),
                  Text(
                    '${_participants.length} Participants',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _participants.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final participant = _participants[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(context); // Close member sheet
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              UserProfileScreen(userId: participant['userId']),
                        ),
                      );
                    },
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey[200],
                      backgroundImage: participant['photoUrl'] != null
                          ? NetworkImage(participant['photoUrl'])
                          : null,
                      child: participant['photoUrl'] == null
                          ? Text(
                              participant['displayName'][0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      participant['displayName'],
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      participant['userId'] == _currentUserId
                          ? 'You'
                          : 'Member',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  void _showMessageActions(Map<String, dynamic> message) {
    final isOwnMessage = message['senderId'] == _currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.black87),
              title: const Text(
                'Reply',
                style: TextStyle(color: Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleReply(message);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.emoji_emotions_outlined,
                color: Colors.black87,
              ),
              title: const Text(
                'React',
                style: TextStyle(color: Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _showEmojiPicker(message['id']);
              },
            ),
            if (isOwnMessage) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete for me',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleDelete(message, false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'Delete for everyone',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleDelete(message, true);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showEmojiPicker(String messageId) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥', '🎉', '👏'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: emojis
                .map(
                  (emoji) => GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _handleReaction(messageId, emoji);
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildReactionChips(String messageId) {
    final reactions = _messageReactions[messageId] ?? [];
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (var reaction in reactions) {
      final emoji = reaction['emoji'];
      grouped.putIfAbsent(emoji, () => []);
      grouped[emoji]!.add(reaction);
    }

    return grouped.entries.map((entry) {
      final emoji = entry.key;
      final users = entry.value;
      final hasMyReaction = users.any((r) => r['user_id'] == _currentUserId);

      return GestureDetector(
        onTap: () => _handleReaction(messageId, emoji),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasMyReaction ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasMyReaction ? Colors.black : Colors.grey[300]!,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                '${users.length}',
                style: TextStyle(
                  color: hasMyReaction ? Colors.white : Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
