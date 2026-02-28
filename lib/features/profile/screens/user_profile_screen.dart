import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'package:bitemates/features/profile/widgets/quest_card.dart';
import 'package:bitemates/features/profile/screens/connected_users_screen.dart';
import 'package:bitemates/core/services/direct_chat_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/features/profile/screens/edit_profile_screen.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/features/host/screens/host_apply_screen.dart';
import 'package:bitemates/features/host/screens/host_pending_screen.dart';
import 'package:bitemates/features/host/screens/host_dashboard_screen.dart';

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
              characterClass: charClass,
              isOwnProfile: widget.isOwnProfile,
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
                offset: const Offset(0, 0), // Removed overlap effect
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

            // 3. Action Buttons & Bio
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                      vertical: 16, // Taller buttons
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
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
                                      vertical: 16, // Taller buttons
                                    ),
                                    side: const BorderSide(
                                      color: AppTheme.primaryColor,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.chat_bubble_outline,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Message',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
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
                    if (widget.isOwnProfile) ...[
                      _HostModeButton(),
                      const SizedBox(height: 16),
                    ],

                    // Bio
                    if (_userData?['bio'] != null) ...[
                      Text(
                        _userData!['bio'],
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                      ).animate().fadeIn(duration: 600.ms, delay: 500.ms),
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
                    style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
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
