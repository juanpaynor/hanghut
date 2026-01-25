import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/table_member_service.dart';
import 'package:intl/intl.dart';

class MyHangoutsList extends StatefulWidget {
  const MyHangoutsList({super.key});

  @override
  State<MyHangoutsList> createState() => _MyHangoutsListState();
}

class _MyHangoutsListState extends State<MyHangoutsList> {
  List<Map<String, dynamic>> _myTables = [];
  bool _isLoading = true;
  String _filter = 'upcoming'; // 'upcoming', 'past', 'all'
  final _tableService = TableService();
  final _memberService = TableMemberService();

  @override
  void initState() {
    super.initState();
    _loadMyTables();
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

  Future<void> _leaveTable(String tableId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Hangout?'),
        content: const Text('Are you sure you want to leave this event?'),
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
                    onRefresh: _loadMyTables,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No hangouts found',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_filter == 'upcoming')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Join a table to get started!',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
        ],
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
