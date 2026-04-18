import 'package:flutter/material.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

/// Host-only sheet for managing hangout participants.
/// Tap any member row to see actions: View Profile, Mute, Kick.
class ManageMembersSheet extends StatefulWidget {
  final String tableId;
  final String tableTitle;

  const ManageMembersSheet({
    super.key,
    required this.tableId,
    required this.tableTitle,
  });

  @override
  State<ManageMembersSheet> createState() => _ManageMembersSheetState();
}

class _ManageMembersSheetState extends State<ManageMembersSheet> {
  final _service = TableMemberService();
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    final members = await _service.getTableMembers(widget.tableId);
    if (mounted)
      setState(() {
        _members = members;
        _loading = false;
      });
  }

  void _showMemberActions(Map<String, dynamic> member) {
    final user = member['users'] as Map<String, dynamic>? ?? {};
    final userId = member['user_id'] as String;
    final name = user['display_name'] as String? ?? 'Unknown';
    final isMuted = member['is_muted'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _AvatarWidget(user: user, isDark: isDark, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                      if (isMuted)
                        Text(
                          'Currently muted',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.person_outline_rounded,
              label: 'View Profile',
              color: isDark ? Colors.white : Colors.black87,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(userId: userId),
                  ),
                );
              },
            ),
            _ActionTile(
              icon: isMuted
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              label: isMuted ? 'Unmute' : 'Mute in chat',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                _toggleMute(userId, name, isMuted);
              },
            ),
            _ActionTile(
              icon: Icons.person_remove_rounded,
              label: 'Remove from hangout',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _kickMember(userId, name);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _kickMember(String userId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_remove_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Remove member?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$name will be removed from this hangout.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Remove',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
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
    if (confirm != true) return;

    setState(() => _processingIds.add(userId));
    final result = await _service.removeMember(widget.tableId, userId);
    if (mounted) {
      setState(() {
        _processingIds.remove(userId);
        if (result['success'] == true)
          _members.removeWhere((m) => m['user_id'] == userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? '$name removed'
                : (result['message'] ?? 'Failed'),
          ),
          backgroundColor: result['success'] == true
              ? Colors.orange
              : Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleMute(
    String userId,
    String name,
    bool currentlyMuted,
  ) async {
    setState(() => _processingIds.add(userId));
    final result = currentlyMuted
        ? await _service.unmuteParticipant(widget.tableId, userId)
        : await _service.muteParticipant(widget.tableId, userId);
    if (mounted) {
      setState(() {
        _processingIds.remove(userId);
        if (result['success'] == true) {
          final idx = _members.indexWhere((m) => m['user_id'] == userId);
          if (idx != -1)
            _members[idx] = {..._members[idx], 'is_muted': !currentlyMuted};
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] ??
                (currentlyMuted ? '$name unmuted' : '$name muted'),
          ),
          backgroundColor: result['success'] == true
              ? AppTheme.primaryColor
              : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage Members',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        widget.tableTitle,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 14,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 6),
                Text(
                  'Tap a member to manage them',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _members.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No members yet.',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _members.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) {
                      final m = _members[i];
                      final user = m['users'] as Map<String, dynamic>? ?? {};
                      final userId = m['user_id'] as String;
                      final name = user['display_name'] as String? ?? 'Unknown';
                      final isMuted = m['is_muted'] == true;
                      final isProcessing = _processingIds.contains(userId);

                      return InkWell(
                        onTap: isProcessing
                            ? null
                            : () => _showMemberActions(m),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              _AvatarWidget(
                                user: user,
                                isDark: isDark,
                                radius: 22,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF1A1A2E),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isMuted) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(
                                                0.15,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.volume_off_rounded,
                                                  size: 10,
                                                  color: Colors.orange[700],
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'muted',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.orange[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      m['status'] as String? ?? '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isProcessing)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.more_vert_rounded,
                                  size: 20,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[400],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

class _AvatarWidget extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isDark;
  final double radius;

  const _AvatarWidget({
    required this.user,
    required this.isDark,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    String? avatarUrl = user['avatar_url'] as String?;
    final photos = user['user_photos'];
    if (avatarUrl == null && photos is List && photos.isNotEmpty) {
      avatarUrl = photos.first['photo_url'] as String?;
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
      backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
          ? NetworkImage(avatarUrl)
          : null,
      child: (avatarUrl == null || avatarUrl.isEmpty)
          ? Icon(
              Icons.person_rounded,
              size: radius,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            )
          : null,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: color.withOpacity(0.4),
      ),
      onTap: onTap,
    );
  }
}
