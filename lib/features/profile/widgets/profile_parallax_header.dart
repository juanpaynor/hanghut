import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ProfileParallaxHeader extends StatelessWidget {
  final String? imageUrl;
  final String displayName;
  final String? username;
  final String characterClass;
  final bool isOwnProfile;
  final VoidCallback? onEdit;
  final VoidCallback? onSettings;
  final VoidCallback? onShare;
  final VoidCallback? onBadgeEdit;

  const ProfileParallaxHeader({
    super.key,
    required this.imageUrl,
    required this.displayName,
    this.username,
    required this.characterClass,
    this.isOwnProfile = false,
    this.onEdit,
    this.onSettings,
    this.onShare,
    this.onBadgeEdit,
  });

  // Badge gradient — consistent purple
  List<Color> _getBadgeGradient() {
    return [const Color(0xFF7C3AED), const Color(0xFF5B21B6)];
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeColors = _getBadgeGradient();

    return SliverAppBar(
      expandedHeight: 400.0,
      pinned: true,
      stretch: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: Navigator.canPop(context)
          ? Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
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
              CachedNetworkImage(
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
              )
            else
              Container(
                color: AppTheme.accentColor.withValues(alpha: 0.2),
                child: const Icon(
                  Icons.person,
                  size: 100,
                  color: AppTheme.accentColor,
                ),
              ),

            // 2. Gradient Overlay (cinematic bottom fade — smoother)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.78),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                  stops: const [0.0, 0.3, 0.5, 0.7, 0.85, 1.0],
                ),
              ),
            ),

            // 3. User Info (Bottom of Header)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Character Class Badge — gradient pill (tappable on own profile)
                  GestureDetector(
                    onTap: onBadgeEdit,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: badgeColors,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: badgeColors[0].withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onBadgeEdit != null)
                              const Padding(
                                padding: EdgeInsets.only(right: 5),
                                child: Icon(Icons.edit, color: Colors.white70, size: 11),
                              ),
                            Text(
                              characterClass.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 200.ms)
                      .slideX(begin: -0.2, end: 0),
                  const SizedBox(height: 10),

                  // Display Name — bold, centered
                  Text(
                        displayName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.7),
                              offset: const Offset(0, 3),
                              blurRadius: 16,
                            ),
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              offset: const Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                      .animate()
                      .fadeIn(duration: 800.ms)
                      .slideY(begin: 0.2, end: 0),

                  // Username handle
                  if (username != null && username!.isNotEmpty)
                    Text(
                          '@$username',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                offset: const Offset(0, 1),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 200.ms)
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
        color: Colors.black.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onTap,
      ),
    );
  }
}
