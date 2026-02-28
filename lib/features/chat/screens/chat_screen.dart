import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:bitemates/core/services/chat_database.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/core/services/user_cache.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:bitemates/features/chat/widgets/chat_header.dart';
import 'package:bitemates/features/chat/widgets/chat_input_bar.dart';
import 'package:bitemates/features/chat/widgets/chat_message_list.dart';
import 'package:bitemates/features/chat/screens/chat_info_screen.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _ablyService = AblyService();
  final _chatDatabase = ChatDatabase();
  final _memberService = TableMemberService();
  final _userCache = UserCache();
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
  bool _ablyConnected = false; // Track Ably connection state
  bool _showConnectionBanner = false; // Show disconnected banner
  Timer? _reconnectTimer; // Automatic reconnection timer

  // Pagination
  int _messageLimit = 50; // Load 50 messages at a time
  int _messageOffset = 0;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;

  // Typing indicators
  bool _otherUserTyping = false;
  Timer? _typingTimer;
  bool _isTyping = false;
  ably.RealtimeChannel? _ablyChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    _messageController.addListener(_onTypingChanged);
    _scrollController.addListener(_onScroll); // Listen for scroll to load more
  }

  Future<void> _initializeChat() async {
    await _getCurrentUser();
    await _checkIfHost();
    await _loadParticipants();
    await _loadMessageHistory();
    _subscribeToAbly();
    _subscribeToReactions();
    _subscribeToParticipants();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _reconnectTimer?.cancel();
    _typingTimer?.cancel();
    _ablyService.leaveChannel(widget.channelId);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('📱 App resumed: Reloading chat history...');
      // Just reload history to catch up (Legacy Mode)
      _loadMessageHistory();
    }
  }

  Future<void> _checkIfHost() async {
    // FORCE LEGACY MODE for stability (fixes sync issues)
    setState(() {
      _useTelegramMode = false;
    });

    if (widget.chatType == 'trip' || widget.chatType == 'dm') {
      setState(() {
        _isHost = false;
      });
      return;
    }

    try {
      final table = await SupabaseConfig.client
          .from('tables')
          .select('host_id') // No longer need chat_storage_type
          .eq('id', widget.tableId)
          .single();

      setState(() {
        _isHost = table['host_id'] == _currentUserId;
      });
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
      // OPTIMIZATION: Only load reactions for visible messages (first 50)
      // This reduces database load for long chats
      final visibleMessages = _messages.take(50).toList();

      final messageIds = visibleMessages
          .map((m) => m['id'])
          .where((id) => id != null)
          .toList();
      if (messageIds.isEmpty) return;

      final reactions = await SupabaseConfig.client
          .from('message_reactions')
          .select('*')
          .inFilter('message_id', messageIds);

      // Fetch user display names for reactions using UserCache
      final userIds = List<Map<String, dynamic>>.from(
        reactions,
      ).map((r) => r['user_id'] as String).toSet().toList();

      // Use UserCache for better performance
      final users = await _userCache.getMany(userIds);

      final reactionMap = <String, List<Map<String, dynamic>>>{};
      for (var reaction in reactions) {
        final msgId = reaction['message_id'];
        reactionMap.putIfAbsent(msgId, () => []);
        reactionMap[msgId]!.add({
          ...reaction,
          'displayName':
              users[reaction['user_id']]?['displayName'] ?? 'Unknown',
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

  void _subscribeToParticipants() {
    if (widget.chatType == 'trip') return;

    if (widget.chatType == 'dm') {
      SupabaseConfig.client
          .channel('direct_chat_participants:${widget.tableId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'direct_chat_participants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'chat_id',
              value: widget.tableId,
            ),
            callback: (payload) {
              _loadParticipants();
            },
          )
          .subscribe();
      return;
    }

    SupabaseConfig.client
        .channel('table_participants:${widget.tableId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'table_members', // Listening to the TABLE we query
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: widget.tableId,
          ),
          callback: (payload) {
            _loadParticipants(); // Reload list on any change
          },
        )
        .subscribe();
  }

  // Quick helper for synchronous-like check if needed, or reuse _checkIfHost
  Future<bool> _checkIfHostBoolean() async {
    try {
      final table = await SupabaseConfig.client
          .from('tables')
          .select('host_id')
          .eq('id', widget.tableId)
          .single();
      return table['host_id'] == _currentUserId;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadParticipants() async {
    try {
      final query = widget.chatType == 'trip'
          ? SupabaseConfig.client
                .from('trip_chat_participants')
                .select('user_id')
                .eq('chat_id', widget.tableId)
          : widget.chatType == 'dm'
          ? SupabaseConfig.client
                .from('direct_chat_participants')
                .select('user_id')
                .eq('chat_id', widget.tableId)
          : SupabaseConfig.client
                .from('table_members')
                .select('user_id, arrival_status')
                .eq('table_id', widget.tableId)
                .inFilter('status', ['approved', 'joined', 'attended']);

      final response = await query;

      // Create a map of userId -> status
      final statusMap = <String, String>{};
      final userIds = <String>[];

      for (var p in response) {
        final uid = p['user_id'] as String;
        userIds.add(uid);
        if (widget.chatType != 'trip' && widget.chatType != 'dm') {
          statusMap[uid] = p['arrival_status'] ?? 'joined';
        }
      }

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
              'arrival_status': statusMap[u['id']] ?? 'joined',
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
      // ✅ Now includes DMs, Trips, and Tables with Telegram mode enabled
      await _loadMessageHistory_Telegram();
    } else {
      await _loadMessageHistory_Legacy();
    }
  }

  /// Telegram mode: Load from local SQLite first with pagination
  Future<void> _loadMessageHistory_Telegram() async {
    try {
      // Load initial batch of messages
      final localMessages = await _chatDatabase.getMessages(
        widget.tableId,
        limit: _messageLimit,
        offset: _messageOffset,
      );

      if (localMessages.isNotEmpty) {
        await _enrichAndDisplayMessages(localMessages);
      }

      // Check if there are more messages
      final totalCount = await _chatDatabase.getMessageCount(widget.tableId);
      setState(() {
        _hasMoreMessages = (_messageOffset + _messageLimit) < totalCount;
      });

      // ALWAYS sync from cloud to catch missed messages
      print('📥 Syncing latest messages from cloud...');
      await _chatDatabase.initialSyncFromCloud(
        widget.tableId,
        chatType: widget.chatType,
      );

      // Refresh with latest data (only first batch)
      final syncedMessages = await _chatDatabase.getMessages(
        widget.tableId,
        limit: _messageLimit,
        offset: 0,
      );
      await _enrichAndDisplayMessages(syncedMessages);

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

  /// Load more messages when scrolling up
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    try {
      _messageOffset += _messageLimit;

      // Call legacy mode with pagination offset
      await _loadMessageHistory_Legacy();

      setState(() => _isLoadingMore = false);
    } catch (e) {
      print('❌ Error loading more messages: $e');
      setState(() {
        _isLoadingMore = false;
        _messageOffset -= _messageLimit; // Revert offset on error
      });
    }
  }

  /// Scroll listener for pagination
  void _onScroll() {
    // With reverse: true, maxScrollExtent is the "Top" (Older messages).
    // So we load more when we approach the max extent.
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadMoreMessages();
    }
  }

  /// Legacy mode: Load from Supabase with optimized single query
  Future<void> _loadMessageHistory_Legacy() async {
    try {
      String tableName;
      String idColumn;
      String sequenceColumn = 'sequence_number';

      if (widget.chatType == 'trip') {
        tableName = 'trip_messages';
        idColumn = 'chat_id';
      } else if (widget.chatType == 'dm') {
        tableName = 'direct_messages';
        idColumn = 'chat_id';
      } else {
        tableName = 'messages';
        idColumn = 'table_id';
      }

      // OPTIMIZED: Single query with joins for user data
      // This replaces 3-4 separate queries with 1 query
      final selectClause =
          '''
        *,
        sender:users!${tableName}_sender_id_fkey(id, display_name, avatar_url)
      ''';

      var query = SupabaseConfig.client
          .from(tableName)
          .select(selectClause)
          .eq(idColumn, widget.tableId)
          .order(sequenceColumn, ascending: false)
          .limit(_messageLimit);

      // Cursor-based pagination: load messages older than current offset
      if (_messageOffset > 0) {
        query = query.range(_messageOffset, _messageOffset + _messageLimit - 1);
      }

      final messages = await query;
      final messageList = List<Map<String, dynamic>>.from(messages);

      if (messageList.isEmpty && _messageOffset == 0) {
        if (mounted) {
          setState(() {
            _messages = [];
            _isLoading = false;
            _hasMoreMessages = false;
          });
        }
        return;
      }

      // Extract user IDs for caching
      final senderIds = messageList
          .map((m) => m['sender_id'] as String)
          .toSet()
          .toList();

      // Preload users into cache for future use
      await _userCache.preloadUsers(senderIds);
      final cachedUsers = await _userCache.getUsers(
        senderIds,
      ); // Get fresh data

      // Handle reply messages if needed (still separate query for now)
      final replyToIds = messageList
          .where((m) => m['reply_to_id'] != null)
          .map((m) => m['reply_to_id'] as String)
          .toSet();

      Map<String, Map<String, dynamic>> replyMap = {};
      if (replyToIds.isNotEmpty) {
        final replyMessages = await SupabaseConfig.client
            .from('messages')
            .select('id, content, sender_id')
            .inFilter('id', replyToIds.toList());

        // Get reply sender names from cache
        final replySenderIds = replyMessages
            .map((r) => r['sender_id'] as String)
            .toSet()
            .toList();
        final replyUsers = await _userCache.getUsers(replySenderIds);

        replyMap = {
          for (var r in replyMessages)
            r['id']: {
              'id': r['id'],
              'content': r['content'],
              'sender_id': r['sender_id'],
              'senderName':
                  replyUsers[r['sender_id']]?.displayName ?? 'Unknown',
            },
        };
      }

      if (mounted) {
        setState(() {
          final newMessages = messageList.map((msg) {
            final senderId = msg['sender_id'] as String;
            final replyToId = msg['reply_to_id'];
            final timestamp =
                msg['sent_at'] ?? msg['created_at'] ?? msg['timestamp'];

            // Use CACHE for valid photo URLs
            final cachedProfile = cachedUsers[senderId];

            // Extract user data from join (Fallback)
            final senderData =
                msg['sender'] is List && (msg['sender'] as List).isNotEmpty
                ? (msg['sender'] as List).first
                : msg['sender'];

            return {
              'id': msg['id'],
              'content': msg['content'],
              'contentType':
                  msg['message_type'] ?? msg['content_type'] ?? 'text',
              'senderId': senderId,
              'senderName':
                  cachedProfile?.displayName ??
                  senderData?['display_name'] ??
                  'Unknown',
              'senderPhotoUrl':
                  cachedProfile?.photoUrl ?? senderData?['avatar_url'],
              'timestamp': timestamp,
              'isMe': senderId == _currentUserId,
              'deletedAt': msg['deleted_at'],
              'deletedForEveryone': msg['deleted_for_everyone'] ?? false,
              'replyTo': replyToId != null ? replyMap[replyToId] : null,
              'sequenceNumber': msg['sequence_number'],
            };
          }).toList();

          // Pagination: Append or replace messages
          if (_messageOffset == 0) {
            _messages = newMessages;
          } else {
            _messages.addAll(newMessages);
          }

          _hasMoreMessages = newMessages.length >= _messageLimit;
          _isLoading = false;
        });

        if (_messageOffset == 0) {
          _scrollToBottom();
        }
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
    _ablyChannel = _ablyService.getChannel(widget.channelId);

    // Monitor connection state
    _ablyService.getConnectionStateStream()?.listen((stateChange) {
      if (mounted) {
        final isConnected =
            stateChange.current == ably.ConnectionState.connected;
        setState(() {
          _ablyConnected = isConnected;
          _showConnectionBanner = !isConnected;
        });

        // Attempt reconnection on disconnect
        // REMOVED: Auto-connect is handled by the SDK. Manual overrides cause loops.
        // if (stateChange.current == ably.ConnectionState.disconnected) {
        //   _reconnectTimer?.cancel();
        //   _reconnectTimer = Timer(Duration(seconds: 3), () {
        //     _ablyService.reconnect();
        //   });
        // }

        // Clear timer on successful connection
        if (isConnected) {
          _reconnectTimer?.cancel();
        }
      }
    });

    // Subscribe to presence for typing indicators
    if (_ablyChannel != null) {
      _ablyChannel!.presence.subscribe().listen((message) {
        if (message.clientId != _currentUserId) {
          final isTyping =
              message.data is Map && (message.data as Map)['typing'] == true;
          if (mounted) {
            setState(() {
              _otherUserTyping =
                  isTyping && message.action != ably.PresenceAction.leave;
            });
          }
        }
      });
    }

    stream?.listen((ably.Message message) async {
      if (message.data != null) {
        final data = Map<String, dynamic>.from(message.data as Map);

        // In Telegram mode, skip our own messages (already added locally)
        if (_useTelegramMode && data['senderId'] == _currentUserId) {
          return;
        }

        // In Telegram mode, save incoming messages to local DB
        if (_useTelegramMode) {
          try {
            final messageToSave = {
              'id':
                  data['id'] ??
                  const Uuid().v4(), // Use ID from Ably or generate
              'table_id': widget.tableId,
              'sender_id': data['senderId'],
              'sender_name': data['senderName'],
              'content': data['content'],
              'timestamp': data['timestamp'] is String
                  ? DateTime.parse(data['timestamp']).millisecondsSinceEpoch
                  : data['timestamp'],
              'message_type': data['contentType'] ?? 'text',
              'chat_type': widget.chatType,
              'synced': 1, // Already from cloud
            };
            await _chatDatabase.saveMessage(messageToSave);
          } catch (e) {
            print('⚠️ Error saving incoming message to local DB: $e');
          }
        }

        if (mounted) {
          setState(() {
            // Insert new message at Top (Index 0) because list is Newest -> Oldest
            _messages.insert(0, {
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
          0.0, // In reverse ListView, 0.0 is the bottom
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
          // Insert at 0 (Bottom) for reversed list
          _messages.insert(0, {
            ...message,
            'timestamp': DateTime.fromMillisecondsSinceEpoch(
              timestamp,
            ).toIso8601String(),
            'contentType': contentType,
            'isMe': true,
            'senderName': _currentUserName ?? 'You',
            'senderPhotoUrl': _currentUserPhoto,
            'senderId': _currentUserId!,
            'status': 'sending',
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
        messageId: messageId, // Pass the message ID
      );

      // Update to sent
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m['id'] == messageId);
          if (index != -1) {
            _messages[index]['status'] = 'sent';
          }
        });
      }

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
    HapticFeedback.lightImpact();
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
        });
      } else if (widget.chatType == 'dm') {
        await SupabaseConfig.client.from('direct_messages').insert({
          'chat_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': content,
          'message_type': contentType,
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
    // 1. Optimistic Update (Immediate UI Feedback)
    final currentReactions = _messageReactions[messageId] ?? [];
    final existingIndex = currentReactions.indexWhere(
      (r) => r['user_id'] == _currentUserId && r['emoji'] == emoji,
    );
    final bool isAdding = existingIndex == -1;

    setState(() {
      final updatedReactions = List<Map<String, dynamic>>.from(
        currentReactions,
      );
      if (isAdding) {
        updatedReactions.add({
          'id': 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
          'message_id': messageId,
          'user_id': _currentUserId,
          'emoji': emoji,
          'displayName': 'You',
        });
      } else {
        updatedReactions.removeAt(existingIndex);
      }
      _messageReactions[messageId] = updatedReactions;
    });

    // 2. Background Sync with Retry
    // We don't await this so the UI stays responsive
    _syncReactionToBackend(messageId, emoji, isAdding).catchError((e) {
      print('❌ Reaction sync failed after retries: $e');
      // Revert optimistic update on final failure
      if (mounted) {
        setState(() {
          _loadReactions(); // Reload from server to restore correct state
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not sync reaction. Message might not be sent yet.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _syncReactionToBackend(
    String messageId,
    String emoji,
    bool isAdding,
  ) async {
    // Increase retries to 20 (approx 40-60 seconds coverage depending on backoff)
    int attempts = 0;
    while (attempts < 20) {
      try {
        // If Telegram Mode, verify message exists first
        if (_useTelegramMode) {
          final messageExists = await SupabaseConfig.client
              .from('messages')
              .select('id')
              .eq('id', messageId)
              .maybeSingle();

          if (messageExists == null) {
            // Message syncing, wait and retry
            throw Exception('Message not synced yet');
          }
        }

        if (isAdding) {
          // Check if truly already exists (idempotency)
          final existing = await SupabaseConfig.client
              .from('message_reactions')
              .select('id')
              .eq('message_id', messageId)
              .eq('user_id', _currentUserId!)
              .eq('emoji', emoji)
              .maybeSingle();

          if (existing == null) {
            await SupabaseConfig.client.from('message_reactions').insert({
              'message_id': messageId,
              'user_id': _currentUserId,
              'emoji': emoji,
            });
          }
        } else {
          // Remove
          final existing = await SupabaseConfig.client
              .from('message_reactions')
              .select('id')
              .eq('message_id', messageId)
              .eq('user_id', _currentUserId!)
              .eq('emoji', emoji)
              .maybeSingle();

          if (existing != null) {
            await SupabaseConfig.client
                .from('message_reactions')
                .delete()
                .eq('id', existing['id']);
          }
        }

        // Success!
        return;
      } catch (e) {
        attempts++;
        if (attempts >= 20) rethrow; // Give up after 20 attempts

        // Exponential backoff capped at 2 seconds
        // 500, 1000, 2000, 2000, 2000...
        int delayMs = 500 * (1 << (attempts - 1));
        if (delayMs > 2000) delayMs = 2000;
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  Future<void> _handleDelete(
    Map<String, dynamic> message,
    bool deleteForEveryone,
  ) async {
    try {
      if (_useTelegramMode) {
        // In Telegram mode: delete from local DB and Supabase
        final messageId = message['id'];

        if (deleteForEveryone) {
          // Delete from Supabase (for everyone)
          await SupabaseConfig.client
              .from('messages')
              .delete()
              .eq('id', messageId);
        }

        // Delete from local DB
        await _chatDatabase.deleteMessage(messageId);

        // Remove from UI
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m['id'] == messageId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                deleteForEveryone
                    ? 'Message deleted for everyone'
                    : 'Message deleted',
              ),
            ),
          );
        }
      } else {
        // Legacy mode: mark as deleted in Supabase
        await SupabaseConfig.client
            .from('messages')
            .update({
              'deleted_at': DateTime.now().toIso8601String(),
              'deleted_for_everyone': deleteForEveryone,
            })
            .eq('id', message['id']);

        await _loadMessageHistory();
      }
    } catch (e) {
      print('❌ Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete message')),
        );
      }
    }
  }

  // Typing indicators logic

  void _onTypingChanged() {
    if (_ablyChannel == null) return;

    // Debounce: Only send typing status every 500ms instead of every keystroke
    final isCurrentlyTyping = _messageController.text.isNotEmpty;

    if (isCurrentlyTyping && !_isTyping) {
      // User just started typing
      _isTyping = true;
      _sendTypingStatus(true);
    }

    // Reset the timer on every keystroke
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 500), () {
      // If text is empty, user stopped typing
      if (_messageController.text.isEmpty && _isTyping) {
        _isTyping = false;
        _sendTypingStatus(false);
      }
    });
  }

  void _sendTypingStatus(bool isTyping) async {
    try {
      if (_ablyChannel == null) return;
      await _ablyChannel!.presence.enterClient(_currentUserId ?? 'unknown', {
        'typing': isTyping,
      });
    } catch (e) {
      print('⚠️ Error updating presence: $e');
    }
  }

  String _getOtherUserName() {
    final other = _participants.firstWhere(
      (p) => p['userId'] != _currentUserId,
      orElse: () => {'name': 'Someone'},
    );
    return other['name'] ?? 'Someone';
  }

  String _getReplyContent(String? replyToId) {
    if (replyToId == null) return '';

    // Look up in loaded messages
    final replyMsg = _messages.firstWhere(
      (m) => m['id'] == replyToId,
      orElse: () => {},
    );

    if (replyMsg.isEmpty) return 'Message unavailable';

    if (replyMsg['contentType'] == 'gif') {
      return 'GIF';
    }

    return replyMsg['content'] ?? 'Message unavailable';
  }

  String _getReplySenderName(String? replyToId) {
    if (replyToId == null) return 'Unknown';

    // Look up in loaded messages
    final replyMsg = _messages.firstWhere(
      (m) => m['id'] == replyToId,
      orElse: () => {},
    );

    if (replyMsg.isEmpty) return 'Unknown';

    return replyMsg['senderName'] ?? 'Unknown';
  }

  Widget _buildTypingIndicator() {
    return SizedBox(
      width: 32,
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (index) {
          return _BouncingDot(index: index);
        }),
      ),
    );
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
        content: Text(
          widget.chatType == 'trip'
              ? 'You will leave this trip group chat.'
              : widget.chatType == 'dm'
              ? 'This conversation will be hidden.'
              : 'You will be removed from this activity and its chat.',
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

    try {
      if (widget.chatType == 'trip') {
        // Leave Trip Chat
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          // Note: tableId is passed as the chatId for trips in ActiveChatsList
          await SupabaseConfig.client
              .from('trip_chat_participants')
              .delete()
              .eq('chat_id', widget.tableId)
              .eq('user_id', user.id);
        }
      } else if (widget.chatType == 'dm') {
        // Hide DM (Delete participant entry or mark hidden)
        // For now, let's delete the participant entry to "leave"
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          await SupabaseConfig.client
              .from('direct_chat_participants')
              .delete()
              .eq('chat_id', widget.tableId)
              .eq('user_id', user.id);
        }
      } else {
        // Legacy/Table Leave
        await _memberService.leaveTable(widget.tableId);
      }

      if (mounted) {
        Navigator.pop(context, true); // Close chat with change signal
      }
    } catch (e) {
      print('Error leaving chat: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to leave chat')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Set a fixed height for the sheet (75% of screen for better UX)
    final screenHeight = MediaQuery.of(context).size.height;

    return Material(
      color: Colors.transparent,
      child: Container(
        height: screenHeight * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            ChatHeader(
              title: widget.tableTitle,
              onLeave: _leaveTable,
              onClose: () => Navigator.pop(context),
              onInfoTap: () {
                if (widget.chatType == 'dm') {
                  // Find the other user
                  final otherUser = _participants.firstWhere(
                    (p) => p['userId'] != _currentUserId,
                    orElse: () => <String, dynamic>{}, // Provide type arguments
                  );
                  if (otherUser.isNotEmpty && otherUser['userId'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            UserProfileScreen(userId: otherUser['userId']),
                      ),
                    );
                  }
                } else {
                  // For tables and trips, show the participant list
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatInfoScreen(
                        title: widget.tableTitle,
                        chatType: widget.chatType,
                        participants: _participants,
                      ),
                    ),
                  );
                }
              },
            ),

            // Connection Status Banner
            if (_showConnectionBanner)
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: Colors.orange.shade100,
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Reconnecting to chat...',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Messages Area
            Expanded(
              child: ChatMessageList(
                isLoading: _isLoading,
                messages: _messages,
                scrollController: _scrollController,
                messageReactions: _messageReactions,
                getReplySenderName: _getReplySenderName,
                getReplyContent: _getReplyContent,
                buildStatusIndicator: (status) => _buildStatusIndicator(status),
                buildReactionChips: (msgId) =>
                    msgId != null ? _buildReactionChips(msgId) : [],
                onReply: _handleReply,
                onShowActions: _showMessageActions,
                onReact: _handleReaction,
                onOpenLink: _onOpenLink,
              ),
            ),

            // Typing Indicator
            if (_otherUserTyping)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Row(
                  children: [
                    _buildTypingIndicator(),
                    const SizedBox(width: 8),
                    Text(
                      '${_getOtherUserName()} is typing...',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[400]
                            : Colors.grey[600],
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

            // Input Area
            ChatInputBar(
              controller: _messageController,
              replyingTo: _replyingTo,
              onCancelReply: _cancelReply,
              onShowGifPicker: _showGifPicker,
              onSendMessage: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Methods (Updated for Light Theme) ---

  Future<void> _onOpenLink(LinkableElement link) async {
    final Uri uri = Uri.parse(link.url);
    // Basic validation or just try to launch
    // checking canLaunchUrl helps avoiding dead links or bad schemes
    if (await canLaunchUrl(uri)) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.3),
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cute Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7FFF).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🔗', style: TextStyle(fontSize: 32)),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Opening External Link',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  'You\'re about to leave the app and visit:',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // URL Container
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!, width: 1),
                  ),
                  child: Text(
                    link.url,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontFamily: 'monospace',
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    // Cancel Button
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.grey[100],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Open Button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFF6B7FFF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Open Link',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    }
  }

  void _showMessageActions(Map<String, dynamic> message) {
    HapticFeedback.mediumImpact();
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[700]
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.reply,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'Reply',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleReply(message);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.emoji_emotions_outlined,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'React',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
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
    final emojis = ['❤️', '😂', '😮', '😢', '🙏', '👍'];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Emoji Picker',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[850]
                          : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: emojis.map((emoji) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _handleReaction(messageId, emoji);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator(String status) {
    IconData icon;
    Color color;

    switch (status) {
      case 'sending':
        icon = Icons.access_time;
        color = Colors.grey[400]!;
        break;
      case 'sent':
        icon = Icons.check;
        color = Colors.grey[400]!;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.grey[400]!;
        break;
      case 'read':
        icon = Icons.done_all;
        color = Colors.blue;
        break;
      default:
        icon = Icons.check;
        color = Colors.grey[400]!;
    }

    return Icon(icon, size: 12, color: color);
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
            color: hasMyReaction
                ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.blue[700]
                      : Colors.black)
                : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[800]
                      : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasMyReaction
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue[700]!
                        : Colors.black)
                  : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[600]!
                        : Colors.grey[300]!),
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

class _BouncingDot extends StatefulWidget {
  final int index;
  const _BouncingDot({required this.index});

  @override
  State<_BouncingDot> createState() => _BouncingDotState();
}

class _BouncingDotState extends State<_BouncingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween<double>(begin: 0.4, end: 1).animate(_controller);

    Future.delayed(Duration(milliseconds: widget.index * 200), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[400]
              : Colors.grey[600],
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
