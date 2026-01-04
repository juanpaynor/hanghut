import 'package:flutter/material.dart';
import 'package:bitemates/core/services/notification_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

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
      print("Error loading notifications: $e");
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
      default:
        iconData = Icons.notifications;
        iconColor = AppTheme.accentColor;
    }

    return Container(
      color: isRead
          ? Colors.transparent
          : AppTheme.accentColor.withOpacity(0.05),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[200],
              backgroundImage: (photoUrl != null)
                  ? CachedNetworkImageProvider(photoUrl)
                  : null,
              child: (photoUrl == null)
                  ? const Icon(Icons.person, size: 20)
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor,
                  ),
                  child: Icon(iconData, size: 8, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        title: RichText(
          text: TextSpan(
            style: TextStyle(color: Colors.black, fontSize: 13),
            children: [
              TextSpan(
                text: actor['display_name'] ?? 'Someone',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: ' ${item['title']}'),
            ],
          ),
        ),
        subtitle: Text(
          timeago.format(createdAt),
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        onTap: () async {
          if (!isRead) {
            await _service.markAsRead(item['id']);
            setState(() {
              item['is_read'] = true;
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            top:
                MediaQuery.of(context).padding.top +
                60, // approximate toolbar height anchor
            right: 16,
            left: 16, // Fill width with padding
            height: MediaQuery.of(context).size.height * 0.6, // 60% height
            child: Hero(
              tag: 'notification_bell',
              // Use a Material widget to handle the 'Circle -> Rect' morph cleanly
              child: Material(
                color: Colors.white, // Background of the expanded bubble
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Prevent layout/semantics crash during Hero flight by hiding content until large enough
                    if (constraints.maxWidth < 150) return const SizedBox();

                    return Column(
                      mainAxisSize: MainAxisSize.min, // key
                      children: [
                        // Header inside the bubble
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFF1F5F9)),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Notifications',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              // Close button (optional, but good UX)
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
                        ),

                        // List
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _handleRefresh,
                            child: _notifications.isEmpty && !_isLoading
                                ? Center(
                                    child: Text(
                                      'No notifications',
                                      style: TextStyle(color: Colors.grey[400]),
                                    ),
                                  )
                                : ListView.separated(
                                    controller: _scrollController,
                                    padding: EdgeInsets.zero,
                                    itemCount:
                                        _notifications.length +
                                        (_hasMore ? 1 : 0),
                                    separatorBuilder: (_, __) => const Divider(
                                      height: 1,
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                    itemBuilder: (context, index) {
                                      if (index == _notifications.length) {
                                        return const Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      return _buildNotificationItem(
                                        _notifications[index],
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
