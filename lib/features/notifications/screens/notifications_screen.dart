import 'package:flutter/material.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/core/services/notification_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/home/screens/post_detail_screen.dart';
import 'package:bitemates/features/ticketing/screens/my_tickets_screen.dart';
import 'package:bitemates/features/profile/screens/my_memberships_screen.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/groups/screens/group_detail_screen.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/core/services/event_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = false;
  bool _hasMore = true;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadNotifications(initial: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadNotifications(initial: false);
      }
    }
  }

  Future<void> _loadNotifications({required bool initial}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      DateTime? lastDate;
      if (!initial && _notifications.isNotEmpty) {
        lastDate = DateTime.parse(_notifications.last['created_at']);
      }

      final newItems = await _service.fetchNotifications(
        limit: _pageSize,
        before: lastDate,
      );

      if (mounted) {
        setState(() {
          if (initial) {
            _notifications = newItems;
          } else {
            _notifications.addAll(newItems);
          }
          _hasMore = newItems.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('⚠️ Error loading notifications: $e');
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _hasMore = true);
    await _loadNotifications(initial: true);
  }

  Widget _buildNotificationItem(Map<String, dynamic> item) {
    // ... [Same Item Logic as Before, slightly condensed for brevity]
    final actor = item['actor'] as Map<String, dynamic>? ?? {};
    final photos = (actor['user_photos'] as List<dynamic>?) ?? [];
    final photoUrl = photos.isNotEmpty
        ? photos.first['photo_url'] as String?
        : null;
    final type = item['type'] as String;
    final isRead = item['is_read'] as bool? ?? false;
    final createdAt = DateTime.parse(item['created_at']);

    IconData iconData;
    Color iconColor;

    switch (type) {
      case 'like':
        iconData = Icons.favorite;
        iconColor = Colors.pink;
        break;
      case 'comment':
        iconData = Icons.comment;
        iconColor = Colors.blue;
        break;
      case 'join_request':
        iconData = Icons.person_add;
        iconColor = Colors.orange;
        break;
      case 'approved':
        iconData = Icons.check_circle;
        iconColor = Colors.green;
        break;
      case 'system':
        iconData = Icons.info;
        iconColor = Colors.grey;
        break;
      case 'chat':
        iconData = Icons.chat_bubble;
        iconColor = Colors.deepPurple;
        break;
      case 'hangout_invite':
        iconData = Icons.mail;
        iconColor = Colors.indigo;
        break;
      case 'follower_hangout':
        iconData = Icons.celebration;
        iconColor = Colors.deepOrange;
        break;
      case 'friend_joined':
        iconData = Icons.person_add_alt_1;
        iconColor = Colors.teal;
        break;
      case 'mention':
        iconData = Icons.alternate_email;
        iconColor = Colors.amber[700]!;
        break;
      case 'badge_earned':
        iconData = Icons.military_tech;
        iconColor = Colors.purple;
        break;
      case 'trip_match':
        iconData = Icons.flight_takeoff;
        iconColor = Colors.teal;
        break;
      case 'group_join_request':
      case 'group_invite':
      case 'group_invite_suggestion':
        iconData = Icons.groups;
        iconColor = Colors.indigo;
        break;
      case 'group_approved':
        iconData = Icons.groups;
        iconColor = Colors.green;
        break;
      case 'group_admin_promoted':
        // military_tech is already bundled elsewhere; avoids a tree-shake "?"
        // glyph if this ever ships in a patch-only build.
        iconData = Icons.military_tech;
        iconColor = Colors.amber;
        break;
      default:
        iconData = Icons.notifications;
        iconColor = AppTheme.accentColor;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ringColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final titleColor =
        theme.textTheme.bodyLarge?.color ??
        (isDark ? Colors.white : Colors.black87);
    final bodyColor = isDark ? Colors.grey[400] : Colors.grey[700];
    final body = item['body']?.toString() ?? '';

    final content = Material(
      color: isRead
          ? Colors.transparent
          : AppTheme.accentColor.withValues(alpha: isDark ? 0.16 : 0.06),
      child: InkWell(
        onTap: () => _handleNotificationTap(item),
        onLongPress: () => _showItemMenu(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isDark
                        ? Colors.grey[800]
                        : Colors.grey[200],
                    backgroundImage: (photoUrl != null)
                        ? CachedNetworkImageProvider(photoUrl)
                        : null,
                    child: (photoUrl == null)
                        ? Icon(
                            Icons.person,
                            size: 22,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          )
                        : null,
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ringColor,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: iconColor,
                        ),
                        child: Icon(iconData, size: 9, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title'] ?? 'New Notification',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: titleColor,
                        height: 1.25,
                      ),
                    ),
                    if (body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: bodyColor,
                            height: 1.3,
                          ),
                        ),
                      ),
                    const SizedBox(height: 5),
                    Text(
                      timeago.format(createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[600] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              _buildTrailing(item, isRead, isDark),
            ],
          ),
        ),
      ),
    );

    final id = item['id']?.toString();
    if (id == null) return content;

    // Swipe left to delete, with an Undo snackbar (the DB delete is deferred
    // until the snackbar closes, so Undo is instant and needs no re-insert).
    return Dismissible(
      key: ValueKey('notif_$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade600,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      onDismissed: (_) => _deleteNotification(item),
      child: content,
    );
  }

  /// Long-press menu for a single notification (discoverable alternative to
  /// the swipe gesture).
  void _showItemMenu(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final isRead = item['is_read'] == true;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              if (!isRead)
                ListTile(
                  leading: const Icon(Icons.done_all),
                  title: const Text('Mark as read'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _service.markAsRead(item['id']);
                    setState(() => item['is_read'] = true);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete notification',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteNotification(item);
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  /// Removes a notification optimistically and shows an Undo snackbar. The
  /// actual DB delete is deferred until the snackbar closes without an undo.
  Future<void> _deleteNotification(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null) return;

    final index = _notifications.indexOf(item);
    if (index != -1) {
      setState(() => _notifications.removeAt(index));
    }

    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('Notification deleted'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            undone = true;
            if (mounted) {
              setState(() {
                final i = index == -1
                    ? _notifications.length
                    : index.clamp(0, _notifications.length);
                _notifications.insert(i, item);
              });
            }
          },
        ),
      ),
    );

    await controller.closed;
    if (!undone) {
      await _service.deleteNotification(id);
    }
  }

  /// Right-side accessory: post thumbnail preview (like Instagram) when the
  /// notification points at a post, otherwise an unread dot.
  Widget _buildTrailing(Map<String, dynamic> item, bool isRead, bool isDark) {
    final preview = item['preview_image_url']?.toString();
    final dot = isRead
        ? null
        : Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentColor,
            ),
          );

    if (preview != null && preview.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 10, top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null)
              Padding(padding: const EdgeInsets.only(right: 8), child: dot),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: isDark ? Colors.grey[850] : Colors.grey[200],
                image: DecorationImage(
                  image: CachedNetworkImageProvider(preview),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (dot != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 6),
        child: dot,
      );
    }
    return const SizedBox.shrink();
  }

  /// Time bucket a notification falls into, for section headers.
  String _bucketFor(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Earlier';
  }

  /// Flatten notifications into rows: section-header strings interleaved with
  /// notification maps (list is already sorted newest-first).
  List<dynamic> _buildRows() {
    final rows = <dynamic>[];
    String? bucket;
    for (final n in _notifications) {
      final b = _bucketFor(DateTime.parse(n['created_at']));
      if (b != bucket) {
        bucket = b;
        rows.add(b);
      }
      rows.add(n);
    }
    return rows;
  }

  Widget _buildEmptyState(bool isDark) {
    // ListView so pull-to-refresh still works when there's nothing yet.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(
          Icons.notifications_none_rounded,
          size: 52,
          color: isDark ? Colors.grey[700] : Colors.grey[300],
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            "You're all caught up",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'New activity will show up here',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: isDark ? Colors.grey[500] : Colors.grey[500],
        ),
      ),
    );
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> item) async {
    final type = item['type'];
    final entityId = item['entity_id'];
    final metadata = item['metadata'] ?? {};
    final isRead = item['is_read'] ?? false;

    // 1. Mark as read immediately
    if (!isRead) {
      _service.markAsRead(item['id']);
      setState(() {
        item['is_read'] = true;
      });
    }

    try {
      if (type == 'chat' ||
          // Chat mentions carry a chat_type → open the chat, not a post.
          (type == 'mention' && metadata['chat_type'] != null)) {
        _navigateToChat(entityId, metadata);
      } else if (type == 'trip_match') {
        // Trip match: entity_id is the chat_id, metadata has channel_id
        _navigateToChat(entityId, {...metadata, 'chat_type': 'trip'});
      } else if ([
        'join_request',
        'approved',
        'declined',
        'invite',
        'table',
        'table_join',
        'hangout_invite',
        'follower_hangout',
        'friend_joined',
        'member_joined',
        'host_status_update',
      ].contains(type)) {
        // Table / hangout — entity_id is the table id
        await _navigateToTable(entityId);
      } else if ([
        'ticket_confirmed',
        'ticket_purchase',
        'ticket_approved',
        'ticket_rejected',
      ].contains(type)) {
        // Ticket notifications — open My Tickets (entity_id is an event/ticket
        // id, NOT a post — this was the source of "Error fetching post").
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyTicketsScreen()),
          );
        }
      } else if ([
        'event_reminder',
        'event_reminder_1h',
        'event_reminder_24h',
        'follower_event',
        'new_event',
      ].contains(type)) {
        // Event notifications — entity_id (or metadata.event_id) is the event id
        final eventId = (metadata['event_id'] ?? entityId)?.toString();
        if (eventId != null) await _navigateToEvent(eventId);
      } else if ([
        'subscription_confirmed',
        'subscription_expired',
        'subscription_renewal_reminder',
        'claim_fulfilled',
      ].contains(type)) {
        // Fan subscription — open My Memberships
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyMembershipsScreen()),
          );
        }
      } else if (type == 'new_follower') {
        // entity_id (or metadata.follower_id) is the follower's user id
        final userId = (metadata['follower_id'] ?? entityId)?.toString();
        if (userId != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  UserProfileScreen(userId: userId, isOwnProfile: false),
            ),
          );
        }
      } else if (type == 'like' || type == 'comment' || type == 'mention') {
        // Social — entity_id (or metadata.post_id) is the post id
        final postId = (metadata['post_id'] ?? entityId)?.toString();
        if (postId != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PostDetailScreen(postId: postId),
            ),
          );
        }
      } else if ([
        'group_join_request',
        'group_approved',
        'group_invite',
        'group_invite_suggestion',
        'group_admin_promoted',
        'group_detail',
      ].contains(type)) {
        // Group membership — entity_id (or metadata.group_id) is the group id
        final groupId = (metadata['group_id'] ?? entityId)?.toString();
        if (groupId != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupDetailScreen(groupId: groupId),
            ),
          );
        }
      } else {
        // Unknown type — don't blindly open a post (it likely 404s). No-op.
        debugPrint('⚠️ Unhandled notification type: $type');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Could not open this notification',
        );
      }
    }
  }

  Future<void> _navigateToChat(
    String entityId,
    Map<String, dynamic> metadata,
  ) async {
    final chatType = metadata['chat_type'] ?? 'table';
    var channelId = '${chatType}_$entityId';
    String tableTitle = 'Chat';

    try {
      if (chatType == 'trip') {
        // Fetch Trip Chat Details (Bucket ID)
        final chat = await SupabaseConfig.client
            .from('trip_group_chats')
            .select('ably_channel_id, destination_city')
            .eq('id', entityId) // entityId is the chat_id
            .maybeSingle();

        if (chat != null) {
          channelId = chat['ably_channel_id'] ?? channelId;
          tableTitle = '${chat['destination_city']} Group';
        }
      } else if (chatType == 'dm' || chatType == 'direct') {
        // For DM notifications, entity_id IS the direct_chats.id (confirmed from schema).
        // No extra DB lookups needed.
        var chatId = metadata['chat_id'] ?? entityId;
        channelId = chatId.startsWith('direct_') ? chatId : 'direct_$chatId';
        tableTitle = metadata['actor_name'] ?? 'Direct Message';
        entityId = chatId;
      } else {
        // Table / Hangout
        final table = await SupabaseConfig.client
            .from('tables')
            .select('title')
            .eq('id', entityId)
            .maybeSingle();
        if (table != null) {
          tableTitle = table['title'] ?? 'Chat';
        }
      }
    } catch (e) {
      debugPrint('⚠️ Converting chat title/channel failed, using default: $e');
    }

    if (mounted) {
      // Normalize 'direct' -> 'dm' so ChatScreen queries the right tables
      final normalizedChatType = (chatType == 'direct') ? 'dm' : chatType;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        builder: (context) => ChatScreen(
          tableId: entityId,
          channelId: channelId,
          tableTitle: tableTitle,
          chatType: normalizedChatType,
        ),
      );
    }
  }

  Future<void> _navigateToTable(String tableId) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final table = await SupabaseConfig.client
          .from('tables')
          .select()
          .eq('id', tableId)
          .single();

      if (mounted) {
        Navigator.pop(context); // Close loader
        Navigator.pop(context); // Close notification panel
        showDialog(
          context: context,
          builder: (context) =>
              TableCompactModal(table: table, matchData: const {}),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loader
      rethrow;
    }
  }

  Future<void> _navigateToEvent(String eventId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final event = await EventService().getEvent(eventId);
      if (mounted) {
        Navigator.pop(context); // Close loader
        if (event != null) {
          Navigator.pop(context); // Close notification panel
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventDetailModal(event: event)),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loader
      rethrow;
    }
  }

  // ... [Existing build logic] ...

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Transparent Scaffold to allow background to show through (dimmed by ModalRoute)
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Gesture Detector to close when tapping outside
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.transparent),
          ),

          // 2. The Anchored Bubble
          Positioned(
            top: MediaQuery.of(context).padding.top + 48,
            right: 8,
            left: 8,
            height: MediaQuery.of(context).size.height * 0.78,
            child: Hero(
              tag: 'notification_bell',
              child: Material(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 150) return const SizedBox();

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : const Color(0xFFF1F5F9),
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  'Notifications',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_notifications.any(
                                    (n) => n['is_read'] != true,
                                  ))
                                    GestureDetector(
                                      onTap: () async {
                                        await _service.markAllAsRead();
                                        setState(() {
                                          for (final n in _notifications) {
                                            n['is_read'] = true;
                                          }
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        child: Text(
                                          'Mark all read',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.accentColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  InkWell(
                                    onTap: () => Navigator.pop(context),
                                    child: const Icon(
                                      Icons.close,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // List
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _handleRefresh,
                            child: _notifications.isEmpty && !_isLoading
                                ? _buildEmptyState(isDark)
                                : Builder(
                                    builder: (context) {
                                      final rows = _buildRows();
                                      return ListView.builder(
                                        controller: _scrollController,
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        itemCount:
                                            rows.length + (_hasMore ? 1 : 0),
                                        itemBuilder: (context, index) {
                                          if (index == rows.length) {
                                            return const Padding(
                                              padding: EdgeInsets.all(16.0),
                                              child: Center(
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              ),
                                            );
                                          }
                                          final row = rows[index];
                                          if (row is String) {
                                            return _buildSectionHeader(row);
                                          }
                                          return _buildNotificationItem(
                                            row as Map<String, dynamic>,
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
