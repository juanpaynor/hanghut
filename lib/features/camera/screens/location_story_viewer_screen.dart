import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/settings/widgets/report_modal.dart';
import 'package:bitemates/features/home/widgets/comments_bottom_sheet.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/core/services/analytics_service.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/camera/widgets/story_viewers_sheet.dart';

class LocationStoryViewerScreen extends StatefulWidget {
  final Map<String, dynamic> initialStory;
  final String? clusterId;
  final List<Map<String, dynamic>>? allUserStories;
  final int startUserIndex;

  const LocationStoryViewerScreen({
    super.key,
    required this.initialStory,
    this.clusterId,
    this.allUserStories,
    this.startUserIndex = 0,
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

  // Cross-user navigation
  List<Map<String, dynamic>> _userQueue = [];
  int _currentUserIndex = 0;
  bool _isLoadingNextUser = false;

  // Progress animation
  late AnimationController _progressController;

  // Video player for current video story
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;

  // Story viewers tracking
  final Map<String, int> _viewerCounts = {}; // postId -> count
  final Set<String> _recordedViews = {}; // postIds we've already recorded

  // Timer for image stories
  static const _imageDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
    _stories = [widget.initialStory];
    _userQueue = widget.allUserStories ?? [];
    _currentUserIndex = widget.startUserIndex;
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

    // Stop current playback before modifying the list
    _progressController.removeStatusListener(_onProgressComplete);
    _progressController.stop();
    _videoController?.dispose();
    _videoController = null;

    if (mounted) {
      setState(() {
        _stories.removeAt(index);
        if (_stories.isEmpty) {
          Navigator.pop(context);
          return;
        }
        // Adjust index: if we deleted the last story, move back
        if (_currentIndex >= _stories.length) {
          _currentIndex = _stories.length - 1;
        }
        _videoInitialized = false;
        _videoError = false;
      });

      // Start playing the next/current story
      if (_stories.isNotEmpty) {
        _startCurrentStory();
      }
    }

    try {
      await SocialService().deletePost(postId);
    } catch (e) {
      debugPrint('Error deleting story: $e');
      if (mounted) {
        ErrorHandler.showError(context, error: e, fallbackMessage: 'Failed to delete story');
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

    final story = _stories[_currentIndex];
    final storyId = story['id']?.toString();
    if (storyId != null) {
      AnalyticsService().logViewStory(storyId);
      _recordView(storyId, story['user_id']);
    }

    // Fetch viewer count if this is the owner's story
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (storyId != null && story['user_id'] == currentUserId) {
      _fetchViewerCount(storyId);
    }

    if (_isVideo) {
      _startVideoStory();
    } else {
      _startImageStory();
    }
  }

  /// Record that the current user viewed this story (fire-and-forget).
  /// Skips if viewer is the author or if already recorded this session.
  void _recordView(String postId, String? authorId) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;
    if (currentUserId == authorId) return; // Don't count self-views
    if (_recordedViews.contains(postId)) return; // Already recorded this session

    _recordedViews.add(postId);

    // Fire-and-forget upsert
    Supabase.instance.client
        .from('story_views')
        .upsert(
          {'post_id': postId, 'viewer_id': currentUserId, 'viewed_at': DateTime.now().toUtc().toIso8601String()},
          onConflict: 'post_id,viewer_id',
        )
        .then((_) => debugPrint('👁️ Recorded view for story $postId'))
        .catchError((e) => debugPrint('⚠️ Failed to record story view: $e'));
  }

  /// Fetch the viewer count for an owner's story.
  Future<void> _fetchViewerCount(String postId) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      var query = Supabase.instance.client
          .from('story_views')
          .select('id')
          .eq('post_id', postId);

      if (currentUserId != null) {
        query = query.neq('viewer_id', currentUserId);
      }

      final response = await query;
      final count = (response as List).length;
      if (mounted) {
        setState(() {
          _viewerCounts[postId] = count;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to fetch viewer count: $e');
    }
  }

  void _startImageStory() {
    _progressController.removeStatusListener(_onProgressComplete);
    _progressController.stop();
    _progressController.reset();
    _progressController.duration = _imageDuration;
    _progressController.addStatusListener(_onProgressComplete);
    _progressController.forward();
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
      _progressController.removeStatusListener(_onProgressComplete);
      _progressController.stop();
      _progressController.reset();
      _progressController.duration = _videoController!.value.duration;
      _progressController.addStatusListener(_onProgressComplete);
      _progressController.forward();

      _videoController!.play();
    } catch (e) {
      debugPrint('⚠️ Video load error: $e');
      if (!mounted) return;
      setState(() => _videoError = true);

      // Auto-advance after 3 seconds on error
      _progressController.removeStatusListener(_onProgressComplete);
      _progressController.stop();
      _progressController.reset();
      _progressController.duration = const Duration(seconds: 3);
      _progressController.addStatusListener(_onProgressComplete);
      _progressController.forward();
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
      // Last story for this user — try advancing to next user
      if (_userQueue.isNotEmpty && _currentUserIndex < _userQueue.length - 1) {
        _advanceToUser(_currentUserIndex + 1);
        return;
      }
      // No more users — clean up and close
      _progressController.removeStatusListener(_onProgressComplete);
      _progressController.stop();
      _videoController?.pause();
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
      // First story for this user — try going to previous user
      if (_userQueue.isNotEmpty && _currentUserIndex > 0) {
        _advanceToUser(_currentUserIndex - 1, goToLast: true);
        return;
      }
      // No previous user — restart current story
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

  /// Switch to a different user in the queue and fetch their stories.
  Future<void> _advanceToUser(int newUserIndex, {bool goToLast = false}) async {
    if (newUserIndex < 0 || newUserIndex >= _userQueue.length) return;

    _progressController.removeStatusListener(_onProgressComplete);
    _progressController.stop();
    _videoController?.dispose();
    _videoController = null;

    setState(() {
      _currentUserIndex = newUserIndex;
      _isLoadingNextUser = true;
      _videoInitialized = false;
      _videoError = false;
    });

    final nextUser = _userQueue[newUserIndex];
    final userId = nextUser['author_id'] as String?;

    if (userId == null) {
      // Fallback — close
      if (mounted && !_isPopping) {
        _isPopping = true;
        Navigator.pop(context);
      }
      return;
    }

    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toUtc().toIso8601String();
      final List<dynamic> response = await Supabase.instance.client
          .from('posts')
          .select('*, user:user_id(id, display_name, avatar_url, user_photos(photo_url, is_primary))')
          .eq('is_story', true)
          .eq('user_id', userId)
          .gte('created_at', cutoff)
          .order('created_at', ascending: false);

      final fetched = List<Map<String, dynamic>>.from(response);

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
        // No stories for this user — skip to next
        if (goToLast && newUserIndex > 0) {
          _advanceToUser(newUserIndex - 1, goToLast: true);
        } else if (!goToLast && newUserIndex < _userQueue.length - 1) {
          _advanceToUser(newUserIndex + 1);
        } else if (mounted && !_isPopping) {
          _isPopping = true;
          Navigator.pop(context);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _stories = fetched;
          _currentIndex = goToLast ? fetched.length - 1 : 0;
          _isLoadingNextUser = false;
        });
        await _fetchInteractionsForStories();
        _startCurrentStory();
      }
    } catch (e) {
      debugPrint('Error advancing to next user: $e');
      if (mounted && !_isPopping) {
        _isPopping = true;
        Navigator.pop(context);
      }
    }
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
            // Stop everything before popping to prevent _onProgressComplete
            // from firing a second Navigator.pop (which would kill the FeedScreen).
            _progressController.removeStatusListener(_onProgressComplete);
            _progressController.stop();
            _videoController?.pause();
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

            // Loading overlay for user transitions
            if (_isLoadingNextUser)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
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
        // Guard against 0×0 dimensions (common on Android / certain codecs)
        final vw = _videoController!.value.size.width;
        final vh = _videoController!.value.size.height;
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: vw > 0 ? vw : 1,
              height: vh > 0 ? vh : 1,
              child: VideoPlayer(_videoController!),
            ),
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
        fit: BoxFit.contain,
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
            onTap: () {
              if (_isPopping) return;
              _isPopping = true;
              _progressController.removeStatusListener(_onProgressComplete);
              _progressController.stop();
              _videoController?.pause();
              Navigator.pop(context);
            },
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
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    final lat = story['latitude'] as num?;
                    final lng = story['longitude'] as num?;
                    if (lat == null || lng == null) return;

                    // Stop playback
                    _progressController.removeStatusListener(_onProgressComplete);
                    _progressController.stop();
                    _videoController?.pause();

                    // Navigate to map with fly-to
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => MainNavigationScreen(
                          initialIndex: 1,
                          flyToLat: lat.toDouble(),
                          flyToLng: lng.toDouble(),
                        ),
                      ),
                      (route) => false,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.primaryColor.withOpacity(0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            story['external_place_name'],
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.map_rounded,
                            color: Colors.white,
                            size: 10,
                          ),
                        ),
                      ],
                    ),
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

                // Viewer count (own stories only)
                if (isOwner) ...[
                  GestureDetector(
                    onTap: () {
                      _pause();
                      final storyId = story['id']?.toString();
                      if (storyId == null) return;
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => StoryViewersSheet(
                          postId: storyId,
                          initialCount: _viewerCounts[storyId] ?? 0,
                        ),
                      ).then((_) {
                        if (mounted) _resume();
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          color: Colors.white,
                          size: 26,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_viewerCounts[story['id']?.toString()] ?? 0}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                ],

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

                // Report button (other people's stories)
                if (!isOwner)
                  GestureDetector(
                    onTap: () {
                      _pause();
                      ReportModal.show(
                        context,
                        targetType: 'post',
                        targetId: story['id']?.toString() ?? '',
                        targetName: story['user']?['display_name'],
                      ).then((_) {
                        if (mounted) _resume();
                      });
                    },
                    child: const Icon(
                      Icons.flag_outlined,
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
