import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TrendingCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> tables;
  final Function(Map<String, dynamic>) onTableTap;

  const TrendingCarousel({
    super.key,
    required this.tables,
    required this.onTableTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tables.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tables.length,
        itemBuilder: (context, index) {
          final table = tables[index];
          final title = table['title'] ?? 'Hangout';
          final bgImage =
              table['image_url'] ??
              table['marker_image_url'] ??
              'https://images.unsplash.com/photo-1543007630-9710e4a00a20?auto=format&fit=crop&q=80';

          return GestureDetector(
            onTap: () => onTableTap(table),
            child: Container(
              width: 140,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Image
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: bgImage,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Colors.grey[200]),
                      errorWidget: (context, url, err) =>
                          Container(color: Colors.grey[300]),
                    ),
                  ),

                  // Gradient
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.9),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // content
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Trending badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PENDING',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
