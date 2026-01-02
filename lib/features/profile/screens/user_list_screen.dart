import 'package:flutter/material.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

class UserListScreen extends StatefulWidget {
  final String title;
  final String currentUserId; // The user whose connections we are viewing
  final Future<List<dynamic>> Function() fetchFunction;

  const UserListScreen({
    super.key,
    required this.title,
    required this.currentUserId,
    required this.fetchFunction,
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
    setState(() => _isLoading = true);
    try {
      // 1. Fetch connections from Stream (dynamic returns)
      final connections = await widget.fetchFunction();

      // 2. Extract User IDs
      // Stream 'Follow' object usually has 'target_id' (user:ID) or 'feed_id'
      // connection structure: { target_id: 'user:123', ... }
      final userIds = <String>{};

      for (var doc in connections) {
        // Handle different possible structures since we are using dynamic
        // Usually it's target_id for following (timeline -> user:X)
        // And feed_id for followers (user:X -> user:ME) - wait, followers list returns feeds that follow ME.
        // Let's assume the helper method returns the target user ID embedded in the ID string.

        String? targetString;
        try {
          // Attempt to read target_id or feed_id
          // If using stream_feeds package, it might be an object with .targetId or .feedId properties
          // But since we cast to dynamic, we might need accessors.
          // Let's try to parse meaningful IDs strings if available.
          // If it's a Map-like object (JSON):
          if (doc is Map) {
            targetString = doc['target_id'] ?? doc['feed_id'];
          } else {
            // Try property access via dynamic
            targetString = doc.targetId; // common property
          }
        } catch (e) {
          // Fallback
          print('Error parsing connection: $e');
        }

        if (targetString != null) {
          final parts = targetString.split(':');
          if (parts.length == 2 && parts[0] == 'user') {
            userIds.add(parts[1]);
          }
        }
      }

      if (userIds.isEmpty) {
        setState(() {
          _users = [];
          _isLoading = false;
        });
        return;
      }

      final response = await SupabaseConfig.client
          .from('users')
          .select('id, display_name, avatar_url, occupation')
          .filter('id', 'in', userIds.toList());

      setState(() {
        _users = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _errorMessage = 'Failed to load list';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            )
          : _errorMessage != null
          ? Center(child: Text(_errorMessage!))
          : _users.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_outlined, size: 60, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text(
                    'No users found',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = _users[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundImage: user['avatar_url'] != null
                        ? NetworkImage(user['avatar_url'])
                        : null,
                    backgroundColor: Colors.grey[200],
                    child: user['avatar_url'] == null
                        ? const Icon(Icons.person, color: Colors.grey)
                        : null,
                  ),
                  title: Text(
                    user['display_name'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: user['occupation'] != null
                      ? Text(user['occupation'])
                      : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfileScreen(
                          userId: user['id'],
                          isOwnProfile:
                              user['id'] ==
                              SupabaseConfig.client.auth.currentUser?.id,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
