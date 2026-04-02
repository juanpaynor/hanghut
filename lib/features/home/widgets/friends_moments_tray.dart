import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

class FriendsMomentsTray extends StatefulWidget {
  final List<Map<String, dynamic>> stories;
  final Function(Map<String, dynamic>) onStoryTap;
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
    // Trigger load more when near the end
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.onLoadMore?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading && widget.stories.isEmpty && widget.onAddStory == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Text(
            "Moments",
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),

        // Story Cards
        SizedBox(
          height: 110,
          child: widget.isLoading && widget.stories.isEmpty
              ? _buildShimmer()
              : ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.stories.length + (widget.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Loading indicator at end for pagination
                    if (index >= widget.stories.length) {
                      return const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: SizedBox(
                          width: 76,
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
                    final isSeen = story['is_seen'] == true;
                    final hasStory = (story['story_count'] ?? 0) > 0;

                    // "Your Story" bubble (first item if is_own)
                    if (isOwn) {
                      return _YourStoryCard(
                        story: story,
                        hasStory: hasStory,
                        onTap: () {
                          if (hasStory) {
                            widget.onStoryTap(story);
                          } else {
                            widget.onAddStory?.call();
                          }
                        },
                      );
                    }

                    return _StoryCard(
                      story: story,
                      isSeen: isSeen,
                      onTap: () => widget.onStoryTap(story),
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
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 52,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// "Your Story" Card — always first in tray
// ==========================================
class _YourStoryCard extends StatefulWidget {
  final Map<String, dynamic> story;
  final bool hasStory;
  final VoidCallback onTap;

  const _YourStoryCard({
    required this.story,
    required this.hasStory,
    required this.onTap,
  });

  @override
  State<_YourStoryCard> createState() => _YourStoryCardState();
}

class _YourStoryCardState extends State<_YourStoryCard> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.story['author_avatar_url'];

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.92),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ring + avatar
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  // Gradient ring if has story, dashed grey if no story
                  gradient: widget.hasStory
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF818CF8), // Indigo 400
                            Color(0xFF6366F1), // Indigo 500
                            Color(0xFF4F46E5), // Indigo 600
                          ],
                        )
                      : null,
                  border: !widget.hasStory
                      ? Border.all(color: Colors.grey[300]!, width: 2)
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.all(widget.hasStory ? 3 : 1),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(21),
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Stack(
                        children: [
                          // Avatar
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(19),
                              color: Colors.grey[300],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: avatarUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                    width: 66,
                                    height: 66,
                                    placeholder: (context, url) => Container(
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: Icon(Icons.person, color: Colors.grey),
                                      ),
                                    ),
                                    errorWidget: (context, url, err) =>
                                        _buildYouAvatar(),
                                  )
                                : _buildYouAvatar(),
                          ),

                          // "+" badge if no story
                          if (!widget.hasStory)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: Theme.of(context).scaffoldBackgroundColor,
                                    width: 2,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Label
              SizedBox(
                width: 76,
                child: Text(
                  "Your Story",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYouAvatar() {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person,
          size: 30,
          color: Colors.white.withOpacity(0.9),
        ),
      ),
    );
  }
}

// ==========================================
// Friend Story Card — with seen/unseen ring
// ==========================================
class _StoryCard extends StatefulWidget {
  final Map<String, dynamic> story;
  final bool isSeen;
  final VoidCallback onTap;

  const _StoryCard({
    required this.story,
    required this.isSeen,
    required this.onTap,
  });

  @override
  State<_StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<_StoryCard> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final authorName =
        widget.story['author_name'] ?? widget.story['display_name'] ?? 'Friend';
    final avatarUrl =
        widget.story['author_avatar_url'] ?? widget.story['avatar_url'];
    final storyCount = widget.story['story_count'] ?? 1;
    final firstName = authorName.toString().split(' ').first;

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.92),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient ring (unseen = indigo gradient, seen = grey)
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: widget.isSeen
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF818CF8), // Indigo 400
                            Color(0xFF6366F1), // Indigo 500
                            Color(0xFF4F46E5), // Indigo 600
                          ],
                        ),
                  color: widget.isSeen ? Colors.grey[300] : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3), // Ring thickness
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(21),
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2), // Inner gap
                      child: Stack(
                        children: [
                          // Avatar image
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(19),
                              color: Colors.grey[300],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: avatarUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                    width: 66,
                                    height: 66,
                                    placeholder: (context, url) => Container(
                                      color: Colors.grey[200],
                                      child: Center(
                                        child: Text(
                                          firstName.isNotEmpty
                                              ? firstName[0].toUpperCase()
                                              : '?',
                                          style: GoogleFonts.inter(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, err) =>
                                        _buildInitialAvatar(firstName),
                                  )
                                : _buildInitialAvatar(firstName),
                          ),

                          // Story count badge (bottom-right)
                          if (storyCount is int && storyCount > 1)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: widget.isSeen
                                      ? Colors.grey[500]
                                      : Theme.of(context).primaryColor,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).scaffoldBackgroundColor,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$storyCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Name label
              SizedBox(
                width: 76,
                child: Text(
                  firstName,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isSeen ? Colors.grey[500] : Colors.grey[800],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialAvatar(String name) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
