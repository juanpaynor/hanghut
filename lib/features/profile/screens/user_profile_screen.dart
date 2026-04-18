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
  List<dynamic> _hostedTables = [];
  List<Map<String, dynamic>> _userPhotos = [];
  Map<String, dynamic>? _userTrip;
  List<Map<String, dynamic>> _pastTrips = [];
  GamificationStats? _gamificationStats;
  List<gm.Badge> _allBadges = [];
  List<UserBadge> _earnedBadges = [];
  String? _errorMessage;
  bool _isFollowing = false;
  bool _isBlocked = false;
  late final bool _isOwnProfile;
  Map<String, dynamic>? _organizerProfile; // null = not an organizer

  @override
  void initState() {
    super.initState();
    // Auto-detect own profile: override widget.isOwnProfile if userId matches current user
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    _isOwnProfile = widget.isOwnProfile || widget.userId == currentUserId;
    _loadUserProfile();
    _loadOrganizerProfile();
    _loadBadges();
    if (!_isOwnProfile) {
      _checkFollowStatus();
      _checkBlockStatus();
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
      }
    } catch (e) {
      // Not an organizer or RPC failed — silently ignore
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
        // Active/upcoming trip (only if end_date hasn't passed)
        supabase
            .from('user_trips')
            .select()
            .eq('user_id', widget.userId)
            .inFilter('status', ['upcoming', 'active'])
            .gte('end_date', DateTime.now().toIso8601String().substring(0, 10))
            .order('start_date', ascending: true)
            .limit(1)
            .maybeSingle(),
        // Past/completed trips
        supabase
            .from('user_trips')
            .select()
            .eq('user_id', widget.userId)
            .or(
              'status.eq.completed,end_date.lt.${DateTime.now().toIso8601String().substring(0, 10)}',
            )
            .order('end_date', ascending: false)
            .limit(5),
        // Gamification stats (XP + level)
        supabase
            .from('user_gamification_stats')
            .select()
            .eq('user_id', widget.userId)
            .maybeSingle(),
      ]);

      final hostedCount = results[0] as int;
      final joinedCount = results[1] as int;
      final followersCount = results[2] as int;
      final followingCount = results[3] as int;
      final hostedTables = results[4] as List<dynamic>;
      final joinedTables = results[5] as List<dynamic>;
      final photosResponse = results[6] as List<dynamic>;
      final tripResult = results[7] as Map<String, dynamic>?;
      final pastTripsResult = results[8] as List<dynamic>;
      final gamificationResult = results[9] as Map<String, dynamic>?;

      // PHASE 1 FIX: Combine hosted and joined tables for complete history
      final List<Map<String, dynamic>> allTables = [];

      // Add hosted tables
      for (var table in hostedTables) {
        allTables.add({
          ...table,
          'role': 'host',
          'sort_date': table['datetime'],
        });
      }

      // Add joined tables
      for (var participation in joinedTables) {
        if (participation['table'] != null) {
          allTables.add({
            ...participation['table'],
            'role': 'participant',
            'sort_date': participation['table']['datetime'],
          });
        }
      }

      // Sort combined list by date
      allTables.sort((a, b) {
        final aDate = DateTime.tryParse(a['sort_date'] ?? '') ?? DateTime(0);
        final bDate = DateTime.tryParse(b['sort_date'] ?? '') ?? DateTime(0);
        return bDate.compareTo(aDate);
      });

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
          _hostedTables = allTables.take(10).toList();
          _userPhotos = photos;
          _userTrip = tripResult;
          _pastTrips = List<Map<String, dynamic>>.from(pastTripsResult);
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
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Unblock User'),
          content: Text('Are you sure you want to unblock $displayName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Unblock',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
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
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Block User'),
          content: Text(
            'Block $displayName?\n\n'
            'They won\'t be able to see your profile, posts, or message you. '
            'You won\'t see their content either.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Block',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
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
                      const SizedBox(height: 16),
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

                    // Tags
                    if (_userData?['tags'] != null &&
                        (_userData!['tags'] as List).isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (_userData!['tags'] as List).map<Widget>((
                          tag,
                        ) {
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
                              tag.toString(),
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

                    // Photos Gallery
                    if (_userPhotos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'GALLERY',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 140,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _userPhotos.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
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
                                borderRadius: BorderRadius.circular(20),
                                child: Hero(
                                  tag: url,
                                  child: CachedNetworkImage(
                                    imageUrl: url,
                                    height: 140,
                                    width: 110,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.grey[800]
                                            : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),
            ),

            // 5. Organizer Section (if applicable)
            if (_organizerProfile != null)
              SliverToBoxAdapter(
                child: _OrganizerSection(
                  profile: _organizerProfile!,
                  isDark: isDark,
                ).animate().fadeIn(duration: 600.ms, delay: 700.ms),
              ),

            // 6. Trip Card (if user has an active/upcoming trip)
            if (_userTrip != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _TripCard(trip: _userTrip!, isDark: isDark),
                ).animate().fadeIn(duration: 500.ms, delay: 600.ms),
              ),

            // 6b. Past Trips
            if (_pastTrips.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.grey,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'TRIPS MADE',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_pastTrips.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._pastTrips.map(
                        (trip) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _PastTripCard(trip: trip, isDark: isDark),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 650.ms),
              ),

            // 7. Adventure Log (History)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildSectionHeader(context, 'ADVENTURE LOG'),
                  const SizedBox(height: 16),
                  if (_hostedTables.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(
                            Icons.explore_outlined,
                            size: 40,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No adventures yet',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._hostedTables.asMap().entries.map((entry) {
                      final i = entry.key;
                      final table = entry.value;
                      final isHost = table['role'] == 'host';
                      final isLast = i == _hostedTables.length - 1;
                      DateTime? dt;
                      try {
                        if (table['datetime'] != null)
                          dt = DateTime.parse(table['datetime']);
                      } catch (_) {}

                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Timeline spine
                            SizedBox(
                              width: 40,
                              child: Column(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isHost
                                          ? AppTheme.accentColor.withOpacity(
                                              0.15,
                                            )
                                          : Colors.blue.withOpacity(0.12),
                                      border: Border.all(
                                        color: isHost
                                            ? AppTheme.accentColor
                                            : Colors.blue,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      isHost
                                          ? Icons.star_rounded
                                          : Icons.people_rounded,
                                      size: 14,
                                      color: isHost
                                          ? AppTheme.accentColor
                                          : Colors.blue,
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 1.5,
                                        color: isDark
                                            ? Colors.white.withOpacity(0.08)
                                            : Colors.grey.shade200,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Card
                            Expanded(
                              child: Container(
                                margin: EdgeInsets.only(
                                  bottom: isLast ? 0 : 12,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.04)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.06)
                                        : Colors.grey.shade100,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            table['title'] ?? 'Unknown Event',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isHost
                                                ? AppTheme.accentColor
                                                      .withOpacity(0.12)
                                                : Colors.blue.withOpacity(0.10),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            isHost ? 'HOST' : 'JOINED',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.6,
                                              color: isHost
                                                  ? AppTheme.accentColor
                                                  : Colors.blue,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today_outlined,
                                          size: 11,
                                          color: Colors.grey[500],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          dt != null
                                              ? DateFormat(
                                                  'MMM d, y',
                                                ).format(dt)
                                              : 'Date unknown',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          isHost ? '+100 XP' : '+50 XP',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
                ]),
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

    final barColor = level >= 8
        ? const Color(0xFFFFD700) // gold for high levels
        : level >= 5
        ? const Color(0xFF8B5CF6) // purple mid
        : const Color(0xFF6366F1); // indigo low

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [barColor, barColor.withOpacity(0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Level $level${isMaxLevel ? ' · MAX' : ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
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
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: isMaxLevel ? 1.0 : progress,
                        minHeight: 6,
                        backgroundColor: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Trip Card ────────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final bool isDark;

  const _TripCard({required this.trip, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final city = trip['destination_city'] as String? ?? '';
    final country = trip['destination_country'] as String? ?? '';
    final startDate = trip['start_date'] != null
        ? DateFormat('MMM d').format(DateTime.parse(trip['start_date']))
        : null;
    final endDate = trip['end_date'] != null
        ? DateFormat('MMM d, y').format(DateTime.parse(trip['end_date']))
        : null;
    final status = trip['status'] as String? ?? 'upcoming';
    final style = trip['travel_style'] as String?;
    final description = trip['description'] as String?;
    final interests = (trip['interests'] as List?)?.cast<String>() ?? [];

    final isActive = status == 'active';
    final accentColor = isActive ? Colors.green : AppTheme.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isActive ? 'CURRENT TRIP' : 'UPCOMING TRIP',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isActive ? 'NOW' : 'SOON',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      accentColor.withOpacity(0.15),
                      accentColor.withOpacity(0.05),
                    ]
                  : [
                      accentColor.withOpacity(0.08),
                      accentColor.withOpacity(0.02),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withOpacity(isDark ? 0.25 : 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text('✈️', style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$city, $country',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        if (startDate != null && endDate != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 11,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$startDate – $endDate',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (style != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        style[0].toUpperCase() + style.substring(1),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (interests.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: interests.take(5).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Past Trip Card ──────────────────────────────────────────────────────────

class _PastTripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final bool isDark;

  const _PastTripCard({required this.trip, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final city = trip['destination_city'] as String? ?? '';
    final country = trip['destination_country'] as String? ?? '';
    final startDate = trip['start_date'] != null
        ? DateFormat('MMM d').format(DateTime.parse(trip['start_date']))
        : null;
    final endDate = trip['end_date'] != null
        ? DateFormat('MMM d, y').format(DateTime.parse(trip['end_date']))
        : null;
    final style = trip['travel_style'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: const Text('✈️', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$city, $country',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (startDate != null && endDate != null)
                  Text(
                    '$startDate – $endDate',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
          if (style != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                style[0].toUpperCase() + style.substring(1),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
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
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => EventDetailModal(event: eventObj),
          );
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: isApproved
              ? const LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFF8B5CF6)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isPending ? Colors.orange[50] : null,
          border: Border.all(
            color: isApproved
                ? Colors.transparent
                : isPending
                ? Colors.orange
                : AppTheme.primaryColor,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              isApproved
                  ? Icons.storefront_rounded
                  : isPending
                  ? Icons.hourglass_top_rounded
                  : Icons.add_business_outlined,
              color: isApproved
                  ? Colors.white
                  : isPending
                  ? Colors.orange[700]
                  : AppTheme.primaryColor,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isApproved
                        ? 'Switch to Host Mode'
                        : isPending
                        ? 'Application Under Review'
                        : 'Become a Host',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isApproved
                          ? Colors.white
                          : isPending
                          ? Colors.orange[800]
                          : AppTheme.primaryColor,
                    ),
                  ),
                  Text(
                    isApproved
                        ? 'Manage experiences & earnings'
                        : isPending
                        ? 'We\'ll notify you when approved'
                        : 'Create & sell your experiences',
                    style: TextStyle(
                      fontSize: 12,
                      color: isApproved
                          ? Colors.white70
                          : isPending
                          ? Colors.orange[600]
                          : AppTheme.primaryColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: isApproved ? Colors.white70 : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}
