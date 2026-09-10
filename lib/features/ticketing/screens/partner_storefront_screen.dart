import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/constants/app_constants.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';
import 'package:bitemates/core/services/event_category_service.dart';
import 'package:bitemates/features/gamification/widgets/partner_collection_shelf.dart';
import 'package:bitemates/features/ticketing/services/partner_profile_service.dart';
import 'package:bitemates/core/utils/image_url.dart';

/// The organizer's page — what they programme, when the next one is, and what
/// there is to collect.
///
/// Deliberately shaped unlike a person's profile. A profile leads with identity
/// (who is this, do I know them); an organizer is judged on their programme, so
/// this leads with the marquee and the dates and puts the follow decision after
/// the evidence rather than before it.
///
/// Powered by the single `get_storefront` RPC (team_comms #220) for partner,
/// counts, upcoming events, experiences and tiers, plus two client-side reads
/// for the track record and the stamp set — both over tables that already carry
/// a public SELECT policy, so neither needs a new endpoint.
class PartnerStorefrontScreen extends StatefulWidget {
  final String partnerId;

  const PartnerStorefrontScreen({super.key, required this.partnerId});

  @override
  State<PartnerStorefrontScreen> createState() =>
      _PartnerStorefrontScreenState();
}

class _PartnerStorefrontScreenState extends State<PartnerStorefrontScreen> {
  Map<String, dynamic>? _partner;
  Map<String, dynamic> _counts = const {};
  List<Event> _events = [];
  List<Map<String, dynamic>> _experiences = [];
  List<Map<String, dynamic>> _tiers = [];

  PartnerTrackRecord _record = PartnerTrackRecord.empty;
  List<EventCategoryItem> _knownFor = const [];

  bool _isLoading = true;
  bool _notFound = false;
  bool _showAllEvents = false;
  bool _isFollowing = false;
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.partnerId.trim().isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    await Future.wait([_loadStorefront(), _loadFollowState()]);
    if (mounted) setState(() => _isLoading = false);
    // History comes after the fold, so it loads after the page is on screen
    // rather than holding the first paint behind three more round trips.
    await _loadTrackRecord();
  }

  /// Past events, hosting history, and the categories they actually programme.
  /// How many listings show before "Show all". Enough to read as a programme
  /// rather than a teaser, short enough that what follows stays reachable.
  static const int _eventPreviewCount = 5;

  int get _visibleEventCount =>
      _showAllEvents ? _events.length : _events.length.clamp(0, _eventPreviewCount);

  Future<void> _loadTrackRecord() async {
    final record = await PartnerProfileService().loadTrackRecord(
      widget.partnerId,
      excludeIds: _events.map((e) => e.id).toSet(),
    );
    if (!mounted) return;

    // "Known for" reads from everything they've run, upcoming and past, so a
    // brand-new organizer still gets a label off their first listing.
    final keys = PartnerProfileService.categoriesOf([
      ..._events,
      ...record.archive,
    ]);
    List<EventCategoryItem> knownFor = const [];
    if (keys.isNotEmpty) {
      final all = await EventCategoryService().getCategories();
      knownFor = keys
          .map((k) => all.where((c) => c.key == k).firstOrNull)
          .whereType<EventCategoryItem>()
          .toList();
    }

    if (!mounted) return;
    setState(() {
      _record = record;
      _knownFor = knownFor;
    });
  }

  Future<void> _loadStorefront() async {
    try {
      final result = await SupabaseConfig.client.rpc('get_storefront', params: {
        'p_slug': null,
        'p_partner_id': widget.partnerId,
      });
      if (result == null) {
        if (mounted) setState(() => _notFound = true);
        return;
      }
      final data = Map<String, dynamic>.from(result as Map);
      if (!mounted) return;
      setState(() {
        _partner = (data['partner'] as Map?)?.cast<String, dynamic>();
        _counts = (data['counts'] as Map?)?.cast<String, dynamic>() ?? {};
        _events = ((data['upcoming_events'] as List?) ?? [])
            .map((e) => _eventFromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _experiences = ((data['experiences'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _tiers = ((data['subscription_tiers'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });

      // Enrich prices from ticket tiers (ticket_price is unreliable), then
      // rebuild so cards show the correct cheapest/range.
      await EventService().enrichPriceRanges(_events);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('⚠️ get_storefront failed: $e');
    }
  }

  Event _eventFromJson(Map<String, dynamic> e) {
    return Event(
      id: e['id'] as String,
      title: e['title'] as String? ?? 'Event',
      description: e['description'] as String? ?? '',
      venueName: e['venue_name'] as String? ?? '',
      venueAddress: '',
      latitude: 0,
      longitude: 0,
      startDatetime:
          DateTime.tryParse(e['start_datetime'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      endDatetime: e['end_datetime'] != null
          ? DateTime.tryParse(e['end_datetime'] as String)
          : null,
      coverImageUrl: e['cover_image_url'] as String?,
      ticketPrice: (e['ticket_price'] as num?)?.toDouble() ?? 0,
      capacity: (e['capacity'] as num?)?.toInt() ?? 0,
      ticketsSold: (e['tickets_sold'] as num?)?.toInt() ?? 0,
      // Prefer the new taxonomy (events.category); fall back to the legacy
      // event_type enum so older rows still resolve (team_comms #226).
      category: (e['category'] ?? e['event_type']) as String? ?? 'other',
      organizerId: widget.partnerId,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _loadFollowState() async {
    // get_storefront returns follower COUNT but not whether the VIEWER follows.
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await SupabaseConfig.client
          .from('partner_followers')
          .select('id')
          .eq('user_id', userId)
          .eq('partner_id', widget.partnerId)
          .limit(1);
      if (mounted) setState(() => _isFollowing = (rows as List).isNotEmpty);
    } catch (e) {
      debugPrint('⚠️ Error loading follow state: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log in to follow organizers')),
      );
      return;
    }

    final previous = _isFollowing;
    final prevCount = (_counts['followers'] as num?)?.toInt() ?? 0;
    setState(() {
      _isFollowing = !previous; // optimistic
      _counts = {..._counts, 'followers': prevCount + (previous ? -1 : 1)};
      _followBusy = true;
    });

    try {
      final result = await SupabaseConfig.client.rpc(
        'toggle_partner_follow',
        params: {'p_partner_id': widget.partnerId},
      );
      final following = (result as Map)['following'] as bool? ?? !previous;
      if (mounted && following != _isFollowing) {
        setState(() {
          _isFollowing = following;
          _counts = {
            ..._counts,
            'followers': prevCount + (following ? 1 : 0),
          };
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error toggling follow: $e');
      if (mounted) {
        setState(() {
          _isFollowing = previous; // revert
          _counts = {..._counts, 'followers': prevCount};
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update follow. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _openExperience(Map<String, dynamic> exp) async {
    // get_storefront returns a minimal experience shape; the modal needs the
    // full `tables` row (it fetches schedules/reviews by id). Fetch then open.
    try {
      final full = await SupabaseConfig.client
          .from('tables')
          .select()
          .eq('id', exp['id'])
          .maybeSingle();
      if (!mounted) return;
      // Opaque full route (not a bottom sheet) — a sheet strips the top
      // safe-area padding, pushing the close/flag icons under the status bar.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExperienceDetailModal(
            experience: full ?? exp,
            matchData: const {},
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ open experience failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_notFound || _partner == null) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          backgroundColor: scaffoldBg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Text('This page isn\'t available',
              style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }

    final p = _partner!;
    final businessName = p['business_name'] as String? ?? 'Organizer';
    final photoUrl = p['profile_photo_url'] as String?;
    final coverUrl = p['cover_image_url'] as String?;
    final description = p['description'] as String?;
    final verified = p['verified'] as bool? ?? false;
    final slug = p['slug'] as String?;
    final isBrand = p['profile_mode'] == 'brand';
    final subsEnabled = p['subscriptions_enabled'] == true;
    final socialLinks = (p['social_links'] as Map?)?.cast<String, dynamic>() ??
        const {};

    final followers = (_counts['followers'] as num?)?.toInt() ?? 0;
    final subscribers = (_counts['subscribers'] as num?)?.toInt() ?? 0;

    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: scaffoldBg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        // The cover runs to the top of the screen, so the back button needs to
        // carry its own contrast rather than borrow the bar's.
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 17, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x59000000),
              minimumSize: const Size(38, 38),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // Marquee — cover, logo and name as one masthead. The logo is a
          // rounded square rather than a circle: circles read as faces, squares
          // read as brands, and that one substitution is most of why this page
          // stops looking like somebody's profile.
          SliverToBoxAdapter(
            child: _Marquee(
              name: businessName,
              logoUrl: photoUrl,
              coverUrl: coverUrl,
              verified: verified,
              accent: primary,
              isBrand: isBrand,
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // What they programme, read off their own listings rather
                  // than a field they'd have to fill in — so it's true on day
                  // one and stays true as they change what they do.
                  if (_knownFor.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _knownFor
                          .map((c) => _CategoryChip(category: c))
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (description != null && description.isNotEmpty) ...[
                    _ClampedText(text: description),
                    const SizedBox(height: 14),
                  ],

                  _TrackRecordStrip(
                    pastEvents: _record.pastEvents,
                    hostingSince: _record.hostingSince,
                    goingToUpcoming:
                        _events.fold<int>(0, (s, e) => s + e.ticketsSold),
                    followers: followers,
                    subscribers: subsEnabled ? subscribers : 0,
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(child: _buildFollowButton(context)),
                      if (slug != null && slug.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        _ViewFullPageButton(slug: slug),
                      ],
                    ],
                  ),

                  if (socialLinks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _SocialLinksRow(socialLinks: socialLinks, noPadding: true),
                  ],

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),

          // Membership tiers
          if (_tiers.isNotEmpty && slug != null && slug.isNotEmpty) ...[
            _sectionHeaderSliver('Membership'),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _TierCard(tier: _tiers[i], slug: slug),
                childCount: _tiers.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],

          // Upcoming events.
          //
          // Capped, because the spread is extreme: one organizer lists 53 and
          // every other lists two or fewer. Rendering all of them buries
          // everything below — the stamp shelf sat under 53 tiles and was
          // effectively unreachable.
          _sectionHeaderSliver(
              _events.isEmpty ? 'No upcoming events' : 'Next up',
              count: _events.length),
          if (_events.isNotEmpty) ...[
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _StorefrontEventTile(event: _events[i]),
                childCount: _visibleEventCount,
              ),
            ),
            if (_events.length > _eventPreviewCount)
              SliverToBoxAdapter(
                child: _ShowAllEventsButton(
                  total: _events.length,
                  expanded: _showAllEvents,
                  onTap: () =>
                      setState(() => _showAllEvents = !_showAllEvents),
                ),
              ),
          ] else
            SliverToBoxAdapter(child: _buildEmptyEvents(context)),

          // Stamps to collect — directly under the programme, above everything
          // optional, so a long listing can never push it out of reach. Hides
          // itself when the organizer has authored no badges, which today is
          // all but one of them.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: PartnerCollectionShelf(
                partnerId: widget.partnerId,
                partnerName: businessName,
              ),
            ),
          ),

          // Experiences
          if (_experiences.isNotEmpty) ...[
            _sectionHeaderSliver('Experiences', count: _experiences.length),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ExperienceTile(
                  experience: _experiences[i],
                  onTap: () => _openExperience(_experiences[i]),
                ),
                childCount: _experiences.length,
              ),
            ),
          ],

          // What they've already done. For most organizers this is the only
          // evidence on the page that they're real, since "Next up" is often a
          // single listing.
          if (_record.archive.isNotEmpty) ...[
            _sectionHeaderSliver('Previously', count: _record.pastEvents),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _record.archive.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) =>
                      _ArchiveTile(event: _record.archive[i]),
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  Widget _sectionHeaderSliver(String title, {int count = 0}) {
    final primary = Theme.of(context).primaryColor;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyEvents(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded, size: 44, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No upcoming events right now',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Follow to get notified when they post one.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final spinner = SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: _isFollowing ? primary : Colors.white,
      ),
    );

    const pad = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    const labelStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);

    if (_isFollowing) {
      return OutlinedButton.icon(
        onPressed: _toggleFollow,
        icon: _followBusy ? spinner : const Icon(Icons.check_rounded, size: 18),
        label: const Text('Following'),
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          padding: pad,
          shape: const StadiumBorder(),
          textStyle: labelStyle,
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: _toggleFollow,
      icon: _followBusy ? spinner : const Icon(Icons.add_rounded, size: 18),
      label: const Text('Follow'),
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: pad,
        shape: const StadiumBorder(),
        textStyle: labelStyle,
      ),
    );
  }
}

/// Compact outlined pill that opens the web storefront at root-level /<slug>.
class _ViewFullPageButton extends StatelessWidget {
  final String slug;

  const _ViewFullPageButton({required this.slug});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton(
      onPressed: () => launchUrl(
        Uri.parse('${AppConstants.webBaseUrl}/$slug'),
        mode: LaunchMode.externalApplication,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? Colors.white70 : Colors.black87,
        side: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
        padding: const EdgeInsets.all(14),
        shape: const CircleBorder(),
      ),
      child: const Icon(Icons.open_in_new_rounded, size: 18),
    );
  }
}

class _TierCard extends StatelessWidget {
  final Map<String, dynamic> tier;
  final String slug;
  const _TierCard({required this.tier, required this.slug});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final name = tier['name'] as String? ?? 'Membership';
    final description = tier['description'] as String?;
    final price = (tier['price_monthly'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C22) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: primary.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Text(
                  price > 0 ? '₱${price.toStringAsFixed(0)}/mo' : 'Free',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: primary),
                ),
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(description,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                      '${AppConstants.webBaseUrl}/$slug/membership/${tier['id']}'),
                  mode: LaunchMode.externalApplication,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: primary),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Subscribe'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialLinksRow extends StatelessWidget {
  final Map<String, dynamic> socialLinks;
  final bool noPadding;

  const _SocialLinksRow({required this.socialLinks, this.noPadding = false});

  static const _platforms = <String, Map<String, Object>>{
    'instagram': {
      'icon': Icons.camera_alt_outlined,
      'label': 'Instagram',
      'prefix': 'https://instagram.com/',
    },
    'facebook': {
      'icon': Icons.facebook,
      'label': 'Facebook',
      'prefix': 'https://facebook.com/',
    },
    'twitter': {
      'icon': Icons.alternate_email,
      'label': 'Twitter/X',
      'prefix': 'https://x.com/',
    },
    'tiktok': {
      'icon': Icons.music_video_outlined,
      'label': 'TikTok',
      'prefix': 'https://tiktok.com/@',
    },
    'youtube': {
      'icon': Icons.play_circle_outline,
      'label': 'YouTube',
      'prefix': '',
    },
    'website': {
      'icon': Icons.language,
      'label': 'Website',
      'prefix': '',
    },
  };

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    for (final entry in _platforms.entries) {
      final handle = socialLinks[entry.key] as String?;
      if (handle == null || handle.isEmpty) continue;
      final prefix = entry.value['prefix'] as String;
      final url = handle.startsWith('http') ? handle : '$prefix$handle';
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            avatar: Icon(entry.value['icon'] as IconData, size: 16),
            label: Text(
              entry.value['label'] as String,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.06),
            side: BorderSide(
              color: Theme.of(context).primaryColor.withOpacity(0.18),
            ),
            shape: const StadiumBorder(),
            onPressed: () => launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: noPadding
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: chips),
    );
  }
}

class _ExperienceTile extends StatelessWidget {
  final Map<String, dynamic> experience;
  final VoidCallback onTap;

  const _ExperienceTile({required this.experience, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final title = experience['title'] as String? ?? 'Experience';
    final city = experience['city'] as String?;
    final imageUrl = experience['image_url'] as String?;
    final price = (experience['price_per_person'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: isDark ? const Color(0xFF1C1C22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: ImageUrl.capped(imageUrl, 1290),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _ph(primary),
                          )
                        : _ph(primary),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (city != null && city.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                city,
                                style: TextStyle(
                                    fontSize: 12.5, color: Colors.grey[600]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          price > 0
                              ? '₱${price.toStringAsFixed(0)} / person'
                              : 'Free',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ph(Color primary) => Container(
        color: primary.withOpacity(0.10),
        child: Icon(Icons.explore_rounded, color: primary),
      );
}

class _StorefrontEventTile extends StatelessWidget {
  final Event event;

  const _StorefrontEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final isFree = event.displayFromPrice <= 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: isDark ? const Color(0xFF1C1C22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => EventDetailModal.show(context, event),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.0 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: event.coverImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: ImageUrl.capped(event.coverImageUrl!, 1290),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _placeholder(primary),
                          )
                        : _placeholder(primary),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              event.isMultiDay
                                  ? event.dateRangeWithTimeLabel
                                  : DateFormat('EEE, MMM d • h:mm a')
                                        .format(event.startLocal),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isFree
                              ? Colors.green.withOpacity(0.12)
                              : primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isFree ? 'Free' : event.priceLabel(),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isFree ? Colors.green[700] : primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(Color primary) {
    return Container(
      color: primary.withOpacity(0.10),
      child: Icon(Icons.event_rounded, color: primary),
    );
  }
}

/// The masthead: cover, logo, name.
///
/// A person's profile centres a circular avatar because the face is the point.
/// Here the programme is the point, so the cover runs full-bleed and the logo
/// sits in the corner of it as a rounded square — the shape language of a
/// venue's signage rather than someone's headshot.
class _Marquee extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final String? coverUrl;
  final bool verified;
  final Color accent;

  /// `profile_mode`. The page is identical either way — only the mark changes
  /// shape, because a solo organizer's mark is their face and a company's is a
  /// logo, and the two want different frames.
  final bool isBrand;

  const _Marquee({
    required this.name,
    required this.logoUrl,
    required this.coverUrl,
    required this.verified,
    required this.accent,
    required this.isBrand,
  });

  /// Cover band, below the status bar. Short on purpose: this page exists to
  /// show a programme, and every point spent up here is a point the dates
  /// don't get.
  static const double _band = 128;
  static const double _logo = 64;
  static const double _overlap = 30;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final hasCover = coverUrl != null && coverUrl!.isNotEmpty;
    final bandHeight = _band + topInset;

    return SizedBox(
      // Band, minus the part the logo hangs over, plus room for two lines of
      // name beside it.
      height: bandHeight + 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: bandHeight,
            child: hasCover
                ? CachedNetworkImage(
                    imageUrl: ImageUrl.capped(coverUrl!, 1290),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _fallbackGround(),
                    placeholder: (_, __) => _fallbackGround(),
                  )
                : _fallbackGround(),
          ),

          // Guarantees the status bar and back button read over any cover.
          // Top-anchored and short, so it darkens the chrome strip without
          // dimming the artwork — and nothing is set in it, so it can't repeat
          // the collision the overlaid name caused.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: topInset + 46,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0x00000000)],
                ),
              ),
            ),
          ),

          // A cover is artwork, and a lot of them are the organizer's own
          // wordmark. Nothing is written on top of it — the earlier version
          // laid the business name over the band and landed it straight on
          // Hanghut's own logotype. The name lives on solid ground below,
          // where it is also legible in either theme without a scrim.
          Positioned(
            left: 20,
            top: bandHeight - _overlap,
            child: _mark(context),
          ),
          Positioned(
            left: 20 + _logo + 14,
            right: 20,
            top: bandHeight + 2,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.verified, size: 17, color: Colors.blue),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackGround() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.55),
              accent.withValues(alpha: 0.22),
            ],
          ),
        ),
      );

  Widget _mark(BuildContext context) {
    // A full circle for a person, a squircle for a brand.
    final radius = BorderRadius.circular(isBrand ? 17 : _logo / 2);
    final ground = Theme.of(context).scaffoldBackgroundColor;

    return Container(
      width: _logo,
      height: _logo,
      decoration: BoxDecoration(
        borderRadius: radius,
        // Punched out of the page rather than outlined in white, so it reads
        // the same on a dark background.
        color: ground,
        border: Border.all(color: ground, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius.subtract(BorderRadius.circular(3)),
        child: logoUrl != null && logoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: ImageUrl.capped(logoUrl!, 1290),
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _monogram(),
                placeholder: (_, __) => _monogram(),
              )
            : _monogram(),
      ),
    );
  }

  Widget _monogram() => ColoredBox(
        color: accent.withValues(alpha: 0.16),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
      );
}

/// Body copy that opens rather than filling the screen.
///
/// Organizer descriptions are free text and some run long — Hanghut Select's
/// is four paragraphs, which pushed 53 upcoming events below the fold. Three
/// lines is enough to know what the page is; the rest is one tap away.
class _ClampedText extends StatefulWidget {
  final String text;

  const _ClampedText({required this.text});

  /// Three lines is enough to know what the page is.
  static const int _maxLines = 3;

  @override
  State<_ClampedText> createState() => _ClampedTextState();
}

class _ClampedTextState extends State<_ClampedText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = TextStyle(
      fontSize: 14,
      color: isDark ? Colors.grey[300] : Colors.grey[700],
      height: 1.45,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure before deciding: a short description gets no toggle at all.
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _ClampedText._maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : _ClampedText._maxLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text(
                    _expanded ? 'Less' : 'More',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One "known for" tag, from the server-driven category taxonomy.
class _CategoryChip extends StatelessWidget {
  final EventCategoryItem category;

  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category.display,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[300] : Colors.grey[800],
        ),
      ),
    );
  }
}

/// The evidence band: a few hard facts, or nothing at all.
///
/// Adaptive because the honest fact differs by organizer. One with a history
/// leads with it; one whose only show is still ahead has no history to claim,
/// so it leads with how many people are already going. An organizer with
/// neither gets no strip rather than a row of zeroes.
class _TrackRecordStrip extends StatelessWidget {
  final int pastEvents;
  final DateTime? hostingSince;
  final int goingToUpcoming;
  final int followers;
  final int subscribers;

  const _TrackRecordStrip({
    required this.pastEvents,
    required this.hostingSince,
    required this.goingToUpcoming,
    required this.followers,
    required this.subscribers,
  });

  @override
  Widget build(BuildContext context) {
    final facts = <({String value, String label})>[];

    if (pastEvents > 0) {
      facts.add((
        value: '$pastEvents',
        label: pastEvents == 1 ? 'event held' : 'events held',
      ));
    } else if (goingToUpcoming > 0) {
      // No history yet — momentum is the truthful headline instead.
      facts.add((value: _compact(goingToUpcoming), label: 'going'));
    }

    if (followers > 0) {
      facts.add((
        value: _compact(followers),
        label: followers == 1 ? 'follower' : 'followers',
      ));
    }
    if (subscribers > 0) {
      facts.add((value: _compact(subscribers), label: 'subscribers'));
    }
    if (hostingSince != null && facts.length < 3) {
      facts.add((
        value: DateFormat('MMM yyyy').format(hostingSince!),
        label: 'hosting since',
      ));
    }

    if (facts.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.withValues(alpha: 0.25);

    final children = <Widget>[];
    for (var i = 0; i < facts.length; i++) {
      if (i > 0) {
        children.add(Container(width: 1, height: 26, color: divider));
      }
      children.add(Expanded(child: _fact(context, facts[i])));
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: divider),
          bottom: BorderSide(color: divider),
        ),
      ),
      child: Row(children: children),
    );
  }

  Widget _fact(BuildContext context, ({String value, String label}) f) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          f.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            // Digits line up across the columns rather than dancing.
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          f.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

/// A past event — small, so a dozen of them read as a body of work rather than
/// a dozen things to click.
class _ArchiveTile extends StatelessWidget {
  final Event event;

  const _ArchiveTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;

    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 100,
              width: 132,
              child: ColorFiltered(
                // Held slightly back from the live listings above, so "Next up"
                // stays the brighter thing on the page.
                colorFilter: const ColorFilter.matrix(<double>[
                  0.6, 0.3, 0.1, 0, 0,
                  0.2, 0.7, 0.1, 0, 0,
                  0.2, 0.3, 0.5, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: event.coverImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: ImageUrl.capped(event.coverImageUrl!, 1290),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: primary.withValues(alpha: 0.10),
                        ),
                      )
                    : Container(
                        color: primary.withValues(alpha: 0.10),
                        child: Icon(Icons.event_rounded,
                            color: primary.withValues(alpha: 0.6)),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('MMM yyyy').format(event.startLocal),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

/// Opens the rest of a long programme in place.
///
/// In place rather than on a new screen: the events are already loaded, so a
/// push would re-fetch what the page is holding, and it would take the reader
/// away from the stamps and the history they came down here to find.
class _ShowAllEventsButton extends StatelessWidget {
  final int total;
  final bool expanded;
  final VoidCallback onTap;

  const _ShowAllEventsButton({
    required this.total,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Material(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  expanded ? 'Show fewer' : 'Show all $total events',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 19,
                  color: primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
