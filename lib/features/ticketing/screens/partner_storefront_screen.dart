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
    final coverUrl = _partner?['cover_image_url'] as String?;
    final description = _partner?['description'] as String?;
    final verified = _partner?['verified'] as bool? ?? false;
    final slug = _partner?['slug'] as String?;
    final socialLinks =
        (_partner?['social_links'] as Map<String, dynamic>?) ?? {};

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _buildCoverPlaceholder(businessName),
                    )
                  : _buildCoverPlaceholder(businessName),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar row — floats up over the cover
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Transform.translate(
                    offset: const Offset(0, -24),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 3,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 8),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.deepPurple[100],
                        backgroundImage:
                            photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null
                            ? Text(
                                businessName.isNotEmpty
                                    ? businessName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),

                // Name + verified + follow button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                businessName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (verified) ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.verified,
                                  size: 18, color: Colors.blue),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildFollowButton(context),
                    ],
                  ),
                ),

                // Follow disclosure
                if (!_isFollowing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Text(
                      'Following also subscribes you to their email updates.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),

                // Description
                if (description != null && description.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Social links
                if (socialLinks.isNotEmpty) ...[
                  _SocialLinksRow(socialLinks: socialLinks),
                  const SizedBox(height: 16),
                ],

                // View full page button
                if (slug != null && slug.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://hanghut.com/$slug'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('View full page'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                const Divider(height: 1),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Text(
                    _events.isEmpty ? 'No upcoming events' : 'Upcoming Events',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_events.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _StorefrontEventTile(event: _events[index]),
                childCount: _events.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
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

    if (_isFollowing) {
      return OutlinedButton.icon(
        onPressed: _toggleFollow,
        icon: _followBusy ? spinner : const Icon(Icons.check, size: 16),
        label: const Text('Following'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: primary,
          side: BorderSide(color: primary),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: _toggleFollow,
      icon: _followBusy ? spinner : const Icon(Icons.add, size: 16),
      label: const Text('Follow'),
      style: ElevatedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }

  Widget _buildCoverPlaceholder(String name) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.6),
          ],
        ),
      ),
      child: Stack(
        children: [
          // subtle pattern overlay
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                ),
                itemBuilder: (_, __) => const Icon(
                  Icons.circle,
                  color: Colors.white,
                  size: 8,
                ),
              ),
            ),
          ),
          // organizer initials — smaller, bottom-left
          Positioned(
            left: 20,
            bottom: 36,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 80,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialLinksRow extends StatelessWidget {
  final Map<String, dynamic> socialLinks;

  const _SocialLinksRow({required this.socialLinks});

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
              style: const TextStyle(fontSize: 12),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: chips),
    );
  }
}

class _StorefrontEventTile extends StatelessWidget {
  final Event event;

  const _StorefrontEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => EventDetailModal.show(context, event),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ??
                Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: event.coverImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: event.coverImageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEE, MMM d • h:mm a').format(event.startDatetime),
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.ticketPrice == 0
                        ? 'Free'
                        : '₱${event.ticketPrice.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: event.ticketPrice == 0
                          ? Colors.green[700]
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.deepPurple[50],
      child: const Icon(Icons.event, color: Colors.deepPurple),
    );
  }
}
