import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

class ActiveUsersBottomSheet extends StatefulWidget {
  final double? minLat;
  final double? maxLat;
  final double? minLng;
  final double? maxLng;

  const ActiveUsersBottomSheet({
    Key? key,
    this.minLat,
    this.maxLat,
    this.minLng,
    this.maxLng,
  }) : super(key: key);

  @override
  State<ActiveUsersBottomSheet> createState() => _ActiveUsersBottomSheetState();
}

class _ActiveUsersBottomSheetState extends State<ActiveUsersBottomSheet> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  final int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchActiveUsers();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreUsers();
    }
  }

  Future<void> _fetchActiveUsers() async {
    try {
      // Use viewport filtering if bounds available
      if (widget.minLat != null &&
          widget.maxLat != null &&
          widget.minLng != null &&
          widget.maxLng != null) {
        final response = await SupabaseConfig.client.rpc(
          'get_active_users_in_viewport',
          params: {
            'min_lat': widget.minLat,
            'max_lat': widget.maxLat,
            'min_lng': widget.minLng,
            'max_lng': widget.maxLng,
            'page_size': _pageSize,
            'page_number': 0,
          },
        );

        if (mounted) {
          setState(() {
            _users = List<Map<String, dynamic>>.from(response);
            _hasMore = _users.length >= _pageSize;
            _isLoading = false;
          });
        }
      } else {
        // Fallback to global active users
        final response = await SupabaseConfig.client.rpc(
          'get_active_users',
          params: {'page_size': _pageSize, 'page_number': 0},
        );

        if (mounted) {
          setState(() {
            _users = List<Map<String, dynamic>>.from(response);
            _hasMore = _users.length >= _pageSize;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error fetching active users: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _page + 1;

      // Use viewport filtering if bounds available
      if (widget.minLat != null &&
          widget.maxLat != null &&
          widget.minLng != null &&
          widget.maxLng != null) {
        final response = await SupabaseConfig.client.rpc(
          'get_active_users_in_viewport',
          params: {
            'min_lat': widget.minLat,
            'max_lat': widget.maxLat,
            'min_lng': widget.minLng,
            'max_lng': widget.maxLng,
            'page_size': _pageSize,
            'page_number': nextPage,
          },
        );

        if (mounted) {
          final newUsers = List<Map<String, dynamic>>.from(response);
          setState(() {
            _users.addAll(newUsers);
            _page = nextPage;
            _hasMore = newUsers.length >= _pageSize;
            _isLoadingMore = false;
          });
        }
      } else {
        // Fallback
        final response = await SupabaseConfig.client.rpc(
          'get_active_users',
          params: {'page_size': _pageSize, 'page_number': nextPage},
        );

        if (mounted) {
          final newUsers = List<Map<String, dynamic>>.from(response);
          setState(() {
            _users.addAll(newUsers);
            _page = nextPage;
            _hasMore = newUsers.length >= _pageSize;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      print('Error loading more users: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              const Text(
                'Active Now',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_users.length} ${widget.minLat != null ? "nearby" : "online"}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // List
          if (_isLoading)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 5,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: _GhostTile(),
              ),
            )
          else if (_users.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                widget.minLat != null
                    ? "No one active in this area.\nTry zooming out or check back later. 🗺️"
                    : "It's quiet... for now. 🦗",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: _users.length + (_isLoadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == _users.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: _GhostTile(),
                    );
                  }

                  final user = _users[index];
                  final lastActive = DateTime.parse(user['last_active_at']);

                  // Logic to prioritize user_photos, similar to other screens
                  String? avatarUrl;
                  if (user['user_photos'] != null &&
                      (user['user_photos'] as List).isNotEmpty) {
                    avatarUrl = user['user_photos'][0]['photo_url'];
                  } else {
                    avatarUrl = user['avatar_url'];
                  }

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: avatarUrl != null
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? const Icon(Icons.person, color: Colors.grey)
                          : null,
                    ),
                    title: Text(
                      user['display_name'] ?? 'User',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Active ${timeago.format(lastActive)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              UserProfileScreen(userId: user['id']),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _GhostTile extends StatefulWidget {
  const _GhostTile();

  @override
  State<_GhostTile> createState() => _GhostTileState();
}

class _GhostTileState extends State<_GhostTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(
      begin: 0.3,
      end: 0.8,
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Row(
            children: [
              // Ghost Avatar
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFEEEEEE),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 16),
              // Ghost Text Lines
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEEEEE),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEEEEE),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
