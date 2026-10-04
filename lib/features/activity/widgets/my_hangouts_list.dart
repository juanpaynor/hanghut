import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:bitemates/features/activity/widgets/hangout_invites_section.dart';
import 'package:bitemates/features/activity/widgets/hangout_nudge_card.dart';
import 'package:bitemates/features/activity/models/hangout_nudge.dart';
import 'package:bitemates/core/services/hangout_nudge_service.dart';
import 'package:bitemates/core/services/analytics_service.dart';
import 'package:bitemates/features/map/widgets/create_hangout/create_hangout_flow.dart';
import 'package:intl/intl.dart';

class MyHangoutsList extends StatefulWidget {
  const MyHangoutsList({super.key});

  @override
  State<MyHangoutsList> createState() => _MyHangoutsListState();
}

class _MyHangoutsListState extends State<MyHangoutsList> {
  /// Lets an accepted invite reload the joined list underneath it — accepting
  /// moves a hangout from the invites section into this list, and without a
  /// handle on each the user would see it vanish from one and not appear in
  /// the other until they pulled to refresh.
  final _invitesKey = GlobalKey<HangoutInvitesSectionState>();

  List<Map<String, dynamic>> _myTables = [];
  bool _isLoading = true;
  String _filter = 'upcoming'; // 'upcoming', 'past', 'all'
  final _tableService = TableService();
  final _memberService = TableMemberService();

  /// Null for users the nudge RPC has nothing to say about, including anyone
  /// who already has an upcoming hangout — who by definition is not looking
  /// at this empty state anyway.
  HangoutNudge? _nudge;

  @override
  void initState() {
    super.initState();
    _loadMyTables();
    _loadNudge();
  }

  /// Cheap here: the service caches for the process lifetime, so mounting the
  /// card on a second surface costs no extra round trip.
  Future<void> _loadNudge() async {
    final nudge = await HangoutNudgeService().fetch();
    if (mounted && nudge != null) setState(() => _nudge = nudge);
  }

  Future<void> _loadMyTables() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Fetch joined tables from table_members
      final response = await SupabaseConfig.client
          .from('table_members')
          .select('*, tables(*)')
          .eq('user_id', user.id)
          .inFilter('status', ['approved', 'joined', 'attended'])
          .order('joined_at', ascending: false);

      final List<Map<String, dynamic>> tables = [];
      for (var row in response) {
        if (row['tables'] != null) {
          final tableData = Map<String, dynamic>.from(row['tables']);
          // Merge member role into table data for easy access
          tableData['my_role'] = row['role'];
          tables.add(tableData);
        }
      }

      // Sort by datetime
      tables.sort((a, b) {
        final dateA = DateTime.parse(a['datetime']);
        final dateB = DateTime.parse(b['datetime']);
        return dateA.compareTo(dateB);
      });

      if (mounted) {
        setState(() {
          _myTables = tables;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ MY HANGOUTS: Error loading tables - $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadMyTables(),
      _invitesKey.currentState?.reload() ?? Future.value(),
      _reloadNudge(),
    ]);
  }

  /// A deliberate pull asks for current numbers, so it bypasses the cache.
  Future<void> _reloadNudge() async {
    final nudge = await HangoutNudgeService().fetch(force: true);
    if (mounted) setState(() => _nudge = nudge);
  }

  Future<void> _leaveTable(String tableId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Hangout?'),
        content: const Text('Are you sure you want to leave this hangout?'),
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

    if (confirmed == true) {
      setState(() => _isLoading = true);
      await _memberService.leaveTable(tableId);
      _loadMyTables(); // Reload
    }
  }

  Future<void> _deleteTable(String tableId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Hangout?'),
        content: const Text(
          'Are you sure? This will cancel the event for all members. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Event'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      await _tableService.deleteTable(tableId);
      _loadMyTables(); // Reload
    }
  }

  List<Map<String, dynamic>> get _filteredTables {
    final now = DateTime.now();
    switch (_filter) {
      case 'upcoming':
        return _myTables.where((table) {
          final date = DateTime.parse(table['datetime']);
          return date.isAfter(now) || date.isAtSameMomentAs(now);
        }).toList();
      case 'past':
        return _myTables.where((table) {
          final date = DateTime.parse(table['datetime']);
          return date.isBefore(now);
        }).toList();
      default:
        return _myTables;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Invites first: an unanswered invite is the only thing on this
          // screen that needs a decision, and it renders nothing at all when
          // there are none.
          HangoutInvitesSection(
            key: _invitesKey,
            onChanged: _loadMyTables,
          ),

          // Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                _buildFilterChip('Upcoming', 'upcoming'),
                const SizedBox(width: 8),
                _buildFilterChip('Past', 'past'),
                const SizedBox(width: 8),
                _buildFilterChip('All', 'all'),
              ],
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).primaryColor,
                    ),
                  )
                : _filteredTables.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _refreshAll,
                    color: Theme.of(context).primaryColor,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _filteredTables.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        return _buildHangoutCard(_filteredTables[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// The empty state is the common case — there are 5 live hangouts in the whole
  /// app — so it has to be the ask, not a dead end. It used to read "No hangouts
  /// found" with no action, while the sibling Hangouts tab already offered
  /// "Start a hangout". Same offer here.
  ///
  /// Past/All get no CTA: an empty history is a statement of fact, not an
  /// invitation, and prompting there would read as nagging.
  Widget _buildEmptyState() {
    final upcoming = _filter == 'upcoming';
    final primary = Theme.of(context).primaryColor;
    final nudge = _nudge;

    // When we can name a real pool of nearby people, that beats a generic
    // ask. "22 people near you are into Nightlife" gives the user a reason;
    // "Start one and see who's around" only gives them a button.
    if (upcoming && nudge != null) {
      return Center(
        child: HangoutNudgeCard(
          nudge: nudge,
          onStart: _startHangout,
          compact: true,
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icons.event_busy is in release 11305a4 (it was already here).
            Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              upcoming ? 'Nothing lined up yet' : 'No hangouts found',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (upcoming) ...[
              const SizedBox(height: 8),
              Text(
                "Start one and see who's around — or join someone else's "
                'from the Hangouts tab.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], height: 1.4),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _startHangout,
                // Icons.add is in release 11305a4.
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Start a hangout'),
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _startHangout() {
    // Same source-tagged entry as the Hangouts tab, so the funnel can tell
    // which empty state actually produces hangouts — and whether the nudge
    // variant beats the plain one.
    final nudge = _nudge;
    final source =
        nudge != null ? 'nudge_my_hangouts' : 'empty_state_my_hangouts';
    AnalyticsService().logHangoutCreateStart(source);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateHangoutFlow(
          source: source,
          initialCategory: nudge?.interestKey,
          onTableCreated: () {
            HangoutNudgeService.invalidate();
            if (mounted) _refreshAll();
          },
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    final primaryColor = Theme.of(context).primaryColor;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildHangoutCard(Map<String, dynamic> table) {
    final date = DateTime.parse(table['datetime']);
    final isHost = table['my_role'] == 'host';
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title + Role Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  table['marker_emoji'] ?? '🍽️',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      table['title'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat('EEE, MMM d • h:mm a').format(date),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isHost
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isHost ? 'HOST' : 'GUEST',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isHost ? Colors.orange : Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Location
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.grey[400]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  table['location_name'] ?? 'Unknown Location',
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // View Chat / Details Button (Placeholder for navigation)
              // Expanded(
              //     child: OutlinedButton(
              //         onPressed: () {
              //             // Navigate to Table/Chat
              //         },
              //         child: const Text('View Details'),
              //     ),
              // ),
              // const SizedBox(width: 12),

              // Leave / Delete Button
              if (isHost)
                TextButton.icon(
                  onPressed: () => _deleteTable(table['id']),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Delete Event',
                    style: TextStyle(color: Colors.red),
                  ),
                )
              else
                TextButton.icon(
                  onPressed: () => _leaveTable(table['id']),
                  icon: const Icon(
                    Icons.exit_to_app,
                    size: 18,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Leave',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
