import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';

import 'package:bitemates/features/trips/widgets/add_trip_modal.dart';
import 'package:bitemates/features/trips/screens/trip_details_screen.dart';
import 'package:intl/intl.dart';

class MyTablesScreen extends StatefulWidget {
  const MyTablesScreen({super.key});

  @override
  State<MyTablesScreen> createState() => _MyTablesScreenState();
}

class _MyTablesScreenState extends State<MyTablesScreen> {
  // List<Map<String, dynamic>> _myTables = []; // Removed tables
  List<Map<String, dynamic>> _myTrips = [];
  bool _isLoading = true;
  // String? _currentUserId; // Unused if mostly trips
  String _filter = 'upcoming'; // 'upcoming', 'past', 'all'
  // late TabController _tabController; // Removed

  @override
  void initState() {
    super.initState();
    // _tabController = TabController(length: 2, vsync: this); // Removed
    // _tabController.addListener(_handleTabSelection); // Removed
    // _loadMyTables(); // Removed
    _loadMyTrips();
  }

  // void _handleTabSelection() { ... } // Removed

  @override
  void dispose() {
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
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ MY TRIPS: Error loading trips - $e');
      if (mounted) setState(() => _isLoading = false);
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'trips_fab',
        onPressed: _showAddTripModal,
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
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
                    'My Trips',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFF333333)),
                    onPressed: _loadMyTrips,
                  ),
                ],
              ),
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

            // Trip content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).primaryColor,
                      ),
                    )
                  : _filteredTrips.isEmpty
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
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMyTrips,
                      color: Theme.of(context).primaryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _filteredTrips.length,
                        itemBuilder: (context, index) {
                          final trip = _filteredTrips[index];
                          return _buildTripCard(trip);
                        },
                      ),
                    ),
            ),
          ],
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
          color: isSelected ? primaryColor : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
    final primaryColor = Theme.of(context).primaryColor;

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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TripDetailsScreen(trip: trip),
              ),
            );
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
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.flight_takeoff,
                        color: primaryColor,
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
                              color: Color(0xFF333333),
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
                          color: primaryColor,
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
                            color: Colors.white,
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
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people, size: 14, color: primaryColor),
                            const SizedBox(width: 4),
                            Text(
                              'View Matches',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primaryColor,
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
