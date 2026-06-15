import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:shimmer/shimmer.dart';

import 'package:bitemates/features/home/widgets/social_post_card.dart';
import 'package:bitemates/features/home/widgets/create_post_modal.dart';
import 'package:bitemates/features/home/widgets/friends_moments_tray.dart';
import 'package:bitemates/core/services/notification_service.dart';

import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:bitemates/core/services/story_service.dart';
import 'package:bitemates/core/services/connectivity_service.dart';
import 'package:bitemates/features/camera/screens/story_camera_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/features/home/widgets/hangout_feed_card.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:bitemates/features/notifications/screens/notifications_screen.dart';
import 'package:bitemates/features/camera/screens/location_story_viewer_screen.dart';

import 'package:bitemates/features/search/screens/discover_search_screen.dart';

class FeedScreen extends StatefulWidget {
  final Function(String)? onJoinTable;
  final Function(Map<String, dynamic>)? onStoryTap;
  final VoidCallback? onSeeAllHangouts;

  const FeedScreen({
    super.key,
    this.onJoinTable,
    this.onStoryTap,
    this.onSeeAllHangouts,
  });

  @override
  State<FeedScreen> createState() => FeedScreenState();
}

class FeedScreenState extends State<FeedScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final SocialService _socialService = SocialService();
  final StoryService _storyService = StoryService();

  List<Map<String, dynamic>> _socialPosts = [];
  List<Map<String, dynamic>> _friendsStories = [];
  bool _isLoadingStories = false;
  bool _hasMoreStories = false;
  bool _isLoadingMoreStories = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  // Cursor pagination (Phase 2)
  String? _nextCursor;
  String? _nextCursorId;
  bool _hasMore = true;

  final int _postsPageSize = 10;

  // Filtering
  String? _activeTypeFilter; // null = All, 'Hangouts', 'Posts', 'Activities'
  final Set<String> _activeVibeFilters = {};
  bool _showStoriesOnly = false;

  static const List<String> _vibeFilters = [
    'Chill 😌',
    'Hype 🔥',
    'Foodie 🍜',
    'Active 🏃',
    'Social 🗣️',
    'Late Night 🌙',
    'Outdoors 🌿',
    'Creative 🎨',
    'Coffee ☕',
    'Adventure 🧗',
  ];

  Position? _userPosition;
  String? _currentUserAvatarUrl;
  final List<StreamSubscription> _ablySubscriptions = [];

  Timer? _scrollDebounce;
  String? _errorMessage;
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  // Cache management
  DateTime? _lastFetchTime;
  static const Duration _cacheLifetime = Duration(minutes: 5);

  @override
  bool get wantKeepAlive => true; // Keep state alive across navigation

  /// Called by MainNavigationScreen when the Home tab is tapped while already active.
  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    print('🔄 FeedScreen: initState called');
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _getUserLocation();
    _fetchCurrentUserAvatar();

    // Start listening for notifications (Realtime Red Dot)
    NotificationService().subscribeToNotifications();

    _connectivitySub = ConnectivityService().onConnectivityChanged.listen((online) {
      if (!mounted) return;
      setState(() => _isOffline = !online);
      if (online && _socialPosts.isEmpty) {
        _loadSocialPosts(force: true);
      }
    });
    _isOffline = !ConnectivityService().isOnline;
  }

  @override
  void dispose() {
    print('🗑️ FeedScreen: dispose called');
    _tabController.dispose();
    _scrollController.dispose();
    _scrollDebounce?.cancel();
    _connectivitySub?.cancel();
    NotificationService().unsubscribeNotifications();
    for (var sub in _ablySubscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await LocationService().getCurrentLocation();
      if (mounted) {
        setState(() {
          _userPosition = position;
        });
        _loadSocialPosts();
        _loadFriendsStories();
        _subscribeToAblyFeed();
      }
    } catch (e) {
      print('❌ Error getting user location: $e');
      if (mounted) {
        _loadSocialPosts();
        _loadFriendsStories();
        _subscribeToAblyFeed(); // ✅ Still need real-time even without location
      }
    }
  }

  Future<void> _fetchCurrentUserAvatar() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await SupabaseConfig.client
          .from('user_photos')
          .select('photo_url')
          .eq('user_id', userId)
          .eq('is_primary', true)
          .maybeSingle();

      if (mounted && data != null && data['photo_url'] != null) {
        setState(() {
          _currentUserAvatarUrl = data['photo_url'];
        });
      }
    } catch (e) {
      print('❌ Error fetching current user avatar: $e');
    }
  }

  void _onScroll() {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Trigger when 70% down (earlier pre-fetching) or 500px from bottom trying to be smoother
    if (currentScroll >= maxScroll * 0.7) {
      if (!_isLoadingMore) {
        _loadMorePosts();
      }
    }
  }

  void _subscribeToAblyFeed() {
    // Cancel existing subscriptions
    for (var sub in _ablySubscriptions) {
      sub.cancel();
    }
    _ablySubscriptions.clear();

    // ✅ Subscribe to single Philippines-wide channel (instead of 19 H3 cells)
    print('📍 Subscribing to Philippines feed channel');

    final stream = AblyService().subscribeToCityFeed('philippines');

    if (stream != null) {
      final sub = stream.listen((message) {
        if (!mounted) return;

        if (message.name == 'post_created') {
          final postData = message.data as Map<String, dynamic>;
          // Avoid duplicates
          if (_socialPosts.any((p) => p['id'] == postData['id'])) return;

          setState(() {
            _socialPosts.insert(0, postData);
            _lastFetchTime = null; // ✅ Invalidate cache on new post
          });
        } else if (message.name == 'post_deleted') {
          final data = message.data as Map<String, dynamic>;
          final postId = data['post_id'];
          setState(() {
            _socialPosts.removeWhere((post) => post['id'] == postId);
            _lastFetchTime = null; // ✅ Invalidate cache on deletion
          });
          // Also refresh the friends stories tray since deleted post might be a story
          _loadFriendsStories();
        }
      });
      _ablySubscriptions.add(sub);
    }
  }

  Future<void> _loadFriendsStories({int offset = 0}) async {
    if (!mounted) return;
    if (offset == 0) {
      setState(() => _isLoadingStories = true);
    } else {
      setState(() => _isLoadingMoreStories = true);
    }
    try {
      final followingOnly = _tabController.index == 1;
      final stories = await _storyService.getFriendsStories(
        followingOnly: followingOnly,
        limit: 20,
        offset: offset,
      );
      if (mounted) {
        setState(() {
          if (offset == 0) {
            _friendsStories = stories;
          } else {
            _friendsStories.addAll(stories);
          }
          _hasMoreStories = stories.length >= 20;
          _isLoadingStories = false;
          _isLoadingMoreStories = false;
        });
      }
    } catch (e) {
      print('❌ Error loading friends stories: $e');
      if (mounted) {
        setState(() {
          _isLoadingStories = false;
          _isLoadingMoreStories = false;
        });
      }
    }
  }

  Future<void> _loadSocialPosts({bool force = false}) async {
    // ✅ Check cache freshness first
    if (!force && _socialPosts.isNotEmpty && _lastFetchTime != null) {
      final age = DateTime.now().difference(_lastFetchTime!);
      if (age < _cacheLifetime) {
        print('✅ Using cached feed (age: ${age.inSeconds}s)');
        return; // Cache is fresh, skip query
      }
      print('⏰ Cache expired (age: ${age.inSeconds}s), refetching...');
    }

    if (!force && _isLoading && _socialPosts.isNotEmpty) return;

    // Don't set isLoading true here if it's already true (initial load)
    if (!(_isLoading && _socialPosts.isEmpty)) {
      setState(() => _isLoading = true);
    }

    // Clear previous error on reload
    setState(() => _errorMessage = null);

    try {
      final result = await _socialService.getFeed(
        limit: _postsPageSize,
        cursor: null, // Initial load, no cursor
        cursorId: null,
        useCursor: true, // Use cursor pagination
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
        followingOnly: _tabController.index == 1,
      );

      if (mounted) {
        final posts = result['posts'] as List<Map<String, dynamic>>;
        setState(() {
          _socialPosts = posts;
          _hasMore = result['hasMore'] as bool? ?? false;
          _nextCursor = result['nextCursor'] as String?;
          _nextCursorId = result['nextCursorId'] as String?;
          _lastFetchTime = DateTime.now(); // ✅ Set cache timestamp
        });
      }
    } catch (e) {
      print('❌ Error loading social posts: $e');
      if (mounted) {
        setState(() {
          // If we have cached posts, stay silent — the OfflineBanner tells the user
          if (_socialPosts.isEmpty) {
            _errorMessage = 'Failed to load feed. Check your connection.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMore) return; // Don't load if no more posts

    setState(() => _isLoadingMore = true);

    try {
      final result = await _socialService.getFeed(
        limit: _postsPageSize,
        cursor: _nextCursor,
        cursorId: _nextCursorId,
        useCursor: true,
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
        followingOnly: _tabController.index == 1,
      );

      if (mounted) {
        final newPosts = result['posts'] as List<Map<String, dynamic>>;
        if (newPosts.isNotEmpty) {
          setState(() {
            _socialPosts.addAll(newPosts);
            _hasMore = result['hasMore'] as bool? ?? false;
            _nextCursor = result['nextCursor'] as String?;
            _nextCursorId = result['nextCursorId'] as String?;
            _isLoadingMore = false;
          });
        } else {
          setState(() {
            _hasMore = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading more posts: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _showCreatePost() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const CreatePostModal();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Buttery smooth liquid morph effect
          final scaleCurve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutQuint,
            reverseCurve: Curves.easeInQuint,
          );

          final fadeCurve = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
            reverseCurve: Curves.easeIn,
          );

          return ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(scaleCurve),
            child: FadeTransition(opacity: fadeCurve, child: child),
          );
        },
      ),
    );

    // Optimistic update: Add post immediately to UI
    if (result != null && mounted) {
      setState(() {
        _socialPosts.insert(0, result);
      });
      // Refresh to get the actual post with all data from server
      _loadSocialPosts();
    }
  }

  // Filter posts based on active filters
  List<Map<String, dynamic>> get _filteredPosts {
    var posts = _socialPosts;

    // Stories-only toggle
    if (_showStoriesOnly) {
      posts = posts.where((p) => p['is_story'] == true).toList();
    }

    // Type filter
    if (_activeTypeFilter != null) {
      switch (_activeTypeFilter) {
        case 'Hangouts':
          posts = posts.where((p) => p['post_type'] == 'hangout').toList();
          break;
        case 'Posts':
          posts = posts
              .where(
                (p) =>
                    p['post_type'] != 'hangout' &&
                    p['post_type'] != 'event' &&
                    p['post_type'] != 'experience',
              )
              .toList();
          break;
        case 'Activities':
          posts = posts
              .where(
                (p) => [
                  'event',
                  'experience',
                  'class',
                  'workshop',
                ].contains(p['post_type']),
              )
              .toList();
          break;
      }
    }

    // Vibe filters (only meaningful for Hangouts)
    if (_activeVibeFilters.isNotEmpty && _activeTypeFilter == 'Hangouts') {
      posts = posts.where((p) {
        final vibes = (p['vibes'] as List?)?.cast<String>() ?? [];
        final activity = (p['activity_type'] as String? ?? '').toLowerCase();
        return _activeVibeFilters.any(
          (v) =>
              vibes.contains(v) ||
              activity.contains(v.split(' ').first.toLowerCase()),
        );
      }).toList();
    }

    return posts;
  }

  bool get _hasActiveFilters =>
      _activeTypeFilter != null ||
      _activeVibeFilters.isNotEmpty ||
      _showStoriesOnly;

  void _showFilterSheet() {
    // Local copies for the sheet so we can cancel
    String? sheetType = _activeTypeFilter;
    final Set<String> sheetVibes = Set.from(_activeVibeFilters);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header row
                  Row(
                    children: [
                      const Text(
                        'Filter',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            sheetType = null;
                            sheetVibes.clear();
                          });
                        },
                        child: Text(
                          'Clear all',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Row 1 — Content type
                  const Text(
                    'Type',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Hangouts', 'Posts', 'Activities'].map((type) {
                      final isSelected = sheetType == type;
                      return ChoiceChip(
                        label: Text(type),
                        selected: isSelected,
                        onSelected: (_) {
                          setSheetState(() {
                            sheetType = isSelected ? null : type;
                            if (sheetType != 'Hangouts') sheetVibes.clear();
                          });
                        },
                        selectedColor: Theme.of(context).primaryColor,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        side: BorderSide.none,
                      );
                    }).toList(),
                  ),

                  // Row 2 — Vibe filters (Hangouts only)
                  if (sheetType == 'Hangouts') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Vibe',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _vibeFilters.map((vibe) {
                        final isSelected = sheetVibes.contains(vibe);
                        return FilterChip(
                          label: Text(vibe),
                          selected: isSelected,
                          onSelected: (val) {
                            setSheetState(() {
                              if (val) {
                                sheetVibes.add(vibe);
                              } else {
                                sheetVibes.remove(vibe);
                              }
                            });
                          },
                          selectedColor: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.15),
                          checkmarkColor: Theme.of(context).primaryColor,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                          backgroundColor: Colors.grey[100],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          side: BorderSide.none,
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Apply button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _activeTypeFilter = sheetType;
                          _activeVibeFilters
                            ..clear()
                            ..addAll(sheetVibes);
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Apply',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Determine list to show
    final postsToShow = _tabController.index == 0
        ? _filteredPosts
        : _socialPosts;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // FAB Removed: Handled by MainNavigationScreen
      body: _isLoading
          ? _buildSkeletonLoader()
          : _isOffline && _socialPosts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      'You\'re offline',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connect to the internet to see what\'s happening.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          : _errorMessage != null && _socialPosts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      'Oops!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _isLoading = true);
                        _loadSocialPosts(force: true);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  _loadSocialPosts(force: true),
                  _loadFriendsStories(),
                ]);
              },
              color: Theme.of(context).primaryColor,
              backgroundColor: Colors.white,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 1. App Bar
                  SliverAppBar(
                    floating: true,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    flexibleSpace: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withOpacity(0.82),
                                Colors.white.withOpacity(0.70),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    centerTitle: false,
                    title: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Row(
                        children: [
                          Text(
                            'HangHut',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    actionsPadding: const EdgeInsets.only(right: 9),
                    actions: [
                      // Stories pill button
                      GestureDetector(
                        onTap: () => setState(
                          () => _showStoriesOnly = !_showStoriesOnly,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _showStoriesOnly
                                ? Theme.of(context).primaryColor
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 14,
                                color: _showStoriesOnly
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Stories',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _showStoriesOnly
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Filter icon button
                      Stack(
                        children: [
                          Material(
                            color: _hasActiveFilters
                                ? Theme.of(context).primaryColor
                                : const Color(0xFFF1F5F9),
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: IconButton(
                              icon: Icon(
                                Icons.tune_rounded,
                                color: _hasActiveFilters
                                    ? Colors.white
                                    : Colors.black87,
                                size: 22,
                              ),
                              onPressed: _showFilterSheet,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      // Search Icon
                      Material(
                        color: const Color(0xFFF1F5F9),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          icon: const Icon(
                            Icons.search,
                            color: Colors.black87,
                            size: 24,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const DiscoverSearchScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      StreamBuilder<int>(
                        stream: NotificationService().unreadCountStream,
                        initialData: 0,
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          return Stack(
                            children: [
                              Hero(
                                tag: 'notification_bell',
                                child: Material(
                                  color: const Color(0xFFF1F5F9),
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.notifications_outlined,
                                      color: Colors.black87,
                                      size: 24,
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        PageRouteBuilder(
                                          opaque: false,
                                          barrierDismissible: true,
                                          barrierColor: Colors.black12,
                                          pageBuilder: (_, __, ___) =>
                                              const NotificationsScreen(),
                                          transitionsBuilder:
                                              (_, anim, __, child) {
                                                return FadeTransition(
                                                  opacity: anim,
                                                  child: child,
                                                );
                                              },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (count > 0)
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      count > 99 ? '99+' : '$count',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                    bottom: TabBar(
                      controller: _tabController,
                      labelColor: Theme.of(context).primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Theme.of(context).primaryColor,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      tabs: const [
                        Tab(text: 'For You'),
                        Tab(text: 'Following'),
                      ],
                    ),
                  ),

                  // ═══════════════════════════════════════════
                  // 2. FRIENDS' STORIES TRAY (Both tabs)
                  // ═══════════════════════════════════════════
                  if (_friendsStories.isNotEmpty || _isLoadingStories)
                    SliverToBoxAdapter(
                      child: FriendsMomentsTray(
                        stories: _friendsStories,
                        isLoading: _isLoadingStories,
                        hasMore: _hasMoreStories,
                        onAddStory: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const StoryCameraScreen(),
                            ),
                          ).then((_) => _loadFriendsStories());
                        },
                        onLoadMore: () {
                          if (!_isLoadingMoreStories) {
                            _loadFriendsStories(offset: _friendsStories.length);
                          }
                        },
                        onStoryTap: (story) async {
                          final authorId = story['author_id']?.toString();
                          final storyIndex = _friendsStories.indexOf(story);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LocationStoryViewerScreen(
                                initialStory: story,
                                clusterId:
                                    authorId ??
                                    story['external_place_id'] ??
                                    story['event_id'] ??
                                    story['table_id'],
                                allUserStories: _friendsStories,
                                startUserIndex: storyIndex != -1
                                    ? storyIndex
                                    : 0,
                              ),
                            ),
                          );

                          // Mark stories as viewed
                          if (authorId != null) {
                            _storyService.markStoriesViewed(authorId);
                          }

                          // Optimistic local update: mark as seen & move to end of unseen group
                          if (mounted) {
                            setState(() {
                              final idx = _friendsStories.indexWhere(
                                (s) => s['author_id'] == authorId,
                              );
                              if (idx >= 0) {
                                _friendsStories[idx] = {
                                  ..._friendsStories[idx],
                                  'is_seen': true,
                                };
                                // Re-sort: own first, then unseen, then seen
                                _friendsStories.sort((a, b) {
                                  final aOwn = a['is_own'] == true ? 0 : 1;
                                  final bOwn = b['is_own'] == true ? 0 : 1;
                                  if (aOwn != bOwn) return aOwn.compareTo(bOwn);
                                  final aSeen = a['is_seen'] == true ? 1 : 0;
                                  final bSeen = b['is_seen'] == true ? 1 : 0;
                                  if (aSeen != bSeen)
                                    return aSeen.compareTo(bSeen);
                                  // Within same group, sort by closeness DESC then time DESC
                                  final aScore =
                                      (a['closeness_score'] ?? 0) as int;
                                  final bScore =
                                      (b['closeness_score'] ?? 0) as int;
                                  if (aScore != bScore)
                                    return bScore.compareTo(aScore);
                                  final aTime =
                                      a['latest_story_time']?.toString() ?? '';
                                  final bTime =
                                      b['latest_story_time']?.toString() ?? '';
                                  return bTime.compareTo(aTime);
                                });
                              }
                            });
                          }
                        },
                      ),
                    ),

                  // ═══════════════════════════════════════════
                  // 4. ACTIVE FILTER SUMMARY CHIPS
                  // ═══════════════════════════════════════════
                  if (_tabController.index == 0 && _hasActiveFilters)
                    SliverToBoxAdapter(
                      child: Container(
                        height: 40,
                        margin: const EdgeInsets.only(bottom: 4, top: 8),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          children: [
                            if (_activeTypeFilter != null)
                              _activeChip(
                                _activeTypeFilter!,
                                onRemove: () =>
                                    setState(() => _activeTypeFilter = null),
                              ),
                            ..._activeVibeFilters.map(
                              (v) => _activeChip(
                                v,
                                onRemove: () => setState(
                                  () => _activeVibeFilters.remove(v),
                                ),
                              ),
                            ),
                            if (_showStoriesOnly)
                              _activeChip(
                                'Stories ✨',
                                onRemove: () =>
                                    setState(() => _showStoriesOnly = false),
                              ),
                          ],
                        ),
                      ),
                    ),

                  // 6. Thread Creation Bar
                  _buildThreadCreationBar(),

                  // 6. Threads Feed
                  if (postsToShow.isEmpty && !_isLoading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No ${_activeTypeFilter ?? 'posts'} found.\nTry adjusting your filters!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // Check if we are at the bottom and loading more
                          if (index == postsToShow.length) {
                            if (_isLoadingMore) {
                              return Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              return const SizedBox(
                                height: 80,
                              ); // Bottom padding for FAB
                            }
                          }

                          final post = postsToShow[index];

                          // Check post type for Hangout Feed Card
                          if (post['post_type'] == 'hangout') {
                            return HangoutFeedCard(
                              key: ValueKey(post['id']),
                              post: post,
                              onTap: () {
                                final metadata = post['metadata'];
                                if (metadata != null &&
                                    metadata['table_id'] != null) {
                                  if (widget.onJoinTable != null) {
                                    widget.onJoinTable!(metadata['table_id']);
                                  } else {
                                    // Fallback for standalone usage
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TableCompactModal(
                                          table: {'id': metadata['table_id']},
                                          matchData: const {},
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              onPostDeleted: (postId) {
                                setState(() {
                                  _socialPosts.removeWhere(
                                    (p) => p['id'] == postId,
                                  );
                                });
                              },
                              onPostEdited: (updatedPost) {
                                setState(() {
                                  final idx = _socialPosts.indexWhere(
                                    (p) => p['id'] == updatedPost['id'],
                                  );
                                  if (idx >= 0) {
                                    _socialPosts[idx] = {
                                      ..._socialPosts[idx],
                                      ...updatedPost,
                                    };
                                  }
                                });
                              },
                            );
                          }

                          return SocialPostCard(
                            key: ValueKey(post['id']),
                            post: post,
                            onTap: () {
                              if (post['is_story'] == true &&
                                  widget.onStoryTap != null) {
                                widget.onStoryTap!(post);
                              } else {
                                // Navigating to normal post detail is handled inside SocialPostCard if needed,
                                // or we can push a PostDetailScreen here. For now, just handle stories.
                              }
                            },
                            onPostDeleted: (postId) {
                              setState(() {
                                _socialPosts.removeWhere(
                                  (p) => p['id'] == postId,
                                );
                              });
                            },
                            onPostEdited: (updatedPost) {
                              setState(() {
                                final idx = _socialPosts.indexWhere(
                                  (p) => p['id'] == updatedPost['id'],
                                );
                                if (idx >= 0) {
                                  _socialPosts[idx] = {
                                    ..._socialPosts[idx],
                                    ...updatedPost,
                                  };
                                }
                              });
                            },
                          );
                        },
                        childCount:
                            postsToShow.length + 1, // +1 for loader/padding
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // New Skeleton Loader
  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 100),
      itemCount: 5,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 120, height: 16, color: Colors.white),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      // Clear posts and reload when switching tabs
      setState(() {
        _socialPosts = [];
        _isLoading = true;
        _hasMore = true;
        _errorMessage = null;
        _lastFetchTime = null; // Force refresh
      });
      _loadSocialPosts();
      _loadFriendsStories(); // Reload stories for the new tab
    } else {
      if (mounted) setState(() {});
    }
  }

  Widget _buildThreadCreationBar() {
    return SliverToBoxAdapter(
      child: GestureDetector(
        onTap: _showCreatePost,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: (Theme.of(context).cardTheme.color ?? Colors.white)
                      .withOpacity(0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _currentUserAvatarUrl != null
                          ? NetworkImage(_currentUserAvatarUrl!)
                          : (SupabaseConfig
                                        .client
                                        .auth
                                        .currentUser
                                        ?.userMetadata?['avatar_url'] !=
                                    null
                                ? NetworkImage(
                                    SupabaseConfig
                                        .client
                                        .auth
                                        .currentUser!
                                        .userMetadata!['avatar_url'],
                                  )
                                : null),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Start a thread...',
                      style: TextStyle(color: Colors.grey[500], fontSize: 15),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.image_outlined,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ],
                ),
              ),
            ), // BackdropFilter
          ), // ClipRRect
        ), // Padding
      ),
    );
  }

  Widget _activeChip(String label, {required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onRemove,
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.12),
        deleteIconColor: Theme.of(context).primaryColor,
        labelStyle: TextStyle(color: Theme.of(context).primaryColor),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}
