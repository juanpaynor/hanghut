import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/core/widgets/skeleton_loader.dart';

class UserListScreen extends StatefulWidget {
  final String title;
  final String userId;
  final String type; // 'followers' or 'following'

  const UserListScreen({
    super.key,
    required this.title,
    required this.userId,
    required this.type,
  });

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
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
      final supabase = SupabaseConfig.client;
      dynamic response;

      if (widget.type == 'followers') {
        response = await supabase
            .from('follows')
            .select('follower:users!follower_id(*)')
            .eq('following_id', widget.userId);
      } else {
        response = await supabase
            .from('follows')
            .select('following:users!following_id(*)')
            .eq('follower_id', widget.userId);
      }

      final List<Map<String, dynamic>> loadedUsers = [];
      for (var item in response) {
        final user = widget.type == 'followers'
            ? item['follower']
            : item['following'];
        if (user != null) {
          loadedUsers.add(user);
        }
      }

      if (mounted) {
        setState(() {
          _users = loadedUsers;
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? _buildSkeleton()
          : _errorMessage != null
          ? Center(child: Text(_errorMessage!))
          : _users.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No users found',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user['avatar_url'] != null
                        ? NetworkImage(user['avatar_url'])
                        : null,
                    child: user['avatar_url'] == null
                        ? Text((user['display_name'] ?? 'U')[0].toUpperCase())
                        : null,
                  ),
                  title: Text(user['display_name'] ?? 'Unknown User'),
                  subtitle: Text('@${user['username'] ?? 'user'}'),
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
            ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, __) => Row(
        children: [
          const SkeletonLoader.circle(size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
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
