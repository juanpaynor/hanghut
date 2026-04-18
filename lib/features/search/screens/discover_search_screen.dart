import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/ticketing/models/event.dart';

class DiscoverSearchScreen extends StatefulWidget {
  const DiscoverSearchScreen({super.key});

  @override
  State<DiscoverSearchScreen> createState() => _DiscoverSearchScreenState();
}

class _DiscoverSearchScreenState extends State<DiscoverSearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  late TabController _tabController;

  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _suggestedPeople = [];
  bool _isDiscoverLoading = true;

  bool _isSearching = false;
  bool _isSearchLoading = false;
  List<Map<String, dynamic>> _peopleResults = [];
  List<Map<String, dynamic>> _hangoutResults = [];
  List<Map<String, dynamic>> _eventResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
    _loadDiscoverFeed();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDiscoverFeed() async {
    try {
      final data = await SocialService().getDiscoverFeed();
      if (mounted) {
        setState(() {
          _upcomingEvents = List<Map<String, dynamic>>.from(
            data['events'] ?? [],
          );
          _suggestedPeople = List<Map<String, dynamic>>.from(
            data['people'] ?? [],
          );
          _isDiscoverLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isDiscoverLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _isSearchLoading = false;
        _peopleResults = [];
        _hangoutResults = [];
        _eventResults = [];
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _isSearchLoading = true;
    });
    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      final q = query.trim();
      final results = await SocialService().searchAll(q);
      if (!mounted) return;
      setState(() {
        _peopleResults = results['people'] ?? [];
        _hangoutResults = results['hangouts'] ?? [];
        _eventResults = results['events'] ?? [];
        _isSearchLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF7F7FA);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(isDark),
            if (_isSearching) _buildTabBar(isDark),
            Expanded(
              child: _isSearching
                  ? _buildSearchResults(isDark)
                  : _buildDiscoverFeed(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'People, hangouts, events...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[600] : Colors.grey[300],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: AppTheme.primaryColor,
      indicatorWeight: 2.5,
      dividerColor: Colors.transparent,
      labelColor: AppTheme.primaryColor,
      unselectedLabelColor: Colors.grey[500],
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tabs: const [
        Tab(text: 'Top'),
        Tab(text: 'People'),
        Tab(text: 'Hangouts'),
        Tab(text: 'Events'),
      ],
    );
  }

  Widget _buildDiscoverFeed(bool isDark) {
    if (_isDiscoverLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _sectionHeader('Explore', isDark),
        const SizedBox(height: 10),
        _buildCategoryChips(),
        const SizedBox(height: 28),
        if (_upcomingEvents.isNotEmpty) ...[
          _sectionHeader('Upcoming Events 🎫', isDark),
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _upcomingEvents.length,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(
                  right: i < _upcomingEvents.length - 1 ? 14 : 0,
                ),
                child: _EventCard(event: _upcomingEvents[i]),
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
        if (_suggestedPeople.isNotEmpty) ...[
          _sectionHeader('Meet New People 👋', isDark),
          const SizedBox(height: 4),
          ..._suggestedPeople.map(
            (u) => _PersonTile(
              user: u,
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: u['id']),
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
      ],
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final chips = [
      ('🌮', 'Food Tours', const Color(0xFFFF6B6B)),
      ('🌙', 'Nightlife', const Color(0xFF845EC2)),
      ('🎨', 'Arts', const Color(0xFFFF9671)),
      ('🏃', 'Active', const Color(0xFF00C9A7)),
      ('☕', 'Chill', const Color(0xFFF9A826)),
      ('🎵', 'Music', const Color(0xFF4FACFE)),
    ];
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        itemBuilder: (_, i) {
          final (emoji, label, color) = chips[i];
          return GestureDetector(
            onTap: () {
              _searchController.text = label;
              _onSearchChanged(label);
            },
            child: Container(
              margin: EdgeInsets.only(right: i < chips.length - 1 ? 10 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    if (_isSearchLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }
    return TabBarView(
      controller: _tabController,
      children: [
        _buildTopTab(isDark),
        _buildPeopleTab(isDark),
        _buildHangoutsTab(isDark),
        _buildEventsTab(isDark),
      ],
    );
  }

  Widget _buildTopTab(bool isDark) {
    final hasAny =
        _peopleResults.isNotEmpty ||
        _hangoutResults.isNotEmpty ||
        _eventResults.isNotEmpty;
    if (!hasAny)
      return _emptyState('No results found.', Icons.search_off_rounded);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (_peopleResults.isNotEmpty) ...[
          _sectionHeader('People', isDark),
          const SizedBox(height: 6),
          ..._peopleResults
              .take(3)
              .map(
                (u) => _PersonTile(
                  user: u,
                  isDark: isDark,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(userId: u['id']),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 20),
        ],
        if (_hangoutResults.isNotEmpty) ...[
          _sectionHeader('Hangouts', isDark),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _hangoutResults.take(4).length,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(right: i < 3 ? 14 : 0),
                child: _HangoutCard(hangout: _hangoutResults[i]),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (_eventResults.isNotEmpty) ...[
          _sectionHeader('Events', isDark),
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _eventResults.take(4).length,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(right: i < 3 ? 14 : 0),
                child: _EventCard(event: _eventResults[i]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPeopleTab(bool isDark) {
    if (_peopleResults.isEmpty)
      return _emptyState(
        'No people found.\nTry a different name or @username.',
        Icons.person_off_outlined,
      );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _peopleResults.length,
      itemBuilder: (_, i) => _PersonTile(
        user: _peopleResults[i],
        isDark: isDark,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(userId: _peopleResults[i]['id']),
          ),
        ),
      ),
    );
  }

  Widget _buildHangoutsTab(bool isDark) {
    if (_hangoutResults.isEmpty)
      return _emptyState(
        'No hangouts found.\nTry cuisine or location keywords.',
        Icons.restaurant_outlined,
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _hangoutResults.length,
      itemBuilder: (_, i) =>
          _HangoutRow(hangout: _hangoutResults[i], isDark: isDark),
    );
  }

  Widget _buildEventsTab(bool isDark) {
    if (_eventResults.isEmpty)
      return _emptyState(
        'No events found.\nTry searching by event name or venue.',
        Icons.event_busy_outlined,
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _eventResults.length,
      itemBuilder: (_, i) => _EventRow(event: _eventResults[i], isDark: isDark),
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Person tile ────────────────────────────────────────────────────────────────

class _PersonTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isDark;
  final VoidCallback onTap;

  const _PersonTile({
    required this.user,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user['display_name'] as String? ?? 'Unknown';
    final username = user['username'] as String?;
    final avatarUrl = user['avatar_url'] as String?;
    final bio = user['bio'] as String?;
    final isVerified = user['is_verified'] == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? Icon(
                        Icons.person_rounded,
                        size: 28,
                        color: isDark ? Colors.grey[600] : Colors.grey[400],
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: Colors.blue,
                          ),
                        ],
                      ],
                    ),
                    if (username != null && username.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        '@$username',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: isDark ? Colors.grey[700] : Colors.grey[300],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hangout card (horizontal scroll, full-bleed) ──────────────────────────────

class _HangoutCard extends StatelessWidget {
  final Map<String, dynamic> hangout;

  const _HangoutCard({required this.hangout});

  @override
  Widget build(BuildContext context) {
    final title = hangout['title'] as String? ?? 'Hangout';
    final location =
        hangout['location_name'] as String? ?? hangout['city'] as String? ?? '';
    final emoji = hangout['marker_emoji'] as String? ?? '🍽️';
    final cuisine = hangout['cuisine_type'] as String?;
    final current = (hangout['current_capacity'] as num?)?.toInt() ?? 0;
    final max = (hangout['max_guests'] as num?)?.toInt() ?? 4;
    final imageUrl = hangout['image_url'] as String?;
    DateTime? dt;
    try {
      if (hangout['datetime'] != null)
        dt = DateTime.parse(hangout['datetime']).toLocal();
    } catch (_) {}

    final isFull = current >= max;
    final fillRatio = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;

    return Container(
      width: 172,
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover)
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.7),
                    AppTheme.primaryColor.withOpacity(0.3),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 48)),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.3, 1.0],
                colors: [Colors.transparent, Colors.black.withOpacity(0.82)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cuisine != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cuisine,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 11,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: fillRatio,
                            minHeight: 4,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isFull ? Colors.redAccent : Colors.greenAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$current/$max',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (dt != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      DateFormat('EEE, MMM d').format(dt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (dt != null)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  DateFormat('MMM d').format(dt),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Hangout row (full-width list) ─────────────────────────────────────────────

class _HangoutRow extends StatelessWidget {
  final Map<String, dynamic> hangout;
  final bool isDark;

  const _HangoutRow({required this.hangout, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final title = hangout['title'] as String? ?? 'Hangout';
    final location =
        hangout['location_name'] as String? ?? hangout['city'] as String? ?? '';
    final emoji = hangout['marker_emoji'] as String? ?? '🍽️';
    final cuisine = hangout['cuisine_type'] as String?;
    final current = (hangout['current_capacity'] as num?)?.toInt() ?? 0;
    final max = (hangout['max_guests'] as num?)?.toInt() ?? 4;
    final imageUrl = hangout['image_url'] as String?;
    DateTime? dt;
    try {
      if (hangout['datetime'] != null)
        dt = DateTime.parse(hangout['datetime']).toLocal();
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
            child: SizedBox(
              width: 82,
              height: 82,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover)
                  : Container(
                      color: isDark
                          ? AppTheme.primaryColor.withOpacity(0.15)
                          : AppTheme.primaryColor.withOpacity(0.07),
                      alignment: Alignment.center,
                      child: Text(emoji, style: const TextStyle(fontSize: 30)),
                    ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (cuisine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      cuisine,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          location,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (dt != null)
                  Text(
                    DateFormat('MMM d').format(dt),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.07)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$current/$max',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event card (horizontal scroll, full-bleed) ────────────────────────────────

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventCard({required this.event});

  void _open(BuildContext context) {
    try {
      final rawDate = event['start_datetime'] as String?;
      final startDate = rawDate != null
          ? DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now()
          : DateTime.now();
      final e = Event(
        id: event['id'] as String,
        title: event['title'] as String? ?? '',
        description: '',
        venueName: event['venue_name'] as String? ?? '',
        venueAddress: '',
        latitude: 0,
        longitude: 0,
        startDatetime: startDate,
        coverImageUrl: event['cover_image_url'] as String?,
        ticketPrice: (event['ticket_price'] as num?)?.toDouble() ?? 0,
        capacity: (event['capacity'] as num?)?.toInt() ?? 0,
        ticketsSold: (event['tickets_sold'] as num?)?.toInt() ?? 0,
        category: event['event_type'] as String? ?? 'other',
        organizerId: '',
        createdAt: DateTime.now(),
      );
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EventDetailModal(event: e),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final title = event['title'] as String? ?? 'Event';
    final venue =
        event['venue_name'] as String? ?? event['city'] as String? ?? '';
    final coverUrl = event['cover_image_url'] as String?;
    final price = (event['ticket_price'] as num?)?.toDouble() ?? 0;
    final capacity = (event['capacity'] as num?)?.toInt() ?? 0;
    final sold = (event['tickets_sold'] as num?)?.toInt() ?? 0;
    DateTime? dt;
    try {
      if (event['start_datetime'] != null)
        dt = DateTime.parse(event['start_datetime']).toLocal();
    } catch (_) {}

    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: 190,
        height: 230,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            (coverUrl != null && coverUrl.isNotEmpty)
                ? CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF845EC2), Color(0xFF4FACFE)],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.event_rounded,
                      size: 52,
                      color: Colors.white54,
                    ),
                  ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.25, 1.0],
                  colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (venue.isNotEmpty)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 11,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              venue,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: price == 0
                                ? Colors.green.withOpacity(0.85)
                                : Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            price == 0
                                ? 'Free'
                                : '₱${price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (capacity > 0)
                          Text(
                            '${capacity - sold} left',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (dt != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMM').format(dt).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        DateFormat('d').format(dt),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Event row (full-width list) ───────────────────────────────────────────────

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isDark;

  const _EventRow({required this.event, required this.isDark});

  void _open(BuildContext context) {
    try {
      final rawDate = event['start_datetime'] as String?;
      final startDate = rawDate != null
          ? DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now()
          : DateTime.now();
      final e = Event(
        id: event['id'] as String,
        title: event['title'] as String? ?? '',
        description: '',
        venueName: event['venue_name'] as String? ?? '',
        venueAddress: '',
        latitude: 0,
        longitude: 0,
        startDatetime: startDate,
        coverImageUrl: event['cover_image_url'] as String?,
        ticketPrice: (event['ticket_price'] as num?)?.toDouble() ?? 0,
        capacity: (event['capacity'] as num?)?.toInt() ?? 0,
        ticketsSold: (event['tickets_sold'] as num?)?.toInt() ?? 0,
        category: event['event_type'] as String? ?? 'other',
        organizerId: '',
        createdAt: DateTime.now(),
      );
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EventDetailModal(event: e),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final title = event['title'] as String? ?? 'Event';
    final venue = event['venue_name'] as String? ?? '';
    final coverUrl = event['cover_image_url'] as String?;
    final price = (event['ticket_price'] as num?)?.toDouble() ?? 0;
    final capacity = (event['capacity'] as num?)?.toInt() ?? 0;
    final sold = (event['tickets_sold'] as num?)?.toInt() ?? 0;
    DateTime? dt;
    try {
      if (event['start_datetime'] != null)
        dt = DateTime.parse(event['start_datetime']).toLocal();
    } catch (_) {}

    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: SizedBox(
                width: 82,
                height: 82,
                child: (coverUrl != null && coverUrl.isNotEmpty)
                    ? CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover)
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF845EC2), Color(0xFF4FACFE)],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.event_rounded,
                          size: 28,
                          color: Colors.white70,
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (venue.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              venue,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (dt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEE, MMM d · h:mm a').format(dt),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: price == 0
                          ? Colors.green.withOpacity(0.12)
                          : AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      price == 0 ? 'Free' : '₱${price.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: price == 0
                            ? Colors.green[700]
                            : AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  if (capacity > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${capacity - sold} left',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
