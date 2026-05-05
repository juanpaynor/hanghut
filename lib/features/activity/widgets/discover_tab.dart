import 'package:flutter/material.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:bitemates/features/home/widgets/trending_carousel.dart';
import 'package:bitemates/features/home/widgets/open_hangout_card.dart';
import 'package:bitemates/features/home/screens/discover_list_screen.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:geolocator/geolocator.dart';

class DiscoverTab extends StatefulWidget {
  const DiscoverTab({super.key});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab>
    with AutomaticKeepAliveClientMixin {
  final TableService _tableService = TableService();

  List<Map<String, dynamic>> _hangouts = [];
  List<Map<String, dynamic>> _experiences = [];
  List<Event> _events = [];
  bool _isLoading = true;
  Position? _userPosition;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final position = await LocationService().getCurrentLocation();
      if (mounted) setState(() => _userPosition = position);
    } catch (_) {}

    await Future.wait([_loadHangouts(), _loadExperiences(), _loadEvents()]);

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadHangouts() async {
    try {
      final tables = await _tableService.getMapReadyTables(
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
        limit: 10,
      );
      final filtered = tables
          .where(
            (t) => t['visibility'] != 'mystery' && t['is_experience'] != true,
          )
          .toList();
      final enriched = await _tableService.enrichTablesWithMembers(filtered);
      if (mounted) setState(() => _hangouts = enriched);
    } catch (e) {
      print('❌ DiscoverTab: error loading hangouts: $e');
    }
  }

  Future<void> _loadExperiences() async {
    try {
      final experiences = await _tableService.getExperiences(
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
        limit: 10,
      );
      if (mounted) setState(() => _experiences = experiences);
    } catch (e) {
      print('❌ DiscoverTab: error loading experiences: $e');
    }
  }

  Future<void> _loadEvents() async {
    try {
      final events = await EventService().getUpcomingEvents(limit: 10);
      if (mounted) setState(() => _events = events);
    } catch (e) {
      print('❌ DiscoverTab: error loading events: $e');
    }
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See All',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6C63FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool hasContent =
        _events.isNotEmpty || _experiences.isNotEmpty || _hangouts.isNotEmpty;

    if (!hasContent) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Nothing nearby right now',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Refresh')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Events & Experiences
          if (_events.isNotEmpty || _experiences.isNotEmpty) ...[
            _buildSectionHeader(
              'Events & Experiences',
              onSeeAll: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DiscoverListScreen(
                      items: [..._experiences, ..._events],
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TrendingCarousel(
                items: [..._experiences, ..._events],
                onItemTap: (item) {
                  if (item is Event) {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => EventDetailModal(event: item),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ExperienceDetailModal(
                          experience: item,
                          matchData: const {},
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ],

          // Open Hangouts
          if (_hangouts.isNotEmpty) ...[
            _buildSectionHeader('Open Hangouts'),
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                itemCount: _hangouts.length,
                itemBuilder: (context, index) {
                  final table = _hangouts[index];
                  return OpenHangoutCard(
                    table: table,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TableCompactModal(
                            table: table,
                            matchData: const {},
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
