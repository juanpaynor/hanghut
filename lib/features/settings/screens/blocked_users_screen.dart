import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/services/report_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    final users = await ReportService().getBlockedUsers();
    if (mounted) {
      setState(() {
        _blockedUsers = users;
        _isLoading = false;
      });
    }
  }

  Future<void> _unblockUser(String userId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unblock User'),
        content: Text('Are you sure you want to unblock $displayName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unblock', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ReportService().unblockUser(userId);
      if (success && mounted) {
        setState(() {
          _blockedUsers.removeWhere(
            (u) => u['blocked_user_id'] == userId,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName has been unblocked')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No blocked users',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Users you block won\'t be able to\nsee your profile or message you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _blockedUsers.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final block = _blockedUsers[index];
                    final user = block['user'] as Map<String, dynamic>? ?? {};
                    final displayName = user['display_name'] ?? 'Unknown';
                    final avatarUrl = user['avatar_url'] as String?;
                    final blockedAt = block['blocked_at'] != null
                        ? DateTime.tryParse(block['blocked_at'])
                        : null;

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: isDark
                            ? Colors.grey[700]
                            : Colors.grey[200],
                        backgroundImage: avatarUrl != null
                            ? CachedNetworkImageProvider(avatarUrl)
                            : null,
                        child: avatarUrl == null
                            ? Icon(Icons.person,
                                color: Colors.grey[400], size: 24)
                            : null,
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: blockedAt != null
                          ? Text(
                              'Blocked ${timeago.format(blockedAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            )
                          : null,
                      trailing: TextButton(
                        onPressed: () => _unblockUser(
                          block['blocked_user_id'],
                          displayName,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Unblock'),
                      ),
                    );
                  },
                ),
    );
  }
}
