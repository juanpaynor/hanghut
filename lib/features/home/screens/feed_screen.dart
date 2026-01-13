import 'package:flutter/material.dart';
import 'dart:async';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:shimmer/shimmer.dart';

import 'package:bitemates/features/home/widgets/social_post_card.dart';
import 'package:bitemates/features/home/widgets/create_post_modal.dart';
import 'package:bitemates/features/home/widgets/trending_carousel.dart';
import 'package:bitemates/core/services/notification_service.dart';

import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/features/home/widgets/hangout_feed_card.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:bitemates/features/notifications/screens/notifications_screen.dart';

class FeedScreen extends StatefulWidget {
  final Function(String)? onJoinTable;

  const FeedScreen({super.key, this.onJoinTable});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final SocialService _socialService = SocialService();
  final TableService _tableService = TableService();

  List<Map<String, dynamic>> _socialPosts = [];
  List<Map<String, dynamic>> _trendingTables = []; // New: Trending Tables
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _socialPostsOffset = 0;
  final int _postsPageSize = 10;

  // Category Filtering
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Hangouts', 'Discussions'];

  Position? _userPosition;
  final List<StreamSubscription> _ablySubscriptions = [];

  Timer? _scrollDebounce;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _getUserLocation();

    // Start listening for notifications (Realtime Red Dot)
    NotificationService().subscribeToNotifications();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await LocationService().getCurrentLocation();
      if (mounted) {
        setState(() {
          _userPosition = position;
        });
        _loadSocialPosts();
        _loadTrendingTables(); // New: Load trending tables
        _subscribeToAblyFeed();
      }
    } catch (e) {
      print('❌ Error getting user location: $e');
      if (mounted) {
        _loadSocialPosts();
        _loadTrendingTables(); // Try loading anyway
      }
    }
  }

  void _onScroll() {
    if (_scrollDebounce?.isActive ?? false) _scrollDebounce!.cancel();

    _scrollDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;

      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent * 0.8) {
        if (!_isLoadingMore) {
          _loadMorePosts();
        }
      }
    });
  }

  void _subscribeToAblyFeed() {
    // Cancel existing subscriptions
    for (var sub in _ablySubscriptions) {
      sub.cancel();
    }
    _ablySubscriptions.clear();

    if (_userPosition == null) return;

    // Get H3 cells for current location (center + neighbors)
    final h3Cells = _socialService.getH3CellsForLocation(
      _userPosition!.latitude,
      _userPosition!.longitude,
    );

    print('📍 Subscribing to ${h3Cells.length} H3 cells');

    // Subscribe to each cell's channel
    for (final cell in h3Cells) {
      final stream = AblyService().subscribeToCityFeed(
        cell,
      ); // Use cell as channel name
      if (stream != null) {
        final sub = stream.listen((message) {
          if (!mounted) return;

          if (message.name == 'post_created') {
            final postData = message.data as Map<String, dynamic>;
            // Avoid duplicates
            if (_socialPosts.any((p) => p['id'] == postData['id'])) return;

            setState(() {
              _socialPosts.insert(0, postData);
            });
          } else if (message.name == 'post_deleted') {
            final data = message.data as Map<String, dynamic>;
            final postId = data['post_id'];
            setState(() {
              _socialPosts.removeWhere((post) => post['id'] == postId);
            });
          }
        });
        _ablySubscriptions.add(sub);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollDebounce?.cancel();
    NotificationService().unsubscribeNotifications();
    for (var sub in _ablySubscriptions) {
      sub.cancel();
    }
    super.dispose();
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
          _trendingTables = tables;
        });
      }
    } catch (e) {
      print('❌ Error loading trending tables: $e');
    }
  }

  Future<void> _loadSocialPosts({bool force = false}) async {
    if (!force && _isLoading && _socialPosts.isNotEmpty) return;

    // Don't set isLoading true here if it's already true (initial load)
    if (!(_isLoading && _socialPosts.isEmpty)) {
      setState(() => _isLoading = true);
    }

    // Clear previous error on reload
    setState(() => _errorMessage = null);

    try {
      final posts = await _socialService.getFeed(
        limit: _postsPageSize,
        offset: 0,
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
      );

      if (mounted) {
        setState(() {
          _socialPosts = posts;
          _socialPostsOffset = posts.length;
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
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final newPosts = await _socialService.getFeed(
        limit: _postsPageSize,
        offset: _socialPostsOffset,
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
      );

      if (mounted && newPosts.isNotEmpty) {
        setState(() {
          _socialPosts.addAll(newPosts);
          _socialPostsOffset += newPosts.length;
          _isLoadingMore = false;
        });
      } else {
        setState(() => _isLoadingMore = false);
      }
    } catch (e) {
      print('❌ Error loading more posts: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _showCreatePost() async {
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreatePostModal(),
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
    // Determine list to show
    final postsToShow = _filteredPosts;

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
                  ),

                  // 2. Context Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userPosition != null
                                ? 'Activities Nearby'
                                : 'Discover Activities',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color.fromARGB(255, 120, 49, 227),
                              letterSpacing: -1,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Find your next activity with friends & strangers.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(
                                context,
                              ).primaryColor, // Bright indigo
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3. Category Filter Chips (NEW)
                  SliverToBoxAdapter(
                    child: Container(
                      height: 40,
                      margin: const EdgeInsets.only(bottom: 16),
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

                  // 4. Trending Carousel (NEW)
                  if (_trendingTables.isNotEmpty &&
                      _selectedCategory != 'Discussions')
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: TrendingCarousel(
                          tables: _trendingTables,
                          onTableTap: (table) {
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
                            );
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: SocialPostCard(post: post),
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

  Widget _buildThreadCreationBar() {
    return SliverToBoxAdapter(
      child: GestureDetector(
        onTap: _showCreatePost,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey[200],
                backgroundImage:
                    SupabaseConfig
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
                    : null,
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
      ),
    );
  }
}
