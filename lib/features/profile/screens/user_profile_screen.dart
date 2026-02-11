import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/settings/screens/settings_screen.dart';
import 'package:bitemates/features/map/screens/map_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';

import 'package:bitemates/features/profile/widgets/quest_card.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/features/profile/screens/edit_profile_screen.dart';
import 'package:bitemates/core/widgets/full_screen_image_viewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/features/shared/widgets/report_modal.dart';
import 'package:bitemates/core/widgets/skeleton_loader.dart';
// PHASE 2: New imports

import 'package:bitemates/features/ticketing/screens/organizer_dashboard_screen.dart';
import 'package:bitemates/features/profile/widgets/profile_completeness_indicator.dart';
import 'package:bitemates/features/profile/screens/connected_users_screen.dart';
import 'package:bitemates/core/services/direct_chat_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';

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
  List<dynamic> _badges = [];
  List<dynamic> _hostedTables = [];
  List<Map<String, dynamic>> _userPhotos = [];
  String? _errorMessage;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    if (!widget.isOwnProfile) {
      _checkFollowStatus();
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
        // Joined tables count
        supabase
            .from('table_participants')
            .count()
            .eq('user_id', widget.userId),
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
        // PHASE 1 NEW: Joined tables history
        supabase
            .from('table_participants')
            .select('joined_at, table:tables!table_id(*)')
            .eq('user_id', widget.userId)
            .order('joined_at', ascending: false)
            .limit(5),
        // Photos
        supabase.from('user_photos').select().eq('user_id', widget.userId),
      ]);

      final hostedCount = results[0] as int;
      final joinedCount = results[1] as int;
      final followersCount = results[2] as int;
      final followingCount = results[3] as int;
      final hostedTables = results[4] as List<dynamic>;
      final joinedTables = results[5] as List<dynamic>;
      final photosResponse = results[6] as List<dynamic>;

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

      // Mock badges (will be replaced with real system later)
      final List<dynamic> badges = [
        {'name': 'Early Bird', 'icon': Icons.wb_sunny, 'color': Colors.orange},
        {
          'name': 'Night Owl',
          'icon': Icons.nights_stay,
          'color': Colors.purple,
        },
        {'name': 'Sushi Lover', 'icon': Icons.rice_bowl, 'color': Colors.red},
      ];

      if (mounted) {
        setState(() {
          _userData = {...userResponse, 'avatar_url': avatarUrl};
          _stats = {
            'hosted': hostedCount,
            'joined': joinedCount,
            'followers': followersCount, // PHASE 1 FIX: Real count
            'following': followingCount, // PHASE 1 FIX: Real count
          };
          _badges = badges;
          _hostedTables = allTables
              .take(10)
              .toList(); // PHASE 1: Show top 10 combined
          _userPhotos = photos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  void _openDirectMessage() async {
    try {
      final chatId = await DirectChatService().startConversation(widget.userId);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              tableId: chatId,
              tableTitle: _userData?['display_name'] ?? 'Direct Message',
              channelId: 'direct_$chatId',
              chatType: 'dm',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening chat: ${e.toString()}')),
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

  Future<void> _launchInstagram(String username) async {
    final cleanUsername = username.replaceAll('@', '').trim();
    if (cleanUsername.isEmpty) return;

    final appUrl = Uri.parse('instagram://user?username=$cleanUsername');
    final webUrl = Uri.parse('https://www.instagram.com/$cleanUsername/');

    try {
      if (await canLaunchUrl(appUrl)) {
        await launchUrl(appUrl);
      } else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching Instagram: $e');
    }
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
  int _calculateLevel() {
    int totalXP = _calculateTotalXP();
    // Each level requires 100 XP more than the previous
    // Level 1: 0-100 XP, Level 2: 100-300 XP, Level 3: 300-600 XP, etc.
    int level = 1;
    int xpNeeded = 0;
    while (totalXP >= xpNeeded) {
      xpNeeded += (level * 100);
      if (totalXP >= xpNeeded) level++;
    }
    return level;
  }

  int _calculateTotalXP() {
    int hosted = _stats?['hosted'] ?? 0;
    int joined = _stats?['joined'] ?? 0;
    return (hosted * 100) + (joined * 50);
  }

  Map<String, int> _getXPProgress() {
    int level = _calculateLevel();
    int totalXP = _calculateTotalXP();

    // Calculate XP for current level
    int xpForCurrentLevel = 0;
    for (int i = 1; i < level; i++) {
      xpForCurrentLevel += (i * 100);
    }

    int currentLevelXP = totalXP - xpForCurrentLevel;
    int xpNeededForNextLevel = level * 100;

    return {
      'current': currentLevelXP,
      'needed': xpNeededForNextLevel,
      'total': totalXP,
    };
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
    final level = _calculateLevel();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadUserProfile,
        color: AppTheme.accentColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. RPG Header (SliverAppBar)
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              leading: widget.isOwnProfile
                  ? null
                  : IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
              actions: [
                if (widget.isOwnProfile) ...[
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: () async {
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
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.isOwnProfile)
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: () => _showSettingsMenu(context),
                  )
                else
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'report') {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => ReportModal(
                            entityType: 'user',
                            entityId: widget.userId,
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Report User',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.more_vert,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDark
                          ? [
                              Colors.purple.shade900,
                              Theme.of(context).scaffoldBackgroundColor,
                            ]
                          : [
                              Colors.blue.shade100,
                              Theme.of(context).scaffoldBackgroundColor,
                            ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 100, 20, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar & Level
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.accentColor,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentColor.withOpacity(
                                      0.5,
                                    ),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 40,
                                backgroundImage: NetworkImage(
                                  _userData?['avatar_url'] ?? '',
                                ),
                                backgroundColor: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.accentColor.withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                'LVL $level',
                                style: const TextStyle(
                                  color: AppTheme.accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 24),
                        // Name & Class
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 10),
                              Text(
                                _userData?['display_name'] ?? 'Unknown',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                              ),
                              Text(
                                charClass.toUpperCase(),
                                style: const TextStyle(
                                  color: AppTheme.accentColor,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if (_userData?['occupation'] != null &&
                                  _userData!['occupation']
                                      .toString()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _userData!['occupation'],
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[700],
                                      ),
                                ),
                              ],
                              if (_userData?['social_instagram'] != null &&
                                  _userData!['social_instagram']
                                      .toString()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _launchInstagram(
                                    _userData!['social_instagram'],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.camera_alt_outlined,
                                        size: 14,
                                        color: AppTheme.accentColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '@${_userData!['social_instagram'].toString().replaceAll('@', '')}',
                                        style: const TextStyle(
                                          color: AppTheme.accentColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              // XP Bar - PHASE 1 FIX: Real XP Data
                              Builder(
                                builder: (context) {
                                  final xpData = _getXPProgress();
                                  final progress =
                                      xpData['current']! / xpData['needed']!;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: isDark
                                              ? Colors.black26
                                              : Colors.white54,
                                          valueColor:
                                              const AlwaysStoppedAnimation(
                                                AppTheme.accentColor,
                                              ),
                                          minHeight: 8,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${xpData['current']} / ${xpData['needed']} XP to next level',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Stats Matrix (REMOVED per request)
            // _buildStatsMatrix(rpgStats),

            // 2. Action Buttons & Bio
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Action Buttons
                    // Stats Row
                    _buildStatsRow(context),
                    const SizedBox(height: 20),

                    // Action Buttons (Only for others)
                    if (!widget.isOwnProfile) ...[
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
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: _isFollowing
                                      ? BorderSide(
                                          color: Theme.of(context).dividerColor,
                                        )
                                      : BorderSide.none,
                                ),
                              ),
                              icon: Icon(
                                _isFollowing ? Icons.check : Icons.person_add,
                                size: 20,
                              ),
                              label: Text(
                                _isFollowing ? 'Following' : 'Follow',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
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
                                  vertical: 12,
                                ),
                                side: const BorderSide(
                                  color: AppTheme.primaryColor,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 20,
                              ),
                              label: const Text(
                                'Message',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Bio
                    if (_userData?['bio'] != null) ...[
                      Text(
                        _userData!['bio'],
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Interests / Tags
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
                              horizontal: 10,
                              vertical: 4,
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
                      ),
                      const SizedBox(height: 24),
                    ],

                    // PHASE 2: Profile Completeness Indicator (only for own profile)
                    if (widget.isOwnProfile) ...[
                      ProfileCompletenessIndicator(
                        userData: _userData ?? {},
                        photos: _userPhotos,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Photos Gallery
                    if (_userPhotos.isNotEmpty) ...[
                      Text(
                        'GALLERY',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 100, // Horizontal strip
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _userPhotos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                                borderRadius: BorderRadius.circular(12),
                                child: Hero(
                                  tag: url,
                                  child: CachedNetworkImage(
                                    imageUrl: url,
                                    height: 100,
                                    width: 100,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[200]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 3. Quests
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildSectionHeader(context, 'ACTIVE QUESTS'),
                  const SizedBox(height: 12),
                  const QuestCard(
                    title: 'Weekend Warrior',
                    description: 'Join a table this weekend',
                    progress: 0.3,
                    reward: '+100 XP',
                    type: 'Weekly',
                  ),
                  if ((_stats?['hosted'] ?? 0) > 0)
                    const QuestCard(
                      title: 'First Host',
                      description: 'Host your first table',
                      progress: 1.0,
                      reward: 'UNLOCKED',
                      isCompleted: true,
                      type: 'Lifetime',
                    )
                  else
                    const QuestCard(
                      title: 'First Host',
                      description: 'Host your first table',
                      progress: 0.0,
                      reward: 'Badge + 500 XP',
                      type: 'Lifetime',
                    ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),

            // 4. Badges (formerly Loot Bag)
            if (_badges.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildSectionHeader(context, 'BADGES'),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: _badges.length,
                        itemBuilder: (context, index) {
                          final badge = _badges[index];
                          return Tooltip(
                            message: badge['name'],
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[900] : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: (badge['color'] as Color).withOpacity(
                                    0.5,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (badge['color'] as Color)
                                        .withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    badge['icon'],
                                    color: badge['color'],
                                    size: 28,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    badge['name'],
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: badge['color'],
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

            // 5. Adventure Log (History)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildSectionHeader(context, 'ADVENTURE LOG'),
                  const SizedBox(height: 12),
                  if (_hostedTables.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(
                        child: Text(
                          'No adventures yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ..._hostedTables.map((table) {
                    final isHost = table['role'] == 'host';
                    return Card(
                      elevation: 0,
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.shade50,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isHost ? AppTheme.accentColor : Colors.blue)
                                .withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isHost ? Icons.star : Icons.people,
                            color: isHost ? AppTheme.accentColor : Colors.blue,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                table['title'] ?? 'Unknown Quest',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // PHASE 2: Role badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (isHost
                                            ? AppTheme.accentColor
                                            : Colors.blue)
                                        .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isHost ? 'HOST' : 'JOINED',
                                style: TextStyle(
                                  color: isHost
                                      ? AppTheme.accentColor
                                      : Colors.blue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          table['datetime'] != null
                              ? DateFormat(
                                  'MMM d, y',
                                ).format(DateTime.parse(table['datetime']))
                              : 'Unknown Date',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isHost ? '+100 XP' : '+50 XP',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 40),
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

  Widget _buildStatsRow(BuildContext context) {
    if (_stats == null) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem('Hosted', _stats!['hosted'] ?? 0),
        _buildStatItem('Joined', _stats!['joined'] ?? 0),
        _buildStatItem(
          'Followers',
          _stats!['followers'] ?? 0,
          onTap: () {
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
        ),
        _buildStatItem(
          'Following',
          _stats!['following'] ?? 0,
          onTap: () {
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
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, int count, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            count.toString(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }
}
