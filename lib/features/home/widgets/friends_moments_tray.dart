import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

// Indigo brand ramp (matches the app's story ring / primary).
const Color _indigo400 = Color(0xFF818CF8);
const Color _indigo500 = Color(0xFF6366F1);
const Color _indigo600 = Color(0xFF4F46E5);

// Tile geometry — a large portrait "moment" card.
const double _ringW = 116;
const double _ringH = 172;
const double _ringPad = 2.5; // unseen gradient ring thickness
const double _radius = 20;

class FriendsMomentsTray extends StatefulWidget {
  final List<Map<String, dynamic>> stories;

  /// [originRect] is the tapped tile's rect in global screen coordinates, so
  /// the opener can morph the story viewer out of the card. May be null if it
  /// couldn't be measured.
  final void Function(Map<String, dynamic> story, Rect? originRect) onStoryTap;
  final VoidCallback? onAddStory;
  final VoidCallback? onLoadMore;
  final bool isLoading;
  final bool hasMore;

  const FriendsMomentsTray({
    super.key,
    required this.stories,
    required this.onStoryTap,
    this.onAddStory,
    this.onLoadMore,
    this.isLoading = false,
    this.hasMore = false,
  });

  @override
  State<FriendsMomentsTray> createState() => _FriendsMomentsTrayState();
}

class _FriendsMomentsTrayState extends State<FriendsMomentsTray> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.hasMore || widget.isLoading) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.onLoadMore?.call();
    }
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
          height: _ringH + 12,
          child: widget.isLoading && widget.stories.isEmpty
              ? _buildShimmer()
              : ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.stories.length + (widget.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= widget.stories.length) {
                      return const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: _ringW,
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      );
                    }

                    final story = widget.stories[index];
                    final isOwn = story['is_own'] == true;
                    final hasStory = (story['story_count'] ?? 0) > 0;

                    if (isOwn) {
                      return _StoryTile(
                        story: story,
                        isOwn: true,
                        isSeen: false,
                        hasStory: hasStory,
                        onTap: (rect) {
                          if (hasStory) {
                            widget.onStoryTap(story, rect);
                          } else {
                            widget.onAddStory?.call();
                          }
                        },
                      );
                    }

                    return _StoryTile(
                      story: story,
                      isOwn: false,
                      isSeen: story['is_seen'] == true,
                      hasStory: true,
                      onTap: (rect) => widget.onStoryTap(story, rect),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            width: _ringW,
            height: _ringH,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(_radius),
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// Story Tile — large cover card ("On the Map")
// ==========================================
class _StoryTile extends StatefulWidget {
  final Map<String, dynamic> story;
  final bool isOwn;
  final bool isSeen;
  final bool hasStory;

  /// Receives the tile's global-screen rect (for the zoom-open transition),
  /// or null if it couldn't be measured.
  final void Function(Rect? originRect) onTap;

  const _StoryTile({
    required this.story,
    required this.isOwn,
    required this.isSeen,
    required this.hasStory,
    required this.onTap,
  });

  @override
  State<_StoryTile> createState() => _StoryTileState();
}

class _StoryTileState extends State<_StoryTile> {
  double _scale = 1.0;

  String? get _coverUrl {
    final img = widget.story['latest_image_url'] as String?;
    if (img != null && img.isNotEmpty) return img;
    return null; // video stories have no thumbnail → gradient fallback
  }

  String get _authorName =>
      (widget.story['author_name'] ??
              widget.story['display_name'] ??
              (widget.isOwn ? 'You' : 'Friend'))
          .toString();

  String get _firstName {
    if (widget.isOwn) return 'Your Story';
    final n = _authorName.trim();
    return n.isEmpty ? 'Friend' : n.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    // "Add story" empty state — dashed placeholder card.
    if (widget.isOwn && !widget.hasStory) {
      return _pressable(child: _addStoryCard(context));
    }

    final Gradient? ringGradient = widget.isSeen
        ? null
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_indigo400, _indigo500, _indigo600],
          );

    return _pressable(
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Container(
          width: _ringW,
          height: _ringH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            gradient: ringGradient,
            color: widget.isSeen ? Colors.grey[300] : null,
          ),
          padding: const EdgeInsets.all(_ringPad),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius - _ringPad),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _cover(),
                // Bottom scrim for legibility of avatar/name.
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
        ),
      ),
    );
  }

  /// The tile's rect in global screen coordinates, for the zoom-open morph.
  Rect? _globalRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Widget _pressable({required Widget child}) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) {
        final rect = _globalRect();
        setState(() => _scale = 1.0);
        widget.onTap(rect);
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: child,
      ),
    );
  }

  Widget _cover() {
    final url = _coverUrl;
    if (url != null) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => _gradientFallback(),
        errorWidget: (_, __, ___) => _gradientFallback(),
      );
    }
    return _gradientFallback();
  }

  // Deterministic brand-tinted gradient when there's no cover image.
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
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ),
    );
  }

  // Frosted location pill, top-left — the "On the Map" signature.
  Widget _locationChip() {
    final place = widget.story['latest_external_place_name'] as String?;
    if (place == null || place.trim().isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.32),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded, size: 11, color: Colors.white),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  place.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
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
    final count = widget.story['story_count'];
    if (count is! int || count <= 1) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.32),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 0.5),
        ),
        child: Text(
          '$count',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // Poster: avatar + name, bottom-left.
  Widget _poster() {
    final avatarUrl = widget.story['author_avatar_url'] as String?;
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
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
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  // ---- "Add to your story" empty card ----
  Widget _addStoryCard(BuildContext context) {
    final avatarUrl = widget.story['author_avatar_url'] as String?;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Container(
        width: _ringW,
        height: _ringH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: Colors.grey[300]!, width: 1.5),
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft self-preview using the user's own avatar if available.
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _indigo500,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: _indigo500.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 22),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Text(
                'Your Story',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
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
