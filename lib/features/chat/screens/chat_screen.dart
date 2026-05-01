import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:bitemates/core/services/chat_database.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/features/chat/widgets/invite_member_sheet.dart';
import 'package:bitemates/core/services/user_cache.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:bitemates/features/chat/widgets/create_poll_sheet.dart';
import 'package:bitemates/features/chat/widgets/rsvp_banner.dart';
import 'package:bitemates/features/chat/widgets/checkin_banner.dart';
import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:bitemates/features/chat/widgets/chat_header.dart';
import 'package:bitemates/features/chat/widgets/chat_input_bar.dart';
import 'package:bitemates/features/chat/widgets/chat_message_list.dart';
import 'package:bitemates/features/chat/screens/chat_info_screen.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/settings/widgets/report_modal.dart';
import 'package:bitemates/core/services/analytics_service.dart';
import 'package:bitemates/features/chat/widgets/verification_sheet.dart';

class ChatScreen extends StatefulWidget {
  final String tableId;
  final String tableTitle;
  final String channelId;
  final String chatType; // 'table', 'trip', 'dm', or 'group'
  final bool embedded; // When true, hides header & bottom-sheet chrome

  const ChatScreen({
    super.key,
    required this.tableId,
    required this.tableTitle,
    required this.channelId,
    this.chatType = 'table',
    this.embedded = false,
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
  bool _isMuted = false; // Set by host; muted users cannot send messages
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

  // Search
  bool _isSearching = false;
  String _searchQuery = '';
  List<int> _matchedIndices = [];
  int _currentMatchIndex = -1;
  final TextEditingController _searchController = TextEditingController();

  // Pinned message
  Map<String, dynamic>? _pinnedMessage;

  // Activity lifecycle
  bool _isActivityPast = false;

  // RSVP state (table chats only)
  String? _currentRsvpStatus;
  int _rsvpGoingCount = 0;
  int _rsvpMaybeCount = 0;
  int _rsvpNotGoingCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    _messageController.addListener(_onTypingChanged);
    _scrollController.addListener(_onScroll);
    // Track screen view with chat type
    AnalyticsService().logScreenView('chat_${widget.chatType}');
  }

  Future<void> _initializeChat() async {
    await _getCurrentUser();
    await _checkIfHost();
    await _checkIfMuted();
    await _markChatAsRead(); // Added: Update read receipt
    await _loadParticipants();
    await _loadMessageHistory();
    _subscribeToAbly();
    _subscribeToReactions();
    _subscribeToParticipants();
    _loadPinnedMessage(); // Load pinned message for banner
    if (widget.chatType == 'table') {
      _loadRsvpData(); // Load RSVP counts for table chats
      _checkIfActivityPast();
    }
  }

  Future<void> _markChatAsRead() async {
    if (_currentUserId == null) {
      print('⚠️ _markChatAsRead: _currentUserId is null, skipping');
      return;
    }
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      print(
        '📖 _markChatAsRead: chatType=${widget.chatType}, tableId=${widget.tableId}, userId=$_currentUserId, now=$now',
      );
      if (widget.chatType == 'trip') {
        await SupabaseConfig.client
            .from('trip_chat_participants')
            .update({'last_read_at': now})
            .eq('chat_id', widget.tableId)
            .eq('user_id', _currentUserId!);
      } else if (widget.chatType == 'dm' || widget.chatType == 'direct') {
        await SupabaseConfig.client
            .from('direct_chat_participants')
            .update({'last_read_at': now})
            .eq('chat_id', widget.tableId)
            .eq('user_id', _currentUserId!);
      } else if (widget.chatType == 'group') {
        await SupabaseConfig.client
            .from('group_members')
            .update({'last_read_at': now})
            .eq('group_id', widget.tableId)
            .eq('user_id', _currentUserId!);
      } else {
        await SupabaseConfig.client
            .from('table_members')
            .update({'last_read_at': now})
            .eq('table_id', widget.tableId)
            .eq('user_id', _currentUserId!);
      }
      print(
        '✅ _markChatAsRead: SUCCESS for ${widget.chatType} ${widget.tableId}',
      );
    } catch (e) {
      print('❌ _markChatAsRead: FAILED - $e');
    }
  }

  @override
  void dispose() {
    // Mark chat as read on close so unread count resets
    _markChatAsRead();
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
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

    if (widget.chatType == 'trip' ||
        widget.chatType == 'dm' ||
        widget.chatType == 'direct') {
      setState(() {
        _isHost = false;
      });
      return;
    }

    if (widget.chatType == 'group') {
      try {
        final group = await SupabaseConfig.client
            .from('groups')
            .select('created_by')
            .eq('id', widget.tableId)
            .single();
        setState(() {
          _isHost = group['created_by'] == _currentUserId;
        });
      } catch (e) {
        print('❌ CHAT: Error checking group owner status - $e');
      }
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
    // Reactions are broadcast via Ably (reaction_updated event).
    // Supabase realtime is not used here — message_reactions is not
    // in the realtime publication.
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
    // Participant and mute changes are broadcast via Ably
    // (participants_updated / mute_updated events).
    // Supabase realtime is not used here to keep connection count low.
  }

  Future<void> _checkIfMuted() async {
    if (widget.chatType != 'table') return;
    try {
      final muted = await _memberService.isCurrentUserMuted(widget.tableId);
      if (mounted) setState(() => _isMuted = muted);
    } catch (_) {}
  }

  void _handleAvatarTap(String userId) {
    if (_isHost && widget.chatType == 'table' && userId != _currentUserId) {
      // Host tapping someone else's avatar → show mute/kick actions
      _showHostActionsForUser(userId);
    } else {
      // Go to profile
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)),
      );
    }
  }

  void _showHostActionsForUser(String userId) async {
    // Find user info from participants
    final participant = _participants.firstWhere(
      (p) => p['userId'] == userId,
      orElse: () => {'userId': userId, 'displayName': 'Unknown'},
    );
    final name = participant['displayName'] as String? ?? 'Unknown';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if user is muted
    bool isMuted = false;
    try {
      final member = await SupabaseConfig.client
          .from('table_members')
          .select('is_muted')
          .eq('table_id', widget.tableId)
          .eq('user_id', userId)
          .maybeSingle();
      isMuted = member?['is_muted'] == true;
    } catch (_) {}

    if (!mounted) return;

    final photoUrl = participant['photoUrl'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Avatar + name header
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                      ? NetworkImage(photoUrl)
                      : null,
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Icon(
                          Icons.person_rounded,
                          size: 28,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (isMuted)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.volume_off_rounded,
                                size: 11,
                                color: Colors.orange[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Muted in chat',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          'Member',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Action tiles
            _buildHostActionTile(
              context: context,
              isDark: isDark,
              icon: Icons.person_outline_rounded,
              label: 'View Profile',
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(userId: userId),
                  ),
                );
              },
            ),
            _buildHostActionTile(
              context: context,
              isDark: isDark,
              icon: isMuted
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              label: isMuted ? 'Unmute in chat' : 'Mute in chat',
              color: Colors.orange,
              onTap: () async {
                Navigator.pop(context);
                final result = isMuted
                    ? await _memberService.unmuteParticipant(
                        widget.tableId,
                        userId,
                      )
                    : await _memberService.muteParticipant(
                        widget.tableId,
                        userId,
                      );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result['message'] ??
                            (isMuted ? '$name unmuted' : '$name muted'),
                      ),
                      backgroundColor: result['success'] == true
                          ? Colors.orange
                          : Colors.red,
                    ),
                  );
                  if (result['success'] == true) {
                    // Broadcast mute change so the affected user updates live
                    await _ablyService.publishMuteUpdated(
                      channelName: widget.channelId,
                      targetUserId: userId,
                      isMuted: !isMuted,
                    );
                    _loadParticipants();
                  }
                }
              },
            ),
            _buildHostActionTile(
              context: context,
              isDark: isDark,
              icon: Icons.person_remove_rounded,
              label: 'Remove from hangout',
              color: Colors.red,
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) {
                    return Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      backgroundColor: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.person_remove_rounded,
                                color: Colors.red,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Remove member?',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$name will be removed from this hangout.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      'Remove',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
                if (confirm != true) return;
                final result = await _memberService.removeMember(
                  widget.tableId,
                  userId,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result['success'] == true
                            ? '$name removed'
                            : (result['message'] ?? 'Failed'),
                      ),
                      backgroundColor: result['success'] == true
                          ? Colors.orange
                          : Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostActionTile({
    required BuildContext context,
    required bool isDark,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: color.withOpacity(0.35),
            ),
          ],
        ),
      ),
    );
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

  // ═══ PINNED MESSAGES ═══
  Future<void> _loadPinnedMessage() async {
    // Only support pinning in group and table chats
    if (widget.chatType == 'dm' ||
        widget.chatType == 'direct' ||
        widget.chatType == 'trip')
      return;

    try {
      String filterColumn = widget.chatType == 'group'
          ? 'group_id'
          : 'table_id';

      final resp = await SupabaseConfig.client
          .from('messages')
          .select(
            'id, content, sender_id, sender_name, timestamp, content_type, is_pinned, pinned_at',
          )
          .eq(filterColumn, widget.tableId)
          .eq('is_pinned', true)
          .order('pinned_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _pinnedMessage = resp;
        });
      }
    } catch (e) {
      print('⚠️ Failed to load pinned message: $e');
    }
  }

  /// Check if the activity's scheduled time has passed
  Future<void> _checkIfActivityPast() async {
    try {
      final table = await SupabaseConfig.client
          .from('tables')
          .select('datetime')
          .eq('id', widget.tableId)
          .single();

      final scheduledAt = DateTime.tryParse(table['datetime'] ?? '');
      if (scheduledAt != null && mounted) {
        setState(() {
          _isActivityPast = scheduledAt.isBefore(DateTime.now());
        });
      }
    } catch (e) {
      print('⚠️ CHAT: Error checking activity time - $e');
    }
  }

  /// Load RSVP counts and current user's status for table chats
  Future<void> _loadRsvpData() async {
    if (_currentUserId == null) return;
    try {
      // Get all RSVP statuses for this table
      final result = await SupabaseConfig.client
          .from('table_members')
          .select('user_id, rsvp_status')
          .eq('table_id', widget.tableId)
          .inFilter('status', ['approved', 'joined', 'attended']);

      int going = 0, maybe = 0, notGoing = 0;
      String? myStatus;

      for (var row in result) {
        final rsvp = row['rsvp_status'] as String?;
        if (rsvp == 'going') going++;
        if (rsvp == 'maybe') maybe++;
        if (rsvp == 'not_going') notGoing++;
        if (row['user_id'] == _currentUserId) {
          myStatus = rsvp;
        }
      }

      if (mounted) {
        setState(() {
          _currentRsvpStatus = myStatus;
          _rsvpGoingCount = going;
          _rsvpMaybeCount = maybe;
          _rsvpNotGoingCount = notGoing;
        });
      }
    } catch (e) {
      print('⚠️ ChatScreen: Error loading RSVP data - $e');
    }
  }

  /// Update the current user's RSVP status
  Future<void> _updateRsvp(String newStatus) async {
    if (_currentUserId == null) return;

    // Optimistic update
    final oldStatus = _currentRsvpStatus;
    setState(() => _currentRsvpStatus = newStatus == 'none' ? null : newStatus);

    try {
      await SupabaseConfig.client
          .from('table_members')
          .update({'rsvp_status': newStatus == 'none' ? null : newStatus})
          .eq('table_id', widget.tableId)
          .eq('user_id', _currentUserId!);

      // Reload counts after update
      await _loadRsvpData();

      // Send a system message about the RSVP change
      if (newStatus != 'none') {
        final rsvpLabel = newStatus == 'going'
            ? 'is going ✅'
            : newStatus == 'maybe'
            ? 'might go 🤔'
            : "can't make it ❌";
        await _sendSystemMessage('${_currentUserName ?? 'Someone'} $rsvpLabel');
      }
    } catch (e) {
      // Revert on error
      if (mounted) setState(() => _currentRsvpStatus = oldStatus);
      print('❌ ChatScreen: Error updating RSVP - $e');
    }
  }

  /// Send a system-level message to this chat (e.g., RSVP updates)
  Future<void> _sendSystemMessage(String text) async {
    try {
      if (widget.chatType == 'group') {
        await SupabaseConfig.client.from('messages').insert({
          'group_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': text,
          'content_type': 'system',
        });
      } else {
        await SupabaseConfig.client.from('messages').insert({
          'table_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': text,
          'content_type': 'system',
        });
      }
      // Also publish on Ably so others see it in real-time
      await _ablyService.publishMessage(
        channelName: widget.channelId,
        content: text,
        contentType: 'system',
        senderId: _currentUserId!,
        senderName: 'System',
        senderPhotoUrl: null,
      );
    } catch (e) {
      print('⚠️ ChatScreen: Failed to send system message - $e');
    }
  }

  Future<void> _togglePinMessage(Map<String, dynamic> message) async {
    final isCurrentlyPinned = message['is_pinned'] == true;
    final messageId = message['id'];

    try {
      if (isCurrentlyPinned) {
        // Unpin
        await SupabaseConfig.client
            .from('messages')
            .update({'is_pinned': false, 'pinned_by': null, 'pinned_at': null})
            .eq('id', messageId);

        if (mounted) {
          setState(() {
            _pinnedMessage = null;
            // Update in-memory message too
            final idx = _messages.indexWhere((m) => m['id'] == messageId);
            if (idx != -1) _messages[idx]['is_pinned'] = false;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Message unpinned')));
          // Broadcast to all clients
          _ablyService.publishPinUpdated(
            channelName: widget.channelId,
            pinnedMessageId: null,
          );
        }
      } else {
        // Unpin any existing pinned message first, then pin this one
        String filterColumn = widget.chatType == 'group'
            ? 'group_id'
            : 'table_id';
        await SupabaseConfig.client
            .from('messages')
            .update({'is_pinned': false, 'pinned_by': null, 'pinned_at': null})
            .eq(filterColumn, widget.tableId)
            .eq('is_pinned', true);

        await SupabaseConfig.client
            .from('messages')
            .update({
              'is_pinned': true,
              'pinned_by': _currentUserId,
              'pinned_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', messageId);

        if (mounted) {
          setState(() {
            _pinnedMessage = {
              'id': messageId,
              'content': message['content'],
              'sender_name': message['senderName'] ?? message['sender_name'],
              'content_type':
                  message['contentType'] ?? message['content_type'] ?? 'text',
            };
            // Update in-memory message
            for (final m in _messages) {
              m['is_pinned'] = (m['id'] == messageId);
            }
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Message pinned 📌')));
          // Broadcast to all clients
          _ablyService.publishPinUpdated(
            channelName: widget.channelId,
            pinnedMessageId: messageId,
            pinnedMessage: {
              'id': messageId,
              'content': message['content'],
              'sender_name': message['senderName'] ?? message['sender_name'],
              'content_type':
                  message['contentType'] ?? message['content_type'] ?? 'text',
            },
          );
        }
      }
    } catch (e) {
      print('❌ Error toggling pin: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${isCurrentlyPinned ? 'unpin' : 'pin'} message',
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadParticipants() async {
    try {
      final dynamic query;
      if (widget.chatType == 'trip') {
        query = SupabaseConfig.client
            .from('trip_chat_participants')
            .select('user_id')
            .eq('chat_id', widget.tableId);
      } else if (widget.chatType == 'dm' || widget.chatType == 'direct') {
        query = SupabaseConfig.client
            .from('direct_chat_participants')
            .select('user_id')
            .eq('chat_id', widget.tableId);
      } else if (widget.chatType == 'group') {
        query = SupabaseConfig.client
            .from('group_members')
            .select('user_id')
            .eq('group_id', widget.tableId)
            .eq('status', 'approved');
      } else {
        query = SupabaseConfig.client
            .from('table_members')
            .select('user_id, arrival_status, rsvp_status')
            .eq('table_id', widget.tableId)
            .inFilter('status', ['approved', 'joined', 'attended']);
      }

      final response = await query;

      // Create maps of userId -> status
      final statusMap = <String, String>{};
      final rsvpMap = <String, String?>{};
      final userIds = <String>[];

      for (var p in response) {
        final uid = p['user_id'] as String;
        userIds.add(uid);
        if (widget.chatType == 'table') {
          statusMap[uid] = p['arrival_status'] ?? 'joined';
          rsvpMap[uid] = p['rsvp_status'] as String?;
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
              'rsvp_status': rsvpMap[u['id']],
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
      } else if (widget.chatType == 'group') {
        tableName = 'messages';
        idColumn = 'group_id';
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
        // Query the correct table based on chat type
        String replyTableName;
        if (widget.chatType == 'trip') {
          replyTableName = 'trip_messages';
        } else if (widget.chatType == 'dm') {
          replyTableName = 'direct_messages';
        } else {
          replyTableName = 'messages';
        }

        final replyMessages = await SupabaseConfig.client
            .from(replyTableName)
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
              'reply_to_id': replyToId,
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

        // Handle pin broadcast
        if (message.name == 'pin_updated') {
          final pinnedId = data['pinnedMessageId'] as String?;
          if (mounted) {
            setState(() {
              if (pinnedId == null) {
                // Unpinned
                _pinnedMessage = null;
                for (final m in _messages) m['is_pinned'] = false;
              } else {
                // Newly pinned
                final pinData = data['pinnedMessage'] as Map?;
                _pinnedMessage = pinData != null
                    ? Map<String, dynamic>.from(pinData)
                    : {'id': pinnedId};
                for (final m in _messages) {
                  m['is_pinned'] = (m['id'] == pinnedId);
                }
              }
            });
          }
          return;
        }

        // Handle mute broadcast
        if (message.name == 'mute_updated') {
          final targetId = data['userId'] as String?;
          if (targetId == _currentUserId) {
            final nowMuted = data['isMuted'] == true;
            if (mounted) setState(() => _isMuted = nowMuted);
          }
          _loadParticipants();
          return;
        }

        // Handle reaction update broadcast
        if (message.name == 'reaction_updated') {
          _loadReactions();
          return;
        }

        // Handle delete-for-everyone broadcast
        if (message.name == 'message_deleted') {
          final deletedId = data['messageId'] as String?;
          if (deletedId != null && mounted) {
            setState(() {
              final idx = _messages.indexWhere((m) => m['id'] == deletedId);
              if (idx != -1) {
                _messages[idx] = {
                  ..._messages[idx],
                  'deletedAt': DateTime.now().toIso8601String(),
                  'deletedForEveryone': true,
                };
              }
            });
          }
          return;
        }

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
            // Resolve reply data from existing messages in memory
            Map<String, dynamic>? replyTo;
            if (data['replyToId'] != null) {
              final replyMsg = _messages.firstWhere(
                (m) => m['id'] == data['replyToId'],
                orElse: () => <String, dynamic>{},
              );
              if (replyMsg.isNotEmpty) {
                replyTo = {
                  'id': replyMsg['id'],
                  'content': replyMsg['content'],
                  'sender_id': replyMsg['senderId'],
                  'senderName': replyMsg['senderName'],
                };
              }
            }

            // Insert new message at Top (Index 0) because list is Newest -> Oldest
            _messages.insert(0, {
              'id': data['id'],
              'content': data['content'],
              'contentType': data['contentType'] ?? 'text',
              'senderId': data['senderId'],
              'senderName': data['senderName'],
              'senderPhotoUrl': data['senderPhotoUrl'],
              'timestamp': data['timestamp'],
              'isMe': data['senderId'] == _currentUserId,
              'reply_to_id': data['replyToId'],
              'replyTo': replyTo,
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

  /// Scroll to a search result by matched index
  void _scrollToSearchResult(int matchIndex) {
    if (matchIndex < 0 || matchIndex >= _matchedIndices.length) return;
    final messageIndex = _matchedIndices[matchIndex];

    // In a reversed ListView, index 0 = bottom. We need to estimate the
    // pixel offset. Each message is roughly 70px tall.
    final estimatedOffset = messageIndex * 70.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          estimatedOffset.clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({String? gifUrl}) async {
    if (_isMuted && !_isHost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You have been muted by the host and cannot send messages.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
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
        replyToId: replyToId, // Pass reply reference
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

      // Send mention push notifications (non-blocking)
      if (contentType == 'text') {
        _sendMentionPushNotifications(content);
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
  Future<void> _sendMessage_Legacy({
    String? gifUrl,
    String? imageUrl,
    String? pollId,
  }) async {
    HapticFeedback.lightImpact();
    // Determine content and type
    final String content;
    final String contentType;
    if (imageUrl != null) {
      content = imageUrl;
      contentType = 'image';
    } else if (pollId != null) {
      content = pollId;
      contentType = 'poll';
    } else if (gifUrl != null) {
      content = gifUrl;
      contentType = 'gif';
    } else {
      content = _messageController.text.trim();
      contentType = 'text';
    }

    if (content.isEmpty || _currentUserId == null) return;

    if (contentType == 'text') _messageController.clear();
    final replyToId = _replyingTo?['id'];
    setState(() {
      _replyingTo = null;
    });

    // Generate a client-side ID so the Ably echo has a stable id
    // and message['id'] is never null (prevents delete crash)
    final messageId = const Uuid().v4();

    try {
      // 1. Save to Supabase
      if (widget.chatType == 'trip') {
        await SupabaseConfig.client.from('trip_messages').insert({
          'id': messageId,
          'chat_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': content,
          'message_type': contentType,
          if (replyToId != null) 'reply_to_id': replyToId,
        });
      } else if (widget.chatType == 'dm') {
        await SupabaseConfig.client.from('direct_messages').insert({
          'id': messageId,
          'chat_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': content,
          'message_type': contentType,
          if (replyToId != null) 'reply_to_id': replyToId,
        });
      } else if (widget.chatType == 'group') {
        await SupabaseConfig.client.from('messages').insert({
          'id': messageId,
          'group_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': content,
          'content_type': contentType,
          if (replyToId != null) 'reply_to_id': replyToId,
        });
      } else {
        await SupabaseConfig.client.from('messages').insert({
          'id': messageId,
          'table_id': widget.tableId,
          'sender_id': _currentUserId,
          'content': content,
          'content_type': contentType,
          if (replyToId != null) 'reply_to_id': replyToId,
        });
      }

      // 2. Publish to Ably so other users see it instantly
      await _ablyService.publishMessage(
        channelName: widget.channelId,
        content: content,
        contentType: contentType,
        senderId: _currentUserId!,
        senderName: _currentUserName ?? 'Unknown',
        senderPhotoUrl: _currentUserPhoto,
        messageId: messageId,
        replyToId: replyToId,
      );

      // No optimistic insert needed — in legacy mode the Ably listener
      // echoes back our own message and handles display for all types.

      // Send mention notifications only for text
      if (contentType == 'text') {
        _sendMentionPushNotifications(content);
      }
    } catch (e) {
      debugPrint('❌ CHAT: Error sending message - $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    }
  }

  /// Send push notification to mentioned users
  Future<void> _sendMentionPushNotifications(String content) async {
    if (_currentUserId == null || _participants.isEmpty) return;

    // Extract @mentions from content
    final mentionRegex = RegExp(r'@([\w\s]+?)(?=\s@|\s[^@]|$)');
    final matches = mentionRegex.allMatches(content);

    for (final match in matches) {
      final name = match.group(1)?.trim();
      if (name == null) continue;

      // Find the participant by display name
      final participant = _participants.firstWhere(
        (p) =>
            (p['displayName'] as String?)?.toLowerCase() == name.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );

      if (participant.isEmpty) continue;
      final userId = participant['userId'] as String?;
      if (userId == null || userId == _currentUserId)
        continue; // Don't notify self

      try {
        // Insert in-app notification
        await SupabaseConfig.client.from('notifications').insert({
          'user_id': userId,
          'actor_id': _currentUserId,
          'type': 'chat',
          'title': '${_currentUserName ?? 'Someone'} mentioned you',
          'body': content.length > 100
              ? '${content.substring(0, 100)}...'
              : content,
          'entity_id': widget.tableId,
          'metadata': {
            'table_id': widget.tableId,
            'chat_type': widget.chatType,
          },
        });

        // Send push notification
        await SupabaseConfig.client.functions.invoke(
          'send-push',
          body: {
            'user_id': userId,
            'title': '${_currentUserName ?? 'Someone'} mentioned you',
            'body': content.length > 100
                ? '${content.substring(0, 100)}...'
                : content,
            'data': {
              'type': 'chat',
              'chat_type': widget.chatType,
              'table_id': widget.tableId,
              'sender_name': _currentUserName ?? 'Someone',
            },
          },
        );
      } catch (e) {
        print('⚠️ Failed to send mention notification to $userId: $e');
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
        // Determine the correct messages table based on chat type
        String messagesTable = 'messages';
        if (widget.chatType == 'dm') messagesTable = 'direct_messages';
        if (widget.chatType == 'trip') messagesTable = 'trip_messages';

        // If Telegram Mode, verify message exists first
        if (_useTelegramMode) {
          final messageExists = await SupabaseConfig.client
              .from(messagesTable)
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

        // Success — broadcast so all clients reload reactions
        await _ablyService.publishReactionUpdated(
          channelName: widget.channelId,
          messageId: messageId,
        );
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
    // Resolve the correct table based on chat type
    String messagesTable = 'messages';
    if (widget.chatType == 'dm') messagesTable = 'direct_messages';
    if (widget.chatType == 'trip') messagesTable = 'trip_messages';

    try {
      if (_useTelegramMode) {
        // In Telegram mode: delete from local DB and Supabase
        final messageId = message['id'];

        if (deleteForEveryone) {
          // Delete from Supabase (for everyone)
          await SupabaseConfig.client
              .from(messagesTable)
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
        // Legacy mode
        final messageId = message['id'];

        if (!deleteForEveryone) {
          // "Delete for me": hard-delete from DB (sender only, RLS enforces this)
          if (mounted) {
            setState(() => _messages.removeWhere((m) => m['id'] == messageId));
          }
          await SupabaseConfig.client
              .from(messagesTable)
              .delete()
              .eq('id', messageId);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Message deleted')));
          }
        } else {
          // "Delete for everyone": optimistic remove + DB update + Ably broadcast
          if (mounted) {
            setState(() => _messages.removeWhere((m) => m['id'] == messageId));
          }
          await SupabaseConfig.client
              .from(messagesTable)
              .update({
                'deleted_at': DateTime.now().toIso8601String(),
                'deleted_for_everyone': true,
              })
              .eq('id', messageId);
          await _ablyService.publishMessageDeleted(
            channelName: widget.channelId,
            messageId: messageId,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Message deleted for everyone')),
            );
          }
        }
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

    if (replyMsg['contentType'] == 'gif') return 'GIF 🎞';
    if (replyMsg['contentType'] == 'image') return 'Photo 🖼️';
    if (replyMsg['contentType'] == 'poll') return 'Poll 📊';

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

  /// Image picker: compress → upload → send as image message
  Future<void> _sendImageMessage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85, // Pre-compress via picker
    );
    if (picked == null || _currentUserId == null) return;

    try {
      // Compress further with flutter_image_compress
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/${const Uuid().v4()}.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        picked.path,
        targetPath,
        quality: 70,
        minWidth: 800,
        minHeight: 1,
        format: CompressFormat.jpeg,
      );
      if (compressed == null) return;

      final bytes = await File(compressed.path).readAsBytes();
      final fileName = '${_currentUserId}/${const Uuid().v4()}.jpg';

      // Upload to Supabase storage
      await SupabaseConfig.client.storage
          .from('chat-images')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      final imageUrl = SupabaseConfig.client.storage
          .from('chat-images')
          .getPublicUrl(fileName);

      // Send as image message
      await _sendMessage_Legacy(gifUrl: null, imageUrl: imageUrl);
    } catch (e) {
      debugPrint('❌ CHAT: Image upload failed - $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send image. Please try again.'),
          ),
        );
      }
    }
  }

  /// Poll creator: show sheet → insert to DB → send poll_id as message
  Future<void> _showCreatePoll() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const CreatePollSheet(),
    );
    if (result == null || _currentUserId == null) return;

    try {
      // Insert poll
      final pollData = await SupabaseConfig.client
          .from('chat_polls')
          .insert({
            'chat_id': widget.tableId,
            'chat_type': widget.chatType,
            'creator_id': _currentUserId,
            'question': result['question'],
            'options': result['options'],
          })
          .select('id')
          .single();

      final pollId = pollData['id'] as String;

      // Send poll_id as a special message
      await _sendMessage_Legacy(gifUrl: null, pollId: pollId);
    } catch (e) {
      debugPrint('❌ CHAT: Poll creation failed - $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create poll. Please try again.'),
          ),
        );
      }
    }
  }

  /// Opens the verification sheet (host scanning mode or attendee QR code)
  void _openVerificationSheet() {
    if (_currentUserId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VerificationSheet(
        currentUserId: _currentUserId!,
        tableId: widget.tableId,
        isMe: !_isHost,
        isHost: _isHost,
        participants: _participants,
      ),
    ).then((verified) {
      if (verified == true && _isHost) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All members verified! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  Future<void> _leaveTable() async {
    final subtitleText = widget.chatType == 'trip'
        ? 'You will leave this trip group chat.'
        : widget.chatType == 'dm'
        ? 'This conversation will be deleted from your inbox.'
        : 'You will be removed from this activity and its chat.';

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                'Leave Chat?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 8),
              // Subtitle
              Text(
                subtitleText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Leave',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      if (widget.chatType == 'trip') {
        // Leave Trip Chat
        final user = SupabaseConfig.client.auth.currentUser;
        if (user != null) {
          // Notify others before leaving
          await _sendSystemMessage(
            '${_currentUserName ?? 'Someone'} has left the chat',
          );
          // Note: tableId is passed as the chatId for trips in ActiveChatsList
          await SupabaseConfig.client
              .from('trip_chat_participants')
              .delete()
              .eq('chat_id', widget.tableId)
              .eq('user_id', user.id);
        }
      } else if (widget.chatType == 'dm') {
        // Delete DM conversation via RPC (bypasses RLS) — no system message for DMs
        await SupabaseConfig.client.rpc(
          'delete_dm_chat',
          params: {'p_chat_id': widget.tableId},
        );
      } else {
        // Table / Group — notify others before leaving
        await _sendSystemMessage(
          '${_currentUserName ?? 'Someone'} has left the chat',
        );
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
    // ── Embedded mode: just the chat body, no chrome ──
    if (widget.embedded) {
      return Column(children: [..._buildChatBody(context)]);
    }

    // ── Bottom-sheet mode (default) ──
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: screenHeight * 0.92,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              ChatHeader(
                title: widget.tableTitle,
                onLeave: _leaveTable,
                onClose: () => Navigator.pop(context),
                onSearch: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchQuery = '';
                      _matchedIndices = [];
                      _currentMatchIndex = -1;
                      _searchController.clear();
                    }
                  });
                },
                extraActions: [
                  // Invite button — host only
                  if (widget.chatType == 'table' && _isHost)
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_add_rounded,
                          size: 18,
                          color: Colors.blue,
                        ),
                      ),
                      tooltip: 'Invite someone',
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => InviteMemberSheet(
                          tableId: widget.tableId,
                          tableTitle: widget.tableTitle,
                        ),
                      ),
                    ),
                  // Verify button — show for all table members
                  if (widget.chatType == 'table')
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isHost ? Icons.qr_code_scanner : Icons.qr_code,
                          size: 18,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                      tooltip: _isHost ? 'Verify Members' : 'My Check-in QR',
                      onPressed: _openVerificationSheet,
                    ),
                ],
                onInfoTap: () {
                  if (widget.chatType == 'dm') {
                    final otherUser = _participants.firstWhere(
                      (p) => p['userId'] != _currentUserId,
                      orElse: () => <String, dynamic>{},
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
              ..._buildChatBody(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Shared chat body: connection banner, search, messages, typing, input
  List<Widget> _buildChatBody(BuildContext context) {
    return [
      // Connection Status Banner
      if (_showConnectionBanner)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
              const SizedBox(width: 12),
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

      // Pinned Message Banner
      if (_pinnedMessage != null)
        GestureDetector(
          onTap: () {
            // Scroll to pinned message
            final idx = _messages.indexWhere(
              (m) => m['id'] == _pinnedMessage!['id'],
            );
            if (idx != -1 && _scrollController.hasClients) {
              // Approximate scroll — messages are in reverse
              _scrollController.animateTo(
                idx * 60.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
              );
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A1A2E)
                  : const Color(0xFFF0F4FF),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[800]!
                      : Colors.grey[200]!,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.push_pin, size: 16, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _pinnedMessage!['sender_name'] ?? 'Pinned Message',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo,
                        ),
                      ),
                      Text(
                        _pinnedMessage!['content_type'] == 'image'
                            ? '📷 Photo'
                            : _pinnedMessage!['content_type'] == 'gif'
                            ? '🎬 GIF'
                            : (_pinnedMessage!['content'] ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[300]
                              : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _togglePinMessage({
                    'id': _pinnedMessage!['id'],
                    'is_pinned': true,
                  }),
                  child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),

      // RSVP Banner (table chats only, hide when activity is past)
      if (widget.chatType == 'table' && !_isActivityPast)
        RsvpBanner(
          tableId: widget.tableId,
          currentRsvpStatus: _currentRsvpStatus,
          goingCount: _rsvpGoingCount,
          maybeCount: _rsvpMaybeCount,
          notGoingCount: _rsvpNotGoingCount,
          onRsvpChanged: _updateRsvp,
        ),

      // Check-in Banner (table chats only, hide when activity is past)
      if (widget.chatType == 'table' && !_isActivityPast)
        CheckinBanner(
          tableId: widget.tableId,
          totalMembers: _participants.length,
          participants: _participants,
        ),

      // Search Bar
      if (_isSearching)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search messages...',
                      hintStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: Colors.grey[500],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (query) {
                      setState(() {
                        _searchQuery = query.toLowerCase();
                        _matchedIndices = [];
                        _currentMatchIndex = -1;
                        if (_searchQuery.isNotEmpty) {
                          for (int i = 0; i < _messages.length; i++) {
                            final content =
                                (_messages[i]['content'] as String?)
                                    ?.toLowerCase() ??
                                '';
                            if (content.contains(_searchQuery)) {
                              _matchedIndices.add(i);
                            }
                          }
                          if (_matchedIndices.isNotEmpty) {
                            _currentMatchIndex = 0;
                            _scrollToSearchResult(0);
                          }
                        }
                      });
                    },
                  ),
                ),
              ),
              if (_matchedIndices.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${_currentMatchIndex + 1}/${_matchedIndices.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  onPressed: _matchedIndices.length > 1
                      ? () {
                          setState(() {
                            _currentMatchIndex =
                                (_currentMatchIndex - 1) %
                                _matchedIndices.length;
                          });
                          _scrollToSearchResult(_currentMatchIndex);
                        }
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  onPressed: _matchedIndices.length > 1
                      ? () {
                          setState(() {
                            _currentMatchIndex =
                                (_currentMatchIndex + 1) %
                                _matchedIndices.length;
                          });
                          _scrollToSearchResult(_currentMatchIndex);
                        }
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
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
          onMentionTap: (userId) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(userId: userId),
              ),
            );
          },
          onAvatarTap: (userId) => _handleAvatarTap(userId),
          participants: _participants,
          searchQuery: _searchQuery,
          matchedIndices: _matchedIndices,
          currentMatchIndex: _currentMatchIndex,
          channelId: widget.channelId,
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

      // Muted banner
      if (_isMuted && !_isHost)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.orange.shade50,
          child: Row(
            children: [
              Icon(
                Icons.volume_off_rounded,
                size: 16,
                color: Colors.orange[700],
              ),
              const SizedBox(width: 8),
              Text(
                'You have been muted by the host.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.orange[800],
                  fontWeight: FontWeight.w500,
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
        onSendImage: _sendImageMessage,
        onCreatePoll: (widget.chatType == 'dm' || widget.chatType == 'direct')
            ? null
            : _showCreatePoll,
        participants: _participants,
      ),
    ];
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
            // Pin/Unpin (available in group and table chats)
            if (widget.chatType == 'group' || widget.chatType == 'table') ...[
              const Divider(),
              ListTile(
                leading: Icon(
                  message['is_pinned'] == true
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  color: Colors.indigo,
                ),
                title: Text(
                  message['is_pinned'] == true
                      ? 'Unpin Message'
                      : 'Pin Message',
                  style: const TextStyle(color: Colors.indigo),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _togglePinMessage(message);
                },
              ),
            ],
            if (!isOwnMessage) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.red),
                title: const Text(
                  'Report Message',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ReportModal.show(
                    context,
                    targetType: 'message',
                    targetId: message['id'] ?? '',
                    targetName: message['senderName'],
                  );
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
