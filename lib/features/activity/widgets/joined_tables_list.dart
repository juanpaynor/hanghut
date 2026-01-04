import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:intl/intl.dart';

class JoinedTablesList extends StatefulWidget {
  const JoinedTablesList({super.key});

  @override
  State<JoinedTablesList> createState() => _JoinedTablesListState();
}

class _JoinedTablesListState extends State<JoinedTablesList> {
  List<Map<String, dynamic>> _myTables = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyTables();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload tables whenever this widget is shown (e.g., when modal reopens)
    if (mounted) {
      _loadMyTables();
    }
  }

  Future<void> _loadMyTables() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    try {
      // Fetch tables where the user is a member (or host)
      // We use !inner join to filter tables by the existence of a table_member record for this user
      // 1. Fetch tables where user is a participant
      final joinedFuture = SupabaseConfig.client
          .from('tables')
          .select('''
            *,
            table_members!inner(user_id, status)
          ''')
          .eq('table_members.user_id', user.id)
          .inFilter('table_members.status', ['approved', 'joined', 'attended']);

      // Execute
      final results = await Future.wait([joinedFuture]);
      final joinedTables = listFrom(results[0]);

      // 3. Deduplicate (by ID)
      final Map<String, Map<String, dynamic>> tableMap = {};

      for (var t in joinedTables) {
        tableMap[t['id']] = t;
      }

      final allTables = tableMap.values.toList();

      // 4. Sort by datetime
      allTables.sort((a, b) {
        final dateA = DateTime.parse(a['datetime']);
        final dateB = DateTime.parse(b['datetime']);
        return dateA.compareTo(dateB);
      });

      if (mounted) {
        setState(() {
          _myTables = allTables;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ MY TABLES: Error loading tables - $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> listFrom(dynamic response) {
    if (response == null) return [];
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardTheme.color ?? Colors.white,
      child: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor,
              ),
            )
          : _myTables.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.table_restaurant,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No joined tables yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join a hangout from the map or feed!',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadMyTables,
              color: Theme.of(context).primaryColor,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _myTables.length,
                itemBuilder: (context, index) {
                  final table = _myTables[index];
                  return _buildTableCard(table);
                },
              ),
            ),
    );
  }

  Widget _buildTableCard(Map<String, dynamic> table) {
    final date = DateTime.parse(table['datetime']);
    // Removed unused time variable
    final activity = table['cuisine_type'] ?? 'Hangout';
    final title = table['title'] ?? 'Untitled';
    final location = table['location_name'] ?? 'Unknown Location';

    return GestureDetector(
      onTap: () async {
        // Open Chat Directly
        final result = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          enableDrag: true,
          builder: (context) => ChatScreen(
            channelId: 'table_${table['id']}',
            tableId: table['id'],
            tableTitle: title,
          ),
        );

        if (result == true) {
          _loadMyTables();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getActivityIcon(activity),
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$location • ${DateFormat('EEE, h:mm a').format(date)}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // Status Arrow
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getActivityIcon(String type) {
    switch (type.toLowerCase()) {
      case 'coffee':
        return Icons.coffee;
      case 'food':
        return Icons.restaurant;
      case 'drinks':
        return Icons.local_bar;
      case 'study':
        return Icons.book;
      case 'game':
        return Icons.sports_esports;
      default:
        return Icons.people;
    }
  }
}
