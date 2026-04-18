import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/core/services/social_service.dart';

/// Host-only sheet to search and invite users to a hangout.
class InviteMemberSheet extends StatefulWidget {
  final String tableId;
  final String tableTitle;

  const InviteMemberSheet({
    super.key,
    required this.tableId,
    required this.tableTitle,
  });

  @override
  State<InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<InviteMemberSheet> {
  final _service = TableMemberService();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  final Set<String> _inviting = {};
  final Set<String> _invited = {};
  Set<String> _existingMemberIds = {};

  @override
  void initState() {
    super.initState();
    _loadExistingMembers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadExistingMembers() async {
    try {
      final members = await SupabaseConfig.client
          .from('table_members')
          .select('user_id, status')
          .eq('table_id', widget.tableId)
          .inFilter('status', ['joined', 'approved', 'attended', 'pending']);
      setState(() {
        _existingMemberIds = {for (final m in members) m['user_id'] as String};
      });
    } catch (_) {}
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = query.trim();
      if (q.isEmpty) {
        setState(() {
          _results = [];
          _searching = false;
        });
      } else {
        _search(q);
      }
    });
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
      final cleanQuery = query.startsWith('@') ? query.substring(1) : query;
      final results = await SocialService().searchUsers(cleanQuery, limit: 10);
      final filtered = results.where((u) {
        final uid = u['id'] as String;
        return uid != currentUserId && !_existingMemberIds.contains(uid);
      }).toList();
      if (mounted)
        setState(() {
          _results = filtered;
          _searching = false;
        });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _invite(Map<String, dynamic> user) async {
    final userId = user['id'] as String;
    setState(() => _inviting.add(userId));
    final result = await _service.inviteUserToTable(widget.tableId, userId);
    if (mounted) {
      setState(() {
        _inviting.remove(userId);
        if (result['success'] == true) {
          _invited.add(userId);
          _existingMemberIds.add(userId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Done'),
          backgroundColor: result['success'] == true
              ? Colors.green
              : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
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
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invite to Hangout',
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
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _controller,
              onChanged: _onSearchChanged,
              autofocus: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search by name or @username',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[500]),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_controller.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                color: Colors.grey[500],
                              ),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _results = []);
                              },
                            )
                          : null),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          // Results
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: _results.isEmpty && !_searching && _controller.text.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Search for people to invite',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : _results.isEmpty && !_searching
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No users found',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) {
                      final user = _results[i];
                      final uid = user['id'] as String;
                      final name = user['display_name'] as String? ?? 'Unknown';
                      final username = user['username'] as String?;
                      final photoUrl = user['avatar_url'] as String?;
                      final isInviting = _inviting.contains(uid);
                      final isInvited = _invited.contains(uid);

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[100],
                          backgroundImage:
                              (photoUrl != null && photoUrl.isNotEmpty)
                              ? NetworkImage(photoUrl)
                              : null,
                          child: (photoUrl == null || photoUrl.isEmpty)
                              ? Icon(
                                  Icons.person_rounded,
                                  size: 22,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[400],
                                )
                              : null,
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A2E),
                          ),
                        ),
                        subtitle: username != null
                            ? Text(
                                '@$username',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              )
                            : null,
                        trailing: isInviting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : isInvited
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: Colors.green[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Added',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green[600],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : GestureDetector(
                                onTap: () => _invite(user),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Invite',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
