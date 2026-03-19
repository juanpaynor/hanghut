import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:bitemates/features/home/widgets/social_post_card.dart';
import 'package:bitemates/features/home/widgets/create_post_modal.dart';
import 'package:bitemates/features/home/widgets/trending_carousel.dart';
import 'package:bitemates/features/home/widgets/friends_moments_tray.dart';
import 'package:bitemates/core/services/notification_service.dart';

import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/story_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/features/home/widgets/hangout_feed_card.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:bitemates/features/notifications/screens/notifications_screen.dart';
import 'package:bitemates/features/camera/screens/location_story_viewer_screen.dart';

import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';
import 'package:bitemates/features/search/screens/user_search_screen.dart';
import 'package:bitemates/features/home/screens/discover_list_screen.dart';

class FeedScreen extends StatefulWidget {
  final Function(String)? onJoinTable;
  final Function(Map<String, dynamic>)? onStoryTap;
  final VoidCallback? onSeeAllHangouts;

  const FeedScreen({super.key, this.onJoinTable, this.onStoryTap, this.onSeeAllHangouts});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final SocialService _socialService = SocialService();
  final TableService _tableService = TableService();
  final StoryService _storyService = StoryService();

  List<Map<String, dynamic>> _socialPosts = [];
  List<Map<String, dynamic>> _trendingTables = []; // New: Trending Tables
  List<Map<String, dynamic>> _trendingExperiences =
      []; // New: Trending Experiences
  List<Event> _trendingEvents = []; // New: Trending Events
  List<Map<String, dynamic>> _friendsStories = [];
  bool _isLoadingStories = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  // Cursor pagination (Phase 2)
  String? _nextCursor;
  String? _nextCursorId;
  bool _hasMore = true;

  final int _postsPageSize = 10;

  // Category Filtering
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Hangouts', 'Discussions'];

  Position? _userPosition;
  String? _currentUserAvatarUrl;
  final List<StreamSubscription> _ablySubscriptions = [];

  Timer? _scrollDebounce;
  String? _errorMessage;

  // Cache management
  DateTime? _lastFetchTime;
  static const Duration _cacheLifetime = Duration(minutes: 5);

  @override
  bool get wantKeepAlive => true; // Keep state alive across navigation

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
  }

  @override
  void dispose() {
    print('🗑️ FeedScreen: dispose called');
    _tabController.dispose();
    _scrollController.dispose();
    _scrollDebounce?.cancel();
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
        _loadTrendingTables();
        _loadTrendingExperiences();
        _loadTrendingEvents();
        _loadFriendsStories();
        _subscribeToAblyFeed();
      }
    } catch (e) {
      print('❌ Error getting user location: $e');
      if (mounted) {
        _loadSocialPosts();
        _loadTrendingTables();
        _loadTrendingExperiences();
        _loadTrendingEvents();
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

  Future<void> _loadTrendingTables() async {
    try {
      final tables = await _tableService.getMapReadyTables(
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
        limit: 10, // Fetch top 10 closest/soonest
      );
      if (mounted) {
        setState(() {
          _trendingTables = tables
              .where((t) => t['visibility'] != 'mystery')
              .toList();
        });
      }
    } catch (e) {
      print('❌ Error loading trending tables: $e');
    }
  }

  Future<void> _loadTrendingExperiences() async {
    try {
      final experiences = await _tableService.getExperiences(
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
        limit: 10,
      );
      if (mounted) {
        setState(() {
          _trendingExperiences = experiences;
        });
      }
    } catch (e) {
      print('❌ Error loading trending experiences: $e');
    }
  }

  Future<void> _loadTrendingEvents() async {
    try {
      final events = await EventService().getUpcomingEvents(limit: 10);
      if (mounted) {
        setState(() {
          _trendingEvents = events;
        });
      }
    } catch (e) {
      print('❌ Error loading trending events: $e');
    }
  }

  Future<void> _loadFriendsStories() async {
    if (!mounted) return;
    setState(() => _isLoadingStories = true);
    try {
      final followingOnly = _tabController.index == 1;
      final stories = await _storyService.getFriendsStories(
        followingOnly: followingOnly,
        limit: 20,
      );
      if (mounted) {
        setState(() {
          _friendsStories = stories;
          _isLoadingStories = false;
        });
      }
    } catch (e) {
      print('❌ Error loading friends stories: $e');
      if (mounted) setState(() => _isLoadingStories = false);
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
          _errorMessage = 'Failed to load feed: $e';
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

  // Filter posts based on category
  List<Map<String, dynamic>> get _filteredPosts {
    if (_selectedCategory == 'All') return _socialPosts;
    if (_selectedCategory == 'Hangouts') {
      return _socialPosts.where((p) => p['post_type'] == 'hangout').toList();
    }
    if (_selectedCategory == 'Discussions') {
      return _socialPosts.where((p) => p['post_type'] != 'hangout').toList();
    }
    return _socialPosts;
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
          : _errorMessage != null
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
                  _loadTrendingTables(),
                  _loadTrendingExperiences(),
                  _loadTrendingEvents(),
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
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    surfaceTintColor: Theme.of(context).scaffoldBackgroundColor,
                    elevation: 0,
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
                    actions: [
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
                                builder: (context) => const UserSearchScreen(),
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
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
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
                  // 2. FRIENDS' MOMENTS STORY TRAY (Both tabs)
                  // ═══════════════════════════════════════════
                  if (_friendsStories.isNotEmpty || _isLoadingStories)
                    SliverToBoxAdapter(
                      child: FriendsMomentsTray(
                        stories: _friendsStories,
                        isLoading: _isLoadingStories,
                        onStoryTap: (story) async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LocationStoryViewerScreen(
                                initialStory: story,
                                clusterId: story['author_id'] ??
                                    story['external_place_id'] ??
                                    story['event_id'] ??
                                    story['table_id'],
                              ),
                            ),
                          );
                          // Refresh stories tray when returning (user may have deleted a story)
                          _loadFriendsStories();
                        },
                      ),
                    ),

                  // ═══════════════════════════════════════════
                  // 3. CATEGORY FILTER CHIPS (Moved up, For You only)
                  // ═══════════════════════════════════════════
                  if (_tabController.index == 0)
                    SliverToBoxAdapter(
                      child: Container(
                        height: 40,
                        margin: const EdgeInsets.only(bottom: 12, top: 14),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (c, i) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final isSelected = category == _selectedCategory;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = category;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // ═══════════════════════════════════════════
                  // 4. DISCOVER SECTION (Merged Experiences + Events)
                  // ═══════════════════════════════════════════
                  if (_tabController.index == 0 &&
                      (_trendingExperiences.isNotEmpty || _trendingEvents.isNotEmpty) &&
                      _selectedCategory != 'Discussions')
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader('Discover', onSeeAll: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DiscoverListScreen(
                                  items: [..._trendingExperiences, ..._trendingEvents],
                                ),
                              ),
                            );
                          }),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: TrendingCarousel(
                              items: [
                                ..._trendingExperiences,
                                ..._trendingEvents,
                              ],
                              onItemTap: (item) {
                                if (item is Event) {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) =>
                                        EventDetailModal(event: item),
                                  );
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ExperienceDetailModal(
                                        experience: item,
                                        matchData: const {},
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ═══════════════════════════════════════════
                  // 5. OPEN HANGOUTS (Was unlabelled Trending Tables)
                  // ═══════════════════════════════════════════
                  if (_tabController.index == 0 &&
                      _trendingTables.isNotEmpty &&
                      _selectedCategory != 'Discussions')
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader('Open Hangouts', onSeeAll: () {
                            if (widget.onSeeAllHangouts != null) {
                              widget.onSeeAllHangouts!();
                            }
                          }),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: TrendingCarousel(
                              items: _trendingTables,
                              onItemTap: (table) {
                                if (widget.onJoinTable != null) {
                                  widget.onJoinTable!(table['id']);
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TableCompactModal(
                                        table: table,
                                        matchData: const {},
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 5. Thread Creation Bar
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
                              'No ${_selectedCategory == 'All' ? 'posts' : _selectedCategory.toLowerCase()} yet.\nStart the conversation!',
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

  /// Reusable section header with Google Fonts and optional "See All" link
  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
        ],
      ),
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: (Theme.of(context).cardTheme.color ?? Colors.white).withOpacity(0.85),
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
              Icon(Icons.image_outlined, color: Colors.grey[400], size: 20),
            ],
          ),
        ),
          ), // BackdropFilter
        ), // ClipRRect
        ), // Padding
      ),
    );
  }
}
