import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/ticketing/models/ticket_tier.dart';
import 'package:bitemates/features/ticketing/screens/event_purchase_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bitemates/features/shared/widgets/friends_going_row.dart';
import 'package:bitemates/features/settings/widgets/report_modal.dart';

class EventDetailModal extends StatefulWidget {
  final Event event;

  const EventDetailModal({super.key, required this.event});

  @override
  State<EventDetailModal> createState() => _EventDetailModalState();
}

class _EventDetailModalState extends State<EventDetailModal> {
  bool _isExpanded = false;
  bool _isSoldOut = false;
  bool _isLoadingTiers = true;
  String? _organizerDisplayName;
  String? _organizerAvatarUrl;

  @override
  void initState() {
    super.initState();
    _fetchAvailability();
    _fetchOrganizerInfo();
  }

  Future<void> _fetchOrganizerInfo() async {
    try {
      final response = await SupabaseConfig.client
          .from('partners')
          .select('business_name, profile_photo_url, verified, user_id, users!user_id (display_name, avatar_url)')
          .eq('id', widget.event.organizerId)
          .maybeSingle();

      if (response != null && mounted) {
        // Use partner business name, or fall back to linked user's display name
        final userData = response['users'] as Map<String, dynamic>?;
        setState(() {
          _organizerDisplayName = response['business_name'] as String?
              ?? userData?['display_name'] as String?;
          _organizerAvatarUrl = response['profile_photo_url'] as String?
              ?? userData?['avatar_url'] as String?;
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

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Hero Image (160px)
            _buildHeroImage(categoryConfig),

            // 2. Content (scrollable to prevent overflow)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      widget.event.title,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Venue
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.event.venueName,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Date & Time
                    _buildDateTimeBox(),

                    const SizedBox(height: 12),

                    // Price & Availability
                    _buildPriceRow(),

                    // Friends Going
                    FriendsGoingRow(
                      entityType: 'event',
                      entityId: widget.event.id,
                    ),

                    const SizedBox(height: 12),

                    // Organizer Card
                    _buildOrganizerCard(),

                    const SizedBox(height: 16),

                    // Description
                    _buildDescription(),

                    const SizedBox(height: 24),

                    // Buy Tickets Button
                    _buildBuyButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroImage(Map<String, dynamic> categoryConfig) {
    return SizedBox(
      height: 160,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image or Gradient
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: widget.event.coverImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: widget.event.coverImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black26,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) =>
                        _buildFallbackGradient(categoryConfig),
                  )
                : _buildFallbackGradient(categoryConfig),
          ),

          // Dark gradient overlay for button visibility
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.4), Colors.transparent],
                  stops: const [0.0, 0.5],
                ),
              ),
            ),
          ),

          // Share Button (top-left)
          Positioned(
            top: 12,
            left: 12,
            child: Material(
              color: Colors.white,
              elevation: 2,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: _onShare,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.share, color: Colors.black87, size: 20),
                ),
              ),
            ),
          ),

          // Report Button (next to share)
          Positioned(
            top: 12,
            left: 56,
            child: Material(
              color: Colors.white,
              elevation: 2,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () {
                  ReportModal.show(
                    context,
                    targetType: 'post',
                    targetId: widget.event.id,
                    targetName: widget.event.title,
                  );
                },
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.flag_outlined, color: Colors.grey, size: 20),
                ),
              ),
            ),
          ),

          // Close Button (top-right)
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.white,
              elevation: 2,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.close, color: Colors.black87, size: 20),
                ),
              ),
            ),
          ),

          // Category Badge
          Positioned(
            top: 56,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    categoryConfig['emoji'] as String,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.event.category.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
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

  Widget _buildDateTimeBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 16, color: Colors.grey[800]),
          const SizedBox(width: 12),
          Text(
            DateFormat(
              'EEEE, MMM d  •  h:mm a',
            ).format(widget.event.startDatetime),
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.confirmation_number, size: 16, color: Colors.grey[800]),
            const SizedBox(width: 8),
            Text(
              '₱${widget.event.ticketPrice.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Text(
          _isSoldOut ? 'Sold Out' : 'Available',
          style: TextStyle(
            color: _isSoldOut ? Colors.red : Colors.green[700],
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildOrganizerCard() {
    final displayName = widget.event.organizerName
        ?? _organizerDisplayName
        ?? 'Event Organizer';
    final photoUrl = widget.event.organizerPhotoUrl
        ?? _organizerAvatarUrl;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: photoUrl != null
                ? NetworkImage(photoUrl)
                : null,
            backgroundColor: Colors.grey[300],
            child: photoUrl == null
                ? const Icon(Icons.business, color: Colors.white, size: 20)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.event.organizerVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 16, color: Colors.blue),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Event Organizer',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    if (widget.event.description.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.event.description,
          style: TextStyle(color: Colors.grey[700], fontSize: 14, height: 1.5),
          maxLines: _isExpanded ? null : 3,
          overflow: _isExpanded ? null : TextOverflow.ellipsis,
        ),
        if (widget.event.description.length > 150)
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

  Widget _buildBuyButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_isLoadingTiers || _isSoldOut) ? null : _onBuyTickets,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isSoldOut ? Colors.grey[300] : Colors.black,
          foregroundColor: _isSoldOut ? Colors.grey[600] : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          disabledBackgroundColor: Colors.grey[300],
          disabledForegroundColor: Colors.grey[600],
        ),
        child: Text(
          _isSoldOut ? 'Sold Out' : 'Buy Tickets',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  void _onShare() {
    Share.share(
      '🎟️ ${widget.event.title}\n'
      '📅 ${DateFormat('EEEE, MMM d at h:mm a').format(widget.event.startDatetime)}\n'
      '📍 ${widget.event.venueName}\n'
      '💰 ₱${widget.event.ticketPrice.toStringAsFixed(0)}\n\n'
      'Get your tickets on HangHut!',
      subject: widget.event.title,
    );
  }

  void _onBuyTickets() {
    Navigator.pop(context); // Close modal
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventPurchaseScreen(event: widget.event),
      ),
    );
  }
}
