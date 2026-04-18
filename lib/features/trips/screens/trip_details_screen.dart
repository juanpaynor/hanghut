import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/trip_service.dart';
import 'package:bitemates/core/services/analytics_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/trips/screens/trip_matches_screen.dart';

// Curated city→Unsplash photo IDs so images always load reliably
const _cityImages = {
  'paris': 'photo-1502602898657-3e91760cbb34',
  'tokyo': 'photo-1540959733332-eab4deabeeaf',
  'new york': 'photo-1490644658840-3f2e3f8c5625',
  'london': 'photo-1486325212027-8081e485255e',
  'barcelona': 'photo-1539037116277-4db20889f2d4',
  'rome': 'photo-1552832230-c0197dd311b5',
  'bali': 'photo-1537996194471-e657df975ab4',
  'bangkok': 'photo-1508009603885-50cf7c579365',
  'singapore': 'photo-1525625293386-3f8f99389edd',
  'dubai': 'photo-1512453979798-5ea266f8880c',
  'manila': 'photo-1567591370429-53d04f3f3cf0',
  'cebu': 'photo-1518548419970-58e3b4079ab2',
};

String _headerImageUrl(String city) {
  final key = city.toLowerCase().trim();
  final photoId = _cityImages[key];
  if (photoId != null) {
    return 'https://images.unsplash.com/$photoId?q=80&w=800&auto=format&fit=crop';
  }
  // Fallback: generic travel image
  return 'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?q=80&w=800&auto=format&fit=crop';
}

class TripDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  final _tripService = TripService();
  List<Map<String, dynamic>> _matches = [];
  bool _isLoadingMatches = true;
  bool _isJoiningChat = false;

  Map<String, dynamic>? _ownerProfile;
  // ignore: unused_field
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOwnerProfile();
    _loadMatches();
  }

  Future<void> _loadOwnerProfile() async {
    try {
      final ownerId = widget.trip['user_id'];
      if (ownerId != null) {
        final profile = await SupabaseConfig.client
            .from('users')
            .select('display_name, avatar_url, bio, user_photos(photo_url)')
            .eq('id', ownerId)
            .maybeSingle();

        if (mounted) {
          setState(() {
            _ownerProfile = profile;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _getAvatarUrl() {
    if (_ownerProfile == null) return null;

    final photos = _ownerProfile!['user_photos'] as List?;
    if (photos != null && photos.isNotEmpty) {
      // Find primary or first
      // Assuming sorting or primary flag, but for now take first
      return photos[0]['photo_url']?.toString();
    }

    final avatar = _ownerProfile!['avatar_url']?.toString();
    if (avatar != null && avatar.isNotEmpty) return avatar;

    return null;
  }

  Future<void> _loadMatches() async {
    final matches = await _tripService.getTripMatches(widget.trip['id']);
    if (mounted) {
      setState(() {
        _matches = matches;
        _isLoadingMatches = false;
      });
    }
  }

  Future<void> _joinGroupChat() async {
    setState(() => _isJoiningChat = true);
    final chatInfo = await _tripService.joinTripGroupChat(widget.trip['id']);

    if (mounted && chatInfo != null) {
      setState(() {
        _isJoiningChat = false;
      });

      AnalyticsService().logJoinTripChat(chatInfo['chatId']);
      // Deriving a title like "Tokyo Chat"
      final title = '${widget.trip['destination_city']} Travelers';

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        builder: (context) => ChatScreen(
          tableId: chatInfo['chatId'], // Actual Trip Chat UUID
          tableTitle: title,
          channelId: chatInfo['channelId'], // Ably Channel ID
          chatType: 'trip',
        ),
      );
    } else {
      if (mounted) setState(() => _isJoiningChat = false);
    }
  }

  Future<void> _deleteTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip?'),
        content: const Text(
          'Are you sure you want to delete this trip? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _tripService.deleteTrip(widget.trip['id']);
      if (success && mounted) {
        Navigator.pop(context); // Return to previous screen
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to delete trip')));
      }
    }
  }

  Future<void> _editTrip() async {
    final trip = widget.trip;
    final descController = TextEditingController(
      text: trip['description'] ?? '',
    );
    final currentStyle = trip['travel_style'] ?? 'moderate';
    String selectedStyle = currentStyle;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit Trip',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Travel Style',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['budget', 'moderate', 'luxury'].map((s) {
                      final labels = {
                        'budget': '💰 Budget',
                        'moderate': '🎯 Moderate',
                        'luxury': '✨ Luxury',
                      };
                      return ChoiceChip(
                        label: Text(labels[s]!),
                        selected: selectedStyle == s,
                        onSelected: (_) => setModal(() => selectedStyle = s),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final ok = await _tripService.updateTrip(trip['id'], {
                          'travel_style': selectedStyle,
                          'description': descController.text.trim().isEmpty
                              ? null
                              : descController.text.trim(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (ok && mounted) {
                          setState(() {
                            widget.trip['travel_style'] = selectedStyle;
                            widget.trip['description'] =
                                descController.text.trim().isEmpty
                                ? null
                                : descController.text.trim();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Trip updated!')),
                          );
                        }
                      },
                      child: const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final startDate = DateTime.parse(widget.trip['start_date']);
    final endDate = DateTime.parse(widget.trip['end_date']);
    final city = widget.trip['destination_city'] as String? ?? '';
    final country = widget.trip['destination_country'] as String? ?? '';
    final isOwner =
        widget.trip['user_id'] == SupabaseConfig.client.auth.currentUser?.id;
    final interests = (widget.trip['interests'] as List?)?.cast<String>() ?? [];
    final goals = (widget.trip['goals'] as List?)?.cast<String>() ?? [];
    final style = widget.trip['travel_style'] as String?;
    final description = widget.trip['description'] as String?;

    final theme = Theme.of(context);

    final styleLabels = {
      'budget': '💰 Budget',
      'moderate': '🎯 Moderate',
      'luxury': '✨ Luxury',
    };

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ── Collapsing header ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            foregroundColor: theme.colorScheme.onSurface,
            actions: [
              if (isOwner) ...[
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  onPressed: _editTrip,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _deleteTrip,
                ),
              ],
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '$city, $country',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    _headerImageUrl(city),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey[800]),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Date badge ────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC107),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${DateFormat('MMM d').format(startDate)} – ${DateFormat('MMM d, yyyy').format(endDate)}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Duration
                  Text(
                    '${endDate.difference(startDate).inDays + 1} days',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Owner card ────────────────────────────────────────
                  if (_ownerProfile != null)
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserProfileScreen(userId: widget.trip['user_id']),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundImage: _getAvatarUrl() != null
                                  ? NetworkImage(_getAvatarUrl()!)
                                  : null,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              child: _getAvatarUrl() == null
                                  ? Text(
                                      (_ownerProfile!['display_name'] ?? 'U')[0]
                                          .toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _ownerProfile!['display_name'] ??
                                        'Traveler',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  if (_ownerProfile!['bio'] != null &&
                                      (_ownerProfile!['bio'] as String)
                                          .isNotEmpty)
                                    Text(
                                      _ownerProfile!['bio'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // ── Trip details chips ────────────────────────────────
                  if (style != null) ...[
                    _sectionLabel(context, 'Travel Style'),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(styleLabels[style] ?? style),
                      backgroundColor: theme.colorScheme.primaryContainer,
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (interests.isNotEmpty) ...[
                    _sectionLabel(context, 'Interests'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: interests
                          .map(
                            (i) => Chip(
                              label: Text(i.replaceAll('_', ' ')),
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface,
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (goals.isNotEmpty) ...[
                    _sectionLabel(context, 'Goals'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: goals
                          .map(
                            (g) => Chip(
                              label: Text(g.replaceAll('_', ' ')),
                              backgroundColor:
                                  theme.colorScheme.tertiaryContainer,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onTertiaryContainer,
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (description != null && description.isNotEmpty) ...[
                    _sectionLabel(context, 'About this trip'),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 4),

                  // ── Join Chat button ──────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isJoiningChat ? null : _joinGroupChat,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                      icon: _isJoiningChat
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.chat_bubble_outline),
                      label: Text(
                        _isJoiningChat
                            ? 'Connecting...'
                            : 'Join $city Group Chat',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Also in Town ──────────────────────────────────────
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TripMatchesScreen(trip: widget.trip),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            'Also in Town',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const Spacer(),
                          if (_matches.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_matches.length} ${_matches.length == 1 ? 'traveler' : 'travelers'}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.primaryColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (_isLoadingMatches)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_matches.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.flight_takeoff,
                            size: 36,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No other travelers yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Be the first to say hi in the chat!',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _matches.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, i) {
                          final m = _matches[i];
                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    UserProfileScreen(userId: m['user_id']),
                              ),
                            ),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundImage: m['avatar_url'] != null
                                      ? NetworkImage(m['avatar_url'])
                                      : null,
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: m['avatar_url'] == null
                                      ? Icon(
                                          Icons.person,
                                          size: 28,
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.4),
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (m['display_name'] ?? 'User')
                                      .toString()
                                      .split(' ')
                                      .first,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  '${m['overlap_days']}d overlap',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        letterSpacing: 0.5,
      ),
    );
  }
}
