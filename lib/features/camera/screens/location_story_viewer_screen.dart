import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/features/home/widgets/comments_bottom_sheet.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

class LocationStoryViewerScreen extends StatefulWidget {
  final Map<String, dynamic> initialStory;
  final String? clusterId;

  const LocationStoryViewerScreen({
    super.key,
    required this.initialStory,
    this.clusterId,
  });

  @override
  State<LocationStoryViewerScreen> createState() =>
      _LocationStoryViewerScreenState();
}

class _LocationStoryViewerScreenState extends State<LocationStoryViewerScreen> {
  late PageController _pageController;
  List<Map<String, dynamic>> _stories = [];
  bool _isLoading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _stories = [widget.initialStory];
    _pageController = PageController();
    _fetchClusterStories();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchClusterStories() async {
    try {
      List<Map<String, dynamic>> fetched = [];

      // The map_live_stories_view is an aggregate (GROUP BY location) —
      // it doesn't have individual story IDs.
      // Query the posts table directly for full story data.
      final initialId = widget.initialStory['id']?.toString();

      if (widget.clusterId != null) {
        // Fetch all stories at this cluster location
        final isEvent = widget.clusterId!.startsWith('evt_');
        final isTable = widget.clusterId!.startsWith('tbl_');

        String columnToMatch = 'external_place_id';
        if (isEvent) columnToMatch = 'event_id';
        if (isTable) columnToMatch = 'table_id';

        final List<dynamic> response = await Supabase.instance.client
            .from('posts')
            .select(
              '*, user:user_id(id, display_name, avatar_url, user_photos(photo_url, is_primary))',
            )
            .eq('is_story', true)
            .eq(columnToMatch, widget.clusterId as Object)
            .gte(
              'created_at',
              DateTime.now()
                  .subtract(const Duration(hours: 24))
                  .toIso8601String(),
            )
            .order('created_at', ascending: false);

        fetched = List<Map<String, dynamic>>.from(response);
      } else if (initialId != null) {
        // Try fetching by the story's location coordinates
        final lat = widget.initialStory['latitude'];
        final lng = widget.initialStory['longitude'];

        if (lat != null && lng != null) {
          // Fetch stories near this location
          final List<dynamic> response = await Supabase.instance.client
              .from('posts')
              .select(
                '*, user:user_id(id, display_name, avatar_url, user_photos(photo_url, is_primary))',
              )
              .eq('is_story', true)
              .gte(
                'created_at',
                DateTime.now()
                    .subtract(const Duration(hours: 24))
                    .toIso8601String(),
              )
              .gte('latitude', (lat as num).toDouble() - 0.001)
              .lte('latitude', (lat as num).toDouble() + 0.001)
              .gte('longitude', (lng as num).toDouble() - 0.001)
              .lte('longitude', (lng as num).toDouble() + 0.001)
              .order('created_at', ascending: false);

          fetched = List<Map<String, dynamic>>.from(response);
        } else {
          // Fallback: fetch just this single story
          final res = await Supabase.instance.client
              .from('posts')
              .select(
                '*, user:user_id(id, display_name, avatar_url, user_photos(photo_url, is_primary))',
              )
              .eq('id', initialId)
              .maybeSingle();

          if (res != null) fetched = [Map<String, dynamic>.from(res)];
        }
      }

      // Map 'user' join to 'users' key and enrich avatar from user_photos
      for (final story in fetched) {
        final userData = story['user'] as Map?;
        if (userData != null) {
          // Enrich avatar_url from user_photos if missing
          String? avatarUrl = userData['avatar_url'] as String?;
          if (avatarUrl == null && userData['user_photos'] != null) {
            final photos = userData['user_photos'] as List;
            if (photos.isNotEmpty) {
              final primary = photos.firstWhere(
                (p) => p['is_primary'] == true,
                orElse: () => photos.first,
              );
              avatarUrl = primary['photo_url'] as String?;
            }
          }
          story['users'] = {
            'display_name': userData['display_name'],
            'avatar_url': avatarUrl,
          };
        }
      }

      // Fallback: keep initial story if fetch returned empty
      if (fetched.isEmpty) {
        fetched = [widget.initialStory];
      }

      if (mounted) {
        setState(() {
          _stories = fetched;
          final initialIndex = _stories.indexWhere(
            (s) => s['id']?.toString() == initialId,
          );
          _currentIndex = initialIndex != -1 ? initialIndex : 0;
          _pageController = PageController(initialPage: _currentIndex);
        });

        await _fetchInteractionsForStories();
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching cluster stories: $e');
      // Still load interactions for the initial story
      if (mounted) {
        await _fetchInteractionsForStories();
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchInteractionsForStories() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _stories.isEmpty) return;

    try {
      final postIds = _stories
          .map((s) => s['id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toList();

      final likesFuture = Supabase.instance.client
          .from('post_likes')
          .select('post_id')
          .inFilter('post_id', postIds)
          .eq('user_id', userId);

      final countsFuture = Supabase.instance.client
          .from('posts')
          .select('id, like_count, comment_count')
          .inFilter('id', postIds);

      final results = await Future.wait([likesFuture, countsFuture]);
      final likedPostIds = (results[0] as List)
          .map((l) => l['post_id'])
          .toSet();
      final countsData = results[1] as List;

      if (mounted) {
        setState(() {
          for (var i = 0; i < _stories.length; i++) {
            final story = _stories[i];
            story['_isLiked'] = likedPostIds.contains(story['id']);

            final countInfo = countsData.firstWhere(
              (c) => c['id'] == story['id'],
              orElse: () => null,
            );

            if (countInfo != null) {
              story['_likeCount'] = countInfo['like_count'] ?? 0;
              story['_commentCount'] = countInfo['comment_count'] ?? 0;
            } else {
              story['_likeCount'] = 0;
              story['_commentCount'] = 0;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching story interactions: $e');
    }
  }

  Future<void> _toggleLike(int index) async {
    final story = _stories[index];
    final postId = story['id']?.toString();
    if (postId == null || postId.isEmpty) return;

    final isCurrentlyLiked = story['_isLiked'] == true;

    setState(() {
      story['_isLiked'] = !isCurrentlyLiked;
      story['_likeCount'] =
          (story['_likeCount'] ?? 0) + (isCurrentlyLiked ? -1 : 1);
    });

    try {
      await SocialService().togglePostLike(postId);
    } catch (e) {
      if (mounted) {
        setState(() {
          story['_isLiked'] = isCurrentlyLiked;
          story['_likeCount'] =
              (story['_likeCount'] ?? 0) + (isCurrentlyLiked ? 1 : -1);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to update like')));
      }
    }
  }

  Future<void> _deleteStory(int index) async {
    final story = _stories[index];
    final postId = story['id'];

    if (mounted) {
      setState(() {
        _stories.removeAt(index);
        if (_stories.isEmpty) {
          Navigator.pop(context);
        }
      });
    }

    try {
      await SocialService().deletePost(postId);
    } catch (e) {
      debugPrint('Error deleting story: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete story: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading &&
        _stories.length == 1 &&
        _stories[0]['image_url'] == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _stories.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final story = _stories[index];
          final author = Map<String, dynamic>.from(
            story['users'] ??
                {
                  'display_name': story['display_name'] ?? story['author_name'],
                  'avatar_url': story['avatar_url'],
                },
          );
          final bool isCurrentPage = index == _currentIndex;

          return _StoryItem(
            story: story,
            author: author,
            isActive: isCurrentPage,
            onClose: () => Navigator.pop(context),
            onLike: () => _toggleLike(index),
            onComment: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => CommentsBottomSheet(post: story),
              );
            },
            onDelete:
                story['user_id'] ==
                    Supabase.instance.client.auth.currentUser?.id
                ? () => _deleteStory(index)
                : null,
          );
        },
      ),
    );
  }
}

class _StoryItem extends StatefulWidget {
  final Map<String, dynamic> story;
  final Map<String, dynamic> author;
  final bool isActive;
  final VoidCallback onClose;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback? onDelete;

  const _StoryItem({
    Key? key,
    required this.story,
    required this.author,
    required this.isActive,
    required this.onClose,
    required this.onLike,
    required this.onComment,
    this.onDelete,
  }) : super(key: key);

  @override
  State<_StoryItem> createState() => _StoryItemState();
}

class _StoryItemState extends State<_StoryItem> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(covariant _StoryItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _videoController?.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      _videoController?.pause();
      _videoController?.seekTo(Duration.zero);
    }
  }

  void _initializeVideo() {
    if (widget.story['video_url'] != null) {
      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(widget.story['video_url']))
            ..initialize().then((_) {
              if (mounted) {
                setState(() {
                  _isVideoInitialized = true;
                });
                _videoController!.setLooping(true);
                if (widget.isActive) {
                  _videoController!.play();
                }
              }
            });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Background Media
        if (widget.story['video_url'] != null && _isVideoInitialized)
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          )
        else if (widget.story['image_url'] != null)
          Image.network(
            widget.story['image_url'],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white, size: 50),
            ),
          )
        else
          Container(color: Colors.grey[900]),

        // Gradient Overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.4),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withOpacity(0.8),
              ],
              stops: const [0.0, 0.2, 0.7, 1.0],
            ),
          ),
        ),

        // 2. Top Bar
        Positioned(
          top: MediaQuery.of(context).padding.top + 40,
          left: 16,
          right: 16,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: widget.onClose,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  if (widget.story['user_id'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            UserProfileScreen(userId: widget.story['user_id']),
                      ),
                    );
                  }
                },
                child: CircleAvatar(
                  radius: 20,
                  backgroundImage: widget.author['avatar_url'] != null
                      ? NetworkImage(widget.author['avatar_url'])
                      : null,
                  backgroundColor: Colors.indigo,
                  child: widget.author['avatar_url'] == null
                      ? Text(
                          widget.author['display_name']?[0] ?? '?',
                          style: const TextStyle(color: Colors.white),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (widget.story['user_id'] != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(
                            userId: widget.story['user_id'],
                          ),
                        ),
                      );
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.author['display_name'] ?? 'Someone',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. Bottom Info
        Positioned(
          bottom: 40,
          left: 20,
          right: 70,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.story['content'] != null &&
                  widget.story['content'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    widget.story['content'],
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 1),
                          blurRadius: 3.0,
                          color: Colors.black.withOpacity(0.8),
                        ),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              if (widget.story['external_place_name'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.story['external_place_name'],
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              if (widget.story['caption'] != null &&
                  widget.story['caption'].toString().isNotEmpty)
                Text(
                  widget.story['caption'],
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
                ),

              const SizedBox(height: 8),

              if (widget.story['vibe_tag'] != null)
                Text(
                  '#${widget.story['vibe_tag']}',
                  style: GoogleFonts.inter(
                    color: Colors.indigoAccent.shade100,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),

        // 4. Right Side Interactions
        Positioned(
          right: 16,
          bottom: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  (widget.story['_isLiked'] == true)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: (widget.story['_isLiked'] == true)
                      ? Colors.red
                      : Colors.white,
                  size: 36,
                ),
                onPressed: widget.onLike,
              ),
              if ((widget.story['_likeCount'] ?? 0) > 0)
                Text(
                  '${widget.story['_likeCount']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 24),

              IconButton(
                icon: const Icon(Icons.comment, color: Colors.white, size: 36),
                onPressed: widget.onComment,
              ),
              if ((widget.story['_commentCount'] ?? 0) > 0)
                Text(
                  '${widget.story['_commentCount']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 24),

              if (widget.onDelete != null)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                    size: 36,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.grey[900],
                        title: const Text(
                          'Delete Story?',
                          style: TextStyle(color: Colors.white),
                        ),
                        content: const Text(
                          'Are you sure you want to remove this story? This cannot be undone.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onDelete!();
                            },
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
