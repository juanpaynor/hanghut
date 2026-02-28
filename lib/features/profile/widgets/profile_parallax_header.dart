import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ProfileParallaxHeader extends StatelessWidget {
  final String? imageUrl;
  final String displayName;
  final String characterClass;
  final bool isOwnProfile;
  final VoidCallback? onEdit;
  final VoidCallback? onSettings;
  final VoidCallback? onShare;

  const ProfileParallaxHeader({
    super.key,
    required this.imageUrl,
    required this.displayName,
    required this.characterClass,
    this.isOwnProfile = false,
    this.onEdit,
    this.onSettings,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SliverAppBar(
      expandedHeight: 400.0, // Taller for cinematic feel
      pinned: true,
      stretch: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: Navigator.canPop(context)
          ? Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      actions: [
        if (isOwnProfile) ...[
          _buildActionButton(Icons.edit, onEdit),
          _buildActionButton(Icons.settings, onSettings),
        ] else ...[
          _buildActionButton(Icons.share, onShare),
        ],
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Hero Image
            if (imageUrl != null && imageUrl!.isNotEmpty)
              ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Colors.black, Colors.transparent],
                    stops: [0.0, 0.8, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: isDark ? Colors.grey[900] : Colors.grey[200],
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: isDark ? Colors.grey[900] : Colors.grey[200],
                    child: const Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.grey,
                    ),
                  ),
                ),
              )
            else
              Container(
                color: AppTheme.accentColor.withOpacity(0.2),
                child: const Icon(
                  Icons.person,
                  size: 100,
                  color: AppTheme.accentColor,
                ),
              ),

            // 2. Gradient Overlay (Bottom Up)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.2),
                    Colors.black.withOpacity(0.7),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                  stops: const [
                    0.0,
                    0.5,
                    0.85,
                    1.0,
                  ], // Fade out before the edge
                ),
              ),
            ),

            // 3. User Info (Bottom of Header)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                        characterClass.toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.accentColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 200.ms)
                      .slideX(begin: -0.2, end: 0),
                  const SizedBox(height: 4),
                  Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42, // Massive, cinematic text
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                          letterSpacing: -1,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              offset: Offset(0, 4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                      .animate()
                      .fadeIn(duration: 800.ms)
                      .slideY(begin: 0.2, end: 0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback? onTap) {
    if (onTap == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onTap,
      ),
    );
  }
}
