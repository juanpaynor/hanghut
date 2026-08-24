import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/constants/app_constants.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';

/// The organizer's brand/sell page. Powered by the single `get_storefront` RPC
/// (team_comms #220): partner, follower/subscriber counts, upcoming events,
/// experiences, and subscription tiers — one call. `profile_mode` ('person' |
/// 'brand') drives presentation (brands get a cover banner).
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

  bool _isLoading = true;
  bool _notFound = false;
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

  String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final showCover = isBrand && coverUrl != null && coverUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: scaffoldBg,
        surfaceTintColor: scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // Brand cover banner
          if (showCover)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: CachedNetworkImage(
                    imageUrl: coverUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      height: 150,
                      color: primary.withOpacity(0.08),
                    ),
                  ),
                ),
              ),
            ),

          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primary.withOpacity(0.5),
                          primary.withOpacity(0.15),
                        ],
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scaffoldBg,
                      ),
                      child: CircleAvatar(
                        radius: 42,
                        backgroundColor: primary.withOpacity(0.12),
                        backgroundImage:
                            photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null
                            ? Text(
                                businessName.isNotEmpty
                                    ? businessName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: primary,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          businessName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified,
                            size: 20, color: Colors.blue),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Follower / subscriber counts
                  Row(
                    children: [
                      _CountStat(
                          value: _fmtCount(followers), label: 'followers'),
                      if (subsEnabled || subscribers > 0) ...[
                        const SizedBox(width: 20),
                        _CountStat(
                            value: _fmtCount(subscribers),
                            label: 'subscribers'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(child: _buildFollowButton(context)),
                      if (slug != null && slug.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        _ViewFullPageButton(slug: slug),
                      ],
                    ],
                  ),

                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                  ],

                  if (socialLinks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SocialLinksRow(socialLinks: socialLinks, noPadding: true),
                  ],

                  const SizedBox(height: 20),
                  Divider(height: 1, color: Colors.grey[200]),
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

          // Upcoming events
          _sectionHeaderSliver(
              _events.isEmpty ? 'No upcoming events' : 'Upcoming Events',
              count: _events.length),
          if (_events.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _StorefrontEventTile(event: _events[i]),
                childCount: _events.length,
              ),
            )
          else
            SliverToBoxAdapter(child: _buildEmptyEvents(context)),

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

class _CountStat extends StatelessWidget {
  final String value;
  final String label;
  const _CountStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600])),
      ],
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
                            imageUrl: imageUrl,
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
                            imageUrl: event.coverImageUrl!,
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
                              DateFormat('EEE, MMM d • h:mm a')
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
