import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:bitemates/features/map/widgets/liquid_morph_route.dart';
import 'package:bitemates/features/camera/screens/location_story_viewer_screen.dart';

/// A unified bottom sheet that shows all overlapping items at a map location.
/// Handles events, tables, and stories in a single picker.
class MapClusterSheet extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic>? currentUserData;
  final dynamic matchingService; // TableMatchingService

  const MapClusterSheet({
    super.key,
    required this.items,
    this.currentUserData,
    this.matchingService,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locationName = _getLocationName();

    // Group items by type
    final events = items.where((i) => i['type'] == 'event').toList();
    final tables = items.where((i) => i['type'] == 'table').toList();
    final stories = items.where((i) => i['type'] == 'story').toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HAPPENING HERE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        locationName,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                          height: 1.1,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${items.length} items',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Type filter chips
          if (_hasMultipleTypes(events, tables, stories))
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                children: [
                  if (events.isNotEmpty)
                    _buildTypeChip(
                      '🎟️ ${events.length} Event${events.length > 1 ? 's' : ''}',
                      const Color(0xFF6C5CE7),
                    ),
                  if (tables.isNotEmpty) ...[
                    if (events.isNotEmpty) const SizedBox(width: 8),
                    _buildTypeChip(
                      '🍽️ ${tables.length} Table${tables.length > 1 ? 's' : ''}',
                      const Color(0xFFE17055),
                    ),
                  ],
                  if (stories.isNotEmpty) ...[
                    if (events.isNotEmpty || tables.isNotEmpty)
                      const SizedBox(width: 8),
                    _buildTypeChip(
                      '📸 ${stories.length} Stor${stories.length > 1 ? 'ies' : 'y'}',
                      const Color(0xFF00B894),
                    ),
                  ],
                ],
              ),
            ),

          // List
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final type = item['type'];

                switch (type) {
                  case 'event':
                    return _buildEventCard(context, item, isDark);
                  case 'table':
                    return _buildTableCard(context, item, isDark);
                  case 'story':
                    return _buildStoryCard(context, item, isDark);
                  default:
                    return const SizedBox.shrink();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getLocationName() {
    for (final item in items) {
      final name = item['location_name'] ?? item['venue_name'];
      if (name != null) return name;
    }
    return 'This Location';
  }

  bool _hasMultipleTypes(List a, List b, List c) {
    int count = 0;
    if (a.isNotEmpty) count++;
    if (b.isNotEmpty) count++;
    if (c.isNotEmpty) count++;
    return count > 1;
  }

  Widget _buildTypeChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ─── Event Card ───
  Widget _buildEventCard(
    BuildContext context,
    Map<String, dynamic> event,
    bool isDark,
  ) {
    final DateTime eventTime = DateTime.parse(event['datetime']);

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        if (event['original_object'] != null &&
            event['original_object'] is Event) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventDetailModal(event: event['original_object']),
            ),
          );
        }
      },
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Date stub
            Container(
              width: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF6C5CE7).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('MMM').format(eventTime).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6C5CE7),
                    ),
                  ),
                  Text(
                    DateFormat('d').format(eventTime),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6C5CE7),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C5CE7).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '🎟️ Event',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event['title'] ?? 'Event',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('h:mm a').format(eventTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Table Card ───
  Widget _buildTableCard(
    BuildContext context,
    Map<String, dynamic> table,
    bool isDark,
  ) {
    final title = table['title'] ?? table['venue_name'] ?? 'Hangout';
    final scheduledTime = table['datetime'] ?? table['scheduled_time'];
    DateTime? dateTime;
    if (scheduledTime != null) {
      dateTime = DateTime.tryParse(scheduledTime);
    }

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);

        Map<String, dynamic>? matchData;
        if (currentUserData != null && matchingService != null) {
          matchData = matchingService.calculateMatch(
            currentUser: currentUserData!,
            table: table,
          );
        }

        final size = MediaQuery.of(context).size;
        final center = Offset(size.width / 2, size.height / 2);

        Navigator.of(context).push(
          LiquidMorphRoute(
            center: center,
            page: TableCompactModal(table: table, matchData: matchData),
          ),
        );
      },
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Emoji / Avatar stub
            Container(
              width: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE17055).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: Center(
                child: table['marker_emoji'] != null
                    ? Text(
                        table['marker_emoji'],
                        style: const TextStyle(fontSize: 28),
                      )
                    : table['host_photo_url'] != null
                    ? CircleAvatar(
                        radius: 20,
                        backgroundImage: CachedNetworkImageProvider(
                          table['host_photo_url'],
                        ),
                      )
                    : const Icon(
                        Icons.restaurant_menu,
                        size: 28,
                        color: Color(0xFFE17055),
                      ),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE17055).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '🍽️ Table',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (dateTime != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('EEE, h:mm a').format(dateTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Story Card ───
  Widget _buildStoryCard(
    BuildContext context,
    Map<String, dynamic> story,
    bool isDark,
  ) {
    final authorName =
        story['author_name'] ?? story['display_name'] ?? 'Someone';
    final thumbnail = story['media_url'] ?? story['thumbnail_url'];
    final createdAt = story['created_at'];
    String? timeAgo;
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeAgo = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeAgo = '${diff.inHours}h ago';
        } else {
          timeAgo = '${diff.inDays}d ago';
        }
      }
    }

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LocationStoryViewerScreen(
              initialStory: story,
              clusterId:
                  story['external_place_id'] ??
                  story['event_id'] ??
                  story['table_id'],
            ),
          ),
        );
      },
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF00B894).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: thumbnail != null
                  ? ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: thumbnail,
                        fit: BoxFit.cover,
                        height: 88,
                        width: 72,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.camera_alt,
                          color: Color(0xFF00B894),
                          size: 28,
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.camera_alt,
                        color: Color(0xFF00B894),
                        size: 28,
                      ),
                    ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B894).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '📸 Story',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (timeAgo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
