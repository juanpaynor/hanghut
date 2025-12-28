import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/trips/widgets/add_trip_modal.dart';
import 'package:intl/intl.dart';

class MyTablesScreen extends StatefulWidget {
  const MyTablesScreen({super.key});

  @override
  State<MyTablesScreen> createState() => _MyTablesScreenState();
}

class _MyTablesScreenState extends State<MyTablesScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _myTables = [];
  List<Map<String, dynamic>> _myTrips = [];
  bool _isLoading = true;
  String? _currentUserId;
  String _filter = 'upcoming'; // 'upcoming', 'past', 'all'
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMyTables();
    _loadMyTrips();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyTrips() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await SupabaseConfig.client
          .from('user_trips')
          .select()
          .eq('user_id', user.id)
          .order('start_date', ascending: true);

      if (mounted) {
        setState(() {
          _myTrips = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('❌ MY TRIPS: Error loading trips - $e');
    }
  }

  void _showAddTripModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddTripModal(
        onTripCreated: () {
          _loadMyTrips();
        },
      ),
    );
  }

  Future<void> _loadMyTables() async {
    setState(() => _isLoading = true);

    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    _currentUserId = user.id;

    try {
      final response = await SupabaseConfig.client
          .from('table_participants')
          .select('''
            status,
            joined_at,
            tables!inner(
              id,
              title,
              location_name,
              datetime,
              latitude,
              longitude,
              max_guests,
              host_id
            )
          ''')
          .eq('user_id', _currentUserId!);

      if (mounted) {
        setState(() {
          _myTables = List<Map<String, dynamic>>.from(response).map((item) {
            final table = item['tables'];
            return {
              'id': table['id'],
              'title': table['title'],
              'restaurantName': table['location_name'],
              'scheduledTime': table['datetime'],
              'locationLat': table['latitude'],
              'locationLng': table['longitude'],
              'maxParticipants': table['max_guests'],
              'hostId': table['host_id'],
              'ablyChannelId': table['ably_channel_id'],
              'status': item['status'],
              'joinedAt': item['joined_at'],
              'isHost': table['host_id'] == _currentUserId,
            };
          }).toList();
          _isLoading = false;
        });

        // Load participant counts for each table
        _loadParticipantCounts();
      }
    } catch (e) {
      print('❌ MY TABLES: Error loading tables - $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadParticipantCounts() async {
    for (var table in _myTables) {
      try {
        final count = await SupabaseConfig.client
            .from('table_participants')
            .select('user_id')
            .eq('table_id', table['id'])
            .eq('status', 'confirmed')
            .count();

        if (mounted) {
          setState(() {
            table['participantCount'] = count.count;
          });
        }
      } catch (e) {
        print('❌ Error loading participant count for ${table['id']}: $e');
      }
    }
  }

  List<Map<String, dynamic>> get _filteredTables {
    final now = DateTime.now();

    switch (_filter) {
      case 'upcoming':
        return _myTables.where((table) {
          final scheduledTime = DateTime.parse(table['scheduledTime']);
          return scheduledTime.isAfter(now);
        }).toList();
      case 'past':
        return _myTables.where((table) {
          final scheduledTime = DateTime.parse(table['scheduledTime']);
          return scheduledTime.isBefore(now);
        }).toList();
      default:
        return _myTables;
    }
  }

  void _openChat(Map<String, dynamic> table) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          tableId: table['id'],
          tableTitle: table['title'],
          channelId: table['ablyChannelId'],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredTrips {
    final now = DateTime.now();

    switch (_filter) {
      case 'upcoming':
        return _myTrips.where((trip) {
          final startDate = DateTime.parse(trip['start_date']);
          return startDate.isAfter(now) || trip['status'] == 'upcoming';
        }).toList();
      case 'past':
        return _myTrips.where((trip) {
          final endDate = DateTime.parse(trip['end_date']);
          return endDate.isBefore(now) || trip['status'] == 'completed';
        }).toList();
      default:
        return _myTrips;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tabController.index == 1 ? _showAddTripModal : null,
        backgroundColor: const Color(0xFF00FFD1),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Trip'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Text(
                    'My Activity',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.black),
                    onPressed: () {
                      _loadMyTables();
                      _loadMyTrips();
                    },
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.black45,
              indicatorColor: const Color(0xFF00FFD1),
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'Tables'),
                Tab(text: 'Trips'),
              ],
            ),

            // Filter tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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

            const SizedBox(height: 16),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tables tab
                  _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00FFD1),
                          ),
                        )
                      : _filteredTables.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _filter == 'upcoming'
                                    ? Icons.event_available
                                    : Icons.history,
                                size: 64,
                                color: Colors.black12,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _filter == 'upcoming'
                                    ? 'No upcoming tables'
                                    : 'No past tables',
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.black38,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Join a table from the map!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black26,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadMyTables,
                          color: const Color(0xFF00FFD1),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _filteredTables.length,
                            itemBuilder: (context, index) {
                              final table = _filteredTables[index];
                              return _buildTableCard(table);
                            },
                          ),
                        ),

                  // Trips tab
                  _filteredTrips.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.flight_takeoff,
                                size: 64,
                                color: Colors.black12,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No trips yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.black38,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Plan your next adventure!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black26,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _showAddTripModal,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Trip'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00FFD1),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadMyTrips,
                          color: const Color(0xFF00FFD1),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _filteredTrips.length,
                            itemBuilder: (context, index) {
                              final trip = _filteredTrips[index];
                              return _buildTripCard(trip);
                            },
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00FFD1)
              : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.black54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTableCard(Map<String, dynamic> table) {
    final scheduledTime = DateTime.parse(table['scheduledTime']);
    final isPast = scheduledTime.isBefore(DateTime.now());
    final participantCount = table['participantCount'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openChat(table),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  table['title'],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (table['isHost']) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00FFD1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'HOST',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            table['restaurantName'],
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isPast ? Icons.check_circle : Icons.access_time,
                      color: isPast
                          ? Colors.green.withOpacity(0.6)
                          : const Color(0xFF00FFD1),
                      size: 24,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.black.withOpacity(0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('MMM d, yyyy · h:mm a').format(scheduledTime),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.people,
                      size: 14,
                      color: Colors.black.withOpacity(0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$participantCount / ${table['maxParticipants']} joined',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FFD1).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble,
                            size: 14,
                            color: Colors.black87,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Open Chat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final startDate = DateTime.parse(trip['start_date']);
    final endDate = DateTime.parse(trip['end_date']);
    final now = DateTime.now();
    final isPast = endDate.isBefore(now);
    final isActive = startDate.isBefore(now) && endDate.isAfter(now);
    final daysUntil = startDate.difference(now).inDays;
    final duration = endDate.difference(startDate).inDays + 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // TODO: Navigate to trip detail screen
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FFD1).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.flight_takeoff,
                        color: Color(0xFF00FFD1),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip['destination_city'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            trip['destination_country'],
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else if (isPast)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 24,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FFD1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          daysUntil == 0
                              ? 'TODAY'
                              : daysUntil == 1
                              ? 'TOMORROW'
                              : '$daysUntil DAYS',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.black.withOpacity(0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)} ($duration days)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                if (trip['interests'] != null &&
                    (trip['interests'] as List).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: (trip['interests'] as List)
                        .take(3)
                        .map(
                          (interest) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              interest.toString().replaceAll('_', ' '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FFD1).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people, size: 14, color: Colors.black87),
                            SizedBox(width: 4),
                            Text(
                              'View Matches',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
