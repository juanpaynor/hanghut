import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/core/services/event_analytics_service.dart';
import 'package:bitemates/features/sharing/models/share_payload.dart';
import 'package:bitemates/features/sharing/widgets/share_to_chat_sheet.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/ticketing/models/ticket_tier.dart';
import 'package:bitemates/features/ticketing/screens/event_purchase_screen.dart';
import 'package:bitemates/features/ticketing/screens/partner_storefront_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/features/shared/widgets/friends_going_row.dart';
import 'package:bitemates/features/settings/widgets/report_modal.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class EventDetailModal extends StatefulWidget {
  final Event event;

  const EventDetailModal({super.key, required this.event});

  static void show(BuildContext context, Event event) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventDetailModal(event: event)),
    );
  }

  @override
  State<EventDetailModal> createState() => _EventDetailModalState();
}

class _EventDetailModalState extends State<EventDetailModal> {
  bool _isExpanded = false;
  bool _isSoldOut = false;
  bool _isLoadingTiers = true;
  // Active-tier price range (fresh from DB on open) — source of truth for price.
  double? _minTierPrice;
  double? _maxTierPrice;
  int _tierCount = 0;
  String? _organizerDisplayName;
  String? _organizerAvatarUrl;
  bool _userHasTicket = false;
  List<Event> _moreEvents = [];
  Map<String, dynamic>? _subscriberDiscount;

  @override
  void initState() {
    super.initState();
    // Provenance: record an app-side event view (deduped once per session).
    EventAnalyticsService.instance.logView(widget.event.id);
    _fetchAvailability();
    _fetchOrganizerInfo();
    _loadMoreEvents();
    _loadSubscriberDiscount();
    if (widget.event.hideVenueUntilRegistered) _checkUserTicket();
  }

  Future<void> _loadSubscriberDiscount() async {
    if (SupabaseConfig.client.auth.currentUser == null) return;
    try {
      final result = await SupabaseConfig.client.rpc(
        'get_subscriber_event_discount',
        params: {'p_event_id': widget.event.id},
      );
      if (mounted && result != null) {
        setState(() {
          _subscriberDiscount = Map<String, dynamic>.from(result as Map);
        });
      }
    } catch (e) {
      debugPrint('⚠️ Subscriber discount load failed: $e');
    }
  }

  Future<void> _loadMoreEvents() async {
    if (!widget.event.hasOrganizer) return;
    try {
      final events = await EventService().getEventsByOrganizer(
        widget.event.organizerId,
        excludeEventId: widget.event.id,
        limit: 5,
      );
      if (mounted) setState(() => _moreEvents = events);
    } catch (e) {
      debugPrint('⚠️ Could not load more events: $e');
    }
  }

  Future<void> _checkUserTicket() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;
      final result = await SupabaseConfig.client
          .from('tickets')
          .select('id')
          .eq('event_id', widget.event.id)
          .eq('user_id', userId)
          .inFilter('status', ['valid', 'approved', 'used'])
          .limit(1)
          .maybeSingle();
      if (mounted) setState(() => _userHasTicket = result != null);
    } catch (e) {
      print('⚠️ Could not check ticket status: $e');
    }
  }

  Future<void> _fetchOrganizerInfo() async {
    if (!widget.event.hasOrganizer) return;
    try {
      final response = await SupabaseConfig.client
          .from('partners')
          .select(
            'business_name, profile_photo_url, verified, user_id, users!user_id (display_name, avatar_url)',
          )
          .eq('id', widget.event.organizerId)
          .maybeSingle();

      if (response != null && mounted) {
        // Use partner business name, or fall back to linked user's display name
        final userData = response['users'] as Map<String, dynamic>?;
        setState(() {
          _organizerDisplayName =
              response['business_name'] as String? ??
              userData?['display_name'] as String?;
          _organizerAvatarUrl =
              response['profile_photo_url'] as String? ??
              userData?['avatar_url'] as String?;
        });
      }
    } catch (e) {
      print('⚠️ Could not fetch organizer info: $e');
    }
  }

  Future<void> _fetchAvailability() async {
    try {
      // Count ACTUAL sold tickets via RPC (bypasses RLS on tickets table)
      // events.tickets_sold is stale and unreliable per web team guidance
      final int actualSold = await SupabaseConfig.client.rpc(
        'get_event_sold_count',
        params: {'p_event_id': widget.event.id},
      );

      final int capacity = widget.event.capacity;
      final bool eventSoldOut = actualSold >= capacity;

      // Also check ticket tiers
      final tierResponse = await SupabaseConfig.client
          .from('ticket_tiers')
          .select()
          .eq('event_id', widget.event.id)
          .eq('is_active', true);

      final tiers = (tierResponse as List)
          .map((json) => TicketTier.fromJson(json))
          .toList();

      final bool allTiersSoldOut =
          tiers.isNotEmpty && tiers.every((t) => t.isSoldOut);

      // Freshly-fetched tier prices are the source of truth for the price
      // display (events.ticket_price is NOT kept in sync with tier edits).
      if (tiers.isNotEmpty) {
        final prices = tiers.map((t) => t.price).toList()..sort();
        _minTierPrice = prices.first;
        _maxTierPrice = prices.last;
        _tierCount = tiers.length;
      }

      if (mounted) {
        setState(() {
          _isSoldOut = eventSoldOut || allTiersSoldOut;
          _isLoadingTiers = false;
        });
      }
    } catch (e) {
      print('🎟️ ERROR fetching availability: $e');
      if (mounted) setState(() => _isLoadingTiers = false);
    }
  }

  // Category design configurations
  static const Map<String, Map<String, dynamic>> categoryDesigns = {
    'concert': {
      'gradient': [Color(0xFF6200EA), Color(0xFF9D46FF)],
      'icon': Icons.music_note,
      'emoji': '🎵',
    },
    'sports': {
      'gradient': [Color(0xFFFF6D00), Color(0xFFFF9E40)],
      'icon': Icons.sports_soccer,
      'emoji': '⚽',
    },
    'workshop': {
      'gradient': [Color(0xFF00C853), Color(0xFF69F0AE)],
      'icon': Icons.school,
      'emoji': '📚',
    },
    'food': {
      'gradient': [Color(0xFFD50000), Color(0xFFFF5252)],
      'icon': Icons.restaurant,
      'emoji': '🍽️',
    },
    'nightlife': {
      'gradient': [Color(0xFF2962FF), Color(0xFF448AFF)],
      'icon': Icons.nightlife,
      'emoji': '🎉',
    },
    'art': {
      'gradient': [Color(0xFFAA00FF), Color(0xFFE040FB)],
      'icon': Icons.palette,
      'emoji': '🎨',
    },
  };

  @override
  Widget build(BuildContext context) {
    final categoryConfig =
        categoryDesigns[widget.event.category] ?? categoryDesigns['concert']!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: _buildBuyButton(),
        ),
      ),
      body: Stack(
        children: [
          // Hero scrolls away with the content (not pinned).
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroImage(categoryConfig),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Invite Only badge for hidden events
                  if (widget.event.isHidden) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.deepPurple.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: Colors.deepPurple,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Invite Only',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Title now lives over the hero image.
                  const SizedBox(height: 4),

                  // At-a-glance: date · venue · price grouped in one card
                  _buildInfoCard(),

                  // Friends Going
                  if (!widget.event.isExternal) ...[
                    const SizedBox(height: 4),
                    FriendsGoingRow(
                      entityType: 'event',
                      entityId: widget.event.id,
                    ),
                  ],

                  const SizedBox(height: 20),

                  // About (the actual event content — before any cross-sell)
                  _buildAboutSection(),

                  // Additional Images
                  _buildImageGallery(),

                  const SizedBox(height: 20),

                  // Organizer — compact one-liner
                  _buildOrganizerInline(),

                  // More from this organizer — quiet, at the very bottom
                  _buildMoreFromOrganizer(),

                  const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Fixed top nav (back/share/report) — stays put while the hero
          // image scrolls away.
          _buildTopActions(),
        ],
      ),
    );
  }

  Widget _buildTopActions() {
    final top = MediaQuery.of(context).padding.top + 8;
    Widget circleBtn({
      required IconData icon,
      required Color iconColor,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      );
    }

    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: Row(
        children: [
          circleBtn(
            icon: Icons.arrow_back,
            iconColor: Colors.black87,
            onTap: () => Navigator.pop(context),
          ),
          const Spacer(),
          circleBtn(
            icon: Icons.share,
            iconColor: Colors.black87,
            onTap: _onShare,
          ),
          const SizedBox(width: 8),
          circleBtn(
            icon: Icons.flag_outlined,
            iconColor: Colors.grey,
            onTap: () => ReportModal.show(
              context,
              targetType: 'post',
              targetId: widget.event.id,
              targetName: widget.event.title,
            ),
          ),
        ],
      ),
    );
  }

  /// Nebula hero — the event's cover cropped to an immersive full-bleed panel,
  /// with a category-gradient ambient base, a scrim that fades the photo into
  /// the page, the category pill, the title, and a live countdown, all layered
  /// over the image. Pure Dart (patchable) — no image analysis, no new package.
  Widget _buildHeroImage(Map<String, dynamic> categoryConfig) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final gradientColors = categoryConfig['gradient'] as List<Color>;
    final screenH = MediaQuery.of(context).size.height;
    final heroH = (screenH * 0.62).clamp(380.0, 560.0);
    final topInset = MediaQuery.of(context).padding.top;

    final allImages = [
      if (widget.event.coverImageUrl != null) widget.event.coverImageUrl!,
      ...widget.event.imageUrls,
    ];

    final venueLocked =
        widget.event.hideVenueUntilRegistered && !_userHasTicket;
    final dateStr =
        DateFormat('EEE, MMM d · h:mm a').format(widget.event.startLocal);
    final subtitle = (venueLocked || widget.event.venueName.isEmpty)
        ? dateStr
        : '$dateStr  ·  ${widget.event.venueName}';

    return GestureDetector(
      onTap: allImages.isNotEmpty ? () => _openImageViewer(allImages, 0) : null,
      child: SizedBox(
        height: heroH,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Ambient base — category gradient (shown while loading / behind
            // any transparency), so the hero is never a blank rectangle.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
            ),

            // The cover photo, cropped to fill the immersive panel.
            if (widget.event.coverImageUrl != null)
              CachedNetworkImage(
                imageUrl: widget.event.coverImageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _buildFallbackGradient(categoryConfig),
                errorWidget: (_, __, ___) =>
                    _buildFallbackGradient(categoryConfig),
              )
            else
              _buildFallbackGradient(categoryConfig),

            // Top scrim — keeps the white nav buttons legible over bright art.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topInset + 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                  ),
                ),
              ),
            ),

            // Bottom scrim — darkens behind the text and fades the photo into
            // the page background for a seamless hand-off to the content.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.65),
                      pageBg,
                    ],
                    stops: const [0.32, 0.78, 1.0],
                  ),
                ),
              ),
            ),

            // Overlay content: pill · title · when/where · countdown.
            Positioned(
              left: 20,
              right: 20,
              bottom: 30,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category pill (gradient accent — the one bold note).
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: AppTheme.brandGradient,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          categoryConfig['emoji'] as String,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.event.category
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Title — big, bold, over the image.
                  Text(
                    widget.event.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 18,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // When · where
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Live countdown to doors — hides itself once the event starts.
                  _CountdownRow(target: widget.event.startLocal),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openImageViewer(List<String> images, int startIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) =>
          _ImageViewerDialog(images: images, initialIndex: startIndex),
    );
  }

  Widget _buildImageGallery() {
    final extras = widget.event.imageUrls;
    if (extras.isEmpty) return const SizedBox.shrink();

    final allImages = [
      if (widget.event.coverImageUrl != null) widget.event.coverImageUrl!,
      ...extras,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Photos',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: extras.length,
            itemBuilder: (context, i) {
              final imgUrl = extras[i];
              final viewerIndex = widget.event.coverImageUrl != null
                  ? i + 1
                  : i;
              return GestureDetector(
                onTap: () => _openImageViewer(allImages, viewerIndex),
                child: Container(
                  width: 90,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey[200],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CachedNetworkImage(
                    imageUrl: imgUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.grey[200]),
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackGradient(Map<String, dynamic> categoryConfig) {
    final gradientColors = categoryConfig['gradient'] as List<Color>;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              categoryConfig['emoji'] as String,
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 8),
            Text(
              widget.event.category.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Grouped "at a glance" card: date · venue · price+availability as three
  /// clean rows in a single container (replaces the old scattered boxes).
  Widget _buildInfoCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final venueLocked =
        widget.event.hideVenueUntilRegistered && !_userHasTicket;
    final divider = Divider(
      height: 20,
      thickness: 1,
      color: isDark ? Colors.grey[800] : Colors.grey[200],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          _infoRow(
            Icons.calendar_today_rounded,
            DateFormat('EEEE, MMM d  •  h:mm a')
                .format(widget.event.startLocal),
          ),
          divider,
          _infoRow(
            venueLocked ? Icons.lock_outline_rounded : Icons.location_on_rounded,
            venueLocked ? 'Register to see venue' : widget.event.venueName,
            muted: venueLocked,
            // Tap the venue to fly the map there — but only when the venue is
            // actually shown (not register-to-see) and has real coordinates.
            onTap: (venueLocked || !_hasVenueCoords) ? null : _flyToVenue,
          ),
          divider,
          _buildPriceInfoRow(isDark),
        ],
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String text, {
    bool muted = false,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final row = Row(
      children: [
        Icon(icon, size: 18, color: isDark ? Colors.grey[400] : Colors.grey[700]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted
                  ? Colors.grey[500]
                  : (isDark ? Colors.grey[100] : Colors.grey[900]),
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              fontStyle: muted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
        // Affordance so users know the venue is tappable → opens the map.
        if (onTap != null) ...[
          const SizedBox(width: 8),
          Text(
            'Map',
            style: TextStyle(
              color: primary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.map_outlined, size: 16, color: primary),
        ],
      ],
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }

  bool get _hasVenueCoords =>
      widget.event.latitude != 0 || widget.event.longitude != 0;

  /// Close the event detail and fly the map to the venue.
  void _flyToVenue() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigationScreen(
          initialIndex: 0,
          flyToLat: widget.event.latitude,
          flyToLng: widget.event.longitude,
        ),
      ),
      (route) => false,
    );
  }

  /// The price to show, derived from the freshly-fetched active tiers when the
  /// event has them (a range, or "From ₱min" for many), else the event's single
  /// ticketPrice. Tiers are the source of truth since events.ticket_price isn't
  /// kept in sync with tier edits on the dashboard.
  String get _priceText {
    if (_tierCount > 0 && _minTierPrice != null) {
      final min = _minTierPrice!;
      final max = _maxTierPrice ?? min;
      if (min <= 0 && max <= 0) return 'Free';
      if (max > min) return '₱${min.toStringAsFixed(0)} – ₱${max.toStringAsFixed(0)}';
      return '₱${min.toStringAsFixed(0)}';
    }
    final p = widget.event.ticketPrice;
    if (p <= 0) return 'Free';
    return widget.event.isExternal
        ? 'From ₱${p.toStringAsFixed(0)}'
        : '₱${p.toStringAsFixed(0)}';
  }

  /// Price row within the info card — preserves subscriber-discount, external
  /// "From ₱", availability, and external-provider styling.
  Widget _buildPriceInfoRow(bool isDark) {
    final hasDiscount = _subscriberDiscount?['has_discount'] == true;
    final discountedPrice = hasDiscount
        ? (_subscriberDiscount!['discounted_price'] as num).toDouble()
        : null;
    final originalPrice = widget.event.ticketPrice;
    final priceColor = isDark ? Colors.white : Colors.black87;

    return Row(
      children: [
        Icon(Icons.confirmation_number_rounded,
            size: 18, color: isDark ? Colors.grey[400] : Colors.grey[700]),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (hasDiscount) ...[
                Text('₱${discountedPrice!.toStringAsFixed(0)}',
                    style: TextStyle(color: priceColor, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text('₱${originalPrice.toStringAsFixed(0)}',
                    style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                        decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 6),
                const Icon(Icons.workspace_premium_rounded, size: 16, color: Color(0xFFFFD700)),
              ] else
                Text(
                  _priceText,
                  style: TextStyle(color: priceColor, fontSize: 20, fontWeight: FontWeight.w800),
                ),
            ],
          ),
        ),
        if (!widget.event.isExternal)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (_isSoldOut ? Colors.red : Colors.green).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isSoldOut ? 'Sold Out' : 'Available',
              style: TextStyle(
                color: _isSoldOut ? Colors.red : Colors.green[700],
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else if (widget.event.externalProviderName != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.open_in_new, size: 12, color: Colors.blue),
                const SizedBox(width: 4),
                Text(widget.event.externalProviderName!,
                    style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMoreFromOrganizer() {
    if (_moreEvents.isEmpty) return const SizedBox.shrink();

    final displayName =
        widget.event.organizerName ?? _organizerDisplayName ?? 'organizer';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Divider(
          height: 1,
          thickness: 1,
          color: isDark ? Colors.grey[850] : Colors.grey[200],
        ),
        const SizedBox(height: 16),
        // Quiet secondary header — a footnote cross-sell, not a primary section.
        Text(
          'More events by $displayName',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _moreEvents.length,
            itemBuilder: (ctx, i) {
              final e = _moreEvents[i];
              return _OrganizerEventCard(
                event: e,
                onTap: () => EventDetailModal.show(context, e),
              );
            },
          ),
        ),
      ],
    );
  }

  /// About section: a header + the (expandable) description. Hidden entirely
  /// when the event has no description.
  Widget _buildAboutSection() {
    final hasHtml = widget.event.descriptionHtml?.trim().isNotEmpty ?? false;
    if (widget.event.description.isEmpty && !hasHtml) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        _buildDescription(),
      ],
    );
  }

  /// Compact one-line organizer row ("Hosted by X ✓ ›") — replaces the old
  /// boxed card that competed with the primary content mid-scroll.
  Widget _buildOrganizerInline() {
    final displayName = widget.event.organizerName ??
        _organizerDisplayName ??
        'Event Organizer';
    final photoUrl = widget.event.organizerPhotoUrl ?? _organizerAvatarUrl;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasOrganizer = widget.event.hasOrganizer;

    return GestureDetector(
      onTap: hasOrganizer
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartnerStorefrontScreen(
                    partnerId: widget.event.organizerId,
                  ),
                ),
              )
          : null,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            backgroundColor: Colors.grey[300],
            child: photoUrl == null
                ? const Icon(Icons.business, color: Colors.white, size: 16)
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            'Hosted by ',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          Flexible(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.event.organizerVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, size: 15, color: Colors.blue),
          ],
          if (hasOrganizer)
            Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    final html = widget.event.descriptionHtml?.trim() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    // Preferred path: render the web-authored rich description (paragraphs,
    // bold, bullets, and tappable hyperlinks). The plain `description` is a
    // tag-stripped copy that loses formatting AND links, so we only use it as a
    // fallback when there's no html.
    if (html.isNotEmpty) {
      // Collapse tall descriptions behind a "See more"; clip by height since
      // HtmlWidget has no maxLines.
      final needsToggle = html.length > 220;
      final content = HtmlWidget(
        html,
        textStyle: TextStyle(color: textColor, fontSize: 14, height: 1.5),
        onTapUrl: _openDescriptionUrl,
      );

      final collapsed = needsToggle && !_isExpanded;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            // When collapsed, clip to a fixed window while letting the HtmlWidget
            // lay out at its natural (unbounded) height via OverflowBox —
            // constraining its height directly overflows its internal Column.
            child: collapsed
                ? ClipRect(
                    child: SizedBox(
                      height: 78,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: content,
                      ),
                    ),
                  )
                : content,
          ),
          if (needsToggle)
            TextButton(
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
              ),
              child: Text(
                _isExpanded ? 'Show less' : 'See more',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    }

    // Fallback: plain text. Normalize CRLF/CR to LF so any line breaks render,
    // and collapse 3+ blank lines into a single blank line.
    if (widget.event.description.isEmpty) return const SizedBox.shrink();
    final description = widget.event.description
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
          maxLines: _isExpanded ? null : 3,
          overflow: _isExpanded ? null : TextOverflow.ellipsis,
        ),
        if (description.length > 150)
          TextButton(
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              _isExpanded ? 'Show less' : 'See more',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  /// Opens links tapped inside the rich description. Only http/https/mailto/tel
  /// are allowed — anything else (e.g. javascript:) is ignored.
  Future<bool> _openDescriptionUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    const allowed = {'http', 'https', 'mailto', 'tel'};
    if (!allowed.contains(uri.scheme)) return false;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _buildBuyButton() {
    // External events: always active, different label
    if (widget.event.isExternal) {
      final providerName = widget.event.externalProviderName;
      final label = providerName != null
          ? 'Get Tickets on $providerName'
          : 'Get Tickets';

      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _onBuyTickets,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    // Price shown on the button so it stays visible after the user scrolls
    // past the info card. Uses the tier-derived "from" price, not ticket_price.
    final hasDiscount = _subscriberDiscount?['has_discount'] == true;
    final price = hasDiscount
        ? (_subscriberDiscount!['discounted_price'] as num).toDouble()
        : widget.event.displayFromPrice;
    final priceLabel = price <= 0 ? '' : '  ·  ₱${price.toStringAsFixed(0)}';
    final label = _isSoldOut
        ? 'Sold Out'
        : price <= 0
            ? 'Get Free Ticket'
            : 'Buy Tickets$priceLabel';

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _isSoldOut
              ? null
              : const LinearGradient(colors: AppTheme.brandGradient),
          color: _isSoldOut ? Colors.grey[300] : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isSoldOut
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: (_isLoadingTiers || _isSoldOut) ? null : _onBuyTickets,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: _isSoldOut ? Colors.grey[600] : Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            disabledBackgroundColor: Colors.transparent,
            disabledForegroundColor: Colors.grey[600],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  void _onShare() {
    // Opens the share-to-chat sheet (recent chats) with an "Outside HangHut"
    // fallback to the system share sheet. Analytics 'share' is logged on the
    // terminal action (chat pick or external share) inside the sheet.
    ShareToChatSheet.show(context, SharePayload.fromEvent(widget.event));
  }

  void _onBuyTickets() {
    EventAnalyticsService.instance.logGetTickets(widget.event.id);
    if (widget.event.isExternal && widget.event.externalTicketUrl != null) {
      // External event: redirect through our tracking endpoint
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id ?? '';
      final supabaseUrl = SupabaseConfig.client.rest.url.replaceAll(
        '/rest/v1',
        '',
      );
      final redirectUrl =
          '$supabaseUrl/functions/v1/redirect-to-external'
          '?event_id=${widget.event.id}'
          '&user_id=$currentUserId';
      launchUrl(Uri.parse(redirectUrl), mode: LaunchMode.externalApplication);
      return;
    }

    // Internal event: check for existing approved registration first
    // (require_approval events: if already approved, skip re-registration)
    _openPurchaseScreen();
  }

  Future<void> _openPurchaseScreen() async {
    String? existingRegistrationId;

    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId != null && widget.event.requireApproval) {
      try {
        final existing = await SupabaseConfig.client
            .from('event_registrations')
            .select('id')
            .eq('event_id', widget.event.id)
            .eq('user_id', userId)
            .eq('status', 'approved')
            .limit(1)
            .maybeSingle();
        existingRegistrationId = existing?['id'] as String?;
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventPurchaseScreen(
          event: widget.event,
          existingRegistrationId: existingRegistrationId,
        ),
      ),
    );
  }
}

class _OrganizerEventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;

  const _OrganizerEventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[100],
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            SizedBox(
              height: 82,
              width: double.infinity,
              child: event.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: event.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.deepPurple[50],
                        child: const Icon(Icons.event, color: Colors.deepPurple),
                      ),
                    )
                  : Container(
                      color: Colors.deepPurple[50],
                      child: const Icon(Icons.event, color: Colors.deepPurple),
                    ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM d').format(event.startLocal),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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

class _ImageViewerDialog extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _ImageViewerDialog({required this.images, required this.initialIndex});

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          // Paged image viewer
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, i) {
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.images[i],
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      color: Colors.white38,
                      size: 64,
                    ),
                  ),
                ),
              );
            },
          ),

          // Close button
          Positioned(
            top: 48,
            right: 16,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              style: IconButton.styleFrom(backgroundColor: Colors.black38),
            ),
          ),

          // Page indicator
          if (widget.images.length > 1)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.images.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _currentIndex == i ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: _currentIndex == i ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

/// Live countdown to an event's start, shown over the Nebula hero as four glassy
/// chips (Days · Hrs · Min · Sec). Ticks once per second and removes itself the
/// moment the event has started, so a past event never shows a stale countdown.
class _CountdownRow extends StatefulWidget {
  final DateTime target;
  const _CountdownRow({required this.target});

  @override
  State<_CountdownRow> createState() => _CountdownRowState();
}

class _CountdownRowState extends State<_CountdownRow> {
  Timer? _timer;
  late Duration _left;

  @override
  void initState() {
    super.initState();
    _left = widget.target.difference(DateTime.now());
    // Only run a ticker while there's time left to show.
    if (!_left.isNegative) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final left = widget.target.difference(DateTime.now());
        setState(() => _left = left);
        if (left.isNegative) _timer?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_left.isNegative) return const SizedBox.shrink();

    final days = _left.inDays;
    final hours = _left.inHours % 24;
    final mins = _left.inMinutes % 60;
    final secs = _left.inSeconds % 60;

    return Row(
      children: [
        _chip(days, 'Days'),
        const SizedBox(width: 8),
        _chip(hours, 'Hrs'),
        const SizedBox(width: 8),
        _chip(mins, 'Min'),
        const SizedBox(width: 8),
        _chip(secs, 'Sec'),
      ],
    );
  }

  Widget _chip(int value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
        ),
        child: Column(
          children: [
            Text(
              value.toString().padLeft(2, '0'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
