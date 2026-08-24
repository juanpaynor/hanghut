import 'package:flutter/material.dart';
import 'package:bitemates/features/activity/services/chat_list_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/groups/screens/group_chat_screen.dart';
import 'package:bitemates/features/groups/utils/group_cover_theme.dart';
import 'package:bitemates/features/groups/screens/create_group_screen.dart';
import 'package:bitemates/features/groups/screens/discover_groups_screen.dart';
import 'package:bitemates/features/search/screens/user_search_screen.dart';
import 'package:bitemates/core/services/direct_chat_service.dart';
import 'package:intl/intl.dart';

/// Unified inbox: DMs, groups, hangouts and trips in ONE recency-sorted list,
/// with filter chips (All / Unread / Groups / DMs) and a floating +New action.
/// (Replaces the old two-tab "Chats" / "Groups" layout.)
class TabbedInbox extends StatefulWidget {
  const TabbedInbox({super.key});

  @override
  State<TabbedInbox> createState() => _TabbedInboxState();
}

enum _InboxFilter { all, unread, groups, dms }

class _TabbedInboxState extends State<TabbedInbox> {
  final ChatListService _chatListService = ChatListService();
  final DirectChatService _directChatService = DirectChatService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  String _search = '';
  _InboxFilter _filter = _InboxFilter.all;

  List<Map<String, dynamic>> _chats = [];
  // group chat_id -> up to 3 member avatar URLs
  final Map<String, List<String>> _groupAvatars = {};

  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _loadChats(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) _loadChats(refresh: false);
    }
  }

  Future<void> _loadChats({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      setState(() {
        _isLoading = true;
        _currentPage = 0;
        _hasMore = true;
        _chats = [];
      });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final all = await _chatListService.fetchActiveChats(
        page: _currentPage,
        limit: _pageSize,
      );
      if (mounted) {
        setState(() {
          if (refresh) {
            _chats = all;
          } else {
            _chats.addAll(all);
          }
          _hasMore = all.length == _pageSize;
          _currentPage++;
          _isLoading = false;
        });
      }
      _fetchGroupAvatars();
    } catch (e) {
      print('❌ INBOX: Error - $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Lazily hydrate member avatars for any group rows we haven't fetched yet.
  Future<void> _fetchGroupAvatars() async {
    final missing = _chats
        .where((c) => c['chat_type'] == 'group')
        .map((c) => c['chat_id']?.toString())
        .whereType<String>()
        .where((id) => !_groupAvatars.containsKey(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    final avatars = await _chatListService.fetchGroupMemberAvatars(missing);
    if (!mounted || avatars.isEmpty) return;
    setState(() => _groupAvatars.addAll(avatars));
  }

  // ── Filtered + searched view of the loaded chats
  List<Map<String, dynamic>> get _visibleChats {
    final q = _search.toLowerCase();
    return _chats.where((c) {
      switch (_filter) {
        case _InboxFilter.all:
          break;
        case _InboxFilter.unread:
          if (c['has_unread'] != true) return false;
          break;
        case _InboxFilter.groups:
          if (c['chat_type'] != 'group') return false;
          break;
        case _InboxFilter.dms:
          if (c['chat_type'] != 'dm') return false;
          break;
      }
      if (q.isEmpty) return true;
      final title = (c['title'] ?? '').toString().toLowerCase();
      final subtitle = (c['subtitle'] ?? '').toString().toLowerCase();
      final last = (c['last_message_text'] ?? '').toString().toLowerCase();
      return title.contains(q) || subtitle.contains(q) || last.contains(q);
    }).toList();
  }

  // ═══════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════
  Color _getTypeColor(String? type) {
    switch (type) {
      case 'dm':
        return Colors.blue;
      case 'trip':
        return Colors.purple;
      case 'table':
        return const Color(0xFFF97316); // orange — hangouts
      default:
        return Theme.of(context).primaryColor;
    }
  }

  IconData _getIconFromKey(String? key) {
    switch (key?.toLowerCase()) {
      case 'coffee':
        return Icons.coffee;
      case 'food':
        return Icons.restaurant;
      case 'drinks':
        return Icons.local_bar;
      case 'study':
        return Icons.book;
      case 'game':
        return Icons.sports_esports;
      case 'flight':
        return Icons.flight;
      case 'person':
        return Icons.person;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  /// Returns (label, color) for a type pill, or null for DMs (the default).
  (String, Color)? _pillFor(String? type) {
    switch (type) {
      case 'group':
        return ('Group', Theme.of(context).primaryColor);
      case 'table':
        return ('Hangout', const Color(0xFFF97316));
      case 'trip':
        return ('Trip', Colors.teal);
      default:
        return null;
    }
  }

  String _formatSubtitle(String subtitle) {
    if (subtitle.isEmpty) return subtitle;
    final lower = subtitle.toLowerCase();
    if (lower.contains('/storage/v1/object/') ||
        RegExp(r'\.(jpg|jpeg|png|gif|webp)(\?|$)', caseSensitive: false)
            .hasMatch(lower)) {
      return '📷 Photo';
    }
    return subtitle;
  }

  Future<bool> _confirmDeleteChat(Map<String, dynamic> chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text(
          'Remove your chat with ${chat['title'] ?? 'this person'}? '
          'This will remove it from your inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await _directChatService.deleteChat(chat['chat_id']);
      if (mounted) {
        setState(() {
          _chats.removeWhere((c) => c['chat_id'] == chat['chat_id']);
        });
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete chat')),
        );
        _loadChats(refresh: true);
      }
      return false;
    }
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    final type = chat['chat_type'];

    // Groups open the full-screen group chat; details/activities live behind
    // the ⓘ button inside it.
    if (type == 'group') {
      final metadata = chat['metadata'];
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            groupId: chat['chat_id'],
            groupName: chat['title'],
            groupImageUrl: chat['image_url'],
            iconEmoji: metadata is Map ? metadata['icon_emoji'] : null,
          ),
        ),
      );
      _loadChats(refresh: true);
      return;
    }

    // Everything else opens the standard chat sheet.
    String channelId;
    if (type == 'trip') {
      final metadata = chat['metadata'] ?? {};
      channelId = metadata['bucket_id'] ?? 'trip_${chat['chat_id']}';
    } else if (type == 'dm') {
      channelId = 'direct_${chat['chat_id']}';
    } else {
      channelId = 'table_${chat['chat_id']}';
    }

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) => ChatScreen(
        channelId: channelId,
        tableId: chat['chat_id'],
        tableTitle: chat['title'] ?? 'Chat',
        chatType: type == 'dm' ? 'dm' : type,
      ),
    );
    _loadChats(refresh: true);
  }

  // ═══════════════════════════════════════════════
  //  +New action sheet
  // ═══════════════════════════════════════════════
  void _openNewSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color ?? Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
            const SizedBox(height: 8),
            _newTile(
              icon: Icons.edit_outlined,
              color: Colors.blue,
              title: 'New message',
              subtitle: 'Start a direct chat',
              onTap: () {
                Navigator.pop(ctx);
                _startNewMessage();
              },
            ),
            _newTile(
              icon: Icons.group_add_outlined,
              color: Theme.of(context).primaryColor,
              title: 'New group',
              subtitle: 'Create a community',
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                );
                _loadChats(refresh: true);
              },
            ),
            _newTile(
              icon: Icons.explore_outlined,
              color: Colors.teal,
              title: 'Discover groups',
              subtitle: 'Find communities to join',
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DiscoverGroupsScreen(),
                  ),
                );
                _loadChats(refresh: true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _newTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
    );
  }

  Future<void> _startNewMessage() async {
    final user = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => const UserSearchScreen(pickMode: true),
      ),
    );
    if (user == null || !mounted) return;
    final targetId = user['id']?.toString();
    if (targetId == null) return;
    try {
      final chatId = await _directChatService.startConversation(targetId);
      if (!mounted) return;
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        builder: (context) => ChatScreen(
          channelId: 'direct_$chatId',
          tableId: chatId,
          tableTitle: user['display_name'] ?? 'Chat',
          chatType: 'dm',
        ),
      );
      _loadChats(refresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start conversation')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visibleChats;
    final searching = _search.isNotEmpty;
    final showPagingLoader =
        _hasMore && !searching && _filter == _InboxFilter.all;

    return Stack(
      children: [
        Column(
          children: [
            // ── Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _search = v.trim()),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search conversations',
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: Colors.grey[500]),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: Colors.grey[500]),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                            FocusScope.of(context).unfocus();
                          },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: theme.cardTheme.color?.withOpacity(0.5) ??
                      Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 15),
              ),
            ),

            // ── Filter chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _filterChip('All', _InboxFilter.all),
                  _filterChip('Unread', _InboxFilter.unread),
                  _filterChip('Groups', _InboxFilter.groups),
                  _filterChip('DMs', _InboxFilter.dms),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadChats(refresh: true),
                color: theme.primaryColor,
                child: visible.isEmpty && !_isLoading
                    ? _buildEmptyState(searching)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: visible.length + (showPagingLoader ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == visible.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          final chat = visible[index];
                          final row = _buildRow(chat);
                          if (chat['chat_type'] == 'dm') {
                            return Dismissible(
                              key: Key('chat_${chat['chat_id']}'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) => _confirmDeleteChat(chat),
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                child: const Icon(Icons.delete_outline,
                                    color: Colors.white, size: 28),
                              ),
                              child: row,
                            );
                          }
                          return row;
                        },
                      ),
              ),
            ),
          ],
        ),

        // ── Floating +New (plain Material pill — no Hero, since this widget
        // tree may already sit inside a Hero).
        Positioned(
          right: 20,
          bottom: 24,
          child: Material(
            color: theme.primaryColor,
            borderRadius: BorderRadius.circular(30),
            elevation: 4,
            shadowColor: Colors.black45,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: _openNewSheet,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text('New',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, _InboxFilter value) {
    final selected = _filter == value;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? theme.primaryColor
                : (theme.cardTheme.color?.withOpacity(0.5) ??
                    Colors.grey[100]),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool searching) {
    IconData icon;
    String title;
    String subtitle;
    if (searching) {
      icon = Icons.search_off_rounded;
      title = 'No matches';
      subtitle = 'No conversations match your search';
    } else {
      switch (_filter) {
        case _InboxFilter.groups:
          icon = Icons.groups_outlined;
          title = 'No groups yet';
          subtitle = 'Tap “New” to create or discover one!';
          break;
        case _InboxFilter.unread:
          icon = Icons.mark_email_read_outlined;
          title = 'All caught up';
          subtitle = 'You have no unread conversations';
          break;
        case _InboxFilter.dms:
          icon = Icons.chat_bubble_outline;
          title = 'No direct messages';
          subtitle = 'Tap “New” to message someone!';
          break;
        case _InboxFilter.all:
          icon = Icons.chat_bubble_outline;
          title = 'No active chats';
          subtitle = 'Join a hangout or message someone!';
          break;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.1),
        Center(
          child: Column(
            children: [
              Icon(icon, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(title,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400])),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  Unified row — one card for every conversation type
  // ═══════════════════════════════════════════════
  Widget _buildRow(Map<String, dynamic> chat) {
    final type = chat['chat_type'] as String?;
    final isGroup = type == 'group';
    final lastActivity = chat['last_activity_at'] != null
        ? DateTime.parse(chat['last_activity_at'])
        : DateTime.now();
    final timeStr = DateFormat('h:mm a').format(lastActivity);
    final metadata = chat['metadata'] ?? {};
    final unread = (chat['unread_count'] as int?) ?? 0;
    final hasUnread = chat['has_unread'] == true;
    final pill = _pillFor(type);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _openChat(chat),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildAvatar(chat, type, metadata),
              const SizedBox(width: 14),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            chat['title'] ?? 'Chat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pill != null) ...[
                          const SizedBox(width: 6),
                          _typePill(pill.$1, pill.$2),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatSubtitle(chat['subtitle'] ?? ''),
                      style: TextStyle(
                        fontSize: 14,
                        color: hasUnread
                            ? theme.textTheme.bodyLarge?.color
                            : Colors.grey[600],
                        fontWeight:
                            hasUnread ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isGroup) _buildGroupFooter(chat, metadata),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Time / unread
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          hasUnread ? theme.primaryColor : Colors.grey[400],
                      fontWeight:
                          hasUnread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (unread > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : unread.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
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
  }

  Widget _buildAvatar(
      Map<String, dynamic> chat, String? type, Map metadata) {
    final imageUrl = chat['image_url']?.toString();
    final isGroup = type == 'group';
    final radius = isGroup ? 13.0 : (type == 'dm' ? 24.0 : 12.0);

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: type == 'dm' ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: type == 'dm' ? null : BorderRadius.circular(radius),
          border: Border.all(color: Colors.grey[200]!),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (isGroup) {
      final iconEmoji = metadata['icon_emoji'] as String?;
      final cover = GroupCover.forGroup(
        category: chat['icon_key'] as String?,
        seed: chat['chat_id'] as String?,
      );
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cover.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Center(
          child: iconEmoji != null && iconEmoji.isNotEmpty
              ? Text(iconEmoji, style: const TextStyle(fontSize: 24))
              : Icon(Icons.groups, color: cover.accent, size: 24),
        ),
      );
    }

    final color = _getTypeColor(type);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: type == 'dm' ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: type == 'dm' ? null : BorderRadius.circular(12),
      ),
      child: Icon(_getIconFromKey(chat['icon_key']), color: color, size: 24),
    );
  }

  /// Member-avatar stack + member count under a group row.
  Widget _buildGroupFooter(Map<String, dynamic> chat, Map metadata) {
    final memberCount = metadata['member_count'] ?? 0;
    final avatars = _groupAvatars[chat['chat_id']?.toString()] ?? const [];
    final cardColor = Theme.of(context).cardTheme.color ?? Colors.white;

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          if (avatars.isNotEmpty) ...[
            SizedBox(
              width: 18.0 + (avatars.length - 1) * 12.0,
              height: 20,
              child: Stack(
                children: [
                  for (int i = 0; i < avatars.length; i++)
                    Positioned(
                      left: i * 12.0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: cardColor, width: 1.5),
                          image: DecorationImage(
                            image: NetworkImage(avatars[i]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ] else ...[
            Icon(Icons.people_outline, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
          ],
          Text(
            '$memberCount members',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _typePill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}
