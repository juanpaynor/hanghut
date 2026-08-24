import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/settings/screens/settings_screen.dart';
import 'package:bitemates/core/widgets/full_screen_image_viewer.dart';
import 'package:bitemates/core/widgets/skeleton_loader.dart';
import 'package:bitemates/features/profile/widgets/profile_parallax_header.dart';
import 'package:bitemates/features/profile/widgets/glass_stats_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
// Restored imports
import 'package:bitemates/features/profile/screens/connected_users_screen.dart';
import 'package:bitemates/core/services/direct_chat_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/profile/screens/edit_profile_screen.dart';
import 'package:bitemates/features/settings/widgets/report_modal.dart';
import 'package:bitemates/core/services/report_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/features/gamification/models/badge.dart' as gm;
import 'package:bitemates/features/gamification/models/user_badge.dart';
import 'package:bitemates/features/gamification/services/badge_service.dart';
import 'package:bitemates/features/profile/widgets/badges_showcase.dart';
import 'package:bitemates/features/gamification/widgets/creator_badge_case.dart';
import 'package:bitemates/features/ticketing/screens/partner_storefront_screen.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/features/home/widgets/social_post_card.dart';
import 'package:bitemates/features/home/widgets/hangout_feed_card.dart';
import 'package:bitemates/features/home/screens/post_detail_screen.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
// Membership sections are commented out below (subscriptions not live yet).
// import 'package:bitemates/features/profile/screens/my_memberships_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final bool isOwnProfile;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.isOwnProfile = false,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _userPhotos = [];
  List<String> _userInterests = [];

  // Facebook-style profile timeline: the user's own posts as full feed cards.
  final SocialService _socialService = SocialService();
  final List<Map<String, dynamic>> _posts = [];
  bool _isLoadingPosts = true; // initial load
  bool _isLoadingMorePosts = false;
  bool _hasMorePosts = true;
  String? _postsCursor;
  String? _postsCursorId;
  static const int _postsPageSize = 10;

  List<gm.Badge> _allBadges = [];
  List<UserBadge> _earnedBadges = [];
  String? _errorMessage;
  bool _isFollowing = false;
  bool _followsYou = false; // Does the viewed user follow the current user?
  bool _isBlocked = false;
  late final bool _isOwnProfile;
  Map<String, dynamic>? _organizerProfile; // null = not an organizer
  Map<String, dynamic>? _storefront; // get_storefront data (brand header)
  Map<String, dynamic>? _viewerSubscription; // viewer's active sub for this organizer
  List<Map<String, dynamic>> _myMemberships = []; // own profile: all active subs
  final ScrollController _profileScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-detect own profile: override widget.isOwnProfile if userId matches current user
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    _isOwnProfile = widget.isOwnProfile || widget.userId == currentUserId;
    _profileScrollController.addListener(() {
      if (_profileScrollController.position.pixels >=
          _profileScrollController.position.maxScrollExtent - 400) {
        _loadMoreUserPosts();
      }
    });
    _loadUserProfile();
    _loadOrganizerProfile();
    _loadBadges();
    _loadUserPosts();
    if (_isOwnProfile) _loadMyMemberships();
    if (!_isOwnProfile) {
      _checkFollowStatus();
      _checkBlockStatus();
    }
  }

  @override
  void dispose() {
    _profileScrollController.dispose();
    super.dispose();
  }

  /// Initial load of the profile timeline (first page of the user's posts).
  Future<void> _loadUserPosts() async {
    try {
      final result = await _socialService.getUserPosts(
        userId: widget.userId,
        limit: _postsPageSize,
      );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(result['posts'] as List));
        _hasMorePosts = result['hasMore'] as bool? ?? false;
        _postsCursor = result['nextCursor'] as String?;
        _postsCursorId = result['nextCursorId'] as String?;
        _isLoadingPosts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  /// Cursor-paginated load-more, triggered near the bottom of the scroll.
  Future<void> _loadMoreUserPosts() async {
    if (_isLoadingMorePosts || !_hasMorePosts || _isLoadingPosts) return;
    setState(() => _isLoadingMorePosts = true);
    try {
      final result = await _socialService.getUserPosts(
        userId: widget.userId,
        limit: _postsPageSize,
        cursor: _postsCursor,
        cursorId: _postsCursorId,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(
          List<Map<String, dynamic>>.from(result['posts'] as List),
        );
        _hasMorePosts = result['hasMore'] as bool? ?? false;
        _postsCursor = result['nextCursor'] as String?;
        _postsCursorId = result['nextCursorId'] as String?;
        _isLoadingMorePosts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMorePosts = false);
    }
  }

  /// Remove a deleted post from the timeline in place.
  void _onPostDeleted(String postId) {
    if (!mounted) return;
    setState(() => _posts.removeWhere((p) => p['id'] == postId));
  }

  /// Merge an edited post's new fields back into the timeline in place.
  void _onPostEdited(Map<String, dynamic> updated) {
    if (!mounted) return;
    final id = updated['id'];
    final idx = _posts.indexWhere((p) => p['id'] == id);
    if (idx != -1) {
      setState(() => _posts[idx] = {..._posts[idx], ...updated});
    }
  }

  Future<void> _loadOrganizerProfile() async {
    try {
      final result = await SupabaseConfig.client.rpc(
        'get_organizer_public_profile',
        params: {'p_user_id': widget.userId},
      );
      if (result != null && mounted) {
        final org = Map<String, dynamic>.from(result as Map);
        setState(() => _organizerProfile = org);
        final partnerId = org['partner_id'] as String?;
        if (partnerId != null) {
          // Storefront powers the brand header (profile_mode, cover, counts).
          try {
            final sf = await SupabaseConfig.client.rpc(
              'get_storefront',
              params: {'p_slug': null, 'p_partner_id': partnerId},
            );
            if (sf != null && mounted) {
              setState(() => _storefront = Map<String, dynamic>.from(sf as Map));
            }
          } catch (_) {/* storefront optional; header just won't show */}
          if (!_isOwnProfile) _loadViewerSubscription(partnerId);
        }
      }
    } catch (e) {
      // Not an organizer or RPC failed — silently ignore
    }
  }

  Future<void> _loadViewerSubscription(String partnerId) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await SupabaseConfig.client
          .from('fan_subscriptions')
          .select(
            'id, tier_id, status, current_period_end, subscription_tiers(name, price_monthly, perks)',
          )
          .eq('fan_id', userId)
          .eq('partner_id', partnerId)
          .inFilter('status', ['active', 'grace_period'])
          .limit(1);
      if (mounted) {
        setState(() {
          _viewerSubscription =
              (rows as List).isNotEmpty
                  ? Map<String, dynamic>.from(rows.first as Map)
                  : null;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error loading viewer subscription: $e');
    }
  }

  Future<void> _loadMyMemberships() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await SupabaseConfig.client
          .from('fan_subscriptions')
          .select(
            'id, tier_id, partner_id, status, current_period_end, '
            'subscription_tiers(name, price_monthly, perks), '
            'partners(business_name, profile_photo_url, slug)',
          )
          .eq('fan_id', userId)
          .inFilter('status', ['active', 'grace_period'])
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _myMemberships = List<Map<String, dynamic>>.from(rows as List);
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error loading memberships: $e');
    }
  }

  Future<void> _loadBadges() async {
    try {
      final badgeService = BadgeService();
      final results = await Future.wait([
        badgeService.getAllBadges(),
        badgeService.getUserBadges(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _allBadges = results[0] as List<gm.Badge>;
          _earnedBadges = results[1] as List<UserBadge>;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Badge load error: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final supabase = SupabaseConfig.client;

      // PHASE 1 OPTIMIZATION: Single combined query with all data
      final userResponse = await supabase
          .from('users')
          .select()
          .eq('id', widget.userId)
          .single();

      // Parallel queries for better performance
      final results = await Future.wait<dynamic>([
        // Hosted tables count
        supabase.from('tables').count().eq('host_id', widget.userId),
        // Joined tables count (from table_members, active statuses only)
        supabase
            .from('table_members')
            .count()
            .eq('user_id', widget.userId)
            .inFilter('status', ['joined', 'approved', 'attended']),
        // PHASE 1 FIX: Real followers count
        supabase.from('follows').count().eq('following_id', widget.userId),
        // PHASE 1 FIX: Real following count
        supabase.from('follows').count().eq('follower_id', widget.userId),
        // Hosted tables history
        supabase
            .from('tables')
            .select('*, participants:table_participants(count)')
            .eq('host_id', widget.userId)
            .order('datetime', ascending: false)
            .limit(5),
        // PHASE 1 NEW: Joined tables history (from table_members)
        supabase
            .from('table_members')
            .select('joined_at, table:tables!table_id(*)')
            .eq('user_id', widget.userId)
            .inFilter('status', ['joined', 'approved', 'attended'])
            .order('joined_at', ascending: false)
            .limit(5),
        // Photos
        supabase.from('user_photos').select().eq('user_id', widget.userId),
        // Interests
        supabase
            .from('user_interests')
            .select('interest_tag:interest_tags(name)')
            .eq('user_id', widget.userId),
      ]);

      final hostedCount = results[0] as int;
      final joinedCount = results[1] as int;
      final followersCount = results[2] as int;
      final followingCount = results[3] as int;
      final photosResponse = results[6] as List<dynamic>;
      final interestsResponse = results[7] as List<dynamic>;

      final List<Map<String, dynamic>> photos = List<Map<String, dynamic>>.from(
        photosResponse,
      );

      String avatarUrl = '';
      try {
        final primary = photos.firstWhere(
          (p) => p['is_primary'] == true,
          orElse: () => photos.isNotEmpty ? photos.first : {'photo_url': ''},
        );
        avatarUrl = primary['photo_url'];
      } catch (e) {
        // Fallback or empty
      }

      if (mounted) {
        setState(() {
          _userData = {...userResponse, 'avatar_url': avatarUrl};
          _stats = {
            'hosted': hostedCount,
            'joined': joinedCount,
            'followers': followersCount,
            'following': followingCount,
          };
          _userPhotos = photos;
          _userInterests = interestsResponse
              .map((r) {
                final tag = r['interest_tag'];
                return tag != null ? tag['name'].toString() : null;
              })
              .whereType<String>()
              .toList();

          // Fallback: old accounts stored interests in users.tags (text array)
          if (_userInterests.isEmpty) {
            final legacyTags = userResponse['tags'];
            if (legacyTags is List && legacyTags.isNotEmpty) {
              _userInterests = legacyTags.map((t) => t.toString()).toList();
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Profile load error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to load profile. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkFollowStatus() async {
    try {
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final results = await Future.wait([
        // Do I follow them?
        SupabaseConfig.client
            .from('follows')
            .select('follower_id')
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId)
            .maybeSingle(),
        // Do they follow me?
        SupabaseConfig.client
            .from('follows')
            .select('follower_id')
            .eq('follower_id', widget.userId)
            .eq('following_id', currentUserId)
            .maybeSingle(),
      ]);

      if (mounted) {
        setState(() {
          _isFollowing = results[0] != null;
          _followsYou = results[1] != null;
        });
      }
    } catch (e) {
      print('Error checking follow status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    try {
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      if (_isFollowing) {
        // Unfollow
        await SupabaseConfig.client
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId);

        if (mounted) {
          setState(() {
            _isFollowing = false;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Unfollowed')));
        }
      } else {
        // Follow
        await SupabaseConfig.client.from('follows').insert({
          'follower_id': currentUserId,
          'following_id': widget.userId,
        });

        if (mounted) {
          setState(() {
            _isFollowing = true;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Following!')));
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Unable to update follow status.',
        );
      }
    }
  }

  Future<void> _checkBlockStatus() async {
    try {
      final isBlocked = await ReportService().isUserBlocked(widget.userId);
      if (mounted) {
        setState(() => _isBlocked = isBlocked);
      }
    } catch (e) {
      print('Error checking block status: $e');
    }
  }

  Future<void> _toggleBlock() async {
    final displayName = _userData?['display_name'] ?? 'this user';

    if (_isBlocked) {
      // Unblock
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_open_rounded,
                    color: Colors.green,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Unblock $displayName?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'They\'ll be able to see your profile and message you again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black54,
                          side: const BorderSide(color: Color(0xFFE0E0E0)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Unblock',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (confirm == true) {
        final success = await ReportService().unblockUser(widget.userId);
        if (success && mounted) {
          setState(() => _isBlocked = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$displayName has been unblocked')),
          );
        }
      }
    } else {
      // Block
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Block $displayName?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'They won\'t be able to see your profile, posts, or message you. You won\'t see their content either.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black54,
                          side: const BorderSide(color: Color(0xFFE0E0E0)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Block',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (confirm == true) {
        final success = await ReportService().blockUser(widget.userId);
        if (success && mounted) {
          setState(() => _isBlocked = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$displayName has been blocked')),
          );
        }
      }
    }
  }

  void _openDirectMessage() async {
    try {
      final chatId = await DirectChatService().startConversation(widget.userId);

      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          enableDrag: true,
          builder: (context) => ChatScreen(
            tableId: chatId,
            tableTitle: _userData?['display_name'] ?? 'Direct Message',
            channelId: 'direct_$chatId',
            chatType: 'dm',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          error: e,
          fallbackMessage: 'Unable to open chat.',
        );
      }
    }
  }

  void _showSettingsMenu(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  // RPG Logic Helper
  Map<String, double> _calculateRpgStats() {
    if (_stats == null) return {};
    // Normalize to 0.0 - 1.0 based on arbitrary max values
    double social = ((_stats!['hosted'] ?? 0) / 10.0).clamp(0.0, 1.0);
    double active = ((_stats!['joined'] ?? 0) / 20.0).clamp(0.0, 1.0);
    double karma = ((_userData?['trust_score'] ?? 50) / 100.0).clamp(0.0, 1.0);
    double explore = (_userPhotos.length / 5.0).clamp(
      0.0,
      1.0,
    ); // Mock explore based on photos
    double taste = 0.7; // Mock taste

    return {
      'Social': social,
      'Active': active,
      'Karma': karma,
      'Explore': explore,
      'Taste': taste,
    };
  }

  String _getCharacterClass(Map<String, double> rpgStats) {
    if (rpgStats.isEmpty) return 'Novice Foodie';

    // Find highest stat
    var highest = rpgStats.entries.reduce((a, b) => a.value > b.value ? a : b);

    switch (highest.key) {
      case 'Social':
        return 'Grand Host';
      case 'Active':
        return 'Table Hopper';
      case 'Karma':
        return 'Trusty Guide';
      case 'Explore':
        return 'Flavor Scout';
      case 'Taste':
        return 'Gourmand';
      default:
        return 'Foodie Adventurer';
    }
  }

  // PHASE 1 FIX: Calculate actual level and XP

  void _showEditBadgeDialog(String currentBadge) {
    final controller = TextEditingController(text: currentBadge);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Badge'),
        content: TextField(
          controller: controller,
          maxLength: 20,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Foodie, Traveler, Night Owl',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newBadge = controller.text.trim();
              if (newBadge.isEmpty) return;
              Navigator.pop(context);
              try {
                final userId = SupabaseConfig.client.auth.currentUser?.id;
                if (userId == null) return;
                await SupabaseConfig.client
                    .from('users')
                    .update({'custom_badge': newBadge})
                    .eq('id', userId);
                setState(() {
                  _userData?['custom_badge'] = newBadge;
                });
              } catch (e) {
                if (mounted) {
                  ErrorHandler.showError(
                    context,
                    error: e,
                    fallbackMessage: 'Unable to update badge.',
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// True when the viewed profile belongs to a brand-mode organizer and we have
  /// its storefront loaded — drives the brand header (team_comms #220).
  bool get _isBrandOrganizer =>
      _storefront != null &&
      (_storefront!['partner'] as Map?)?['profile_mode'] == 'brand';

  @override
  Widget build(BuildContext context) {
    // 1. Loading State (Premium Shimmer)
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 20),
            // Avatar + Info Skeleton
            const Row(
              children: [
                SkeletonLoader.circle(size: 80),
                SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLoader(width: 150, height: 24),
                      SizedBox(height: 12),
                      SkeletonLoader(width: 100, height: 16),
                      SizedBox(height: 12),
                      SkeletonLoader(width: 200, height: 8),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Bio Lines
            const SkeletonLoader(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            const SkeletonLoader(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            const SkeletonLoader(width: 200, height: 14),
            const SizedBox(height: 40),
            // Stats Matrix Placeholder
            const Center(child: SkeletonLoader.circle(size: 200)),
          ],
        ),
      );
    }

    // 2. Error State
    if (_errorMessage != null || _userData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(child: Text('User not found: $_errorMessage')),
      );
    }

    final rpgStats = _calculateRpgStats();
    final charClass = _getCharacterClass(rpgStats);
    // Use custom badge if set, otherwise fallback to computed RPG class
    final badgeText = _userData?['custom_badge'] ?? charClass;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () => Future.wait([_loadUserProfile(), _loadUserPosts()]),
        color: AppTheme.accentColor,
        child: CustomScrollView(
          controller: _profileScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. RPG Header (Parallax)
            ProfileParallaxHeader(
              imageUrl: _userData?['avatar_url'],
              displayName: _userData?['display_name'] ?? 'Unknown',
              username: _userData?['username'],
              characterClass: badgeText,
              isOwnProfile: _isOwnProfile,
              onBadgeEdit: _isOwnProfile
                  ? () => _showEditBadgeDialog(badgeText)
                  : null,
              onEdit: () async {
                final bool? result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditProfileScreen(
                      userProfile: _userData ?? {},
                      userPhotos: _userPhotos,
                    ),
                  ),
                );

                if (result == true) {
                  _loadUserProfile();
                }
              },
              onSettings: () => _showSettingsMenu(context),
              onShare: () {
                // Implement share
              },
            ),

            // 2. Glass Stats Card (Floating Overlap)
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(
                  0,
                  -8,
                ), // Lowered — slight overlap for depth
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child:
                      GlassStatsCard(
                            stats: _stats ?? {},
                            onFollowersTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ConnectedUsersScreen(
                                    userId: widget.userId,
                                    initialTabIndex: 0,
                                  ),
                                ),
                              );
                            },
                            onFollowingTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ConnectedUsersScreen(
                                    userId: widget.userId,
                                    initialTabIndex: 1,
                                  ),
                                ),
                              );
                            },
                          )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 300.ms)
                          .slideY(begin: 0.2, end: 0),
                ),
              ),
            ),

            // Brand header — brand-mode organizers lead with a branded block
            // (cover, logo, name, follow, counts). Person-mode organizers keep
            // the personal profile + compact card below (team_comms #220).
            if (_isBrandOrganizer)
              SliverToBoxAdapter(
                child: _BrandHeader(
                  storefront: _storefront!,
                  isDark: isDark,
                ).animate().fadeIn(duration: 500.ms, delay: 250.ms),
              ),

            // Badges Showcase
            if (_allBadges.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: BadgesShowcase(
                    allBadges: _allBadges,
                    earnedBadges: _earnedBadges,
                    isOwnProfile: _isOwnProfile,
                  ).animate().fadeIn(duration: 500.ms, delay: 500.ms),
                ),
              ),

            // Partner loyalty badges (Steam-style case). Self-loading and
            // hidden when the user has earned none, so it costs nothing to place.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: CreatorBadgeCase(
                  userId: widget.userId,
                  isOwnProfile: _isOwnProfile,
                ).animate().fadeIn(duration: 500.ms, delay: 550.ms),
              ),
            ),

            // 3. Action Buttons & Bio
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8), // Adjusted for overlap offset
                    // Action Buttons (Only for others)
                    if (!_isOwnProfile) ...[
                      Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _toggleFollow,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isFollowing
                                        ? Colors.transparent
                                        : AppTheme.primaryColor,
                                    foregroundColor: _isFollowing
                                        ? Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.color
                                        : Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14, // Tighter
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        24,
                                      ), // Pill shape
                                      side: _isFollowing
                                          ? BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            )
                                          : BorderSide.none,
                                    ),
                                  ),
                                  icon: Icon(
                                    _isFollowing
                                        ? Icons.check
                                        : Icons.person_add,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _isFollowing
                                        ? 'Following'
                                        : (_followsYou
                                              ? 'Follow back'
                                              : 'Follow'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _openDirectMessage,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    side: const BorderSide(
                                      color: AppTheme.primaryColor,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.chat_bubble_outline,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Message',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz, size: 20),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    side: BorderSide(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  onSelected: (value) {
                                    if (value == 'report') {
                                      ReportModal.show(
                                        context,
                                        targetType: 'user',
                                        targetId: widget.userId,
                                        targetName: _userData?['display_name'],
                                      );
                                    } else if (value == 'block') {
                                      _toggleBlock();
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'report',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.flag_outlined,
                                            size: 18,
                                            color: Colors.orange,
                                          ),
                                          SizedBox(width: 10),
                                          Text('Report'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'block',
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isBlocked
                                                ? Icons.check_circle_outline
                                                : Icons.block,
                                            size: 18,
                                            color: _isBlocked
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _isBlocked ? 'Unblock' : 'Block',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 400.ms)
                          .slideY(begin: 0.2, end: 0),
                      const SizedBox(height: 24),
                    ],

                    // Bio
                    if (_userData?['bio'] != null &&
                        (_userData!['bio'] as String).isNotEmpty) ...[
                      Text(
                        _userData!['bio'],
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                      ).animate().fadeIn(duration: 600.ms, delay: 500.ms),
                      const SizedBox(height: 16),
                    ],

                    // Occupation
                    if (_userData?['occupation'] != null &&
                        (_userData!['occupation'] as String).isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.work_outline_rounded,
                            size: 16,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _userData!['occupation'],
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(duration: 600.ms, delay: 520.ms),
                      const SizedBox(height: 8),
                    ],

                    // Nationality
                    if (_userData?['nationality'] != null &&
                        (_userData!['nationality'] as String).isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            size: 16,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _userData!['nationality'],
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ).animate().fadeIn(duration: 600.ms, delay: 550.ms),
                      const SizedBox(height: 16),
                    ],

                    // Interests
                    if (_userInterests.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _userInterests.map<Widget>((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.accentColor.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ).animate().fadeIn(duration: 600.ms, delay: 600.ms),
                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),
            ),

            // 5. Organizer card — compact link to the storefront, for
            // PERSON-mode organizers only. Brand-mode organizers get the full
            // brand header up top instead (team_comms #220).
            if (_organizerProfile != null && !_isBrandOrganizer)
              SliverToBoxAdapter(
                child: _OrganizerSection(
                  profile: _organizerProfile!,
                  isDark: isDark,
                ).animate().fadeIn(duration: 600.ms, delay: 700.ms),
              ),

            // 5b/5c. Membership sections — commented out for now: the
            // subscription model isn't live yet, so there's nothing real to
            // manage/view. Re-enable once fan subscriptions ship.
            // if (!_isOwnProfile &&
            //     _organizerProfile != null &&
            //     _organizerProfile!['show_membership_tab'] == true)
            //   SliverToBoxAdapter(
            //     child: _MembershipSection(
            //       tiers: (_organizerProfile!['tiers'] as List? ?? [])
            //           .cast<Map<String, dynamic>>(),
            //       viewerSubscription: _viewerSubscription,
            //       slug: _organizerProfile!['slug'] as String? ?? '',
            //       isDark: isDark,
            //       onManage: () => Navigator.push(
            //         context,
            //         MaterialPageRoute(
            //           builder: (_) => const MyMembershipsScreen(),
            //         ),
            //       ),
            //     ).animate().fadeIn(duration: 600.ms, delay: 750.ms),
            //   ),
            //
            // if (_isOwnProfile && _myMemberships.isNotEmpty)
            //   SliverToBoxAdapter(
            //     child: _MyMembershipsCompact(
            //       memberships: _myMemberships,
            //       isDark: isDark,
            //       onViewAll: () => Navigator.push(
            //         context,
            //         MaterialPageRoute(
            //           builder: (_) => const MyMembershipsScreen(),
            //         ),
            //       ),
            //     ).animate().fadeIn(duration: 600.ms, delay: 720.ms),
            //   ),

            // 6a. Featured Photos (manually curated from user_photos)
            if (_userPhotos.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: _buildSectionHeader(context, 'FEATURED'),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 160,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: _userPhotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final url = _userPhotos[index]['photo_url'] ?? '';
                      return GestureDetector(
                        onTap: () {
                          if (url.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    FullScreenImageViewer(imageUrl: url),
                              ),
                            );
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Hero(
                            tag: 'featured_$url',
                            child: CachedNetworkImage(
                              imageUrl: url,
                              height: 160,
                              width: 120,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                width: 120,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                width: 120,
                                color: isDark
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.grey[100],
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],

            // 6b. POSTS — Facebook-style timeline of the user's own posts.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              sliver: SliverToBoxAdapter(
                child: _buildSectionHeader(context, 'POSTS'),
              ),
            ),

            // 6c. Timeline body: loading / empty / list of full post cards.
            if (_isLoadingPosts)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (_posts.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 40,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No posts yet',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        if (_isOwnProfile) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Share your first moment on the feed',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = _posts[index];
                    // Hangout posts get their own rich card (same as the feed);
                    // everything else uses the standard post card.
                    if (post['post_type'] == 'hangout') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: HangoutFeedCard(
                          key: ValueKey(post['id']),
                          post: post,
                          onTap: () {
                            final metadata =
                                post['metadata'] as Map<String, dynamic>?;
                            final tableId = metadata?['table_id'];
                            if (tableId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TableCompactModal(
                                    table: {'id': tableId},
                                    matchData: const {},
                                  ),
                                ),
                              );
                            }
                          },
                          onPostDeleted: _onPostDeleted,
                          onPostEdited: _onPostEdited,
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SocialPostCard(
                        key: ValueKey(post['id']),
                        post: post,
                        onTap: () {
                          final id = post['id']?.toString();
                          if (id == null) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PostDetailScreen(postId: id),
                            ),
                          );
                        },
                        onPostDeleted: _onPostDeleted,
                        onPostEdited: _onPostEdited,
                      ),
                    );
                  },
                  childCount: _posts.length,
                ),
              ),

            // 6d. Load-more spinner for the timeline
            if (!_isLoadingPosts && _isLoadingMorePosts)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),

            // Bottom spacer
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 80,
              ),
            ),
          ], // Close slivers array
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

}

// ─── Membership Section ───────────────────────────────────────────────────────

class _MembershipSection extends StatelessWidget {
  final List<Map<String, dynamic>> tiers;
  final Map<String, dynamic>? viewerSubscription;
  final String slug;
  final bool isDark;
  final VoidCallback onManage;

  const _MembershipSection({
    required this.tiers,
    required this.viewerSubscription,
    required this.slug,
    required this.isDark,
    required this.onManage,
  });

  IconData _perkIcon(String type) {
    switch (type) {
      case 'digital_download':
        return Icons.download_rounded;
      case 'community_link':
        return Icons.group_rounded;
      case 'merch':
        return Icons.redeem_rounded;
      case 'shoutout':
        return Icons.campaign_rounded;
      case 'early_access':
        return Icons.bolt_rounded;
      case 'gated_posts':
        return Icons.lock_open_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.grey.shade200;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MEMBERSHIP',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (viewerSubscription != null)
                GestureDetector(
                  onTap: onManage,
                  child: Text(
                    'Manage →',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Active subscriber view
          if (viewerSubscription != null) ...[
            _ActiveSubCard(
              subscription: viewerSubscription!,
              cardColor: cardColor,
              borderColor: borderColor,
              isDark: isDark,
              perkIcon: _perkIcon,
              onManage: onManage,
            ),
          ] else if (tiers.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No membership tiers available yet.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),
          ] else ...[
            ...tiers.map((tier) => _TierCard(
              tier: tier,
              slug: slug,
              cardColor: cardColor,
              borderColor: borderColor,
              isDark: isDark,
              perkIcon: _perkIcon,
            )),
          ],
        ],
      ),
    );
  }
}

class _ActiveSubCard extends StatelessWidget {
  final Map<String, dynamic> subscription;
  final Color cardColor;
  final Color borderColor;
  final bool isDark;
  final IconData Function(String) perkIcon;
  final VoidCallback onManage;

  const _ActiveSubCard({
    required this.subscription,
    required this.cardColor,
    required this.borderColor,
    required this.isDark,
    required this.perkIcon,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final tier = subscription['subscription_tiers'] as Map<String, dynamic>?;
    final tierName = tier?['name'] as String? ?? 'Member';
    final price = tier?['price_monthly'];
    final priceStr = price != null ? '₱${price.toString()}/mo' : '';
    final periodEnd = subscription['current_period_end'] as String?;
    DateTime? renewDate;
    if (periodEnd != null) renewDate = DateTime.tryParse(periodEnd);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tierName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[600],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (priceStr.isNotEmpty) priceStr,
              if (renewDate != null)
                'Renews ${DateFormat('MMM d, y').format(renewDate)}',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onManage,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: const BorderSide(color: AppTheme.primaryColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.star_outline_rounded, size: 16),
              label: const Text('View perks',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final Map<String, dynamic> tier;
  final String slug;
  final Color cardColor;
  final Color borderColor;
  final bool isDark;
  final IconData Function(String) perkIcon;

  const _TierCard({
    required this.tier,
    required this.slug,
    required this.cardColor,
    required this.borderColor,
    required this.isDark,
    required this.perkIcon,
  });

  @override
  Widget build(BuildContext context) {
    final name = tier['name'] as String? ?? '';
    final price = tier['price_monthly'];
    final rawPerks = tier['perks'] as List? ?? [];
    final perks = rawPerks.cast<Map<String, dynamic>>().take(3).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                price != null ? '₱$price/mo' : '',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          if (perks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: perks.map((p) {
                final label = p['label'] as String? ?? '';
                final type = p['type'] as String? ?? 'custom';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(perkIcon(type), size: 12, color: Colors.grey[500]),
                    const SizedBox(width: 3),
                    Text(
                      label,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final uri = Uri.parse(
                  'https://hanghut.com/$slug/membership/${tier['id']}',
                );
                if (!await launchUrl(uri,
                    mode: LaunchMode.externalApplication)) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open browser')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text(
                'Join now',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── My Memberships Compact (own profile) ────────────────────────────────────

class _MyMembershipsCompact extends StatelessWidget {
  final List<Map<String, dynamic>> memberships;
  final bool isDark;
  final VoidCallback onViewAll;

  const _MyMembershipsCompact({
    required this.memberships,
    required this.isDark,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = memberships.take(2).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MY MEMBERSHIPS',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  'All →',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...preview.map((sub) {
            final partner = sub['partners'] as Map<String, dynamic>?;
            final tier = sub['subscription_tiers'] as Map<String, dynamic>?;
            final name = partner?['business_name'] as String? ?? 'Organizer';
            final photoUrl = partner?['profile_photo_url'] as String?;
            final tierName = tier?['name'] as String? ?? '';
            final price = tier?['price_monthly'];
            final periodEnd = sub['current_period_end'] as String?;
            DateTime? renewDate;
            if (periodEnd != null) renewDate = DateTime.tryParse(periodEnd);

            return GestureDetector(
              onTap: onViewAll,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? Colors.white10
                            : Colors.grey.shade100,
                        border: Border.all(
                          color:
                              const Color(0xFFFFD700).withOpacity(0.5),
                          width: 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.storefront_rounded,
                                size: 20,
                                color: AppTheme.primaryColor,
                              ),
                            )
                          : const Icon(
                              Icons.storefront_rounded,
                              size: 20,
                              color: AppTheme.primaryColor,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (tierName.isNotEmpty) tierName,
                              if (price != null) '₱$price/mo',
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(Icons.workspace_premium_rounded,
                            color: Color(0xFFFFD700), size: 16),
                        if (renewDate != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('MMM d').format(renewDate),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          if (memberships.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: onViewAll,
                child: Text(
                  '+${memberships.length - 2} more',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


// ─── Organizer card ───────────────────────────────────────────────────────────
// Compact link to the organizer's storefront (their brand/sell page). The
// social profile no longer renders the events grid / tiers / social links —
// those live on the storefront now (team_comms #220, get_storefront).
class _OrganizerSection extends StatelessWidget {
  final Map<String, dynamic> profile;
  final bool isDark;

  const _OrganizerSection({required this.profile, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVerified = profile['verified'] == true;
    final businessName = profile['business_name'] as String? ?? 'Organizer';
    final photoUrl = profile['profile_photo_url'] as String?;
    final partnerId = profile['partner_id'] as String? ?? '';
    final isBrand = profile['profile_mode'] == 'brand';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: partnerId.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PartnerStorefrontScreen(partnerId: partnerId),
                      ),
                    ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? Colors.white10 : Colors.grey.shade100,
                      border: Border.all(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: photoUrl != null && photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(
                              Icons.storefront_rounded,
                              color: AppTheme.primaryColor,
                              size: 26,
                            ),
                          )
                        : const Icon(
                            Icons.storefront_rounded,
                            color: AppTheme.primaryColor,
                            size: 26,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                businessName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.verified_rounded,
                                size: 18,
                                color: AppTheme.primaryColor,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isBrand ? 'View store' : 'View organizer page',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'ORGANIZER',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
        ),
      ],
    );
  }
}

// ─── Brand header ─────────────────────────────────────────────────────────────
// Leads a brand-mode organizer's profile: cover, logo, name, follower/event
// counts, Follow button, and a link into the full storefront. Powered by
// get_storefront (team_comms #220).
class _BrandHeader extends StatefulWidget {
  final Map<String, dynamic> storefront;
  final bool isDark;

  const _BrandHeader({required this.storefront, required this.isDark});

  @override
  State<_BrandHeader> createState() => _BrandHeaderState();
}

class _BrandHeaderState extends State<_BrandHeader> {
  bool _following = false;
  bool _busy = false;
  int _followers = 0;

  Map<String, dynamic> get _partner =>
      (widget.storefront['partner'] as Map).cast<String, dynamic>();
  String get _partnerId => _partner['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    final counts =
        (widget.storefront['counts'] as Map?)?.cast<String, dynamic>() ?? {};
    _followers = (counts['followers'] as num?)?.toInt() ?? 0;
    _loadFollow();
  }

  Future<void> _loadFollow() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null || _partnerId.isEmpty) return;
    try {
      final rows = await SupabaseConfig.client
          .from('partner_followers')
          .select('id')
          .eq('user_id', uid)
          .eq('partner_id', _partnerId)
          .limit(1);
      if (mounted) setState(() => _following = (rows as List).isNotEmpty);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log in to follow organizers')),
      );
      return;
    }
    final prev = _following;
    final prevCount = _followers;
    setState(() {
      _following = !prev;
      _followers = prevCount + (prev ? -1 : 1);
      _busy = true;
    });
    try {
      final res = await SupabaseConfig.client.rpc(
        'toggle_partner_follow',
        params: {'p_partner_id': _partnerId},
      );
      final f = (res as Map)['following'] as bool? ?? !prev;
      if (mounted) {
        setState(() {
          _following = f;
          _followers = prevCount + (f ? 1 : 0);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _following = prev;
          _followers = prevCount;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isDark = widget.isDark;
    final p = _partner;
    final name = p['business_name'] as String? ?? 'Organizer';
    final logo = p['profile_photo_url'] as String?;
    final cover = p['cover_image_url'] as String?;
    final verified = p['verified'] == true;
    final events =
        ((widget.storefront['upcoming_events'] as List?) ?? const []).length;
    final hasCover = cover != null && cover.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCover)
              CachedNetworkImage(
                imageUrl: cover,
                height: 116,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 116,
                  color: primary.withOpacity(0.08),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white10 : Colors.grey.shade100,
                          border: Border.all(
                            color: primary.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: logo != null && logo.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: logo,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.storefront_rounded,
                                  color: primary,
                                  size: 24,
                                ),
                              )
                            : Icon(Icons.storefront_rounded,
                                color: primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (verified) ...[
                                  const SizedBox(width: 5),
                                  const Icon(Icons.verified,
                                      size: 16, color: Colors.blue),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_followers ${_followers == 1 ? 'follower' : 'followers'}'
                              '${events > 0 ? ' · $events upcoming' : ''}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _followButton(primary)),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _partnerId.isEmpty
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PartnerStorefrontScreen(
                                        partnerId: _partnerId),
                                  ),
                                ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white70 : Colors.black87,
                          side: BorderSide(
                              color:
                                  isDark ? Colors.grey[700]! : Colors.grey[300]!),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                        child: const Text('View store'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _followButton(Color primary) {
    final spinner = SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: _following ? primary : Colors.white,
      ),
    );
    const pad = EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    const labelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);

    if (_following) {
      return OutlinedButton.icon(
        onPressed: _toggle,
        icon: _busy ? spinner : const Icon(Icons.check_rounded, size: 18),
        label: const Text('Following'),
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          padding: pad,
          shape: const StadiumBorder(),
          textStyle: labelStyle,
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: _toggle,
      icon: _busy ? spinner : const Icon(Icons.add_rounded, size: 18),
      label: const Text('Follow'),
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: pad,
        shape: const StadiumBorder(),
        textStyle: labelStyle,
      ),
    );
  }
}
