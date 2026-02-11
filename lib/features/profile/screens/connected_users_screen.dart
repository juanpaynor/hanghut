import 'package:flutter/material.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/core/widgets/skeleton_loader.dart';
import 'package:bitemates/core/theme/app_theme.dart';

class ConnectedUsersScreen extends StatefulWidget {
  final String userId;
  final int initialTabIndex; // 0 for followers, 1 for following

  const ConnectedUsersScreen({
    super.key,
    required this.userId,
    this.initialTabIndex = 0,
  });

  @override
  State<ConnectedUsersScreen> createState() => _ConnectedUsersScreenState();
}

class _ConnectedUsersScreenState extends State<ConnectedUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accentColor,
          labelColor: AppTheme.accentColor,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Followers'),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _UserListTab(userId: widget.userId, type: 'followers'),
          _UserListTab(userId: widget.userId, type: 'following'),
        ],
      ),
    );
  }
}

class _UserListTab extends StatefulWidget {
  final String userId;
  final String type; // 'followers' or 'following'

  const _UserListTab({required this.userId, required this.type});

  @override
  State<_UserListTab> createState() => _UserListTabState();
}

class _UserListTabState extends State<_UserListTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final socialService = SocialService();
      List<Map<String, dynamic>> users;

      if (widget.type == 'followers') {
        users = await socialService.getFollowers(widget.userId);
      } else {
        users = await socialService.getFollowing(widget.userId);
      }

      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load users';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              widget.type == 'followers'
                  ? 'No followers yet'
                  : 'Not following anyone',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        final avatarUrl = user['avatar_url'];
        final displayName = user['display_name'] ?? 'Unknown User';
        final occupation = user['occupation'] as String?;
        final bio = user['bio'] as String?;
        final subtitle = occupation ?? bio ?? 'No bio available';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(displayName[0].toUpperCase())
                : null,
          ),
          title: Text(displayName),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          trailing: _FollowButton(userId: user['id']),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(userId: user['id']),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, __) => Row(
        children: const [
          SkeletonLoader.circle(size: 40),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: 120, height: 16),
                SizedBox(height: 8),
                SkeletonLoader(width: 80, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowButton extends StatefulWidget {
  final String userId;

  const _FollowButton({required this.userId});

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _isFollowing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final isFollowing = await SocialService().isFollowing(widget.userId);
    if (mounted) {
      setState(() {
        _isFollowing = isFollowing;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggle() async {
    setState(() => _isLoading = true);
    try {
      if (_isFollowing) {
        await SocialService().unfollowUser(widget.userId);
      } else {
        await SocialService().followUser(widget.userId);
      }
      if (mounted) {
        setState(() {
          _isFollowing = !_isFollowing;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Action failed')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // Don't show follow button for self
    // (Assuming SocialService handles auth check, but here we can check basic logic if needed)
    // For now, always show if not loading

    return OutlinedButton(
      onPressed: _toggle,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: BorderSide(
          color: _isFollowing ? Colors.grey : AppTheme.accentColor,
        ),
        backgroundColor: _isFollowing
            ? Colors.transparent
            : AppTheme.accentColor,
      ),
      child: Text(
        _isFollowing ? 'Following' : 'Follow',
        style: TextStyle(
          color: _isFollowing ? Colors.grey : Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }
}
