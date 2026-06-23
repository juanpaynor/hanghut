import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';

class PartnerStorefrontScreen extends StatefulWidget {
  final String partnerId;

  const PartnerStorefrontScreen({super.key, required this.partnerId});

  @override
  State<PartnerStorefrontScreen> createState() =>
      _PartnerStorefrontScreenState();
}

class _PartnerStorefrontScreenState extends State<PartnerStorefrontScreen> {
  Map<String, dynamic>? _partner;
  List<Event> _events = [];
  bool _isLoading = true;
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
    await Future.wait([_loadPartner(), _loadEvents(), _loadFollowState()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadFollowState() async {
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
    setState(() {
      _isFollowing = !previous; // optimistic
      _followBusy = true;
    });

    try {
      final result = await SupabaseConfig.client.rpc(
        'toggle_partner_follow',
        params: {'p_partner_id': widget.partnerId},
      );
      final following = (result as Map)['following'] as bool? ?? !previous;
      if (mounted) setState(() => _isFollowing = following);
    } catch (e) {
      debugPrint('⚠️ Error toggling follow: $e');
      if (mounted) {
        setState(() => _isFollowing = previous); // revert
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update follow. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _loadPartner() async {
    try {
      final response = await SupabaseConfig.client
          .from('partners')
          .select(
            'id, business_name, business_type, profile_photo_url, cover_image_url, description, verified, slug, social_links',
          )
          .eq('id', widget.partnerId)
          .single();
      if (mounted) setState(() => _partner = response);
    } catch (e) {
      debugPrint('⚠️ Error loading partner: $e');
    }
  }

  Future<void> _loadEvents() async {
    try {
      final events = await EventService().getEventsByOrganizer(
        widget.partnerId,
        limit: 20,
      );
      if (mounted) setState(() => _events = events);
    } catch (e) {
      debugPrint('⚠️ Error loading partner events: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final businessName = _partner?['business_name'] as String? ?? 'Organizer';
    final photoUrl = _partner?['profile_photo_url'] as String?;
    final description = _partner?['description'] as String?;
    final verified = _partner?['verified'] as bool? ?? false;
    final slug = _partner?['slug'] as String?;
    final businessType = _partner?['business_type'] as String?;
    final socialLinks =
        (_partner?['social_links'] as Map<String, dynamic>?) ?? {};

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final primary = Theme.of(context).primaryColor;
    final eventCount = _events.length;

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
          // ── PROFILE HEADER ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar — fully visible, soft indigo ring
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

                  // Name + verified
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
                        const Icon(Icons.verified, size: 20, color: Colors.blue),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Subtitle: event count / business type
                  Row(
                    children: [
                      Icon(Icons.event_rounded,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 5),
                      Text(
                        eventCount == 0
                            ? (businessType ?? 'Organizer')
                            : '$eventCount upcoming '
                                '${eventCount == 1 ? 'event' : 'events'}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Action row: Follow (primary) + View full page
                  Row(
                    children: [
                      Expanded(child: _buildFollowButton(context)),
                      if (slug != null && slug.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        _ViewFullPageButton(slug: slug),
                      ],
                    ],
                  ),

                  if (!_isFollowing) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Following also subscribes you to their email updates.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],

                  // Description
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

                  // Social links
                  if (socialLinks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SocialLinksRow(
                      socialLinks: socialLinks,
                      noPadding: true,
                    ),
                  ],

                  const SizedBox(height: 20),
                  Divider(height: 1, color: Colors.grey[200]),
                  const SizedBox(height: 18),

                  // Events header
                  Row(
                    children: [
                      Text(
                        _events.isEmpty
                            ? 'No upcoming events'
                            : 'Upcoming Events',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (eventCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$eventCount',
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
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),

          if (_events.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _StorefrontEventTile(event: _events[index]),
                childCount: _events.length,
              ),
            )
          else
            SliverToBoxAdapter(child: _buildEmptyEvents(context)),

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  Widget _buildEmptyEvents(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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

/// Compact outlined "view full page" pill that opens the web storefront.
class _ViewFullPageButton extends StatelessWidget {
  final String slug;

  const _ViewFullPageButton({required this.slug});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton(
      onPressed: () => launchUrl(
        Uri.parse('https://hanghut.com/$slug'),
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
            backgroundColor:
                Theme.of(context).primaryColor.withOpacity(0.06),
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

class _StorefrontEventTile extends StatelessWidget {
  final Event event;

  const _StorefrontEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final isFree = event.ticketPrice == 0;

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
                                  .format(event.startDatetime),
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
                      // Price pill
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
                          isFree
                              ? 'Free'
                              : '₱${event.ticketPrice.toStringAsFixed(0)}',
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
