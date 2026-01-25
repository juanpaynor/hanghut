import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:bitemates/features/chat/widgets/chat_participant_header.dart';
import 'package:bitemates/features/chat/widgets/verification_sheet.dart';

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

    // Cleanup old messages on init (runs in background)
    _chatDatabase.cleanupOldMessages().catchError((e) {
      print('⚠️ Cleanup failed: $e');
    });
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
    if (state == AppLifecycleState.resumed && _useTelegramMode) {
      print('📱 App resumed: Syncing chat...');
      Future.wait([
        _chatDatabase.initialSyncFromCloud(
          widget.tableId,
          chatType: widget.chatType,
        ),
        _syncPendingMessages(),
      ]).then((_) {
        // Refresh local view after sync
        _loadMessageHistory_Telegram();
      });
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

    if (widget.chatType == 'dm') {
      setState(() {
        _isHost = false;
        _useTelegramMode = false; // DMs use legacy mode
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

  Future<void> _verifyParticipant(String participantId) async {
    // 1. Find my own status
    final myStatus = _participants.firstWhere(
      (p) => p['userId'] == _currentUserId,
      orElse: () => {},
    )['arrival_status'];

    final isMe = participantId == _currentUserId;
    final isHost = await _checkIfHostBoolean(); // Helper to check quickly

    // 2. Logic Gate
    if (!isMe) {
      // Trying to verify someone else
      // Rule: Only Verified users or Host can verify others
      // "Host is automatically verified" via triggers/logic usually,
      // but let's check explicit status or implicit host power.
      final amIVerified = myStatus == 'verified' || isHost;

      if (!amIVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You must be verified yourself before verifying others!',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // 3. Open Sheet
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => VerificationSheet(
          currentUserId: _currentUserId!,
          targetUserId: participantId,
          tableId: widget.tableId,
          isMe: isMe,
        ),
      );
    }
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
    if (_useTelegramMode && widget.chatType != 'dm') {
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
    if (_isLoadingMore || !_hasMoreMessages || !_useTelegramMode) return;

    setState(() => _isLoadingMore = true);

    try {
      _messageOffset += _messageLimit;

      final olderMessages = await _chatDatabase.getMessages(
        widget.tableId,
        limit: _messageLimit,
        offset: _messageOffset,
      );

      if (olderMessages.isNotEmpty) {
        // Append older messages to the END of the list (since we are Newest -> Oldest)
        final enrichedOlder = await _enrichMessages(olderMessages);
        setState(() {
          _messages = [..._messages, ...enrichedOlder];
        });
      }

      // Check if there are even more messages
      final totalCount = await _chatDatabase.getMessageCount(widget.tableId);
      setState(() {
        // Offset is how many we've loaded. Has more if offset + limit < total
        _hasMoreMessages = (_messageOffset + _messageLimit) < totalCount;
        _isLoadingMore = false;
      });
    } catch (e) {
      print('❌ Error loading more messages: $e');
      setState(() => _isLoadingMore = false);
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

  /// Helper to enrich messages without setting state
  Future<List<Map<String, dynamic>>> _enrichMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    final userIds = messages
        .map((m) => m['sender_id'] as String?)
        .where((id) => id != null)
        .toSet()
        .toList();

    if (userIds.isEmpty) return messages;

    try {
      final users = await SupabaseConfig.client
          .from('users')
          .select('id, display_name, avatar_url')
          .inFilter('id', userIds);

      final userMap = {for (var u in users) u['id']: u};

      return messages.map((msg) {
        final user = userMap[msg['sender_id']];
        return {
          ...msg,
          'sender_name': user?['display_name'] ?? 'Unknown',
          'sender_photo': user?['avatar_url'],
        };
      }).toList();
    } catch (e) {
      print('❌ Error enriching messages: $e');
      return messages;
    }
  }

  /// Legacy mode: Load from Supabase
  Future<void> _loadMessageHistory_Legacy() async {
    try {
      String tableName;
      String idColumn;
      String timestampColumn;

      if (widget.chatType == 'trip') {
        tableName = 'trip_messages';
        idColumn = 'chat_id';
        timestampColumn = 'sent_at';
      } else if (widget.chatType == 'dm') {
        tableName = 'direct_messages';
        idColumn = 'chat_id';
        timestampColumn = 'created_at';
      } else {
        tableName = 'messages';
        idColumn = 'table_id';
        timestampColumn = 'timestamp';
      }

      // Note: trip_messages has 'message_type', messages has 'content_type'.
      // We handle this mismatch in the map below.

      final messages = await SupabaseConfig.client
          .from(tableName)
          .select('*')
          .eq(idColumn, widget.tableId)
          .eq(idColumn, widget.tableId)
          .order(timestampColumn, ascending: false) // Newest first
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

    if (!_isTyping) {
      _isTyping = true;
      _sendTypingStatus(true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      _sendTypingStatus(false);
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

            // --- EVENT COORDINATION HEADER ---
            if (widget.chatType != 'trip')
              ChatParticipantHeader(
                participants: _participants,
                onVerifyPressed: _verifyParticipant,
                onReadyPressed: () {
                  if (_currentUserId != null) {
                    _verifyParticipant(_currentUserId!);
                  }
                },
              ),

            const Divider(height: 1, color: Colors.black12),

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
                            Icons.forum_outlined, // More conversational icon
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Say Hi! 👋',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      reverse: true, // Standard Chat UI: Bottom is start
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      controller: _scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg['isMe'] as bool;

                        // Header Logic: Show if this message is the First (Oldest) of a block.
                        // In Newest->Oldest list:
                        // Next item (index + 1) is OLDER.
                        // If Next item has different sender, then THIS item is the start of a new block (going up/chronologically down).
                        // Visual Stack: [Next/Older] -> [This/Newer].
                        // Header goes above [Next/Older] usually?
                        // Wait. Header goes above the GROUP.
                        // Group: [Older, ..., Newer].
                        // Visual Top: Older.
                        // Visual Bottom: Newer.
                        // We iterate 0 (Newer) ... N (Older).
                        // Header should appear on the OLDER message if the EVEN OLDER message is different.
                        // So checking strict Index logic:
                        // We want header on `msg` if `msg` is the "Top" of its group.
                        // "Top" means Oldest in group.
                        // So `msg` must be Older than `msg-1` (Newer). (Always true).
                        // `msg` must be Newer than `msg+1` (Even Older).
                        // If `msg+1` sender != `msg` sender. Then `msg` is the start of this group (from top).
                        // So Check: index == last || messages[index+1].sender != msg.sender.

                        final bool showHeader =
                            index == _messages.length - 1 ||
                            _messages[index + 1]['senderId'] != msg['senderId'];

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
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),

                                    // Message Bubble & Actions Wrapper
                                    TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: 1),
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                      builder: (context, value, child) {
                                        return Opacity(
                                          opacity: value,
                                          child: Transform.translate(
                                            offset: Offset(0, 20 * (1 - value)),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: Row(
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
                                            child: Dismissible(
                                              key: Key(
                                                msg['id'] ??
                                                    UniqueKey().toString(),
                                              ),
                                              direction:
                                                  DismissDirection.startToEnd,
                                              confirmDismiss: (direction) async {
                                                HapticFeedback.mediumImpact();
                                                _handleReply(msg);
                                                return false;
                                              },
                                              background: Container(
                                                alignment: Alignment.centerLeft,
                                                padding: const EdgeInsets.only(
                                                  left: 20,
                                                ),
                                                child: Icon(
                                                  Icons.reply,
                                                  color: Theme.of(
                                                    context,
                                                  ).primaryColor,
                                                ),
                                              ),
                                              child: GestureDetector(
                                                onLongPress: () =>
                                                    _showMessageActions(msg),
                                                onDoubleTap: () {
                                                  HapticFeedback.lightImpact();
                                                  // Quick react with heart (like Instagram)
                                                  if (msg['id'] != null) {
                                                    _handleReaction(
                                                      msg['id'],
                                                      '❤️',
                                                    );
                                                  }
                                                },
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        bottom:
                                                            _messageReactions[msg['id']]
                                                                    ?.isNotEmpty ==
                                                                true
                                                            ? 12.0
                                                            : 0,
                                                      ),
                                                      child: Container(
                                                        padding:
                                                            msg['contentType'] ==
                                                                'gif'
                                                            ? EdgeInsets.zero
                                                            : const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 8,
                                                              ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              msg['contentType'] ==
                                                                  'gif'
                                                              ? Colors
                                                                    .transparent
                                                              : (isMe
                                                                    ? Theme.of(
                                                                                context,
                                                                              ).brightness ==
                                                                              Brightness.dark
                                                                          ? Colors.blue[700] // My bubble in dark mode
                                                                          : Colors
                                                                                .black // My bubble in light mode
                                                                    : Theme.of(
                                                                            context,
                                                                          ).brightness ==
                                                                          Brightness
                                                                              .dark
                                                                    ? Colors
                                                                          .grey[800] // Other bubble in dark mode
                                                                    : Colors
                                                                          .grey[100]), // Other bubble in light mode
                                                          borderRadius: BorderRadius.only(
                                                            topLeft:
                                                                const Radius.circular(
                                                                  16, // Slightly reduced radius
                                                                ),
                                                            topRight:
                                                                const Radius.circular(
                                                                  16,
                                                                ),
                                                            bottomLeft:
                                                                Radius.circular(
                                                                  isMe ? 16 : 4,
                                                                ),
                                                            bottomRight:
                                                                Radius.circular(
                                                                  isMe ? 4 : 16,
                                                                ),
                                                          ),
                                                          // Add shadow to mine for pop
                                                          boxShadow:
                                                              isMe &&
                                                                  msg['contentType'] !=
                                                                      'gif'
                                                              ? [
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withValues(
                                                                          alpha:
                                                                              0.1,
                                                                        ),
                                                                    blurRadius:
                                                                        4,
                                                                    offset:
                                                                        Offset(
                                                                          0,
                                                                          2,
                                                                        ),
                                                                  ),
                                                                ]
                                                              : null,
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            // Reply Preview Inside Bubble
                                                            if (msg['reply_to_id'] !=
                                                                null)
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
                                                                      ? Colors.white.withValues(
                                                                          alpha:
                                                                              0.2,
                                                                        )
                                                                      : Colors.black.withValues(
                                                                          alpha:
                                                                              0.05,
                                                                        ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        8,
                                                                      ),
                                                                  border: Border(
                                                                    left: BorderSide(
                                                                      color:
                                                                          isMe
                                                                          ? Colors.white
                                                                          : Colors.black54,
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
                                                                      _getReplySenderName(
                                                                        msg['reply_to_id'],
                                                                      ),
                                                                      style: TextStyle(
                                                                        color:
                                                                            isMe
                                                                            ? Colors.white
                                                                            : Colors.black87,
                                                                        fontSize:
                                                                            11,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                      ),
                                                                    ),
                                                                    Text(
                                                                      _getReplyContent(
                                                                        msg['reply_to_id'],
                                                                      ),
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      style: TextStyle(
                                                                        color:
                                                                            isMe
                                                                            ? Colors.white.withValues(
                                                                                alpha: 0.8,
                                                                              )
                                                                            : Colors.black87.withValues(
                                                                                alpha: 0.8,
                                                                              ),
                                                                        fontSize:
                                                                            11,
                                                                      ),
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
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  placeholder: (context, url) => Container(
                                                                    width: 200,
                                                                    height: 200,
                                                                    color: Colors
                                                                        .grey[200],
                                                                    child: const Center(
                                                                      child: CircularProgressIndicator(
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
                                                                        Icons
                                                                            .error,
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
                                                                      ? Colors
                                                                            .white
                                                                      : Theme.of(
                                                                              context,
                                                                            ).brightness ==
                                                                            Brightness.dark
                                                                      ? Colors
                                                                            .white
                                                                      : Colors
                                                                            .black87,
                                                                  fontSize: 15,
                                                                  fontStyle:
                                                                      (msg['deletedAt'] !=
                                                                              null &&
                                                                          (msg['deletedForEveryone'] ||
                                                                              !isMe))
                                                                      ? FontStyle
                                                                            .italic
                                                                      : FontStyle
                                                                            .normal,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    // Positioned Reactions
                                                    if (_messageReactions[msg['id']]
                                                            ?.isNotEmpty ==
                                                        true)
                                                      Positioned(
                                                        bottom: -8,
                                                        left: isMe ? null : 0,
                                                        right: isMe ? 0 : null,
                                                        child: Wrap(
                                                          spacing: 4,
                                                          children:
                                                              _buildReactionChips(
                                                                msg['id'],
                                                              ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Timestamp & Status (Reactions moved to Stack)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                              left: 4,
                                              right: 4,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isMe) ...[
                                                  _buildStatusIndicator(
                                                    msg['status'] ?? 'sent',
                                                  ),
                                                  const SizedBox(width: 4),
                                                ],
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
                                    const SizedBox(height: 2),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[900]
                    : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    if (_replyingTo != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[850]
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[700]!
                                : Colors.grey[200]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 36,
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.blue[400]
                                    : Colors.black,
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
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Methods (Updated for Light Theme) ---

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
