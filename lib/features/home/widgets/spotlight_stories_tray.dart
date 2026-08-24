import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

/// A saturation ColorFilter matrix. s=1 is full colour, s=0 is greyscale.
/// Used to mute already-seen story covers so unseen ones pop.
List<double> _saturationMatrix(double s) {
  const double rw = 0.2126, gw = 0.7152, bw = 0.0722;
  final double r = (1 - s) * rw, g = (1 - s) * gw, b = (1 - s) * bw;
  return <double>[
    r + s, g, b, 0, 0,
    r, g + s, b, 0, 0,
    r, g, b + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

// Indigo brand ramp (matches the app's story ring / primary).
const Color _indigo400 = Color(0xFF818CF8);
const Color _indigo500 = Color(0xFF6366F1);
const Color _indigo600 = Color(0xFF4F46E5);

// Carousel geometry.
const double _tileW = 158;
const double _tileH = 214;
const double _radius = 22;
// Slot width ≈ tile width so neighbours hug the centered tile (a tight deck),
// with a couple peeking on each side rather than one distant sliver.
const double _viewportFraction = 0.47;
// Parallax: covers are overscaled by this so they can drift within the frame
// without exposing edges; _parallaxPx is the max horizontal drift per tile.
const double _coverOverscan = 1.22;
const double _parallaxPx = 10.0;
// How muted a seen cover looks (0 = greyscale, 1 = full colour).
const double _seenSaturation = 0.15;

/// "Spotlight" story tray: a depth carousel. The centered story blooms large
/// while neighbours shrink and dim; swipe moves the deck. Tapping the centered
/// tile opens the viewer (morphing out of the card); tapping a side tile brings
/// it to center first.
///
/// Drop-in replacement for FriendsMomentsTray — identical constructor.
class SpotlightStoriesTray extends StatefulWidget {
  final List<Map<String, dynamic>> stories;

  /// [originRect] is the tapped tile's rect in global screen coords, so the
  /// opener can morph the viewer out of the card. Null if unmeasurable.
  final void Function(Map<String, dynamic> story, Rect? originRect) onStoryTap;
  final VoidCallback? onAddStory;
  final VoidCallback? onLoadMore;
  final bool isLoading;
  final bool hasMore;

  const SpotlightStoriesTray({
    super.key,
    required this.stories,
    required this.onStoryTap,
    this.onAddStory,
    this.onLoadMore,
    this.isLoading = false,
    this.hasMore = false,
  });

  @override
  State<SpotlightStoriesTray> createState() => _SpotlightStoriesTrayState();
}

class _SpotlightStoriesTrayState extends State<SpotlightStoriesTray> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: _viewportFraction);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    // A light tick when a tile locks into the spotlight.
    HapticFeedback.selectionClick();
    if (widget.hasMore &&
        !widget.isLoading &&
        index >= widget.stories.length - 2) {
      widget.onLoadMore?.call();
    }
  }

  /// Signed distance of [index] from the currently-centered page (0 == center).
  double _delta(int index) {
    double page;
    if (_controller.hasClients && _controller.position.haveDimensions) {
      page = _controller.page ?? _controller.initialPage.toDouble();
    } else {
      page = _controller.initialPage.toDouble();
    }
    return index - page;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading &&
        widget.stories.isEmpty &&
        widget.onAddStory == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: _tileH + 20,
          child: widget.isLoading && widget.stories.isEmpty
              ? _buildShimmer()
              : PageView.builder(
                  controller: _controller,
                  onPageChanged: _onPageChanged,
                  physics: const BouncingScrollPhysics(),
                  padEnds: true,
                  itemCount: widget.stories.length,
                  itemBuilder: (context, index) {
                    // Built once per item; only the transform rebuilds on scroll.
                    final tile = _SpotlightTile(
                      story: widget.stories[index],
                      controller: _controller,
                      index: index,
                      onTap: (rect) => _handleTap(index, rect),
                    );
                    return AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        // Graduated falloff: center 1.0, each step out shrinks
                        // and dims, so it reads as depth rather than a flat row.
                        final d = _delta(index).abs();
                        final scale = (1.0 - d * 0.14).clamp(0.70, 1.0);
                        final opacity = (1.0 - d * 0.42).clamp(0.32, 1.0);
                        return Center(
                          child: Opacity(
                            opacity: opacity,
                            child: Transform.scale(scale: scale, child: child),
                          ),
                        );
                      },
                      child: tile,
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _handleTap(int index, Rect? rect) {
    final page = _controller.hasClients
        ? (_controller.page ?? _controller.initialPage.toDouble())
        : _controller.initialPage.toDouble();
    final isCentered = (index - page).abs() < 0.5;

    if (!isCentered) {
      // Bring the tapped tile to the spotlight instead of opening it.
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final story = widget.stories[index];
    final isOwn = story['is_own'] == true;
    final hasStory = (story['story_count'] ?? 0) > 0;
    if (isOwn && !hasStory) {
      widget.onAddStory?.call();
    } else {
      widget.onStoryTap(story, rect);
    }
  }

  Widget _buildShimmer() {
    return Center(
      child: Container(
        width: _tileW,
        height: _tileH,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
    );
  }
}

// ==========================================
// Spotlight tile — large cover card
// ==========================================
class _SpotlightTile extends StatelessWidget {
  final Map<String, dynamic> story;
  final PageController controller;
  final int index;
  final void Function(Rect? originRect) onTap;

  const _SpotlightTile({
    required this.story,
    required this.controller,
    required this.index,
    required this.onTap,
  });

  /// Signed distance of this tile from the centered page (0 == center).
  double _pageDelta() {
    if (controller.hasClients && controller.position.haveDimensions) {
      return index - (controller.page ?? controller.initialPage.toDouble());
    }
    return index - controller.initialPage.toDouble();
  }

  bool get _isOwn => story['is_own'] == true;
  bool get _isSeen => story['is_seen'] == true;
  bool get _hasStory => (story['story_count'] ?? 0) > 0;

  String? get _coverUrl {
    final img = story['latest_image_url'] as String?;
    return (img != null && img.isNotEmpty) ? img : null;
  }

  String get _authorName =>
      (story['author_name'] ??
              story['display_name'] ??
              (_isOwn ? 'You' : 'Friend'))
          .toString();

  String get _firstName {
    if (_isOwn) return 'Your Story';
    final n = _authorName.trim();
    return n.isEmpty ? 'Friend' : n.split(' ').first;
  }

  /// The tile's rect in global screen coords (center tile is unscaled → exact).
  Rect? _rectOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (innerContext) => GestureDetector(
        onTap: () => onTap(_rectOf(innerContext)),
        child: Center(
          child: SizedBox(
            width: _tileW,
            height: _tileH,
            child: (_isOwn && !_hasStory)
                ? _addStoryCard(context)
                : _storyCard(),
          ),
        ),
      ),
    );
  }

  Widget _storyCard() {
    final Gradient? ring = _isSeen
        ? null
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_indigo400, _indigo500, _indigo600],
          );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        gradient: ring,
        color: _isSeen ? Colors.grey[300] : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius - 2.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _cover(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
            _locationChip(),
            _countBadge(),
            _poster(),
          ],
        ),
      ),
    );
  }

  Widget _cover() {
    final url = _coverUrl;
    if (url == null) return _desaturate(_gradientFallback());

    // Overscaled so the parallax drift never exposes the frame edge. Built
    // once and passed as the AnimatedBuilder child so the image isn't rebuilt
    // every scroll frame — only the cheap Transform is.
    final image = Transform.scale(
      scale: _coverOverscan,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => _gradientFallback(),
        errorWidget: (_, __, ___) => _gradientFallback(),
      ),
    );

    return _desaturate(
      AnimatedBuilder(
        animation: controller,
        child: image,
        builder: (context, child) {
          // Drift the cover against the swipe for a layered, parallax feel.
          final dx = _pageDelta().clamp(-1.5, 1.5) * -_parallaxPx;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
      ),
    );
  }

  /// Mute the cover when the story has already been seen, so unseen ones pop.
  Widget _desaturate(Widget child) {
    if (!_isSeen) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_saturationMatrix(_seenSaturation)),
      child: child,
    );
  }

  Widget _gradientFallback() {
    final seed = _authorName.isNotEmpty ? _authorName.codeUnitAt(0) : 0;
    final palettes = <List<Color>>[
      [_indigo400, _indigo600],
      [const Color(0xFFF9A8D4), const Color(0xFFEC4899)],
      [const Color(0xFF7DD3FC), const Color(0xFF0EA5E9)],
      [const Color(0xFFFDBA74), const Color(0xFFF97316)],
      [const Color(0xFF6EE7B7), const Color(0xFF10B981)],
    ];
    final colors = palettes[seed % palettes.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          _firstName.isNotEmpty ? _firstName[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            fontSize: 44,
            fontWeight: FontWeight.w800,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ),
    );
  }

  Widget _locationChip() {
    final place = story['latest_external_place_name'] as String?;
    if (place == null || place.trim().isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  place.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBadge() {
    final count = story['story_count'];
    if (count is! int || count <= 1) return const SizedBox.shrink();
    return Positioned(
      top: 10,
      right: 10,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.34),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 0.5),
        ),
        child: Text(
          '$count',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _poster() {
    final avatarUrl = story['author_avatar_url'] as String?;
    return Positioned(
      left: 10,
      right: 10,
      bottom: 10,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              color: Colors.grey[400],
            ),
            clipBehavior: Clip.antiAlias,
            child: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: avatarUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _avatarInitial(),
                    errorWidget: (_, __, ___) => _avatarInitial(),
                  )
                : _avatarInitial(),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarInitial() {
    return Container(
      color: _indigo500,
      alignment: Alignment.center,
      child: Text(
        _firstName.isNotEmpty ? _firstName[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _addStoryCard(BuildContext context) {
    final avatarUrl = story['author_avatar_url'] as String?;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: Colors.grey[300]!, width: 1.5),
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (avatarUrl != null && avatarUrl.isNotEmpty)
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.15),
                BlendMode.darken,
              ),
              child: CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _addStoryGradient(),
              ),
            )
          else
            _addStoryGradient(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.15),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _indigo500,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _indigo500.withOpacity(0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 26),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Text(
              'Your Story',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addStoryGradient() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC4B5FD), Color(0xFF8B5CF6)],
        ),
      ),
    );
  }
}
