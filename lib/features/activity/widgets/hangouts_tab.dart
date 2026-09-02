import 'package:flutter/material.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/analytics_service.dart';
import 'package:bitemates/features/home/widgets/open_hangout_card.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:bitemates/features/map/widgets/create_hangout/create_hangout_flow.dart';

/// Dedicated "Hangouts" browse tab in Explore — a paginated grid of open
/// hangouts with quick vibe filters. Split out of DiscoverTab so Discover can
/// focus on events/experiences.
class HangoutsTab extends StatefulWidget {
  final void Function(String tableId)? onHangoutTap;
  const HangoutsTab({super.key, this.onHangoutTap});

  @override
  State<HangoutsTab> createState() => _HangoutsTabState();
}

class _HangoutsTabState extends State<HangoutsTab> {
  static const int _pageSize = 12;
  static const List<Map<String, String>> _vibes = [
    {'label': 'Chill 😌', 'key': 'chill'},
    {'label': 'Foodie 🍜', 'key': 'food'},
    {'label': 'Active 🏃', 'key': 'sports'},
    {'label': 'Social 🗣️', 'key': 'social'},
    {'label': 'Late Night 🌙', 'key': 'nightlife'},
    {'label': 'Coffee ☕', 'key': 'coffee'},
    {'label': 'Outdoors 🌿', 'key': 'outdoor'},
  ];

  final TableService _service = TableService();
  final ScrollController _scroll = ScrollController();

  final List<Map<String, dynamic>> _hangouts = [];
  final Set<String> _vibeFilters = {};

  bool _loading = true; // first load / refresh
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _error = false;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int offset) async {
    final tables = await _service.getMapReadyTables(
      limit: _pageSize,
      offset: offset,
    );
    final filtered = tables
        .where((t) => t['visibility'] != 'mystery' && t['is_experience'] != true)
        .toList();
    return _service.enrichTablesWithMembers(filtered);
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final page = await _fetchPage(0);
      if (!mounted) return;
      setState(() {
        _hangouts
          ..clear()
          ..addAll(page);
        _offset = page.length;
        _hasMore = page.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ HangoutsTab: first load failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchPage(_offset);
      if (!mounted) return;
      setState(() {
        _hangouts.addAll(page);
        _offset += page.length;
        _hasMore = page.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('❌ HangoutsTab: load more failed: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_vibeFilters.isEmpty) return _hangouts;
    return _hangouts.where((t) {
      final type = (t['activity_type'] as String? ?? '').toLowerCase();
      return _vibeFilters.any((v) => type.contains(v));
    }).toList();
  }

  void _openHangout(Map<String, dynamic> table) {
    final id = table['id']?.toString();
    if (id != null && widget.onHangoutTap != null) {
      widget.onHangoutTap!(id);
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TableCompactModal(table: table, matchData: const {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildVibeChips(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadFirst,
            child: _buildBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return _messageState(
        icon: Icons.wifi_off_rounded,
        title: 'Couldn\'t load hangouts',
        subtitle: 'Pull to try again.',
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      final noFilters = _vibeFilters.isEmpty;
      return _messageState(
        icon: Icons.groups_outlined,
        title: noFilters
            ? 'No open hangouts right now'
            : 'Nothing matches these vibes',
        subtitle: noFilters
            ? 'Be the first — start one and see who\'s around.'
            : 'Try clearing a filter.',
        ctaLabel: noFilters ? 'Start a hangout' : null,
        onCta: noFilters ? _startHangout : null,
      );
    }

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final table = items[i];
                return OpenHangoutCard(
                  table: table,
                  onTap: () => _openHangout(table),
                );
              },
              childCount: items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildFooter()),
      ],
    );
  }

  Widget _buildFooter() {
    // Only meaningful when the vibe filter isn't hiding loaded rows.
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasMore && _hangouts.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'You\'re all caught up',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }

  Widget _buildVibeChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 36,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        scrollDirection: Axis.horizontal,
        children: [
          ..._vibes.map((v) {
            final selected = _vibeFilters.contains(v['key']);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _vibeFilters.remove(v['key']);
                  } else {
                    _vibeFilters.add(v['key']!);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    v['label']!,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF8E88FF)
                          : (isDark ? Colors.white : Colors.black87),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _startHangout() {
    AnalyticsService().logHangoutCreateStart('empty_state_discover');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateHangoutFlow(
          onTableCreated: () {
            if (mounted) _loadFirst();
          },
        ),
      ),
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? ctaLabel,
    VoidCallback? onCta,
  }) {
    // Wrapped in a scroll view so pull-to-refresh works on the empty state too.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 52, color: Colors.grey[400]),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                  if (ctaLabel != null && onCta != null) ...[
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: onCta,
                      icon: const Icon(Icons.add, size: 20),
                      label: Text(ctaLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
