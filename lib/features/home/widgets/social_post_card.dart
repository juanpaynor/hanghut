import 'package:flutter/material.dart';
import 'package:bitemates/core/utils/error_handler.dart';

import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/features/home/widgets/comments_bottom_sheet.dart';
import 'package:bitemates/features/sharing/models/share_payload.dart';
import 'package:bitemates/features/sharing/widgets/share_to_chat_sheet.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/widgets/full_screen_image_viewer.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/home/widgets/like_facepile.dart';
import 'package:bitemates/features/home/widgets/event_attachment_card.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/settings/widgets/report_modal.dart';
import 'package:bitemates/features/home/widgets/edit_post_modal.dart';
import 'package:bitemates/features/home/widgets/mention_text.dart';

/// Ensures only one feed video plays at a time. Mobile GPUs expose very few
/// hardware video decoders, so several simultaneously-playing feed videos cause
/// severe jank / heat. Cards request the single playback slot through this.
class _FeedVideoManager {
  _FeedVideoManager._();
  static final _FeedVideoManager instance = _FeedVideoManager._();

  VideoPlayerController? _active;

  void play(VideoPlayerController controller) {
    if (identical(_active, controller)) {
      if (controller.value.isInitialized && !controller.value.isPlaying) {
        controller.play();
      }
      return;
    }
    final previous = _active;
    _active = controller;
    if (previous != null && previous.value.isInitialized) {
      previous.pause();
    }
    if (controller.value.isInitialized) controller.play();
  }

  void release(VideoPlayerController controller) {
    if (identical(_active, controller)) _active = null;
  }
}

class SocialPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTap;
  final ValueChanged<String>? onPostDeleted;
  final ValueChanged<Map<String, dynamic>>? onPostEdited;

  const SocialPostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onPostDeleted,
    this.onPostEdited,
  });

  @override
  State<SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<SocialPostCard> {
  late bool _isLiked;
  late int _likeCount;
  bool _isAnimatingLike = false;
  Map<String, dynamic>? _attachedEvent;
  bool _isLoadingEvent = false;
  late int _commentCount;

  // Immersive (media-forward) card carousel state.
  final PageController _carouselController = PageController();
  int _carouselIndex = 0;

  // Inline video playback
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  // Set when inline init fails/times out (e.g. Android can't decode a QuickTime
  // .mov container). We then fall back to opening the video in the OS player.
  bool _videoError = false;
  bool _isMuted = true;
  // Visibility-gated playback: lazily init when the card scrolls into view and
  // only let the single most-visible video play (mobile has few HW decoders).
  ScrollPosition? _scrollPosition;
  bool _isActiveVideo = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post['user_has_liked'] ?? false;
    _likeCount = widget.post['likes_count'] ?? 0;
    _commentCount = widget.post['comment_count'] ?? 0;

    _fetchAttachedEvent();
    // Video is initialized lazily once the card scrolls into view — see
    // _evaluateVideoVisibility(). This avoids spinning up decoders for cards
    // built off-screen by the list's cacheExtent.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hasVideo =
        (widget.post['video_url'] as String?)?.isNotEmpty ?? false;
    if (!hasVideo) return;
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (!identical(newPosition, _scrollPosition)) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = newPosition;
      _scrollPosition?.addListener(_onScroll);
    }
    // Run an initial check after first layout so a video already on screen
    // (no scroll yet) still starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _evaluateVideoVisibility();
    });
  }

  void _onScroll() {
    if (mounted) _evaluateVideoVisibility();
  }

  /// Measures how much of this card is on screen and drives lazy init +
  /// single-active playback via [_FeedVideoManager].
  void _evaluateVideoVisibility() {
    final hasVideo =
        (widget.post['video_url'] as String?)?.isNotEmpty ?? false;
    if (!hasVideo) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || box.size.height == 0) return;

    final screenH = MediaQuery.of(context).size.height;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final visibleTop = top.clamp(0.0, screenH);
    final visibleBottom = bottom.clamp(0.0, screenH);
    final visibleFraction =
        ((visibleBottom - visibleTop) / box.size.height).clamp(0.0, 1.0);

    // Lazy-init the controller the first time the card is meaningfully visible.
    if (visibleFraction >= 0.25 && _videoController == null) {
      _initVideo();
    }

    if (visibleFraction >= 0.65) {
      // Most-visible card: claim the single playback slot.
      if (_videoInitialized && _videoController != null) {
        _FeedVideoManager.instance.play(_videoController!);
        _isActiveVideo = true;
      }
    } else if (visibleFraction < 0.25) {
      // Mostly off screen: yield the slot and pause.
      if (_isActiveVideo && _videoController != null) {
        _videoController!.pause();
        _FeedVideoManager.instance.release(_videoController!);
        _isActiveVideo = false;
      }
    }
  }

  void _initVideo() {
    final videoUrl = widget.post['video_url'] as String?;
    if (videoUrl == null || videoUrl.isEmpty || _videoController != null) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
      ..setLooping(true)
      ..setVolume(0); // Start muted
    _videoController = controller;
    controller
        .initialize()
        // Safety net: some unsupported containers make ExoPlayer hang rather
        // than error. Time out so we fall back to the OS player instead of
        // spinning forever.
        .timeout(const Duration(seconds: 12))
        .then((_) {
          if (!mounted) return;
          setState(() => _videoInitialized = true);
          // Re-check visibility now that it's ready — if still the visible
          // card, the manager starts it.
          _evaluateVideoVisibility();
        })
        .catchError((e) {
          debugPrint('Video init error: $e');
          if (mounted) setState(() => _videoError = true);
        });
  }

  @override
  void didUpdateWidget(covariant SocialPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync like state when parent rebuilds with fresh data (e.g. pull-to-refresh)
    if (oldWidget.post['id'] != widget.post['id']) {
      _isLiked = widget.post['user_has_liked'] ?? false;
      _likeCount = widget.post['likes_count'] ?? 0;
      _commentCount = widget.post['comment_count'] ?? 0;
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    if (_videoController != null) {
      _FeedVideoManager.instance.release(_videoController!);
    }
    _videoController?.dispose();
    _carouselController.dispose();
    super.dispose();
  }

  Future<void> _fetchAttachedEvent() async {
    final eventId = widget.post['event_id'];
    if (eventId == null) return;

    // Reuse a previously-fetched event cached on the post map. Without this,
    // scrolling a card off-screen and back re-runs initState → re-queries the
    // DB AND grows the card's height asynchronously once the result lands,
    // which shifts the feed (the "snap"/reload while scrolling). The post map
    // lives in the parent's list, so the cache survives card recreation.
    final cached = widget.post['_attachedEvent'];
    if (cached is Map<String, dynamic>) {
      _attachedEvent = cached; // set before first build → renders synchronously
      return;
    }

    if (mounted) setState(() => _isLoadingEvent = true);
    try {
      final data = await SupabaseConfig.client
          .from('events')
          .select('*')
          .eq('id', eventId)
          .single();
      widget.post['_attachedEvent'] = data; // cache for future rebuilds
      if (mounted) setState(() => _attachedEvent = data);
    } catch (e) {
      debugPrint('⚠️ [SocialPostCard] Error fetching event $eventId: $e');
    } finally {
      if (mounted) setState(() => _isLoadingEvent = false);
    }
  }

  /// Whether this post may be shared. Non-public posts (private / followers-
  /// only) must not leak via a share link — enforced at share time in the app,
  /// with web enforcing 404 as defense in depth (team_comms #252). Stories are
  /// gated separately in build() since they hard-expire.
  bool get _isShareable {
    final visibility =
        (widget.post['visibility'] as String?)?.toLowerCase() ?? 'public';
    return visibility == 'public';
  }

  /// Builds an [Event] model from the attached-event map, filling defaults for
  /// fields the feed query may omit. Returns null if there's no attached event.
  /// Shared by the open (tap) and share affordances.
  Event? _attachedEventModel() {
    if (_attachedEvent == null) return null;
    final eventData = Map<String, dynamic>.from(_attachedEvent!);
    eventData['venue_address'] ??= eventData['venue_name'] ?? 'TBA';
    eventData['category'] ??= 'general';
    eventData['created_at'] ??= DateTime.now().toIso8601String();
    eventData['tickets_sold'] ??= 0;
    return Event.fromJson(eventData);
  }

  void _handleLike() async {
    final wasLiked = _isLiked;
    final prevCount = _likeCount;

    // Optimistic Update
    setState(() {
      if (_isLiked) {
        _isLiked = false;
        _likeCount = (_likeCount - 1).clamp(0, 999999);
      } else {
        _isLiked = true;
        _likeCount++;
      }
    });

    // Await service — revert on failure
    try {
      await SocialService().togglePostLike(widget.post['id']);
    } catch (e) {
      // Revert optimistic update
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _likeCount = prevCount;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Extract data from Supabase post
    final content = widget.post['content'] as String? ?? '';
    final imageUrl = widget.post['image_url'] as String?;
    final imageUrls = widget.post['image_urls'] as List?;
    final gifUrl = widget.post['gif_url'] as String?;
    final videoUrl = widget.post['video_url'] as String?;
    final isStory = widget.post['is_story'] == true;
    final createdAt = widget.post['created_at'] as String?;
    final user = widget.post['user'] as Map<String, dynamic>?;
    final displayName = user?['display_name'] ?? 'User';
    final avatarUrl = user?['avatar_url'] as String?;

    // Convert image_urls to List<String> if present, otherwise use single image_url
    // Only show images if there's no GIF (mutually exclusive)
    final List<String> images = [];
    if (gifUrl == null || gifUrl.isEmpty) {
      if (imageUrls != null && imageUrls.isNotEmpty) {
        images.addAll(imageUrls.map((url) => url.toString()));
      } else if (imageUrl != null && imageUrl.isNotEmpty) {
        images.add(imageUrl);
      }
    }

    // Parse timestamp
    DateTime? postTime;
    if (createdAt != null) {
      try {
        postTime = DateTime.parse(createdAt);
      } catch (e) {
        debugPrint('⚠️ Error parsing timestamp: $e');
      }
    }

    // Media-forward immersive card for photo/GIF posts (team_comms n/a — design
    // ask). Video keeps the classic layout (its player is aspect-driven with its
    // own controls); event-attached & story posts stay classic too.
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;

    // Event-attached posts → immersive with the event cover as the media and the
    // event info (date / title / venue / price / Get Tickets) overlaid.
    final evCover = _attachedEvent?['cover_image_url']?.toString();
    if (!isStory && _attachedEvent != null && evCover != null && evCover.isNotEmpty) {
      return _buildImmersiveEventCard(
        displayName: displayName,
        avatarUrl: avatarUrl,
        user: user,
        postTime: postTime,
      );
    }

    final useImmersive = !isStory &&
        _attachedEvent == null &&
        widget.post['event_id'] == null && // event handled above
        !hasVideo &&
        (images.isNotEmpty || (gifUrl != null && gifUrl.isNotEmpty));
    if (useImmersive) {
      return _buildImmersiveCard(
        content: content,
        images: images,
        gifUrl: gifUrl,
        displayName: displayName,
        avatarUrl: avatarUrl,
        user: user,
        postTime: postTime,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row (Avatar + Name + Time)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // Navigate to user profile
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                userId: widget.post['user_id'],
                              ),
                            ),
                          );
                        },
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey[100],
                          backgroundImage:
                              avatarUrl != null && avatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(avatarUrl)
                              : null,
                          child: avatarUrl == null || avatarUrl.isEmpty
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                            if (postTime != null)
                              Text(
                                timeago.format(postTime),
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // More options menu (only show for post owner)
                      if (widget.post['user_id'] ==
                          SupabaseConfig.client.auth.currentUser?.id)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_horiz, color: Colors.grey[400]),
                          onSelected: (value) async {
                            if (value == 'edit') {
                              final result = await Navigator.of(context)
                                  .push<Map<String, dynamic>?>(
                                    PageRouteBuilder(
                                      opaque: false,
                                      barrierDismissible: true,
                                      barrierColor: Colors.black54,
                                      transitionDuration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      reverseTransitionDuration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      pageBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                          ) {
                                            return EditPostModal(
                                              post: widget.post,
                                            );
                                          },
                                      transitionsBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                            child,
                                          ) {
                                            return FadeTransition(
                                              opacity: CurvedAnimation(
                                                parent: animation,
                                                curve: Curves.easeOut,
                                              ),
                                              child: child,
                                            );
                                          },
                                    ),
                                  );
                              if (result != null && mounted) {
                                widget.onPostEdited?.call(result);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post updated')),
                                );
                              }
                            } else if (value == 'delete') {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Post'),
                                  content: const Text(
                                    'Are you sure you want to delete this post?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true && context.mounted) {
                                final success = await SocialService()
                                    .deletePost(widget.post['id']);
                                if (success && context.mounted) {
                                  widget.onPostDeleted?.call(widget.post['id']);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Post deleted'),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    color: Colors.black87,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Edit Post'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text(
                                    'Delete Post',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_horiz, color: Colors.grey[400]),
                          onSelected: (value) {
                            if (value == 'report') {
                              ReportModal.show(
                                context,
                                targetType: 'post',
                                targetId: widget.post['id'],
                                targetName: 'Post by $displayName',
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'report',
                              child: Row(
                                children: [
                                  Icon(Icons.flag_outlined, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text(
                                    'Report Post',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Post Text (with auto-linking for URLs)
                if (content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: MentionText(
                      text: content,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),

                // Event Attachment
                if (_attachedEvent != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: EventAttachmentCard(
                      event: _attachedEvent!,
                      onShare: () {
                        final event = _attachedEventModel();
                        if (event == null) return;
                        ShareToChatSheet.show(
                          context,
                          SharePayload.fromEvent(event),
                        );
                      },
                      onTap: () {
                        try {
                          final event = _attachedEventModel();
                          if (event == null) return;

                          // Always open the detail page first so the user sees
                          // the description/venue/date before any checkout. The
                          // modal's CTA handles both paths: external → redirect,
                          // internal → EventPurchaseScreen (with the approved-
                          // registration check). Previously internal Hanghut
                          // events skipped straight to checkout.
                          EventDetailModal.show(context, event);
                        } catch (e) {
                          debugPrint('Error parsing event: $e');
                          ErrorHandler.showError(
                            context,
                            error: e,
                            fallbackMessage: 'Could not open event',
                          );
                        }
                      },
                      onImageTap: () {
                        final imageUrl = _attachedEvent!['cover_image_url'];
                        if (imageUrl != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FullScreenImageViewer(imageUrl: imageUrl),
                            ),
                          );
                        }
                      },
                    ),
                  )
                else if (widget.post['event_id'] != null && _isLoadingEvent)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),

                // Video Display (if video_url present)
                if (videoUrl != null && videoUrl.isNotEmpty) ...[
                  _buildVideoThumbnail(videoUrl, imageUrl),
                  const SizedBox(height: 12),
                ]
                // Post Images (Grid Collage for multiple, single for one)
                else if (images.isNotEmpty) ...[
                  _buildImageCollage(images, isStory: isStory),
                  const SizedBox(height: 12),
                ],

                // GIF Display (mutually exclusive with images)
                if (gifUrl != null && gifUrl.isNotEmpty) ...[
                  AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Image.network(
                      gifUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[100],
                          child: Center(
                            child: Icon(
                              Icons.gif_box_outlined,
                              color: Colors.grey[400],
                              size: 40,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Who liked this (facepile + names) — renders nothing at 0 likes
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 16, 4),
                  child: LikeFacepile(
                    postId: widget.post['id'].toString(),
                    likeCount: _likeCount,
                    // Preview faces embedded by the feed RPC (top_likers) — no
                    // per-post fetch. Null on payloads without it (falls back).
                    initialLikers: (widget.post['top_likers'] as List?)
                        ?.map((e) => Map<String, dynamic>.from(e as Map))
                        .toList(),
                  ),
                ),

                // Action Buttons (Like, Comment)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      _buildActionButton(
                        icon: _isLiked
                            ? Icons.favorite
                            : Icons.favorite_border_rounded,
                        label: _likeCount > 0 ? '$_likeCount' : 'Like',
                        onTap: _handleLike,
                        color: _isLiked ? Colors.red : Colors.grey[600]!,
                        activeColor: Colors.red,
                      ),
                      const SizedBox(width: 20),
                      _buildActionButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        label:
                            widget.post['comment_count'] != null &&
                                widget.post['comment_count'] > 0
                            ? '${widget.post['comment_count']}'
                            : 'Comment',
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) =>
                                CommentsBottomSheet(post: widget.post),
                          );
                        },
                        color: Colors.grey[600],
                        activeColor: Colors.blueAccent,
                      ),
                      // Share is suppressed for stories (they hard-expire in
                      // 24h → a shared link would 404) and for non-public posts
                      // (private/followers-only must not leak via a share link).
                      // Coordinated with web in team_comms #252 (a)+(b).
                      if (!isStory && _isShareable) ...[
                        const SizedBox(width: 20),
                        _buildActionButton(
                          icon: Icons.share_outlined,
                          label: 'Share',
                          onTap: () => ShareToChatSheet.show(
                            context,
                            SharePayload.fromPost(widget.post),
                          ),
                          color: Colors.grey[600],
                          activeColor: Theme.of(context).primaryColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Divider between posts
        Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),
      ],
    );
  }

  /// Build inline video player (tap to play/pause, mute button, double-tap for fullscreen)
  // ══════════════════════════════════════════════════════════════════════════
  // Immersive (media-forward) card — photo/GIF posts. Full-bleed media with a
  // floating author pill, overlaid ⋮ menu, a vertical action rail, carousel dots
  // and an overlaid caption. Video/event/story posts keep the classic layout.
  // ══════════════════════════════════════════════════════════════════════════

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  Widget _buildImmersiveCard({
    required String content,
    required List<String> images,
    String? gifUrl,
    required String displayName,
    String? avatarUrl,
    Map<String, dynamic>? user,
    DateTime? postTime,
  }) {
    final multi = images.length > 1;
    Widget imgPlaceholder() => Container(color: Colors.grey[800]);

    void openMedia() {
      // Story taps route out via the feed; otherwise open the image full-screen
      // (there is no post-detail screen — widget.onTap is a no-op for posts).
      if (widget.post['is_story'] == true) {
        widget.onTap?.call();
        return;
      }
      final url = (gifUrl != null && gifUrl.isNotEmpty)
          ? gifUrl
          : (images.isNotEmpty
              ? images[_carouselIndex.clamp(0, images.length - 1)]
              : null);
      if (url != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenImageViewer(imageUrl: url),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: GestureDetector(
        onTap: openMedia,
        onDoubleTap: () {
          if (!_isLiked) _handleLike();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Media
                if (gifUrl != null && gifUrl.isNotEmpty)
                  Image.network(
                    gifUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => imgPlaceholder(),
                  )
                else if (multi)
                  PageView.builder(
                    controller: _carouselController,
                    onPageChanged: (i) => setState(() => _carouselIndex = i),
                    itemCount: images.length,
                    itemBuilder: (_, i) => CachedNetworkImage(
                      imageUrl: images[i],
                      fit: BoxFit.cover,
                      memCacheWidth: 1200,
                      placeholder: (_, __) => imgPlaceholder(),
                      errorWidget: (_, __, ___) => imgPlaceholder(),
                    ),
                  )
                else
                  CachedNetworkImage(
                    imageUrl: images.first,
                    fit: BoxFit.cover,
                    memCacheWidth: 1200,
                    placeholder: (_, __) => imgPlaceholder(),
                    errorWidget: (_, __, ___) => imgPlaceholder(),
                  ),

                // Legibility scrims (top for pill/menu, bottom for caption/rail).
                // Ramps to near-opaque at the bottom so white text stays legible
                // even over a light/white poster.
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x73000000),
                          Color(0x00000000),
                          Color(0x80000000),
                          Color(0xF7000000),
                        ],
                        stops: [0.0, 0.30, 0.60, 1.0],
                      ),
                    ),
                  ),
                ),

                // Author pill
                Positioned(
                  top: 12,
                  left: 12,
                  right: 58,
                  child: _immersiveAuthorPill(
                      displayName, avatarUrl, user, postTime),
                ),

                // More menu
                Positioned(
                  top: 12,
                  right: 10,
                  child: _immersiveMoreMenu(displayName),
                ),

                // Vertical action rail
                Positioned(right: 8, bottom: 22, child: _immersiveActionRail()),

                // Carousel dots
                if (multi)
                  Positioned(
                    left: 16,
                    bottom: content.isNotEmpty ? 58 : 18,
                    child: Row(
                      children: List.generate(images.length, (i) {
                        final active = i == _carouselIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: active ? 18 : 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white54,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),

                // Caption
                if (content.isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 60,
                    bottom: 16,
                    child: Text(
                      content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(color: Color(0x99000000), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImmersiveEventCard({
    required String displayName,
    String? avatarUrl,
    Map<String, dynamic>? user,
    DateTime? postTime,
  }) {
    const accent = Color(0xFF6C63FF);
    final ev = _attachedEvent!;
    final cover = ev['cover_image_url'].toString();
    final title = (ev['title'] ?? 'Event').toString();
    final venue = (ev['venue_name'] ?? '').toString();
    final price = ev['ticket_price'];
    final isFree = price == null || (price is num && price <= 0);
    String whenStr = '';
    final raw = ev['start_datetime']?.toString();
    if (raw != null) {
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt != null) whenStr = DateFormat('MMM d · h:mm a').format(dt);
    }
    void open() {
      final event = _attachedEventModel();
      if (event != null) EventDetailModal.show(context, event);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: GestureDetector(
        onTap: open,
        onDoubleTap: () {
          if (!_isLiked) _handleLike();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  // Cap decode size — a full-res poster decoded at native size is
                  // a common scroll-jank source in a phone-width card.
                  memCacheWidth: 1200,
                  placeholder: (_, __) => Container(color: Colors.grey[800]),
                  errorWidget: (_, __, ___) => Container(color: Colors.grey[800]),
                ),

                // Stronger bottom scrim — the info block needs more contrast,
                // and must stay legible over light/white event posters.
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x73000000),
                          Color(0x00000000),
                          Color(0x80000000),
                          Color(0xF7000000),
                        ],
                        stops: [0.0, 0.28, 0.58, 1.0],
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 12,
                  left: 12,
                  right: 58,
                  child: _immersiveAuthorPill(
                      displayName, avatarUrl, user, postTime),
                ),
                Positioned(
                  top: 12,
                  right: 10,
                  child: _immersiveMoreMenu(displayName),
                ),
                // Rail sits higher so it never collides with the info block.
                Positioned(right: 8, bottom: 150, child: _immersiveActionRail()),

                // Event info block
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (whenStr.isNotEmpty)
                        Text(
                          whenStr.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            shadows: [
                              Shadow(color: Color(0x99000000), blurRadius: 6),
                            ],
                          ),
                        ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(color: Color(0x99000000), blurRadius: 10),
                          ],
                        ),
                      ),
                      if (venue.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                venue,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                        color: Color(0x99000000),
                                        blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isFree
                                  ? const Color(0xFF22A06B)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              isFree
                                  ? 'FREE'
                                  : '₱${(price as num).toStringAsFixed(0)}',
                              style: TextStyle(
                                color:
                                    isFree ? Colors.white : const Color(0xFF15131E),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: open,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 8),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Text(
                                'Get Tickets  →',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _immersiveAuthorPill(String displayName, String? avatarUrl,
      Map<String, dynamic>? user, DateTime? postTime) {
    final username = user?['username']?.toString();
    final verified =
        user?['is_verified'] == true || user?['verified'] == true;
    final sub = [
      if (username != null && username.isNotEmpty) '@$username',
      if (postTime != null) timeago.format(postTime),
    ].join(' · ');
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(userId: widget.post['user_id']),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.verified,
                            color: Color(0xFF4FA0FF), size: 14),
                      ],
                    ],
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _immersiveActionRail() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _railAction(
          icon: _isLiked ? Icons.favorite : Icons.favorite_border_rounded,
          label: _likeCount > 0 ? _compact(_likeCount) : '',
          color: _isLiked ? Colors.red : Colors.white,
          onTap: _handleLike,
        ),
        const SizedBox(height: 16),
        _railAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: _commentCount > 0 ? _compact(_commentCount) : '',
          color: Colors.white,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => CommentsBottomSheet(post: widget.post),
          ),
        ),
        if (_isShareable) ...[
          const SizedBox(height: 16),
          _railAction(
            icon: Icons.send_outlined,
            label: '',
            color: Colors.white,
            onTap: () => ShareToChatSheet.show(
              context,
              SharePayload.fromPost(widget.post),
            ),
          ),
        ],
      ],
    );
  }

  Widget _railAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 29,
            shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8)],
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Color(0x99000000), blurRadius: 6)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _immersiveMoreMenu(String displayName) {
    final isOwner =
        widget.post['user_id'] == SupabaseConfig.client.auth.currentUser?.id;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, color: Colors.white),
        onSelected: (value) async {
          if (value == 'report') {
            ReportModal.show(
              context,
              targetType: 'post',
              targetId: widget.post['id'],
              targetName: 'Post by $displayName',
            );
          } else if (value == 'edit') {
            final result = await Navigator.of(context).push<Map<String, dynamic>?>(
              PageRouteBuilder(
                opaque: false,
                barrierDismissible: true,
                barrierColor: Colors.black54,
                transitionDuration: const Duration(milliseconds: 300),
                reverseTransitionDuration: const Duration(milliseconds: 250),
                pageBuilder: (context, animation, secondaryAnimation) =>
                    EditPostModal(post: widget.post),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(
                  opacity: CurvedAnimation(
                      parent: animation, curve: Curves.easeOut),
                  child: child,
                ),
              ),
            );
            if (result != null && mounted) {
              widget.onPostEdited?.call(result);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Post updated')),
                );
              }
            }
          } else if (value == 'delete') {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Post'),
                content:
                    const Text('Are you sure you want to delete this post?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirm == true && context.mounted) {
              final success =
                  await SocialService().deletePost(widget.post['id']);
              if (success && context.mounted) {
                widget.onPostDeleted?.call(widget.post['id']);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Post deleted')),
                );
              }
            }
          }
        },
        itemBuilder: (context) => isOwner
            ? const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, color: Colors.black87),
                    SizedBox(width: 8),
                    Text('Edit Post'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Post', style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ]
            : const [
                PopupMenuItem(
                  value: 'report',
                  child: Row(children: [
                    Icon(Icons.flag_outlined, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Report Post', style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
      ),
    );
  }

  Widget _buildVideoThumbnail(String videoUrl, String? posterUrl) {
    if (_videoInitialized && _videoController != null) {
      final isPlaying = _videoController!.value.isPlaying;
      return GestureDetector(
        onTap: () {
          setState(() {
            if (_videoController!.value.isPlaying) {
              _videoController!.pause();
              _FeedVideoManager.instance.release(_videoController!);
              _isActiveVideo = false;
            } else {
              // Route through the manager so any other playing video pauses.
              _FeedVideoManager.instance.play(_videoController!);
              _isActiveVideo = true;
            }
          });
        },
        onDoubleTap: () => _openVideoPlayer(videoUrl),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
            // Play/Pause overlay
            if (!isPlaying)
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            // Mute/unmute button (bottom-right)
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isMuted = !_isMuted;
                    _videoController!.setVolume(_isMuted ? 0 : 1);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
            // Video badge
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Video',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Init failed (e.g. Android can't decode a QuickTime .mov container) — show
    // the poster with a Tap-to-play button that hands off to the OS video
    // player, which handles containers ExoPlayer won't.
    if (_videoError) {
      return GestureDetector(
        onTap: () => _launchVideoExternally(videoUrl),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (posterUrl != null && posterUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: posterUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[900]),
                )
              else
                Container(color: Colors.grey[900]),
              Container(color: Colors.black.withOpacity(0.35)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Tap to play',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Loading / fallback state — show poster with loading spinner
    return GestureDetector(
      onTap: () => _openVideoPlayer(videoUrl),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (posterUrl != null && posterUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: posterUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Colors.grey[900]),
              )
            else
              Container(
                color: Colors.grey[900],
                child: Icon(Icons.videocam, color: Colors.grey[600], size: 48),
              ),
            Container(color: Colors.black.withOpacity(0.3)),
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _openVideoPlayer(String videoUrl) {
    // If inline playback already failed, don't push a fullscreen player that
    // would fail the same way — hand off to the OS player.
    if (_videoError) {
      _launchVideoExternally(videoUrl);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenVideoPlayer(videoUrl: videoUrl),
      ),
    );
  }

  /// Build collage grid for images (Instagram/Facebook style)
  Widget _buildImageCollage(List<String> imageUrls, {bool isStory = false}) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    // Single image — Instagram-style: 4:5 portrait (tallest allowed), cover crop
    if (imageUrls.length == 1) {
      return GestureDetector(
        onTap: () {
          if (isStory && widget.onTap != null) {
            widget.onTap!(); // Route to story viewer
          } else {
            _openImageViewer(imageUrls, 0);
          }
        },
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: CachedNetworkImage(
                imageUrl: imageUrls[0],
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => _buildErrorImage(),
              ),
            ),
            // Story indicator badge
            if (isStory)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Story',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Two images - side by side, 1:1 square crops (Instagram style)
    if (imageUrls.length == 2) {
      return AspectRatio(
        aspectRatio: 2 / 1,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _openImageViewer(imageUrls, 0),
                child: CachedNetworkImage(
                  imageUrl: imageUrls[0],
                  height: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: GestureDetector(
                onTap: () => _openImageViewer(imageUrls, 1),
                child: CachedNetworkImage(
                  imageUrl: imageUrls[1],
                  height: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Three images - 1 large on left, 2 stacked on right
    if (imageUrls.length == 3) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => _openImageViewer(imageUrls, 0),
                child: CachedNetworkImage(
                  imageUrl: imageUrls[0],
                  height: 250,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openImageViewer(imageUrls, 1),
                      child: CachedNetworkImage(
                        imageUrl: imageUrls[1],
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openImageViewer(imageUrls, 2),
                      child: CachedNetworkImage(
                        imageUrl: imageUrls[2],
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Four+ images - 2x2 grid, with "+X" overlay for more
    return AspectRatio(
      aspectRatio: 1,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openImageViewer(imageUrls, 0),
                    child: CachedNetworkImage(
                      imageUrl: imageUrls[0],
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openImageViewer(imageUrls, 2),
                    child: CachedNetworkImage(
                      imageUrl: imageUrls[2],
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openImageViewer(imageUrls, 1),
                    child: CachedNetworkImage(
                      imageUrl: imageUrls[1],
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openImageViewer(imageUrls, 3),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: imageUrls[3],
                          fit: BoxFit.cover,
                        ),
                        if (imageUrls.length > 4)
                          Container(
                            color: Colors.black.withOpacity(0.6),
                            child: Center(
                              child: Text(
                                '+${imageUrls.length - 4}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openImageViewer(List<String> images, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          imageUrl: images[initialIndex],
          imageUrls: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _buildErrorImage() {
    return Container(
      height: 250,
      color: Colors.grey[100],
      child: Center(
        child: Icon(
          Icons.image_not_supported_rounded,
          color: Colors.grey[400],
          size: 40,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    Color? activeColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: activeColor != null && color == Colors.red
                  ? activeColor
                  : (color ?? Colors.grey[600]),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color ?? Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen video player (tap to play/pause, swipe to dismiss)
class _FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const _FullScreenVideoPlayer({required this.videoUrl});

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller
        .initialize()
        .timeout(const Duration(seconds: 12))
        .then((_) {
          if (mounted) {
            setState(() => _isInitialized = true);
            _controller.play();
            _controller.setLooping(true);
          }
        })
        .catchError((e) {
          if (mounted) setState(() => _error = true);
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: _togglePlayPause,
        child: Center(
          child: _isInitialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      // Play/Pause overlay
                      if (!_controller.value.isPlaying)
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                )
              : _error
                  ? _buildFullscreenError(context)
                  : const CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildFullscreenError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_circle_outline,
              color: Colors.white70, size: 64),
          const SizedBox(height: 16),
          const Text(
            "This video can't play in-app on this device.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _launchVideoExternally(widget.videoUrl);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            label: const Text('Open in player'),
          ),
        ],
      ),
    );
  }
}

/// Opens [url] in the device's default handler (OS video player / browser).
/// Fallback for when in-app playback fails on an unsupported container (e.g.
/// a QuickTime .mov that Android's ExoPlayer can't decode). Pure Dart via
/// url_launcher — safe to ship as a Shorebird patch.
Future<void> _launchVideoExternally(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
