import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/core/services/event_category_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class DiscoverTab extends StatefulWidget {
  final void Function(String tableId)? onHangoutTap;
  const DiscoverTab({super.key, this.onHangoutTap});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab>
    with AutomaticKeepAliveClientMixin {
  final TableService _tableService = TableService();

  List<Map<String, dynamic>> _experiences = [];
  List<Event> _events = [];
  bool _isLoading = true;
  Position? _userPosition;

  // Events pagination (infinite scroll).
  static const int _eventsPageSize = 20;
  final ScrollController _scrollController = ScrollController();
  bool _loadingMoreEvents = false;
  bool _hasMoreEvents = true;

  // Filters
  String _sectionFilter = 'All'; // 'All' | 'Events' | 'Experiences'

  // Event date-range filter (applies to events only).
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // Search + sort + category (events).
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchExpanded = false;
  Timer? _searchDebounce;
  String _query = '';
  String _sort = 'soonest'; // soonest | price_low | nearest | popular
  String? _eventCategory; // null = all categories

  static const Map<String, String> _sortLabels = {
    'soonest': 'Soonest',
    'price_low': 'Price: Low to High',
    'nearest': 'Nearest',
    'popular': 'Most Popular',
  };

  // Server-driven category list (team_comms #174). Empty until fetched.
  List<EventCategoryItem> _categories = [];

  bool get _isFiltering =>
      _query.trim().isNotEmpty ||
      _eventCategory != null ||
      _rangeStart != null ||
      _sort != 'soonest';

  // Frosted sticky header — measured so content can pad below it.
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 130;

  void _measureHeader() {
    final ctx = _headerKey.currentContext;
    if (ctx == null) return;
    final h = (ctx.findRenderObject() as RenderBox).size.height;
    if ((h - _headerHeight).abs() > 0.5 && mounted) {
      setState(() => _headerHeight = h);
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await EventCategoryService().getCategories();
    if (mounted) setState(() => _categories = cats);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _loadMoreEvents();
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  // Section visibility (drives both the default rails and the filtered results).
  bool get _showEvents =>
      _sectionFilter == 'All' || _sectionFilter == 'Events';
  bool get _showExperiences =>
      _sectionFilter == 'All' || _sectionFilter == 'Experiences';

  void _toggleSearch() {
    setState(() => _searchExpanded = !_searchExpanded);
    if (_searchExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.unfocus();
      _searchDebounce?.cancel();
      _searchController.clear();
      setState(() => _query = '');
    }
  }

  /// Experiences matching the current text query (title).
  List<Map<String, dynamic>> get _searchExperiences {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _experiences
        .where((t) => (t['title'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  void _openExperience(Map<String, dynamic> exp) {
    // Opaque full route (not a bottom sheet) — a sheet strips the top safe-area
    // padding, pushing the close/flag icons up under the status bar.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ExperienceDetailModal(experience: exp, matchData: const {}),
      ),
    );
  }

  // ── Filtered / sorted events ───────────────────────────────────────────────
  List<Event> get _visibleEvents {
    final q = _query.trim().toLowerCase();
    final list = _events.where((e) {
      if (_eventCategory != null && e.category != _eventCategory) return false;
      if (q.isNotEmpty) {
        return e.title.toLowerCase().contains(q) ||
            e.venueName.toLowerCase().contains(q);
      }
      return true;
    }).toList();
    _sortEvents(list);
    return list;
  }

  void _sortEvents(List<Event> list) {
    switch (_sort) {
      case 'price_low':
        list.sort((a, b) => a.ticketPrice.compareTo(b.ticketPrice));
        break;
      case 'popular':
        list.sort((a, b) => b.ticketsSold.compareTo(a.ticketsSold));
        break;
      case 'nearest':
        final pos = _userPosition;
        if (pos != null) {
          list.sort((a, b) {
            final da = Geolocator.distanceBetween(
                pos.latitude, pos.longitude, a.latitude, a.longitude);
            final db = Geolocator.distanceBetween(
                pos.latitude, pos.longitude, b.latitude, b.longitude);
            return da.compareTo(db);
          });
        }
        break;
      case 'soonest':
      default:
        list.sort((a, b) => a.startDatetime.compareTo(b.startDatetime));
    }
  }

  // ── Curated rails (default view) ───────────────────────────────────────────
  List<Event> get _trendingEvents {
    final list = [..._events]
      ..sort((a, b) => b.ticketsSold.compareTo(a.ticketsSold));
    return list.where((e) => e.ticketsSold > 0).take(10).toList();
  }

  List<Event> get _thisWeekendEvents {
    final now = DateTime.now();
    final sat = now.add(Duration(days: (DateTime.saturday - now.weekday) % 7));
    final satStart = DateTime(sat.year, sat.month, sat.day);
    final monStart = satStart.add(const Duration(days: 2)); // covers Sat+Sun
    return _events
        .where((e) =>
            e.startDatetime.isAfter(now) &&
            e.startDatetime.isBefore(monStart))
        .take(10)
        .toList();
  }

  List<Event> get _freeEvents =>
      _events.where((e) => e.ticketPrice <= 0).take(10).toList();

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final position = await LocationService().getCurrentLocation();
      if (mounted) setState(() => _userPosition = position);
    } catch (_) {}

    await Future.wait([_loadEvents(), _loadExperiences()]);

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadExperiences() async {
    try {
      final exps = await _tableService.getExperiences(
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
        limit: 20,
      );
      if (mounted) setState(() => _experiences = exps);
    } catch (e) {
      print('❌ DiscoverTab: error loading experiences: $e');
    }
  }

  /// End of the selected end day (inclusive); single-day picks end == start.
  DateTime? get _rangeEndOfDay {
    if (_rangeStart == null) return null;
    final d = _rangeEnd ?? _rangeStart!;
    return DateTime(d.year, d.month, d.day, 23, 59, 59);
  }

  // First page.
  Future<void> _loadEvents() async {
    try {
      final events = await EventService().getUpcomingEvents(
        limit: _eventsPageSize,
        offset: 0,
        startDate: _rangeStart,
        endDate: _rangeEndOfDay,
      );
      if (mounted) {
        setState(() {
          _events = events;
          _hasMoreEvents = events.length == _eventsPageSize;
        });
      }
    } catch (e) {
      print('❌ DiscoverTab: error loading events: $e');
    }
  }

  // Next page (infinite scroll). Appends to the base list the rails/grid derive
  // from. Date-range scoping is preserved via the cursor offset.
  Future<void> _loadMoreEvents() async {
    if (_loadingMoreEvents || !_hasMoreEvents || _events.isEmpty) return;
    setState(() => _loadingMoreEvents = true);
    try {
      final more = await EventService().getUpcomingEvents(
        limit: _eventsPageSize,
        offset: _events.length,
        startDate: _rangeStart,
        endDate: _rangeEndOfDay,
      );
      if (mounted) {
        setState(() {
          // Guard against any overlap by id.
          final existing = _events.map((e) => e.id).toSet();
          _events.addAll(more.where((e) => !existing.contains(e.id)));
          _hasMoreEvents = more.length == _eventsPageSize;
          _loadingMoreEvents = false;
        });
      }
    } catch (e) {
      print('❌ DiscoverTab: error loading more events: $e');
      if (mounted) setState(() => _loadingMoreEvents = false);
    }
  }

  Future<void> _openDateRangePicker() async {
    DateTime? start = _rangeStart;
    DateTime? end = _rangeEnd;
    DateTime focused = _rangeStart ?? DateTime.now();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'Filter events by date',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TableCalendar(
                    firstDay: DateTime.now().subtract(const Duration(days: 1)),
                    lastDay: DateTime.now().add(const Duration(days: 365)),
                    focusedDay: focused,
                    rangeStartDay: start,
                    rangeEndDay: end,
                    rangeSelectionMode: RangeSelectionMode.toggledOn,
                    calendarFormat: CalendarFormat.month,
                    availableGestures: AvailableGestures.horizontalSwipe,
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                    calendarStyle: CalendarStyle(
                      rangeHighlightColor:
                          const Color(0xFF6C63FF).withValues(alpha: 0.15),
                      rangeStartDecoration: const BoxDecoration(
                        color: Color(0xFF6C63FF),
                        shape: BoxShape.circle,
                      ),
                      rangeEndDecoration: const BoxDecoration(
                        color: Color(0xFF6C63FF),
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                    ),
                    onRangeSelected: (s, e, f) {
                      setSheet(() {
                        start = s;
                        end = e;
                        focused = f;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setSheet(() {
                              start = null;
                              end = null;
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((applied) {
      if (applied == true) {
        setState(() {
          _rangeStart = start;
          _rangeEnd = end;
        });
        _loadEvents();
      }
    });
  }

  void _clearDateRange() {
    setState(() {
      _rangeStart = null;
      _rangeEnd = null;
    });
    _loadEvents();
  }

  String get _dateRangeLabel {
    if (_rangeStart == null) return 'Any date';
    final fmt = DateFormat('MMM d');
    if (_rangeEnd == null || isSameDay(_rangeStart, _rangeEnd)) {
      return fmt.format(_rangeStart!);
    }
    return '${fmt.format(_rangeStart!)} – ${fmt.format(_rangeEnd!)}';
  }

  Widget _buildEventsGrid() {
    final items = _visibleEvents;
    // Split into two columns, alternating tall/short for a staggered feel
    final left = <Event>[];
    final right = <Event>[];
    for (var i = 0; i < items.length; i++) {
      if (i.isEven) {
        left.add(items[i]);
      } else {
        right.add(items[i]);
      }
    }

    void onTap(Event item) => EventDetailModal.show(context, item);

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
        // Section chips + date/sort pills (scrollable) with a pinned search icon.
        Row(
          children: [
            Expanded(
              // Fade the right edge so chips dissolve instead of being hard-cut
              // by the search icon (also signals "scroll for more").
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0.0, 0.88, 1.0],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    padding: const EdgeInsets.only(left: 16, right: 20),
                    scrollDirection: Axis.horizontal,
                    children: [
                    ...['All', 'Events', 'Experiences'].map((s) {
                      final selected = _sectionFilter == s;
                      return GestureDetector(
                        onTap: () => setState(() => _sectionFilter = s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: _glassPill(active: selected),
                          child: Center(
                            child: Text(
                              s,
                              style: TextStyle(
                                color: _glassText(selected),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    // Date + sort live on this same row (events only)
                    if (_showEvents) ...[
                      _datePill(),
                      const SizedBox(width: 8),
                      _sortPill(),
                    ],
                  ],
                ),
              ),
            ),
            ),
            _searchIconButton(),
            const SizedBox(width: 12),
          ],
        ),
        // Inline search field — morphs open/closed under the section row.
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _searchExpanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: _buildInlineSearchField(),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        // Category chips
        if (_showEvents) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                _categoryChip('All', null),
                ..._categories.map((c) => _categoryChip(c.display, c.key)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _datePill() {
    return GestureDetector(
      onTap: _openDateRangePicker,
      child: Container(
        margin: const EdgeInsets.only(right: 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: _glassPill(active: _rangeStart != null),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size: 15,
              color: _glassText(_rangeStart != null),
            ),
            const SizedBox(width: 6),
            Text(
              _dateRangeLabel,
              style: TextStyle(
                color: _glassText(_rangeStart != null),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (_rangeStart != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _clearDateRange,
                child: const Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sortPill() {
    return GestureDetector(
      onTap: _openSortSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: _glassPill(active: _sort != 'soonest'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert, size: 16, color: _glassText(_sort != 'soonest')),
            const SizedBox(width: 4),
            Text(
              _sortLabels[_sort]!,
              style: TextStyle(
                color: _glassText(_sort != 'soonest'),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(String label, String? key) {
    final selected = _eventCategory == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => setState(() => _eventCategory = selected ? null : key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6C63FF).withValues(alpha: 0.20)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF6C63FF)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.08)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? const Color(0xFF8E88FF)
                : (isDark ? Colors.white : Colors.black87),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12.5,
          ),
        ),
      ),
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

    if (_isLoading) return _buildLoadingShimmer();

    // Re-measure the frosted header after each layout (its height changes with
    // filter mode) so the scrolling content pads correctly beneath it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.only(top: _headerHeight + 8, bottom: 32),
            children: [
              if (_query.trim().isNotEmpty || _isFiltering)
                ..._buildFilteredView()
              else
                ..._buildDefaultView(),
              if (_loadingMoreEvents)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildGlassHeader(),
        ),
      ],
    );
  }

  Widget _buildGlassHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          key: _headerKey,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.6),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              _buildFilterRow(),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ── Default (curated) view ─────────────────────────────────────────────────
  List<Widget> _buildDefaultView() {
    final hasContent = _events.isNotEmpty || _experiences.isNotEmpty;
    if (!hasContent) return [_buildGlobalEmpty()];

    return [
      if (_showEvents && _events.isNotEmpty) ...[
        _buildEventRail('🔥 Trending', _trendingEvents),
        _buildEventRail('📅 This Weekend', _thisWeekendEvents),
        _buildEventRail('🎟️ Free', _freeEvents),
        _buildSectionHeader('All Events'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildEventsGrid(),
        ),
        const SizedBox(height: 8),
      ],
      if (_showExperiences && _experiences.isNotEmpty) ...[
        _buildSectionHeader('✨ Experiences'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildExperiencesGrid(_experiences),
        ),
        const SizedBox(height: 12),
      ],
      // Section chosen but nothing to show for it.
      if (_sectionFilter == 'Experiences' && _experiences.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: _buildEmpty('No experiences available yet'),
        ),
    ];
  }

  Widget _buildExperiencesGrid(List<Map<String, dynamic>> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _ActivityTile(
        item: items[i],
        tall: false,
        onTap: () => _openExperience(items[i]),
      ),
    );
  }

  // ── Filtered / search results ──────────────────────────────────────────────
  List<Widget> _buildFilteredView() {
    final searching = _query.trim().isNotEmpty;
    // Respect the active section chip. Experiences only join when
    // text-searching (category/date/sort controls are event-specific).
    final events = _showEvents ? _visibleEvents : <Event>[];
    final experiences =
        (_showExperiences && searching) ? _searchExperiences : <Map<String, dynamic>>[];
    final total = events.length + experiences.length;

    if (total == 0) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: _buildEmpty(
            searching
                ? 'No results for "${_query.trim()}"'
                : 'No events match these filters',
          ),
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          '$total result${total == 1 ? '' : 's'}',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ),
      if (events.isNotEmpty) ...[
        if (searching) _buildSectionHeader('Events'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemCount: events.length,
            itemBuilder: (_, i) => _ActivityTile(
              item: events[i],
              tall: false,
              onTap: () => EventDetailModal.show(context, events[i]),
            ),
          ),
        ),
      ],
      if (experiences.isNotEmpty) ...[
        _buildSectionHeader('Experiences'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildExperiencesGrid(experiences),
        ),
      ],
    ];
  }

  // ── Curated event rail (horizontal) ────────────────────────────────────────
  Widget _buildEventRail(String title, List<Event> events) {
    if (events.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title),
        SizedBox(
          height: 222,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _EventRailCard(
              event: events[i],
              onTap: () => EventDetailModal.show(context, events[i]),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ── Glass styling helpers ──────────────────────────────────────────────────
  BoxDecoration _glassPill({required bool active}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (active) {
      return BoxDecoration(
        color: const Color(0xFF6C63FF),
        borderRadius: BorderRadius.circular(20),
      );
    }
    return BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.black.withValues(alpha: 0.08),
      ),
    );
  }

  Color _glassText(bool active) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return active ? Colors.white : (isDark ? Colors.white : Colors.black87);
  }

  // ── Search (top-right icon → inline expanding field) ────────────────────────
  Widget _searchIconButton() {
    final active = _searchExpanded || _query.trim().isNotEmpty;
    return GestureDetector(
      onTap: _toggleSearch,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF6C63FF)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.04)),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? const Color(0xFF6C63FF)
                : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        child: Icon(
          _searchExpanded ? Icons.close : Icons.search,
          size: 20,
          color: _glassText(active),
        ),
      ),
    );
  }

  Widget _buildInlineSearchField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: 'Search events, experiences',
        hintStyle: TextStyle(
          color: isDark ? Colors.white54 : Colors.grey[500],
        ),
        prefixIcon: Icon(
          Icons.search,
          color: isDark ? Colors.white60 : Colors.grey[600],
        ),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.clear,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            : null,
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }

  // ── Sort bottom sheet ──────────────────────────────────────────────────────
  void _openSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('Sort by',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._sortLabels.entries.map((e) {
                final selected = _sort == e.key;
                return ListTile(
                  title: Text(e.value),
                  trailing: selected
                      ? const Icon(Icons.check, color: Color(0xFF6C63FF))
                      : null,
                  onTap: () {
                    setState(() => _sort = e.key);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 44, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildGlobalEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Center(
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
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _shimmerBox(height: 48, radius: 14),
        const SizedBox(height: 16),
        _shimmerBox(height: 28, width: 160, radius: 8),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _shimmerBox(height: 190, radius: 16)),
            const SizedBox(width: 12),
            Expanded(child: _shimmerBox(height: 190, radius: 16)),
          ],
        ),
        const SizedBox(height: 20),
        _shimmerBox(height: 28, width: 140, radius: 8),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _shimmerBox(height: 190, radius: 16)),
            const SizedBox(width: 12),
            Expanded(child: _shimmerBox(height: 190, radius: 16)),
          ],
        ),
      ],
    );
  }

  Widget _shimmerBox({double? height, double? width, double radius = 12}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(radius),
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

              // Price pill (events only — experiences/hangouts have no ticket price)
              if (widget.item is Event)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Builder(
                    builder: (_) {
                      final event = widget.item as Event;
                      final isFree = event.displayFromPrice <= 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isFree
                              ? const Color(0xFF22A06B)
                              : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isFree ? 'FREE' : event.priceLabel(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    },
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

/// Fixed-width event card used in the horizontal curated rails.
class _EventRailCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;

  const _EventRailCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEE, MMM d · h:mm a').format(event.startLocal);
    final isFree = event.displayFromPrice <= 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              child: Stack(
                children: [
                  SizedBox(
                    height: 120,
                    width: 168,
                    child: event.coverImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: event.coverImageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: Colors.grey[300]),
                            errorWidget: (_, __, ___) =>
                                Container(color: Colors.grey[300]),
                          )
                        : Container(color: Colors.grey[300]),
                  ),
                  // Price / Free pill
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isFree
                            ? const Color(0xFF22A06B)
                            : Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isFree ? 'FREE' : event.priceLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (event.isSoldOut || event.isLowAvailability)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: event.isSoldOut
                              ? Colors.red
                              : Colors.amber[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          event.isSoldOut
                              ? 'SOLD OUT'
                              : '${event.ticketsAvailable} left',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.grey[600],
                      fontSize: 11.5,
                    ),
                  ),
                  Text(
                    event.venueName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey[500],
                      fontSize: 11,
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
}
