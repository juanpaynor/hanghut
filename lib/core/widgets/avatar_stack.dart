import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AvatarStack extends StatelessWidget {
  final List<String?> avatarUrls;
  final int totalCount;
  final double size;
  final double overlap;
  final Color borderColor;
  final double borderWidth;

  const AvatarStack({
    super.key,
    required this.avatarUrls,
    required this.totalCount,
    this.size = 32,
    this.overlap = 0.4, // Percentage overlap (0.0 to 1.0)
    this.borderColor = Colors.white,
    this.borderWidth = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    // Determine how many avatars to show (max 3 usually looks best)
    final int showCount = avatarUrls.length > 3 ? 3 : avatarUrls.length;
    final int remaining = totalCount - showCount;
    final double offsetStep = size * (1 - overlap);

    return SizedBox(
      height: size,
      // Calculate total width based on overlap
      width: size + (showCount + (remaining > 0 ? 1 : 0) - 1) * offsetStep,
      child: Stack(
        children: [
          // Render avatars in reverse order so first one is on top (or bottom depending on preference)
          // Standard facepile usually has the first person on top-left (index 0)
          for (int i = 0; i < showCount; i++)
            Positioned(
              left: i * offsetStep,
              child: _buildAvatar(avatarUrls[i], i),
            ),

          // Render "+N" bubble if there are more people
          if (remaining > 0)
            Positioned(
              left: showCount * offsetStep,
              child: _buildCountBubble(remaining),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String? url, int index) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
        color: Colors.grey[200],
      ),
      child: ClipOval(
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) => Center(
                  child: Icon(
                    Icons.person,
                    size: size * 0.6,
                    color: Colors.grey[400],
                  ),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Icon(
                    Icons.person,
                    size: size * 0.6,
                    color: Colors.grey[400],
                  ),
                ),
              )
            : Center(
                child: Icon(
                  Icons.person,
                  size: size * 0.6,
                  color: Colors.grey[400],
                ),
              ),
      ),
    );
  }

  Widget _buildCountBubble(int count) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black, // Premium feel
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Center(
        child: Text(
          '+$count',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
