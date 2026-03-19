import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/features/home/widgets/comments_bottom_sheet.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/core/services/analytics_service.dart';

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

class _LocationStoryViewerScreenState extends State<LocationStoryViewerScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _stories = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _isPopping = false;
  bool _isPaused = false;

  // Progress animation
  late AnimationController _progressController;

  // Video player for current video story
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;

  // Timer for image stories
  static const _imageDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
    _stories = [widget.initialStory];
    _fetchClusterStories();
    AnalyticsService().logScreenView('story_viewer');
  }

  @override
  void dispose() {
    _progressController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  // DATA LAYER (preserved from original)
  // ═══════════════════════════════════════════════

  Future<void> _fetchClusterStories() async {
    try {
      List<Map<String, dynamic>> fetched = [];

      final initialId = widget.initialStory['id']?.toString();

      if (widget.clusterId != null) {
        final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(widget.clusterId!);
        final isEvent = widget.clusterId!.startsWith('evt_');
        final isTable = widget.clusterId!.startsWith('tbl_');

        String columnToMatch = 'external_place_id';
        if (isUuid) columnToMatch = 'user_id';
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
                  .toUtc()
                  .toIso8601String(),
            )
            .order('created_at', ascending: false);

        fetched = List<Map<String, dynamic>>.from(response);
      } else if (initialId != null) {
        final lat = widget.initialStory['latitude'];
        final lng = widget.initialStory['longitude'];

        if (lat != null && lng != null) {
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
                    .toUtc()
                    .toIso8601String(),
              )
              .gte('latitude', (lat as num).toDouble() - 0.001)
              .lte('latitude', (lat as num).toDouble() + 0.001)
              .gte('longitude', (lng as num).toDouble() - 0.001)
              .lte('longitude', (lng as num).toDouble() + 0.001)
              .order('created_at', ascending: false);

          fetched = List<Map<String, dynamic>>.from(response);
        } else {
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

      // Enrich avatar from user_photos
      for (final story in fetched) {
        final userData = story['user'] as Map?;
        if (userData != null) {
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

      if (fetched.isEmpty) {
        fetched = [widget.initialStory];
      }

      if (mounted) {
        final initialIndex = fetched.indexWhere(
          (s) => s['id']?.toString() == initialId,
        );
        setState(() {
          _stories = fetched;
          _currentIndex = initialIndex != -1 ? initialIndex : 0;
        });

        await _fetchInteractionsForStories();
        setState(() => _isLoading = false);
        _startCurrentStory();
      }
    } catch (e) {
      debugPrint('Error fetching cluster stories: $e');
      if (mounted) {
        await _fetchInteractionsForStories();
        setState(() => _isLoading = false);
        _startCurrentStory();
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
          .select('id, post_likes(count), comments(count)')
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

            final countInfo = countsData
                .cast<Map<String, dynamic>?>()
                .firstWhere((c) => c?['id'] == story['id'], orElse: () => null);

            if (countInfo != null) {
              final likesList = countInfo['post_likes'] as List?;
              final commentsList = countInfo['comments'] as List?;

              story['_likeCount'] = likesList != null && likesList.isNotEmpty
                  ? likesList[0]['count'] ?? 0
                  : 0;
              story['_commentCount'] =
                  commentsList != null && commentsList.isNotEmpty
                  ? commentsList[0]['count'] ?? 0
                  : 0;
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

  // ═══════════════════════════════════════════════
  // STORY PLAYBACK CONTROLLER
  // ═══════════════════════════════════════════════

  bool get _isVideo => _stories[_currentIndex]['video_url'] != null;

  void _startCurrentStory() {
    if (_stories.isEmpty || _currentIndex >= _stories.length) return;

    _videoError = false;
    _videoInitialized = false;

    final storyId = _stories[_currentIndex]['id']?.toString();
    if (storyId != null) AnalyticsService().logViewStory(storyId);

    if (_isVideo) {
      _startVideoStory();
    } else {
      _startImageStory();
    }
  }

  void _startImageStory() {
    _progressController.stop();
    _progressController.reset();
    _progressController.duration = _imageDuration;
    _progressController.forward();
    _progressController.addStatusListener(_onProgressComplete);
  }

  void _startVideoStory() async {
    _videoController?.dispose();
    _videoController = null;

    final url = _stories[_currentIndex]['video_url'] as String;

    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoController!.initialize();
      if (!mounted) return;

      setState(() => _videoInitialized = true);

      // Set progress duration to video duration
      _progressController.stop();
      _progressController.reset();
      _progressController.duration = _videoController!.value.duration;
      _progressController.forward();
      _progressController.addStatusListener(_onProgressComplete);

      _videoController!.play();
    } catch (e) {
      debugPrint('⚠️ Video load error: $e');
      if (!mounted) return;
      setState(() => _videoError = true);

      // Auto-advance after 3 seconds on error
      _progressController.stop();
      _progressController.reset();
      _progressController.duration = const Duration(seconds: 3);
      _progressController.forward();
      _progressController.addStatusListener(_onProgressComplete);
    }
  }

  void _onProgressComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _progressController.removeStatusListener(_onProgressComplete);
      _goNext();
    }
  }

  void _goNext() {
    if (_currentIndex >= _stories.length - 1) {
      // Last story — close
      if (mounted && !_isPopping) {
        _isPopping = true;
        Navigator.pop(context);
      }
      return;
    }

    _progressController.removeStatusListener(_onProgressComplete);
    _videoController?.dispose();
    _videoController = null;

    setState(() {
      _currentIndex++;
      _videoInitialized = false;
      _videoError = false;
    });
    _startCurrentStory();
  }

  void _goPrevious() {
    if (_currentIndex <= 0) {
      // Restart current story
      _progressController.removeStatusListener(_onProgressComplete);
      _videoController?.dispose();
      _videoController = null;
      _startCurrentStory();
      return;
    }

    _progressController.removeStatusListener(_onProgressComplete);
    _videoController?.dispose();
    _videoController = null;

    setState(() {
      _currentIndex--;
      _videoInitialized = false;
      _videoError = false;
    });
    _startCurrentStory();
  }

  void _pause() {
    if (_isPaused) return;
    _isPaused = true;
    _progressController.stop(canceled: false);
    _videoController?.pause();
  }

  void _resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _progressController.forward();
    _videoController?.play();
  }

  // ═══════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════

  String _formatTimeAgo(String? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.parse(timestamp);
    final diff = DateTime.now().toUtc().difference(date);

    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Map<String, dynamic> _getAuthor(Map<String, dynamic> story) {
    return Map<String, dynamic>.from(
      story['users'] ??
          {
            'display_name':
                story['display_name'] ?? story['author_name'] ?? 'Someone',
            'avatar_url': story['avatar_url'] ?? story['author_avatar_url'],
          },
    );
  }

  // ═══════════════════════════════════════════════
  // UI LAYER — Custom Story Viewer
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading &&
        _stories.length == 1 &&
        _stories[0]['image_url'] == null &&
        _stories[0]['video_url'] == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_stories.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No stories', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 10 && mounted && !_isPopping) {
            _isPopping = true;
            Navigator.pop(context);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media content
            _buildMediaContent(),

            // Left/Right tap zones
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onTap: _goPrevious,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onTap: _goNext,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),

            // Progress indicators
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              right: 12,
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, _) => _buildProgressIndicators(),
              ),
            ),

            // Header
            _buildHeader(),

            // Footer
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildFooter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent() {
    if (_currentIndex >= _stories.length) return const SizedBox();
    final story = _stories[_currentIndex];
    final hasVideo = story['video_url'] != null;

    if (hasVideo) {
      if (_videoError) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, color: Colors.white54, size: 48),
              SizedBox(height: 12),
              Text(
                'Video couldn\'t be played',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        );
      }

      if (_videoInitialized && _videoController != null) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        );
      }

      // Loading state
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else {
      // Image story
      final imageUrl = story['image_url'] ?? '';
      if (imageUrl.isEmpty) {
        return const Center(
          child: Icon(Icons.image_not_supported, color: Colors.white54, size: 48),
        );
      }
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        ),
      );
    }
  }

  Widget _buildProgressIndicators() {
    return Row(
      children: List.generate(_stories.length, (index) {
        double progress;
        if (index < _currentIndex) {
          progress = 1.0; // Completed
        } else if (index == _currentIndex) {
          progress = _progressController.value; // Current
        } else {
          progress = 0.0; // Upcoming
        }

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < _stories.length - 1 ? 4 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1.5),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white30,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 2.5,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHeader() {
    if (_currentIndex >= _stories.length) return const SizedBox();
    final story = _stories[_currentIndex];
    final author = _getAuthor(story);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 24,
      left: 12,
      right: 12,
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (story['user_id'] != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        UserProfileScreen(userId: story['user_id']),
                  ),
                );
              }
            },
            child: CircleAvatar(
              radius: 18,
              backgroundImage: author['avatar_url'] != null
                  ? NetworkImage(author['avatar_url'])
                  : null,
              backgroundColor: Colors.indigo,
              child: author['avatar_url'] == null
                  ? Text(
                      author['display_name']?[0] ?? '?',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (story['user_id'] != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserProfileScreen(userId: story['user_id']),
                    ),
                  );
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    author['display_name'] ?? 'Someone',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _formatTimeAgo(story['created_at']),
                    style: GoogleFonts.inter(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Close button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.black26,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    if (_currentIndex >= _stories.length) return const SizedBox();
    final story = _stories[_currentIndex];
    final isOwner =
        story['user_id'] == Supabase.instance.client.auth.currentUser?.id;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.only(bottom: 41, left: 16, right: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content text
            if (story['content'] != null &&
                story['content'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  story['content'],
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
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

            // Location pill
            if (story['external_place_name'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
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
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        story['external_place_name'],
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Vibe tag
            if (story['vibe_tag'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '#${story['vibe_tag']}',
                  style: GoogleFonts.inter(
                    color: Colors.indigoAccent.shade100,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),

            // Interaction row
            Row(
              children: [
                // Like button
                GestureDetector(
                  onTap: () => _toggleLike(_currentIndex),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (story['_isLiked'] == true)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: (story['_isLiked'] == true)
                            ? Colors.red
                            : Colors.white,
                        size: 28,
                      ),
                      if ((story['_likeCount'] ?? 0) > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${story['_likeCount']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 20),

                // Comment button
                GestureDetector(
                  onTap: () {
                    _pause();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => CommentsBottomSheet(post: story),
                    ).then((_) {
                      if (mounted) _resume();
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.white,
                        size: 26,
                      ),
                      if ((story['_commentCount'] ?? 0) > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${story['_commentCount']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const Spacer(),

                // Delete button (own stories only)
                if (isOwner)
                  GestureDetector(
                    onTap: () {
                      _pause();
                      showDialog(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          title: const Text(
                            'Delete Story?',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: const Text(
                            'This cannot be undone.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(dialogCtx);
                                _resume();
                              },
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(dialogCtx);
                                _deleteStory(_currentIndex);
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
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white70,
                      size: 26,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
