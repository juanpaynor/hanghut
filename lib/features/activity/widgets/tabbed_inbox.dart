import 'package:flutter/material.dart';
import 'package:bitemates/features/activity/services/chat_list_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/groups/screens/group_detail_screen.dart';
import 'package:bitemates/features/groups/screens/create_group_screen.dart';
import 'package:bitemates/features/groups/screens/discover_groups_screen.dart';
import 'package:bitemates/core/services/direct_chat_service.dart';
import 'package:intl/intl.dart';

/// Tabbed inbox: "Chats" (existing) + "Groups" (new)
class TabbedInbox extends StatefulWidget {
  const TabbedInbox({super.key});

  @override
  State<TabbedInbox> createState() => _TabbedInboxState();
}

class _TabbedInboxState extends State<TabbedInbox>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Tab Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color?.withOpacity(0.5) ??
                Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: theme.primaryColor,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey[600],
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            dividerHeight: 0,
            tabs: const [
              Tab(text: 'Chats'),
              Tab(text: 'Groups'),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _ChatsTab(),
              _GroupsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
//  CHATS TAB — existing ActiveChatsList logic
// ═══════════════════════════════════════════════
class _ChatsTab extends StatefulWidget {
  const _ChatsTab();

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  final ChatListService _chatListService = ChatListService();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _chats = [];
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
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadChats(refresh: false);
      }
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
      // Filter out group types — those appear in the Groups tab
      final newChats =
          all.where((c) => c['chat_type'] != 'group').toList();

      if (mounted) {
        setState(() {
          if (refresh) {
            _chats = newChats;
          } else {
            _chats.addAll(newChats);
          }
          _hasMore = all.length == _pageSize; // Use original length for paging
          _currentPage++;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ CHATS TAB: Error - $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'dm':
        return Colors.blue;
      case 'trip':
        return Colors.purple;
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
      await DirectChatService().deleteChat(chat['chat_id']);
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _loadChats(refresh: true),
      color: Theme.of(context).primaryColor,
      child: _chats.isEmpty && !_isLoading
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No active chats',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(height: 8),
                      Text('Join a hangout or message someone!',
                          style: TextStyle(color: Colors.grey[400])),
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _chats.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _chats.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final chat = _chats[index];
                final isDm = chat['chat_type'] == 'dm';

                if (isDm) {
                  return Dismissible(
                    key: Key('chat_${chat['chat_id']}'),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmDeleteChat(chat),
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.white, size: 28),
                    ),
                    child: _buildChatCard(chat),
                  );
                }

                return _buildChatCard(chat);
              },
            ),
    );
  }

  Widget _buildChatCard(Map<String, dynamic> chat) {
    final type = chat['chat_type'];
    final lastActivity = chat['last_activity_at'] != null
        ? DateTime.parse(chat['last_activity_at'])
        : DateTime.now();
    final timeStr = DateFormat('h:mm a').format(lastActivity);
    final metadata = chat['metadata'] ?? {};

    return GestureDetector(
      onTap: () async {
        String channelId;
        String tableTitle = chat['title'] ?? 'Chat';

        if (type == 'trip') {
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
            tableTitle: tableTitle,
            chatType: type == 'dm' ? 'dm' : type,
          ),
        );
        _loadChats(refresh: true);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
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
              // Avatar
              if (chat['image_url'] != null &&
                  chat['image_url'].toString().isNotEmpty)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey[200]!),
                    image: DecorationImage(
                      image: NetworkImage(chat['image_url']),
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getTypeColor(type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getIconFromKey(chat['icon_key']),
                    color: _getTypeColor(type),
                    size: 24,
                  ),
                ),
              const SizedBox(width: 16),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat['title'] ?? 'Chat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatSubtitle(chat['subtitle'] ?? ''),
                      style: TextStyle(
                        fontSize: 14,
                        color: chat['has_unread'] == true
                            ? Theme.of(context).textTheme.bodyLarge?.color
                            : Colors.grey[600],
                        fontWeight: chat['has_unread'] == true
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Time / Unread
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (type == 'dm' ||
                      (chat['unread_count'] != null &&
                          chat['unread_count'] > 0))
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: chat['has_unread'] == true
                            ? Theme.of(context).primaryColor
                            : Colors.grey[400],
                        fontWeight: chat['has_unread'] == true
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    )
                  else
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                  if (chat['unread_count'] != null &&
                      chat['unread_count'] > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        chat['unread_count'] > 99
                            ? '99+'
                            : chat['unread_count'].toString(),
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
}

// ═══════════════════════════════════════════════
//  GROUPS TAB
// ═══════════════════════════════════════════════
class _GroupsTab extends StatefulWidget {
  const _GroupsTab();

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  final ChatListService _chatListService = ChatListService();

  List<Map<String, dynamic>> _groupChats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      // Fetch group entries from the unified view (already filtered by user)
      final all = await _chatListService.fetchActiveChats(
        page: 0,
        limit: 50,
      );
      final groups = all.where((c) => c['chat_type'] == 'group').toList();
      if (mounted) {
        setState(() {
          _groupChats = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ GROUPS TAB: Error - $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _loadGroups,
      color: theme.primaryColor,
      child: Column(
        children: [
          // ── Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateGroupScreen(),
                        ),
                      );
                      _loadGroups(); // Refresh after creating
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.primaryColor,
                      side: BorderSide(color: theme.primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DiscoverGroupsScreen(),
                        ),
                      );
                      _loadGroups(); // Refresh after potentially joining
                    },
                    icon: const Icon(Icons.explore, size: 18),
                    label: const Text('Discover'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      side: const BorderSide(color: Colors.teal),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _groupChats.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          SizedBox(
                              height:
                                  MediaQuery.of(context).size.height * 0.05),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.groups_outlined,
                                    size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text('No groups yet',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey[400],
                                      fontWeight: FontWeight.w600,
                                    )),
                                const SizedBox(height: 8),
                                Text('Create or discover a community!',
                                    style:
                                        TextStyle(color: Colors.grey[400])),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _groupChats.length,
                        itemBuilder: (context, index) =>
                            _buildGroupCard(_groupChats[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> chat) {
    final metadata = chat['metadata'] ?? {};
    final iconEmoji = metadata['icon_emoji'] as String?;
    final memberCount = metadata['member_count'] ?? 0;
    final lastActivity = chat['last_activity_at'] != null
        ? DateTime.parse(chat['last_activity_at'])
        : DateTime.now();
    final timeStr = DateFormat('h:mm a').format(lastActivity);

    return GestureDetector(
      onTap: () async {
        // Navigate to group detail screen
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupDetailScreen(groupId: chat['chat_id']),
          ),
        );
        _loadGroups();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
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
              // Group Icon
              if (chat['image_url'] != null &&
                  chat['image_url'].toString().isNotEmpty)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey[200]!),
                    image: DecorationImage(
                      image: NetworkImage(chat['image_url']),
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: iconEmoji != null && iconEmoji.isNotEmpty
                        ? Text(iconEmoji, style: const TextStyle(fontSize: 24))
                        : const Icon(Icons.groups, color: Colors.teal, size: 24),
                  ),
                ),
              const SizedBox(width: 16),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat['title'] ?? 'Group',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '$memberCount members',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            chat['subtitle'] ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: chat['has_unread'] == true
                                  ? Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color
                                  : Colors.grey[600],
                              fontWeight: chat['has_unread'] == true
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Time / Unread
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: chat['has_unread'] == true
                          ? Colors.teal
                          : Colors.grey[400],
                      fontWeight: chat['has_unread'] == true
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (chat['unread_count'] != null &&
                      chat['unread_count'] > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        chat['unread_count'] > 99
                            ? '99+'
                            : chat['unread_count'].toString(),
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
}
