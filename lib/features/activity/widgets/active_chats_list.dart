import 'package:flutter/material.dart';
import 'package:bitemates/features/activity/services/chat_list_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:intl/intl.dart';

class ActiveChatsList extends StatefulWidget {
  const ActiveChatsList({super.key});

  @override
  State<ActiveChatsList> createState() => _ActiveChatsListState();
}

class _ActiveChatsListState extends State<ActiveChatsList> {
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
      final newChats = await _chatListService.fetchActiveChats(
        page: _currentPage,
        limit: _pageSize,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _chats = newChats;
          } else {
            _chats.addAll(newChats);
          }

          _hasMore = newChats.length == _pageSize;
          _currentPage++;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ ACTIVE CHATS: Error loading chats - $e');
      if (mounted) setState(() => _isLoading = false);
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

  Color _getTypeColor(String type) {
    switch (type) {
      case 'dm':
        return Colors.blue;
      case 'trip':
        return Colors.purple;
      default:
        return Theme.of(context).primaryColor; // Table
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardTheme.color ?? Colors.white,
      child: RefreshIndicator(
        onRefresh: () => _loadChats(refresh: true),
        color: Theme.of(context).primaryColor,
        child: _chats.isEmpty && !_isLoading
            ? ListView(
                // Use ListView to allow pull-to-refresh even when empty
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No active chats',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Join a hangout or message someone!',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
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

                  return _buildChatCard(_chats[index]);
                },
              ),
      ),
    );
  }

  Widget _buildChatCard(Map<String, dynamic> chat) {
    // Data from View: chat_id, chat_type, title, subtitle, image_url, icon_key, last_activity_at, metadata
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

        // Resolve Channel ID based on type & metadata
        if (type == 'trip') {
          // Trip metadata has bucket_id
          channelId = metadata['bucket_id'] ?? 'trip_${chat['chat_id']}';
        } else if (type == 'dm') {
          channelId = 'direct_${chat['chat_id']}';
        } else {
          // Table
          channelId = 'table_${chat['chat_id']}';
        }

        final result = await showModalBottomSheet<bool>(
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

        if (result == true) {
          _loadChats(refresh: true);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
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
              // Icon / Avatar Box
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
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chat['subtitle'] ?? '',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Time / Arrow
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (type == 'dm')
                    Text(
                      timeStr,
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    )
                  else
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
