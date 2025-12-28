import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/chat/widgets/tenor_gif_picker.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

class TableDetailsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> table;
  final Map<String, dynamic>? matchData;

  const TableDetailsBottomSheet({
    super.key,
    required this.table,
    this.matchData,
  });

  @override
  State<TableDetailsBottomSheet> createState() =>
      _TableDetailsBottomSheetState();
}

class _TableDetailsBottomSheetState extends State<TableDetailsBottomSheet> {
  final _memberService = TableMemberService();
  bool _isLoading = false;
  Map<String, dynamic>? _membershipStatus;
  bool _isHost = false;
  List<Map<String, dynamic>> _members = [];
  String? _selectedGifUrl;

  @override
  void initState() {
    super.initState();
    _checkMembershipStatus();
    _loadMembers();
    _selectedGifUrl = widget.table['image_url'];
  }

  Future<void> _loadMembers() async {
    try {
      final members = await SupabaseConfig.client
          .from('table_members')
          .select(
            'user_id, users:user_id(display_name), user_photos:user_id(photo_url, is_primary)',
          )
          .eq('table_id', widget.table['id'])
          .inFilter('status', ['approved', 'joined']);

      if (mounted) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(members);
        });
      }
    } catch (e) {
      print('Error loading members: $e');
    }
  }

  Future<void> _checkMembershipStatus() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    _isHost = widget.table['host_id'] == user.id;

    if (!_isHost) {
      final status = await _memberService.getUserMembershipStatus(
        widget.table['id'],
      );
      if (mounted) {
        setState(() {
          _membershipStatus = status;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduledAt = DateTime.parse(widget.table['scheduled_time']);
    final currentCapacity = widget.table['current_capacity'] ?? 0;
    final maxCapacity = widget.table['max_capacity'] ?? 0;
    final timeUntil = scheduledAt.difference(DateTime.now());

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Image Section
                  _buildHeroImage(),

                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stats Bar
                        _buildStatsBar(currentCapacity, maxCapacity, timeUntil),

                        const SizedBox(height: 12),

                        // Venue & Address
                        _buildVenueSection(),

                        const SizedBox(height: 12),

                        // Event Details
                        _buildEventDetails(scheduledAt),

                        if (false) ...[
                          const SizedBox(height: 12),
                          _buildMembersSection(),
                        ],

                        if (false) ...[
                          const SizedBox(height: 16),
                          _buildDescription(),
                        ],

                        const SizedBox(height: 12),
                      ],
                    ),
                  ),

                  // Action Buttons (Sticky)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: _isHost
                          ? _buildHostActions()
                          : _buildMemberActions(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    return Center(
      child: GestureDetector(
        onTap: () async {
          if (_isHost) {
            final gifUrl = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => TenorGifPicker(
                onGifSelected: (gifUrl) {
                  Navigator.pop(context, gifUrl);
                },
              ),
            );

            if (gifUrl != null) {
              setState(() {
                _selectedGifUrl = gifUrl;
              });
              // Save to database
              await SupabaseConfig.client
                  .from('tables')
                  .update({'image_url': gifUrl})
                  .eq('id', widget.table['id']);
            }
          }
        },
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF5F5F5),
            image: _selectedGifUrl != null
                ? DecorationImage(
                    image: NetworkImage(_selectedGifUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: _selectedGifUrl == null
              ? const Icon(
                  Icons.add_photo_alternate,
                  size: 30,
                  color: Colors.black26,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildStatsBar(
    int currentCapacity,
    int maxCapacity,
    Duration timeUntil,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            Icons.people,
            '$currentCapacity/$maxCapacity',
            'Members',
          ),
          Container(width: 1, height: 40, color: Colors.black12),
          _buildStatItem(Icons.timer, _formatTimeUntil(timeUntil), 'Until'),
          Container(width: 1, height: 40, color: Colors.black12),
          _buildStatItem(
            Icons.auto_awesome,
            widget.matchData != null
                ? '${(widget.matchData!['score'] * 100).toInt()}%'
                : 'N/A',
            'Match',
          ),
          Container(width: 1, height: 40, color: Colors.black12),
          _buildStatItem(
            Icons.attach_money,
            _formatBudgetRangeShort(widget.table['budget_range']),
            'Budget',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.black, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildVenueSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.restaurant, color: Colors.black, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.table['venue_name'] ?? 'Unknown Venue',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            widget.table['venue_address'] ?? 'No address',
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildHostCard() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                UserProfileScreen(userId: widget.table['host_id']),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: widget.table['host_photo_url'] != null
                  ? NetworkImage(widget.table['host_photo_url'])
                  : null,
              backgroundColor: Colors.grey.shade300,
              child: widget.table['host_photo_url'] == null
                  ? const Icon(Icons.person, color: Colors.black54)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.table['host_name'] ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, color: Colors.black, size: 16),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Host • Trust Score: ${widget.table['host_trust_score'] ?? 0}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDetails(DateTime scheduledAt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildDetailRow2(
            Icons.calendar_today,
            'When',
            DateFormat('EEE, MMM d @ h:mm a').format(scheduledAt),
          ),
          const Divider(height: 20, color: Colors.black12),
          _buildDetailRow2(
            Icons.local_activity,
            'Activity',
            _formatActivityType(widget.table['activity_type']),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Members (${_members.length})',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserProfileScreen(userId: member['user_id']),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: 12,
                    left: 4,
                    top: 4,
                    bottom: 4,
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage:
                            member['user_photos'] != null &&
                                (member['user_photos'] as List).isNotEmpty
                            ? NetworkImage(
                                (member['user_photos'] as List)[0]['photo_url'],
                              )
                            : null,
                        backgroundColor: Colors.grey.shade300,
                        child:
                            member['user_photos'] == null ||
                                (member['user_photos'] as List).isEmpty
                            ? const Icon(
                                Icons.person,
                                color: Colors.black54,
                                size: 20,
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        member['users']?['display_name'] ?? 'User',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDescription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Description',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.table['description'],
          style: const TextStyle(color: Colors.black87, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildDetailRow2(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.black, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimeUntil(Duration duration) {
    if (duration.isNegative) return 'Started';
    if (duration.inDays > 0) return '${duration.inDays}d';
    if (duration.inHours > 0) return '${duration.inHours}h';
    return '${duration.inMinutes}m';
  }

  String _formatBudgetRangeShort(String? range) {
    if (range == null) return 'N/A';
    final map = {
      'budget': '\$',
      'moderate': '\$\$',
      'upscale': '\$\$\$',
      'fine_dining': '\$\$\$\$',
    };
    return map[range] ?? range;
  }

  String _formatActivityType(String? type) {
    if (type == null) return 'Social';
    final types = {
      'coffee': '☕ Coffee',
      'lunch': '🍽️ Lunch',
      'dinner': '🍷 Dinner',
      'drinks': '🍹 Drinks',
      'brunch': '🥐 Brunch',
    };
    return types[type] ?? type;
  }

  Widget _buildHostActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _openChat,
                icon: const Icon(Icons.chat, size: 20),
                label: const Text('Chat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _cancelTable,
                icon: const Icon(Icons.delete, size: 20),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _viewMembers,
                icon: const Icon(Icons.people, size: 20),
                label: const Text('Members'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _viewPendingRequests,
                icon: const Icon(Icons.people_outline, size: 20),
                label: const Text('Requests'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMemberActions() {
    // Check if user is already a member
    if (_membershipStatus != null) {
      final status = _membershipStatus!['status'];

      if (status == 'pending') {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.orange),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Request pending approval',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: _isLoading ? null : _cancelRequest,
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      } else if (status == 'approved' || status == 'joined') {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.black),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You\'re in! See you there 🎉',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _openChat,
                    icon: const Icon(Icons.chat, size: 20),
                    label: const Text('Chat'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _isLoading ? null : _leaveTable,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Leave'),
                ),
              ],
            ),
          ],
        );
      }
    }

    // Not a member - show join button
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _joinTable,
      icon: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.add, size: 20),
      label: const Text(
        'Join Table',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Member Actions
  Future<void> _joinTable() async {
    setState(() => _isLoading = true);

    final result = await _memberService.joinTable(widget.table['id']);

    if (mounted) {
      setState(() => _isLoading = false);

      if (result['success']) {
        Navigator.pop(context, true); // Return true to refresh map
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'])));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _leaveTable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Leave Table?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to leave this table?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    final result = await _memberService.leaveTable(widget.table['id']);

    if (mounted) {
      setState(() => _isLoading = false);

      Navigator.pop(context, true); // Return true to refresh map
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['message'])));
    }
  }

  Future<void> _cancelRequest() async {
    await _leaveTable(); // Same logic as leaving
  }

  void _openChat() {
    Navigator.pop(context); // Close bottom sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          tableId: widget.table['id'],
          tableTitle: widget.table['title'] ?? widget.table['venue_name'],
          channelId:
              widget.table['ably_channel_id'] ??
              'table:${widget.table['id']}:chat',
        ),
      ),
    );
  }

  // Host Actions
  void _viewPendingRequests() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pending requests screen coming soon!')),
    );
  }

  void _viewMembers() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('View members screen coming soon!')),
    );
  }

  Future<void> _cancelTable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Cancel Table?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will notify all members. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Table'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Table'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      // Update table status to cancelled
      await SupabaseConfig.client
          .from('tables')
          .update({'status': 'cancelled'})
          .eq('id', widget.table['id']);

      if (mounted) {
        Navigator.pop(context, true); // Return true to refresh map
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Table cancelled successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling table: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
