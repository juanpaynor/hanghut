import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/ticketing/models/event.dart';

class TrendingCarousel extends StatelessWidget {
  final List<dynamic>
  items; // Support both Map<String, dynamic> (Tables) and Event
  final Function(dynamic) onItemTap;
  final String? fixedBadge; // If null, derives from item

  const TrendingCarousel({
    super.key,
    required this.items,
    required this.onItemTap,
    this.fixedBadge,
  });

  String _getTitle(dynamic item) {
    if (item is Event) return item.title;
    if (item is Map) return item['title'] ?? 'Hangout';
    return '';
  }

  String? _getImageUrl(dynamic item) {
    if (item is Event) return item.coverImageUrl;
    if (item is Map) {
      String? img = item['marker_image_url'] ?? item['image_url'];
      if (img == null && item['images'] != null && (item['images'] as List).isNotEmpty) {
        img = (item['images'] as List).first as String?;
      }
      return img ?? 'https://images.unsplash.com/photo-1543007630-9710e4a00a20?auto=format&fit=crop&q=80';
    }
    return '';
  }

  String _getBadge(dynamic item) {
    if (fixedBadge != null) return fixedBadge!;
    if (item is Event) return 'EVENT';
    if (item is Map) {
      if (item['is_experience'] == true) {
        final expType = item['experience_type'] as String?;
        return expType?.replaceAll('_', ' ').toUpperCase() ?? 'EXPERIENCE';
      }
      final type = item['cuisine_type']; // Activity type
      return type?.toUpperCase() ?? 'PENDING';
    }
    return 'HAPPENING';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final title = _getTitle(item);
          final bgImage = _getImageUrl(item);
          final badge = _getBadge(item);

          return _CarouselCard(
            title: title,
            bgImage: bgImage,
            badge: badge,
            onTap: () => onItemTap(item),
          );
        },
      ),
    );
  }
}

class _CarouselCard extends StatefulWidget {
  final String title;
  final String? bgImage;
  final String badge;
  final VoidCallback onTap;

  const _CarouselCard({
    required this.title,
    required this.bgImage,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_CarouselCard> createState() => _CarouselCardState();
}

class _CarouselCardState extends State<_CarouselCard> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 140,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Image
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: widget.bgImage ?? '',
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
                      child: Text(
                        widget.badge,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.title,
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
      ),
    );
  }
}
