import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitemates/core/services/group_service.dart';
import 'package:bitemates/core/services/group_member_service.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/map/widgets/create_hangout/create_hangout_flow.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bitemates/features/groups/screens/edit_group_screen.dart';

/// Minimal group detail: cover → meta → tabs (Chat | Members | About)
class GroupDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  final GroupService _groupService = GroupService();
  final GroupMemberService _memberService = GroupMemberService();

  late TabController _tabController;

  Map<String, dynamic>? _group;
  Map<String, dynamic>? _membership;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _activities = [];
  bool _isLoading = true;

  // Invite search state
  final TextEditingController _inviteController = TextEditingController();
  Timer? _inviteDebounce;
  List<Map<String, dynamic>> _inviteSearchResults = [];
  bool _showInviteResults = false;
  bool _isInviting = false;

  String? get _currentUserId => SupabaseConfig.client.auth.currentUser?.id;
  bool get _isMember => _membership?['status'] == 'approved';
  bool get _isAdmin =>
      _membership?['role'] == 'admin' || _membership?['role'] == 'owner';
  bool get _isOwner => _membership?['role'] == 'owner';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inviteController.dispose();
    _inviteDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadGroup(),
      _loadMembership(),
      _loadMembers(),
      _loadActivities(),
    ]);
    if (_isAdmin) {
      await _loadPendingRequests();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadGroup() async {
    final g = await _groupService.getGroup(widget.groupId);
    if (mounted) setState(() => _group = g);
  }

  Future<void> _loadMembership() async {
    final m = await _memberService.getUserMembershipStatus(widget.groupId);
    if (mounted) setState(() => _membership = m);
  }

  Future<void> _loadMembers() async {
    final list = await _memberService.getMembers(widget.groupId);
    if (mounted) setState(() => _members = list);
  }

  Future<void> _loadPendingRequests() async {
    final list = await _memberService.getPendingRequests(widget.groupId);
    if (mounted) setState(() => _pendingRequests = list);
  }

  Future<void> _loadActivities() async {
    final list = await _groupService.getGroupActivities(widget.groupId);
    if (mounted) setState(() => _activities = list);
  }

  // ─── Actions ───────────────────────────────────

  Future<void> _joinGroup() async {
    HapticFeedback.mediumImpact();
    final result = await _memberService.joinGroup(widget.groupId);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Done')));
      await _loadAll();
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _memberService.leaveGroup(widget.groupId);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Done')));
      Navigator.pop(context);
    }
  }

  Future<void> _openGroupChat() async {
    if (!_isMember) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) => ChatScreen(
        channelId: 'group_${widget.groupId}',
        tableId: widget.groupId,
        tableTitle: _group?['name'] ?? 'Group Chat',
        chatType: 'group',
      ),
    );
  }

  void _shareGroup() {
    final name = _group?['name'] ?? 'a group';
    SharePlus.instance.share(
      ShareParams(text: 'Check out "$name" on HangHut!'),
    );
  }

  // ─── Build ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Group not found')),
      );
    }

    final group = _group!;
    final coverUrl = group['cover_image_url'] as String?;
    final iconEmoji = group['icon_emoji'] as String?;
    final category = group['category'] as String? ?? 'other';
    final memberCount = group['member_count'] ?? _members.length;
    final privacy = group['privacy'] as String? ?? 'public';
    final primaryColor = theme.colorScheme.primary;
    final mutedText = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // ── Cover Photo Header
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              backgroundColor: theme.scaffoldBackgroundColor,
              leading: _circleIconButton(
                icon: Icons.arrow_back_ios_new,
                onTap: () => Navigator.pop(context),
              ),
              actions: [
                if (_isMember)
                  _circleIconButton(
                    icon: Icons.chat_bubble_outline,
                    onTap: _openGroupChat,
                  ),
                if (_isAdmin)
                  _circleIconButton(
                    icon: Icons.more_horiz,
                    onTap: () => _showOwnerMenu(context),
                  ),
                const SizedBox(width: 4),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cover image or gradient
                    if (coverUrl != null)
                      Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _defaultCoverGradient(primaryColor),
                      )
                    else
                      _defaultCoverGradient(primaryColor),

                    // Gradient overlay for readability
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                          stops: const [0.3, 1.0],
                        ),
                      ),
                    ),

                    // Group name + pills on overlay
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group['name'] ?? 'Group',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _pill(
                                text: _getCategoryLabel(category),
                                emoji: iconEmoji,
                                icon: iconEmoji == null || iconEmoji.isEmpty
                                    ? _getCategoryIcon(category)
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              _pill(
                                text:
                                    privacy[0].toUpperCase() +
                                    privacy.substring(1),
                                icon: _privacyIcon(privacy),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Info Row + Action Buttons
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  children: [
                    // Member count + location
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 16, color: mutedText),
                        const SizedBox(width: 6),
                        Text(
                          '$memberCount member${memberCount == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 14, color: mutedText),
                        ),
                        if (group['location_city'] != null) ...[
                          const SizedBox(width: 16),
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: mutedText,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              group['location_city'],
                              style: TextStyle(fontSize: 14, color: mutedText),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      children: [
                        // Primary action
                        Expanded(child: _buildPrimaryAction(primaryColor)),
                        const SizedBox(width: 12),
                        // Share button
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _shareGroup,
                            icon: Icon(
                              Icons.share_outlined,
                              size: 18,
                              color: mutedText,
                            ),
                            label: Text(
                              'Share',
                              style: TextStyle(color: mutedText),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.grey[800]!
                                    : Colors.grey[300]!,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Tab Bar
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: primaryColor,
                  unselectedLabelColor: mutedText,
                  indicatorColor: primaryColor,
                  indicatorWeight: 2.5,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: isDark ? Colors.grey[850] : Colors.grey[200],
                  dividerHeight: 0.5,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  tabs: [
                    const Tab(text: 'Chat'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Flexible(
                            child: Text(
                              'Activities',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_activities.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_activities.length}',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Members'),
                          if (_isAdmin && _pendingRequests.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_pendingRequests.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Tab(text: 'About'),
                  ],
                ),
                theme.scaffoldBackgroundColor,
              ),
            ),
          ];
        },

        // ── Tab Body
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildChatTab(),
            _buildActivitiesTab(),
            _buildMembersTab(),
            _buildAboutTab(),
          ],
        ),
      ),
    );
  }

  // ─── Primary Action Button ────────────────────

  Widget _buildPrimaryAction(Color primaryColor) {
    if (_isMember && !_isOwner) {
      return OutlinedButton.icon(
        onPressed: _leaveGroup,
        icon: const Icon(Icons.logout, size: 18),
        label: const Text('Leave'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red[400],
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: Colors.red[300]!),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    if (_membership?['status'] == 'pending') {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_top, size: 18),
        label: const Text('Pending'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: Colors.grey[400]!),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    if (_isOwner) {
      return ElevatedButton.icon(
        onPressed: () => _tabController.animateTo(2),
        icon: const Icon(Icons.person_add_outlined, size: 18),
        label: const Text('Invite'),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    // Not a member — Join
    return ElevatedButton.icon(
      onPressed: _joinGroup,
      icon: const Icon(Icons.group_add_outlined, size: 18),
      label: const Text('Join Group'),
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── Chat Tab ──────────────────────────────────

  Widget _buildChatTab() {
    if (_membership?['status'] == 'pending') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_top, size: 48, color: Colors.orange[400]),
            const SizedBox(height: 16),
            Text(
              'Awaiting Approval',
              style: TextStyle(
                color: Colors.orange[400],
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your join request is being reviewed\nby the group admin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    if (!_isMember) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Join the group to access the chat',
              style: TextStyle(color: Colors.grey[500], fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _joinGroup,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Join Group'),
            ),
          ],
        ),
      );
    }

    return ChatScreen(
      channelId: 'group_${widget.groupId}',
      tableId: widget.groupId,
      tableTitle: _group?['name'] ?? 'Group Chat',
      chatType: 'group',
      embedded: true,
    );
  }

  // ─── Activities Tab ────────────────────────────

  Widget _buildActivitiesTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();

    // Split into upcoming and past
    final upcoming = _activities.where((a) {
      final dt = DateTime.tryParse(a['datetime']?.toString() ?? '');
      return dt != null && dt.isAfter(now);
    }).toList();
    final past = _activities.where((a) {
      final dt = DateTime.tryParse(a['datetime']?.toString() ?? '');
      return dt == null || !dt.isAfter(now);
    }).toList();

    if (_activities.isEmpty && !_isAdmin) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No activities yet',
              style: TextStyle(color: Colors.grey[500], fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadActivities,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
            children: [
              // Upcoming
              if (upcoming.isNotEmpty) ...[
                _sectionHeader(
                  'Upcoming',
                  primaryColor,
                  count: upcoming.length,
                ),
                const SizedBox(height: 10),
                ...upcoming.map((a) => _buildActivityCard(a, isDark)),
              ],

              // Empty state for upcoming (but admin can create)
              if (upcoming.isEmpty && _isAdmin) ...[
                _sectionHeader('Upcoming', primaryColor),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.celebration_outlined,
                        size: 40,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Create the first group activity!',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _openCreateActivityModal,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Create Activity'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Past
              if (past.isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionHeader('Past', Colors.grey[500]!, count: past.length),
                const SizedBox(height: 10),
                ...past.map((a) => _buildActivityCard(a, isDark, isPast: true)),
              ],
            ],
          ),
        ),

        // FAB for admins
        if (_isAdmin)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'group_activity_fab',
              onPressed: _openCreateActivityModal,
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Activity',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActivityCard(
    Map<String, dynamic> activity,
    bool isDark, {
    bool isPast = false,
  }) {
    final title = activity['title'] as String? ?? 'Untitled';
    final venue = activity['location_name'] as String? ?? '';
    final emoji = activity['marker_emoji'] as String? ?? '📍';
    final datetime = DateTime.tryParse(activity['datetime']?.toString() ?? '');
    final visibility = activity['visibility'] as String? ?? 'public';
    final maxGuests = activity['max_guests'] as int? ?? 0;

    final dateStr = datetime != null
        ? DateFormat('EEE, MMM d · h:mm a').format(datetime.toLocal())
        : 'TBD';

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => TableCompactModal(table: activity),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isPast
              ? (isDark ? const Color(0xFF151515) : Colors.grey[100])
              : (isDark ? const Color(0xFF1A1A1A) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            // Emoji
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isPast ? Colors.grey[500] : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 13,
                        color: isPast ? Colors.grey[500] : Colors.grey[400],
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: isPast ? Colors.grey[500] : Colors.grey[400],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (venue.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            venue,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Badges
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (visibility == 'group_only')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 10,
                          color: Colors.amber[700],
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Private',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '$maxGuests spots',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateActivityModal() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CreateHangoutFlow(
              groupId: widget.groupId,
              groupName: _group?['name'] ?? 'Group',
              onTableCreated: () {
                _loadActivities();
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // ─── Invite Search Logic ────────────────────────

  void _onInviteSearchChanged(String query) {
    if (_inviteDebounce?.isActive ?? false) _inviteDebounce!.cancel();
    _inviteDebounce = Timer(const Duration(milliseconds: 400), () {
      if (query.trim().isNotEmpty) {
        _searchUsersForInvite(query.trim());
      } else {
        setState(() {
          _inviteSearchResults = [];
          _showInviteResults = false;
        });
      }
    });
  }

  Future<void> _searchUsersForInvite(String query) async {
    try {
      final cleanQuery = query.startsWith('@') ? query.substring(1) : query;
      if (cleanQuery.isEmpty) return;

      final results = await SocialService().searchUsers(cleanQuery, limit: 5);

      // Get existing member IDs to filter them out
      final memberIds = _members
          .map((m) {
            final user = m['users'] as Map<String, dynamic>?;
            return user?['id'] as String?;
          })
          .whereType<String>()
          .toSet();

      final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

      final filtered = results.where((u) {
        final uid = u['id'] as String;
        return uid != currentUserId && !memberIds.contains(uid);
      }).toList();

      if (mounted) {
        setState(() {
          _inviteSearchResults = filtered;
          _showInviteResults = filtered.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('❌ Invite search error: $e');
    }
  }

  Future<void> _handleInviteTap(Map<String, dynamic> user) async {
    final userId = user['id'] as String;
    setState(() => _isInviting = true);

    Map<String, dynamic> result;
    if (_isAdmin) {
      result = await _memberService.inviteMember(widget.groupId, userId);
    } else {
      result = await _memberService.suggestInvite(widget.groupId, userId);
    }

    if (mounted) {
      setState(() {
        _isInviting = false;
        _inviteSearchResults = [];
        _showInviteResults = false;
        _inviteController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Done'),
          backgroundColor: result['success'] == true
              ? Colors.green
              : Colors.red,
        ),
      );

      if (result['success'] == true && _isAdmin) {
        await _loadMembers();
      }
    }
  }

  // ─── Members Tab ───────────────────────────────

  Widget _buildMembersTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadMembers();
        if (_isAdmin) await _loadPendingRequests();
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── Invite People Section (members can see) ───
          if (_isMember) ...[
            _sectionHeader(
              _isAdmin ? 'Invite People' : 'Suggest an Invite',
              primaryColor,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inviteController,
              onChanged: _onInviteSearchChanged,
              decoration: InputDecoration(
                hintText: '@username',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                prefixIcon: Icon(
                  Icons.alternate_email,
                  color: primaryColor.withOpacity(0.6),
                  size: 20,
                ),
                filled: true,
                fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
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

            // Search Results
            if (_showInviteResults && _inviteSearchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: _inviteSearchResults.map((user) {
                    final displayName = user['display_name'] ?? 'User';
                    final username = user['username'] ?? '';
                    final avatarUrl = user['avatar_url'] as String?;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: isDark
                            ? Colors.grey[800]
                            : Colors.grey[200],
                        backgroundImage: avatarUrl != null
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null
                            ? Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[600],
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: username.isNotEmpty
                          ? Text(
                              '@$username',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            )
                          : null,
                      trailing: _isInviting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _isAdmin
                                    ? primaryColor.withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _isAdmin ? 'Invite' : 'Suggest',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _isAdmin
                                      ? primaryColor
                                      : Colors.orange[700],
                                ),
                              ),
                            ),
                      onTap: _isInviting ? null : () => _handleInviteTap(user),
                    );
                  }).toList(),
                ),
              ),

            if (!_isAdmin)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Your suggestion will be sent to group admins',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            Divider(
              height: 28,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
            ),
          ],

          // Pending requests section (admin only)
          if (_isAdmin && _pendingRequests.isNotEmpty) ...[
            _sectionHeader(
              'Pending Requests',
              Colors.orange[600]!,
              count: _pendingRequests.length,
            ),
            const SizedBox(height: 10),
            ..._pendingRequests.map(
              (req) => _buildMemberTile(req, isPending: true),
            ),
            Divider(
              height: 32,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
            ),
          ],

          // Members
          _sectionHeader(
            'Members',
            Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
            count: _members.length,
          ),
          const SizedBox(height: 10),
          ..._members.map((m) => _buildMemberTile(m)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, Color color, {int? count}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color.withOpacity(0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMemberTile(
    Map<String, dynamic> member, {
    bool isPending = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = member['users'] as Map<String, dynamic>? ?? {};
    final displayName = user['display_name'] ?? 'Unknown';
    final photos = user['user_photos'] as List? ?? [];
    final primaryPhoto = photos.isNotEmpty
        ? (photos.firstWhere(
                (p) => p['is_primary'] == true,
                orElse: () => photos.first,
              )['photo_url']
              as String?)
        : null;
    final role = member['role'] as String? ?? 'member';
    final joinedAt = member['joined_at'] != null
        ? DateFormat('MMM d, yyyy').format(DateTime.parse(member['joined_at']))
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPending
            ? Colors.orange.withOpacity(isDark ? 0.08 : 0.04)
            : (isDark ? const Color(0xFF1A1A1A) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending
              ? Colors.orange.withOpacity(0.2)
              : (isDark ? Colors.grey[850]! : Colors.grey[200]!),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
            backgroundImage: primaryPhoto != null
                ? NetworkImage(primaryPhoto)
                : null,
            child: primaryPhoto == null
                ? Text(
                    displayName[0].toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          // Name & Role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (role == 'owner' || role == 'admin') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: role == 'owner'
                              ? Colors.amber.withOpacity(0.12)
                              : Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          role == 'owner' ? '👑 Owner' : '⭐ Admin',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: role == 'owner'
                                ? Colors.amber[700]
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (joinedAt != null && !isPending)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Joined $joinedAt',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
              ],
            ),
          ),
          // Admin actions
          if (isPending && _isAdmin) ...[
            _miniActionButton(
              icon: Icons.check_circle,
              color: Colors.green,
              onTap: () async {
                await _memberService.approveRequest(widget.groupId, user['id']);
                await _loadAll();
              },
            ),
            const SizedBox(width: 4),
            _miniActionButton(
              icon: Icons.cancel,
              color: Colors.red[400]!,
              onTap: () async {
                await _memberService.rejectRequest(widget.groupId, user['id']);
                await _loadAll();
              },
            ),
          ] else if (!isPending &&
              _isAdmin &&
              user['id'] != _currentUserId &&
              role != 'owner') ...[
            PopupMenuButton<String>(
              iconSize: 18,
              icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey[500]),
              onSelected: (v) => _handleMemberAction(v, user['id'], role),
              itemBuilder: (_) => [
                if (role == 'member')
                  const PopupMenuItem(
                    value: 'promote',
                    child: Text('Promote to Admin'),
                  ),
                if (role == 'admin')
                  const PopupMenuItem(
                    value: 'demote',
                    child: Text('Demote to Member'),
                  ),
                const PopupMenuItem(
                  value: 'kick',
                  child: Text('Remove', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 26),
      ),
    );
  }

  Future<void> _handleMemberAction(
    String action,
    String userId,
    String currentRole,
  ) async {
    Map<String, dynamic>? result;
    switch (action) {
      case 'promote':
        result = await _memberService.updateRole(
          widget.groupId,
          userId,
          'admin',
        );
        break;
      case 'demote':
        result = await _memberService.updateRole(
          widget.groupId,
          userId,
          'member',
        );
        break;
      case 'kick':
        result = await _memberService.removeMember(widget.groupId, userId);
        break;
    }
    if (result != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Done')));
      await _loadAll();
    }
  }

  // ─── About Tab ─────────────────────────────────

  Widget _buildAboutTab() {
    final group = _group!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final description = group['description'] as String?;
    final rules = group['rules'] as String?;
    final createdAt = group['created_at'] != null
        ? DateFormat('MMMM d, yyyy').format(DateTime.parse(group['created_at']))
        : 'Unknown';
    final creator = group['creator'] as Map<String, dynamic>? ?? {};
    final creatorName = creator['display_name'] ?? 'Unknown';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Description
        if (description != null && description.isNotEmpty) ...[
          _sectionLabel('Description'),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[700],
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
        ],

        // Rules
        if (rules != null && rules.isNotEmpty) ...[
          _sectionLabel('Group Rules'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(isDark ? 0.06 : 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: Colors.amber[600]!, width: 3),
              ),
            ),
            child: Text(
              rules,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[700],
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],

        // Info
        _sectionLabel('Info'),
        const SizedBox(height: 12),
        _infoRow(Icons.calendar_today_outlined, 'Created', createdAt),
        _infoRow(Icons.person_outline, 'Created by', creatorName),
        _infoRow(
          Icons.category_outlined,
          'Category',
          _getCategoryLabel(group['category']?.toString() ?? 'other'),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: Colors.grey[500],
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Text(
            '$label',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Widget _pill({required String text, String? emoji, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null && emoji.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(emoji, style: const TextStyle(fontSize: 12)),
            )
          else if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(icon, size: 12, color: Colors.white70),
            ),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultCoverGradient(Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withOpacity(0.7),
            primaryColor.withOpacity(0.3),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.groups,
          size: 64,
          color: Colors.white.withOpacity(0.2),
        ),
      ),
    );
  }

  void _showOwnerMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Group'),
              onTap: () async {
                Navigator.pop(ctx);
                final didUpdate = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditGroupScreen(group: _group!),
                  ),
                );
                if (didUpdate == true) await _loadAll();
              },
            ),
            if (_isOwner)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red[400]),
                title: Text(
                  'Delete Group',
                  style: TextStyle(color: Colors.red[400]),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteGroup();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _getCategoryLabel(String cat) {
    const labels = {
      'food': 'Food',
      'nightlife': 'Nightlife',
      'travel': 'Travel',
      'fitness': 'Fitness',
      'outdoors': 'Outdoors',
      'gaming': 'Gaming',
      'arts': 'Arts',
      'music': 'Music',
      'professional': 'Professional',
      'other': 'General',
    };
    return labels[cat] ?? 'General';
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'food':
        return Icons.restaurant;
      case 'nightlife':
        return Icons.nightlife;
      case 'travel':
        return Icons.flight;
      case 'fitness':
        return Icons.fitness_center;
      case 'outdoors':
        return Icons.terrain;
      case 'gaming':
        return Icons.sports_esports;
      case 'arts':
        return Icons.palette;
      case 'music':
        return Icons.music_note;
      case 'professional':
        return Icons.work_outline;
      default:
        return Icons.groups;
    }
  }

  IconData _privacyIcon(String privacy) {
    switch (privacy) {
      case 'public':
        return Icons.public;
      case 'private':
        return Icons.lock_outline;
      case 'hidden':
        return Icons.visibility_off;
      default:
        return Icons.public;
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
          'This will permanently delete the group and all its data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _groupService.deleteGroup(widget.groupId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? 'Group deleted'
                : result['message'] ?? 'Error',
          ),
        ),
      );
      if (result['success'] == true) Navigator.pop(context);
    }
  }
}

// ─── Sliver Delegate ─────────────────────────────

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _SliverTabBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) => false;
}
