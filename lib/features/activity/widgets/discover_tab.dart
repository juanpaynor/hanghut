import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:bitemates/features/home/widgets/open_hangout_card.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:geolocator/geolocator.dart';

class DiscoverTab extends StatefulWidget {
  final void Function(String tableId)? onHangoutTap;
  const DiscoverTab({super.key, this.onHangoutTap});

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

  // Filters
  String _sectionFilter = 'All'; // 'All' | 'Activities' | 'Hangouts'
  final Set<String> _vibeFilters = {};

  static const List<Map<String, String>> _vibes = [
    {'label': 'Chill 😌', 'key': 'chill'},
    {'label': 'Foodie 🍜', 'key': 'food'},
    {'label': 'Active 🏃', 'key': 'sports'},
    {'label': 'Social 🗣️', 'key': 'social'},
    {'label': 'Late Night 🌙', 'key': 'nightlife'},
    {'label': 'Coffee ☕', 'key': 'coffee'},
    {'label': 'Outdoors 🌿', 'key': 'outdoor'},
  ];

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

  List<Map<String, dynamic>> get _filteredHangouts {
    if (_vibeFilters.isEmpty) return _hangouts;
    return _hangouts.where((t) {
      final type = (t['activity_type'] as String? ?? '').toLowerCase();
      return _vibeFilters.any((v) => type.contains(v));
    }).toList();
  }

  Widget _buildActivitiesGrid() {
    final items = <dynamic>[..._experiences, ..._events];
    // Split into two columns, alternating tall/short for a staggered feel
    final left = <dynamic>[];
    final right = <dynamic>[];
    for (var i = 0; i < items.length; i++) {
      if (i.isEven) {
        left.add(items[i]);
      } else {
        right.add(items[i]);
      }
    }

    void onTap(dynamic item) {
      if (item is Event) {
        EventDetailModal.show(context, item);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ExperienceDetailModal(experience: item, matchData: const {}),
          ),
        );
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < left.length; i++)
                _ActivityTile(
                  item: left[i],
                  tall: i.isEven,
                  onTap: () => onTap(left[i]),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              // Offset the right column with a small spacer for stagger
              const SizedBox(height: 32),
              for (var i = 0; i < right.length; i++)
                _ActivityTile(
                  item: right[i],
                  tall: i.isOdd,
                  onTap: () => onTap(right[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section chips
        SizedBox(
          height: 40,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: ['All', 'Activities', 'Hangouts'].map((s) {
              final selected = _sectionFilter == s;
              return GestureDetector(
                onTap: () => setState(() {
                  _sectionFilter = s;
                  if (s != 'Hangouts') _vibeFilters.clear();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF6C63FF)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    s,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Vibe chips (Hangouts only)
        if (_sectionFilter == 'Hangouts') ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: _vibes.map((v) {
                final selected = _vibeFilters.contains(v['key']);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (selected) {
                      _vibeFilters.remove(v['key']);
                    } else {
                      _vibeFilters.add(v['key']!);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF6C63FF).withOpacity(0.15)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF6C63FF)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      v['label']!,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF6C63FF)
                            : Colors.black87,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
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
          const SizedBox(height: 12),
          _buildFilterRow(),

          // Activities grid
          if ((_sectionFilter == 'All' || _sectionFilter == 'Activities') &&
              (_events.isNotEmpty || _experiences.isNotEmpty)) ...[
            _buildSectionHeader('Activities'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildActivitiesGrid(),
            ),
            const SizedBox(height: 8),
          ],

          // Hangouts
          if ((_sectionFilter == 'All' || _sectionFilter == 'Hangouts') &&
              _hangouts.isNotEmpty) ...[
            _buildSectionHeader('Hangouts'),
            if (_filteredHangouts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 40,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No hangouts match your vibe.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _filteredHangouts.length,
                  itemBuilder: (context, index) {
                    final table = _filteredHangouts[index];
                    return OpenHangoutCard(
                      table: table,
                      onTap: () {
                        final id = table['id']?.toString();
                        if (id != null && widget.onHangoutTap != null) {
                          widget.onHangoutTap!(id);
                        } else {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => TableCompactModal(
                              table: table,
                              matchData: const {},
                            ),
                          );
                        }
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

class _ActivityTile extends StatefulWidget {
  final dynamic item;
  final bool tall;
  final VoidCallback onTap;

  const _ActivityTile({
    required this.item,
    required this.tall,
    required this.onTap,
  });

  @override
  State<_ActivityTile> createState() => _ActivityTileState();
}

class _ActivityTileState extends State<_ActivityTile> {
  double _scale = 1.0;

  String get _title {
    if (widget.item is Event) return (widget.item as Event).title;
    if (widget.item is Map) return widget.item['title'] ?? '';
    return '';
  }

  String? get _imageUrl {
    if (widget.item is Event) return (widget.item as Event).coverImageUrl;
    if (widget.item is Map) {
      String? img = widget.item['marker_image_url'] ?? widget.item['image_url'];
      if (img == null &&
          widget.item['images'] != null &&
          (widget.item['images'] as List).isNotEmpty) {
        img = (widget.item['images'] as List).first as String?;
      }
      return img;
    }
    return null;
  }

  String get _badge {
    if (widget.item is Event) return 'EVENT';
    if (widget.item is Map) {
      if (widget.item['is_experience'] == true) {
        final t = widget.item['experience_type'] as String?;
        return t?.replaceAll('_', ' ').toUpperCase() ?? 'EXPERIENCE';
      }
      final t = widget.item['cuisine_type'] as String?;
      if (t != null && t.toLowerCase() != 'other') return t.toUpperCase();
    }
    return 'ACTIVITY';
  }

  Color get _badgeColor {
    switch (_badge) {
      case 'EVENT':
        return const Color(0xFF6C63FF);
      case 'EXPERIENCE':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFF43B89C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.tall ? 200.0 : 150.0;
    final imgUrl = _imageUrl;

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.grey[200],
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background image
              if (imgUrl != null)
                CachedNetworkImage(
                  imageUrl: imgUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.grey[300]),
                  errorWidget: (_, __, ___) => _buildFallback(),
                )
              else
                _buildFallback(),

              // Gradient overlay
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.72),
                    ],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),

              // Badge + Title
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _badgeColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_badgeColor.withOpacity(0.7), _badgeColor],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.local_activity_rounded,
          color: Colors.white.withOpacity(0.4),
          size: 40,
        ),
      ),
    );
  }
}
