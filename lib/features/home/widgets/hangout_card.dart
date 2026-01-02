import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/widgets/avatar_stack.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HangoutCard extends StatelessWidget {
  final Map<String, dynamic> table;
  final VoidCallback onTap;
  final VoidCallback onJoin;

  const HangoutCard({
    super.key,
    required this.table,
    required this.onTap,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final title = table['title'] ?? 'Hangout';
    final venueName = table['location_name'] ?? 'Unknown Location';
    final time = DateTime.parse(table['datetime']);
    final timeStr = DateFormat('h:mm a').format(time); // e.g. 8:30 PM
    final dateStr = DateFormat('MMM d').format(time); // e.g. Oct 24

    // Extract participants logic (mocking if not fully available or fetching from joined)
    // For now assuming table['participants'] or similar is enriched, or passing empty
    // The feed screen logic currently enriches 'users' (host).
    // We might need to fetch participants or just show host + placeholder.
    final hostPhoto =
        table['users']?['user_photos'] is List &&
            (table['users']['user_photos'] as List).isNotEmpty
        ? table['users']['user_photos'][0]['photo_url']
        : table['users']?['avatar_url'];

    final List<String> avatars = [];
    if (hostPhoto != null) avatars.add(hostPhoto);

    // Image logic: Use table image, or venue image, or marker image, or fallback
    final bgImage =
        table['image_url'] ??
        table['marker_image_url'] ??
        'https://images.unsplash.com/photo-1543007630-9710e4a00a20?auto=format&fit=crop&q=80';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 280, // Taller, immersive
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.black, // Fallback color
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 1. Background Image
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: bgImage,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Colors.grey[200]),
                errorWidget: (context, url, error) =>
                    Container(color: Colors.grey[300]),
              ),
            ),

            // 2. Gradient Overlay (Bottom Up)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.2),
                      Colors.black.withOpacity(0.8),
                    ],
                    stops: const [0.4, 0.6, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Content Content
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Date Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$dateStr • $timeStr',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Location
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          venueName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Footer: Avatars + Joint Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Avatars
                      Row(
                        children: [
                          if (avatars.isNotEmpty)
                            AvatarStack(
                              avatarUrls: avatars,
                              totalCount: avatars.length,
                              size: 32,
                              borderColor: Colors.black,
                            ),
                          if (avatars.isEmpty)
                            const Text(
                              "Be the first!",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),

                      // Join Button
                      Material(
                        color: Theme.of(context).primaryColor,
                        elevation: 4,
                        shadowColor: Theme.of(
                          context,
                        ).primaryColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          onTap: onJoin,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            child: const Text(
                              'Join',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 4. Distance / Badges (Top Right)
            /*
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '0.2 mi',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            */
          ],
        ),
      ),
    );
  }
}
