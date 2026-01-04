import 'package:flutter/material.dart';

import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/widgets/full_screen_image_viewer.dart';

class HangoutFeedCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onTap;
  final Function(String)? onPostDeleted;

  const HangoutFeedCard({
    super.key,
    required this.post,
    required this.onTap,
    this.onPostDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final user = post['user'];
    final createdAt = DateTime.parse(post['created_at']);
    final metadata = post['metadata'] as Map<String, dynamic>? ?? {};

    final venueName = metadata['venue_name'] ?? 'Unknown Venue';
    final activityType = metadata['activity_type'] ?? 'Hangout';
    final imageUrl = metadata['image_url'];
    final scheduledTimeStr = metadata['scheduled_time'];
    final scheduledTime = scheduledTimeStr != null
        ? DateTime.parse(scheduledTimeStr)
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        // Gradient border effect
        border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header (User Info + Badge)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: user?['avatar_url'] != null
                      ? NetworkImage(user!['avatar_url']) as ImageProvider
                      : null,
                  child: user?['avatar_url'] == null
                      ? const Icon(Icons.person, size: 20)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?['display_name'] ?? 'Someone',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _getActivityDescription(activityType),
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 13,
                        ),
                      ),
                      if (metadata['description'] != null &&
                          (metadata['description'] as String).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Linkify(
                          onOpen: (link) async {
                            final Uri uri = Uri.parse(link.url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          text: metadata['description'] as String,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color,
                            fontSize: 13,
                          ),
                          linkStyle: const TextStyle(color: Colors.blue),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.celebration,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'New',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Main Content (Image/Map + Details)
          Container(
            height: 180,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.grey[200],
            ),
            child: Stack(
              children: [
                // Image Background with Preview Gesture
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      if (imageUrl != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                FullScreenImageViewer(imageUrl: imageUrl),
                          ),
                        );
                      } else {
                        onTap(); // If it's a map or placeholder, treat as card tap
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        image:
                            (imageUrl != null ||
                                _getStaticMapUrl(metadata) != null)
                            ? DecorationImage(
                                image: imageUrl != null
                                    ? CachedNetworkImageProvider(imageUrl)
                                    : CachedNetworkImageProvider(
                                        _getStaticMapUrl(metadata)!,
                                      ),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                // Gradient Overlay (Darker at bottom for text readability)
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                ),

                // Center Content if no image
                if (imageUrl == null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 40,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          venueName,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Bottom Details inside image
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              venueName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 4),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (scheduledTime != null)
                              Text(
                                DateFormat(
                                  'h:mm a • EEE, MMM d',
                                ).format(scheduledTime),
                                style: TextStyle(
                                  color: Colors.white, // Standard white
                                  fontSize: 14,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Join Button
                      if (metadata['status'] == 'ended')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Ended',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Join',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Footer (Time ago)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(
                  timeago.format(createdAt),
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _getStaticMapUrl(Map<String, dynamic> metadata) {
    try {
      // Temporary token from Info.plist - TODO: Move to Env config
      const mapboxToken =
          'sk.eyJ1Ijoiam9obmlub3BhdGluIiwiYSI6ImNtaWoyeDJ0bzBvYWIzZXIxZ3NuNGVtY2cifQ.klu_T_fIF06R96z5MGDsMw';

      // We need coordinates. TableService stores table_id but we might not have lat/lng directly in metadata
      // unless we put it there.
      // Let's check TableService.dart:
      // metadata: { 'table_id': ..., 'venue_name': ..., 'activity_type': ... }
      // It DOES NOT currently put lat/lng in metadata.
      // However, the post itself has 'latitude' and 'longitude' columns!

      final lat = post['latitude']; // Post table has these
      final lng = post['longitude'];

      if (lat == null || lng == null) return null;

      // Construct Mapbox Static Image URL
      // Style: Streets v11
      // Size: 600x320 (matches close to container aspect ratio)
      // Zoom: 15
      return 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/static/$lng,$lat,15,0,0/600x320?access_token=$mapboxToken';
    } catch (e) {
      print('Error generating static map URL: $e');
      return null;
    }
  }

  String _getActivityDescription(String type) {
    return 'created an event';
  }
}
