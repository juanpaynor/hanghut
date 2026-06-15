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
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/features/host/screens/host_apply_screen.dart';
import 'package:bitemates/features/host/screens/host_pending_screen.dart';
import 'package:bitemates/features/host/screens/host_dashboard_screen.dart';
import 'package:bitemates/features/settings/widgets/report_modal.dart';
import 'package:bitemates/core/services/report_service.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/features/gamification/models/gamification_stats.dart';
import 'package:bitemates/features/gamification/models/badge.dart' as gm;
import 'package:bitemates/features/gamification/models/user_badge.dart';
import 'package:bitemates/features/gamification/services/badge_service.dart';
import 'package:bitemates/features/profile/widgets/badges_showcase.dart';
import 'package:bitemates/features/profile/screens/my_memberships_screen.dart';

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
  List<String> _postImages = [];
  List<String> _userInterests = [];
  int _postImagesPage = 0;
  static const int _postImagesPageSize = 30;
  bool _hasMorePostImages = true;
  bool _isLoadingMorePostImages = false;

  GamificationStats? _gamificationStats;
  List<gm.Badge> _allBadges = [];
  List<UserBadge> _earnedBadges = [];
  String? _errorMessage;
  bool _isFollowing = false;
  bool _isBlocked = false;
  late final bool _isOwnProfile;
  Map<String, dynamic>? _organizerProfile; // null = not an organizer
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
        _loadMorePostImages();
      }
    });
    _loadUserProfile();
    _loadOrganizerProfile();
    _loadBadges();
    _loadMorePostImages();
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

  Future<void> _loadMorePostImages() async {
    if (_isLoadingMorePostImages || !_hasMorePostImages) return;
    if (mounted) setState(() => _isLoadingMorePostImages = true);
    try {
      final offset = _postImagesPage * _postImagesPageSize;
      final response = await SupabaseConfig.client
          .from('posts')
          .select('image_url, image_urls')
          .eq('user_id', widget.userId)
          .eq('is_story', false)
          .order('created_at', ascending: false)
          .range(offset, offset + _postImagesPageSize - 1);
      if (!mounted) return;
      final List<String> newImages = [];
      for (final post in response as List<dynamic>) {
        final urls = post['image_urls'];
        if (urls != null && urls is List && urls.isNotEmpty) {
          for (final u in urls) {
            if (u != null && u.toString().isNotEmpty)
              newImages.add(u.toString());
          }
        } else {
          final single = post['image_url'];
          if (single != null && single.toString().isNotEmpty)
            newImages.add(single.toString());
        }
      }
      setState(() {
        _postImages.addAll(newImages);
        _postImagesPage++;
        if (newImages.length < _postImagesPageSize) _hasMorePostImages = false;
        _isLoadingMorePostImages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMorePostImages = false);
    }
  }

  Future<void> _loadOrganizerProfile() async {
    try {
      final result = await SupabaseConfig.client.rpc(
        'get_organizer_public_profile',
        params: {'p_user_id': widget.userId},
      );
      if (result != null && mounted) {
        setState(() {
          _organizerProfile = Map<String, dynamic>.from(result as Map);
        });
        if (!_isOwnProfile) {
          _loadViewerSubscription(result['partner_id'] as String);
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
        // Gamification stats (XP + level)
        supabase
            .from('user_gamification_stats')
            .select()
            .eq('user_id', widget.userId)
            .maybeSingle(),
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
      final gamificationResult = results[7] as Map<String, dynamic>?;
      final interestsResponse = results[8] as List<dynamic>;

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
          _gamificationStats = gamificationResult != null
              ? GamificationStats.fromJson(gamificationResult)
              : null;
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

      final result = await SupabaseConfig.client
          .from('follows')
          .select('follower_id')
          .eq('follower_id', currentUserId)
          .eq('following_id', widget.userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isFollowing = result != null;
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

  /// Whether the organizer has anything live worth showing: at least one
  /// active upcoming event or one active subscription tier. The RPC already
  /// filters both lists to active/upcoming only.
  bool get _hasActiveOrganizerContent {
    if (_organizerProfile == null) return false;
    final events = _organizerProfile!['events'];
    final tiers = _organizerProfile!['tiers'];
    final hasEvents = events is List && events.isNotEmpty;
    final hasTiers = tiers is List && tiers.isNotEmpty;
    return hasEvents || hasTiers;
  }

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
        onRefresh: _loadUserProfile,
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

            // XP Level Bar
            if (_gamificationStats != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: _XpLevelBar(
                    stats: _gamificationStats!,
                    isDark: isDark,
                  ).animate().fadeIn(duration: 500.ms, delay: 400.ms),
                ),
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
                                    _isFollowing ? 'Following' : 'Follow',
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

                    // Switch to Host Mode (own profile only)
                    if (_isOwnProfile) ...[
                      _HostModeButton(),
                      const SizedBox(height: 8),
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

            // 5. Organizer Section — only shown when the organizer has active
            // content (an upcoming event OR an active subscription tier).
            // Being an approved partner alone is not enough: cancelling all
            // events/tiers hides this section.
            if (_organizerProfile != null && _hasActiveOrganizerContent)
              SliverToBoxAdapter(
                child: _OrganizerSection(
                  profile: _organizerProfile!,
                  isDark: isDark,
                ).animate().fadeIn(duration: 600.ms, delay: 700.ms),
              ),

            // 5b. Membership Section (organizer has show_membership_tab=true, viewed by others)
            if (!_isOwnProfile &&
                _organizerProfile != null &&
                _organizerProfile!['show_membership_tab'] == true)
              SliverToBoxAdapter(
                child: _MembershipSection(
                  tiers: (_organizerProfile!['tiers'] as List? ?? [])
                      .cast<Map<String, dynamic>>(),
                  viewerSubscription: _viewerSubscription,
                  slug: _organizerProfile!['slug'] as String? ?? '',
                  isDark: isDark,
                  onManage: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyMembershipsScreen(),
                    ),
                  ),
                ).animate().fadeIn(duration: 600.ms, delay: 750.ms),
              ),

            // 5c. My Memberships (own profile, has active subscriptions)
            if (_isOwnProfile && _myMemberships.isNotEmpty)
              SliverToBoxAdapter(
                child: _MyMembershipsCompact(
                  memberships: _myMemberships,
                  isDark: isDark,
                  onViewAll: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyMembershipsScreen(),
                    ),
                  ),
                ).animate().fadeIn(duration: 600.ms, delay: 720.ms),
              ),

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

            // 6b. Photos Grid (Instagram-style) — header
            if (_postImages.isNotEmpty || _isLoadingMorePostImages)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: _buildSectionHeader(context, 'PHOTOS'),
                ),
              ),

            // 6c. Photos — Polaroid scatter (lazy, paginated)
            if (_postImages.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.80,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildPolaroidTile(context, index, isDark),
                    childCount: _postImages.length,
                  ),
                ),
              ),

            // 6d. Load-more footer for photos
            if (_postImages.isNotEmpty || _isLoadingMorePostImages)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _isLoadingMorePostImages
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _hasMorePostImages
                      ? Center(
                          child: TextButton(
                            onPressed: _loadMorePostImages,
                            child: Text(
                              'Load more',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox(height: 8),
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

  // Deterministic tilt per index so the scatter is stable across rebuilds.
  static const _polaroidTilts = [
    -0.045,
    0.032,
    -0.022,
    0.05,
    -0.05,
    0.028,
    -0.035,
    0.04,
  ];

  /// A single tilted polaroid card for the PHOTOS scatter.
  Widget _buildPolaroidTile(BuildContext context, int index, bool isDark) {
    final url = _postImages[index];
    final tilt = _polaroidTilts[index % _polaroidTilts.length];
    // Unique per-tile tag — guards against duplicate URLs in the grid.
    final heroTag = 'polaroid_${index}_$url';

    return Transform.rotate(
      angle: tilt,
      child: GestureDetector(
        onTap: () => _openPhoto(context, url, heroTag),
        child: Container(
          // White polaroid frame — chunkier at the bottom lip.
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF26262E) : Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Hero(
                    tag: heroTag,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey[200],
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey[200],
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens a photo with a morph (Hero) transition. The black backdrop fades in
  /// while the tapped image flies and expands into the fullscreen viewer.
  void _openPhoto(BuildContext context, String url, Object heroTag) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) =>
            FullScreenImageViewer(imageUrl: url, heroTag: heroTag),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
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

// ─── XP Level Bar ─────────────────────────────────────────────────────────────

class _XpLevelBar extends StatelessWidget {
  final GamificationStats stats;
  final bool isDark;

  const _XpLevelBar({required this.stats, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final level = stats.level;
    final xp = stats.totalXp;
    final progress = levelProgress(xp).clamp(0.0, 1.0);
    final isMaxLevel = level >= kLevelThresholds.length;
    final xpForNext = isMaxLevel
        ? kLevelThresholds.last
        : kLevelThresholds[level]; // next level threshold
    final xpInCurrentLevel = isMaxLevel ? xp : xp - kLevelThresholds[level - 1];
    final xpNeeded = isMaxLevel ? 0 : xpForNext - kLevelThresholds[level - 1];

    // Hanghut brand indigo — consistent across all levels.
    const barColor = AppTheme.primaryColor; // 0xFF6B7FFF
    const barColorLight = Color(0xFFA5B0FF);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.06),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.92),
                      Colors.white.withValues(alpha: 0.7),
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.7),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: barColor.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [barColorLight, barColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: barColor.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$level',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Level $level${isMaxLevel ? ' · MAX' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: barColor,
                              ),
                            ),
                            Text(
                              isMaxLevel
                                  ? '$xp XP total'
                                  : '$xpInCurrentLevel / $xpNeeded XP',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: isMaxLevel ? 1.0 : progress,
                            minHeight: 7,
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : barColor.withValues(alpha: 0.12),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              barColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Organizer Public Profile Section ────────────────────────────────────────

class _OrganizerSection extends StatelessWidget {
  final Map<String, dynamic> profile;
  final bool isDark;

  const _OrganizerSection({required this.profile, required this.isDark});

  void _launchUrl(BuildContext context, String url) async {
    // Ensure URL has a scheme
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVerified = profile['verified'] == true;
    final businessName = profile['business_name'] as String? ?? '';
    final description = profile['description'] as String?;
    final photoUrl = profile['profile_photo_url'] as String?;
    final instagram = profile['instagram'] as String?;
    final facebook = profile['facebook'] as String?;
    final website = profile['website'] as String?;
    final tiktok = profile['tiktok'] as String?;
    final twitter = profile['twitter'] as String?;

    final rawEvents = profile['events'] as List?;
    final events = rawEvents?.cast<Map<String, dynamic>>() ?? [];

    final hasSocialLinks = [
      instagram,
      facebook,
      website,
      tiktok,
      twitter,
    ].any((v) => v != null && v.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header
          _buildSectionHeader(context),
          const SizedBox(height: 16),

          // ── Organizer identity card
          Container(
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
                // Logo / profile photo
                Container(
                  width: 56,
                  height: 56,
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
                            size: 28,
                          ),
                        )
                      : const Icon(
                          Icons.storefront_rounded,
                          color: AppTheme.primaryColor,
                          size: 28,
                        ),
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
                              businessName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Verified Organizer',
                              child: Icon(
                                Icons.verified_rounded,
                                size: 18,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Social links row
          if (hasSocialLinks) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (instagram != null && instagram.isNotEmpty)
                  _SocialChip(
                    icon: Icons.camera_alt_outlined,
                    label: instagram.startsWith('@')
                        ? instagram
                        : '@$instagram',
                    onTap: () => _launchUrl(
                      context,
                      'https://instagram.com/${instagram.replaceAll('@', '')}',
                    ),
                    isDark: isDark,
                  ),
                if (tiktok != null && tiktok.isNotEmpty)
                  _SocialChip(
                    icon: Icons.music_note_rounded,
                    label: tiktok.startsWith('@') ? tiktok : '@$tiktok',
                    onTap: () => _launchUrl(
                      context,
                      'https://tiktok.com/@${tiktok.replaceAll('@', '')}',
                    ),
                    isDark: isDark,
                  ),
                if (facebook != null && facebook.isNotEmpty)
                  _SocialChip(
                    icon: Icons.facebook_rounded,
                    label: 'Facebook',
                    onTap: () => _launchUrl(context, facebook),
                    isDark: isDark,
                  ),
                if (twitter != null && twitter.isNotEmpty)
                  _SocialChip(
                    icon: Icons.alternate_email_rounded,
                    label: twitter.startsWith('@') ? twitter : '@$twitter',
                    onTap: () => _launchUrl(
                      context,
                      'https://x.com/${twitter.replaceAll('@', '')}',
                    ),
                    isDark: isDark,
                  ),
                if (website != null && website.isNotEmpty)
                  _SocialChip(
                    icon: Icons.language_rounded,
                    label: 'Website',
                    onTap: () => _launchUrl(context, website),
                    isDark: isDark,
                  ),
              ],
            ),
          ],

          // ── Active events
          if (events.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'UPCOMING EVENTS',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: events.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) =>
                    _OrganizerEventCard(event: events[i], isDark: isDark),
              ),
            ),
          ],
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
          'EVENT ORGANIZER',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ─── Social link chip ─────────────────────────────────────────────────────────

class _SocialChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _SocialChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.primaryColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Single event card inside organizer section ───────────────────────────────

class _OrganizerEventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isDark;

  const _OrganizerEventCard({required this.event, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final title = event['title'] as String? ?? 'Event';
    final coverUrl = event['cover_image_url'] as String?;
    final venueStr = event['venue_name'] as String?;
    final rawDate = event['start_datetime'] as String?;
    final price = event['ticket_price'];

    DateTime? startDate;
    if (rawDate != null) {
      startDate = DateTime.tryParse(rawDate)?.toLocal();
    }

    return GestureDetector(
      onTap: () {
        // Build a minimal Event object to pass to EventDetailModal
        try {
          final eventObj = Event(
            id: event['id'] as String,
            title: title,
            description: '',
            venueName: venueStr ?? '',
            venueAddress: '',
            latitude: 0,
            longitude: 0,
            startDatetime: startDate ?? DateTime.now(),
            coverImageUrl: coverUrl,
            ticketPrice: (price as num?)?.toDouble() ?? 0,
            capacity: (event['capacity'] as num?)?.toInt() ?? 0,
            ticketsSold: (event['tickets_sold'] as num?)?.toInt() ?? 0,
            category: event['event_type'] as String? ?? 'other',
            organizerId: event['organizer_id'] as String? ?? '',
            createdAt: DateTime.now(),
          );
          EventDetailModal.show(context, eventObj);
        } catch (_) {}
      },
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.grey.shade200,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            SizedBox(
              height: 90,
              width: double.infinity,
              child: coverUrl != null && coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _EventCoverPlaceholder(isDark: isDark),
                    )
                  : _EventCoverPlaceholder(isDark: isDark),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 10,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          startDate != null
                              ? DateFormat('MMM d').format(startDate)
                              : '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          price != null && price > 0
                              ? '₱${(price as num).toStringAsFixed(0)}'
                              : 'Free',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
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
    );
  }
}

class _EventCoverPlaceholder extends StatelessWidget {
  final bool isDark;
  const _EventCoverPlaceholder({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? Colors.white10 : Colors.grey.shade100,
      child: Center(
        child: Icon(
          Icons.event_rounded,
          size: 32,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
  }
}

// ─── Host Mode Entry Point Button ────────────────────────────────────────────

class _HostModeButton extends StatefulWidget {
  const _HostModeButton();

  @override
  State<_HostModeButton> createState() => _HostModeButtonState();
}

class _HostModeButtonState extends State<_HostModeButton> {
  final _hostService = HostService();
  Map<String, dynamic>? _partner;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPartner();
  }

  Future<void> _loadPartner() async {
    final partner = await _hostService.getMyPartnerProfile();
    if (mounted) {
      setState(() {
        _partner = partner;
        _isLoading = false;
      });
    }
  }

  void _onTap() {
    if (_partner == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HostApplyScreen()),
      ).then((_) => _loadPartner());
    } else if (_partner!['status'] == 'approved') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HostDashboardScreen(partner: _partner!),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HostPendingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox(height: 52);

    final isApproved = _partner?['status'] == 'approved';
    final isPending = _partner != null && !isApproved;

    return GestureDetector(
      onTap: _onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isApproved
              ? AppTheme.primaryColor.withOpacity(0.08)
              : isPending
              ? Colors.orange.withOpacity(0.08)
              : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isApproved
                ? AppTheme.primaryColor.withOpacity(0.3)
                : isPending
                ? Colors.orange.withOpacity(0.4)
                : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isApproved
                  ? Icons.storefront_outlined
                  : isPending
                  ? Icons.hourglass_top_rounded
                  : Icons.add_business_outlined,
              size: 16,
              color: isApproved
                  ? AppTheme.primaryColor
                  : isPending
                  ? Colors.orange[700]
                  : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Text(
              isApproved
                  ? 'Switch to Host Mode'
                  : isPending
                  ? 'Application Under Review'
                  : 'Become a Host',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isApproved
                    ? AppTheme.primaryColor
                    : isPending
                    ? Colors.orange[700]
                    : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
