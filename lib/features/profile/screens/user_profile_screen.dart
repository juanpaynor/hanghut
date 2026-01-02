import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/core/services/gamification_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/profile/screens/edit_profile_screen.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/core/services/social_service.dart';
import 'package:bitemates/features/profile/screens/user_list_screen.dart';

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

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PageController _carouselController = PageController(); // Restored
  int _currentCarouselIndex = 0; // Restored

  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _userPhotos = [];
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _upcomingTables = [];
  List<Map<String, dynamic>> _pastTables = [];
  List<Map<String, dynamic>> _hostedTables = [];
  List<Map<String, dynamic>> _badges = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _carouselController.dispose(); // Restored
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);

    try {
      final supabase = SupabaseConfig.client;

      // 1. Fetch User Data (Basic info)
      final userResponse = await supabase
          .from('users')
          .select(
            'id, display_name, bio, avatar_url, trust_score, occupation, social_instagram, tags',
          )
          .eq('id', widget.userId)
          .single();

      // 2. Fetch User Photos (Gallery) - Sorted by sort_order
      final photosResponse = await supabase
          .from('user_photos')
          .select()
          .eq('user_id', widget.userId)
          .order('sort_order', ascending: true);

      // 3. Fetch User Stats (Hosted, Joined) - Simplified/Mocked for now or aggregate
      // Ideally this would be a specialized query or edge function
      final tablesHosted = await supabase
          .from('tables')
          .count(CountOption.exact)
          .eq('host_id', widget.userId);

      final tablesJoined = await supabase
          .from('table_participants')
          .count(CountOption.exact)
          .eq('user_id', widget.userId);

      // 4. Fetch Actual Tables

      // Hosted Tables
      final hostedTablesData = await supabase
          .from('tables')
          .select('*, participants:table_participants(count)')
          .eq('host_id', widget.userId)
          .order('datetime', ascending: false);

      // Joined Tables (Upcoming & Past)
      final joinedTablesData = await supabase
          .from('table_participants')
          .select('tables(*)')
          .eq('user_id', widget.userId);

      // Process Joined Tables
      final List<Map<String, dynamic>> upcoming = [];
      final List<Map<String, dynamic>> past = [];

      for (var entry in joinedTablesData) {
        final table = entry['tables'];
        if (table != null) {
          final dt = DateTime.parse(table['datetime']);
          if (dt.isAfter(DateTime.now())) {
            upcoming.add(entry);
          } else {
            past.add(entry);
          }
        }
      }

      // 5. Get Badges (Gamification)
      final badges = await GamificationService().getUserBadges(widget.userId);

      // 6. Get Connections (Following/Followers)
      final socialService = SocialService();
      // Fetch concurrently for speed
      final results = await Future.wait([
        socialService.getFollowing(widget.userId),
        socialService.getFollowers(widget.userId),
      ]);
      final followingCount = results[0].length;
      final followersCount = results[1].length;

      if (mounted) {
        setState(() {
          _userData = userResponse;
          _userPhotos = List<Map<String, dynamic>>.from(photosResponse);
          _stats = {
            'hosted': tablesHosted,
            'joined': tablesJoined,
            'following': followingCount,
            'followers': followersCount,
            'rating': 5.0, // Mock for now
          };
          _hostedTables = List<Map<String, dynamic>>.from(hostedTablesData);
          _upcomingTables = upcoming;
          _pastTables = past;
          _badges = badges;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load profile. Please try again.';
        });
      }
    }
  }

  void _openUserList(String title, Future<List<dynamic>> Function() fetchFunc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserListScreen(
          title: title,
          currentUserId: widget.userId,
          fetchFunction: fetchFunc,
        ),
      ),
    );
  }

  Future<void> _launchInstagram() async {
    final handle = _userData?['social_instagram'];
    if (handle != null && handle.isNotEmpty) {
      final uri = Uri.parse('https://instagram.com/$handle');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accentColor),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red),
              SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.black54, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadUserProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.black,
                ),
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_userData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('User not found')),
      );
    }

    final showCarousel = _userPhotos.isNotEmpty;
    final primaryPhoto = showCarousel
        ? _userPhotos.first
        : {'photo_url': _userData?['avatar_url']};

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Header / App Bar
          SliverAppBar(
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () {
                if (widget.isOwnProfile) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) =>
                          const MainNavigationScreen(initialIndex: 1),
                    ),
                    (route) => false,
                  );
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
            actions: [
              // Options menu for both own and other profiles?
              // For now, keep it simple. If own profile, maybe settings icon?
              // User asked for "Edit Profile" as a button, not icon.
              if (!widget.isOwnProfile)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  onPressed: () {},
                ),
            ],
            expandedHeight: 380, // Taller header
            pinned: true,
            backgroundColor: AppTheme.primaryColor,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Image Layer
                  if (showCarousel)
                    PageView.builder(
                      controller: _carouselController,
                      itemCount: _userPhotos.length,
                      onPageChanged: (index) =>
                          setState(() => _currentCarouselIndex = index),
                      itemBuilder: (context, index) {
                        return Image.network(
                          _userPhotos[index]['photo_url'],
                          fit: BoxFit.cover,
                        );
                      },
                    )
                  else if (primaryPhoto['photo_url'] != null)
                    Image.network(primaryPhoto['photo_url'], fit: BoxFit.cover)
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.accentColor, Colors.white],
                        ),
                      ),
                    ),

                  // 2. Gradient Overlay (Top) - For status bar visibility
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 100,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black54, Colors.transparent],
                        ),
                      ),
                    ),
                  ),

                  // 3. Gradient Overlay (Bottom) - For text readability
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 200,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.9),
                            Colors.black.withOpacity(0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 4. Indicator Dots
                  if (showCarousel && _userPhotos.length > 1)
                    Positioned(
                      top: 110,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          '${_currentCarouselIndex + 1}/${_userPhotos.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  // 5. User Info (Name & Verified)
                  Positioned(
                    bottom: 24,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              // Allow text to wrap if name is long
                              child: Text(
                                _userData!['display_name'] ?? 'Unknown',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32, // Slightly smaller but cleaner
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if ((_userData!['trust_score'] ?? 0) > 80) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.verified,
                                color: AppTheme.accentColor, // Gold/Yellow
                                size: 28,
                              ),
                            ],
                          ],
                        ),
                        // Optional: Add occupation line here if user has one
                        if (_userData!['occupation'] != null &&
                            _userData!['occupation'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              _userData!['occupation'],
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Stats Row (Clean, Passport Style)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPassportStat('Hosted', '${_stats!['hosted'] ?? 0}'),
                      _buildVerticalDivider(),
                      _buildPassportStat('Joined', '${_stats!['joined'] ?? 0}'),
                      _buildVerticalDivider(),
                      _buildPassportStat(
                        'Following',
                        '${_stats!['following'] ?? 0}',
                        onTap: () => _openUserList(
                          'Following',
                          () => SocialService().getFollowing(widget.userId),
                        ),
                      ),
                      _buildVerticalDivider(),
                      _buildPassportStat(
                        'Followers',
                        '${_stats!['followers'] ?? 0}',
                        onTap: () => _openUserList(
                          'Followers',
                          () => SocialService().getFollowers(widget.userId),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Main Action Button (Edit or Follow)
                  _buildMainActionButton(context),
                ],
              ),
            ),
          ),

          // Bio Section
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'About',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Instagram Button (Restored)
                      if (_userData!['social_instagram'] != null &&
                          _userData!['social_instagram'].toString().isNotEmpty)
                        GestureDetector(
                          onTap: _launchInstagram,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  size: 16,
                                  color: AppTheme.textPrimary,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '@${_userData!['social_instagram']}',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    _userData!['bio'] ?? 'No bio yet',
                    style: TextStyle(
                      color: _userData!['bio'] != null
                          ? AppTheme.textSecondary
                          : Colors.grey,
                      fontSize: 16,
                      height: 1.5,
                      fontStyle: _userData!['bio'] != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),

                  // Tags Display
                  if (_userData!['tags'] != null &&
                      (_userData!['tags'] as List).isNotEmpty) ...[
                    SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (_userData!['tags'] as List).map<Widget>((tag) {
                        return Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            tag.toString(),
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Photos Gallery
          if (_userPhotos.length > 1)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Photos',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _userPhotos.length,
                      itemBuilder: (context, index) {
                        final photo = _userPhotos[index];
                        return Container(
                          width: 120,
                          margin: EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            image: DecorationImage(
                              image: NetworkImage(photo['photo_url']),
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),

          // Badges Section
          if (_badges.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Passport',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _badges.length,
                      itemBuilder: (context, index) {
                        final badge = _badges[index];
                        return Container(
                          width: 80,
                          margin: EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: badge['color'].withOpacity(0.3),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                badge['icon'],
                                color: badge['color'],
                                size: 32,
                              ),
                              SizedBox(height: 8),
                              Text(
                                badge['name'],
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),

          // Action Buttons
          if (!widget.isOwnProfile)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // TODO: Send message
                        },
                        icon: Icon(Icons.message),
                        label: Text('Message'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          final socialService = SocialService();
                          // For now, always follow (since isFollowing logic needs update)
                          // In the future, this will toggle based on follow status
                          await socialService.followUser(widget.userId);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Following ${_userData!['display_name']}',
                                ),
                                backgroundColor: AppTheme.accentColor,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          print('Error following user: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to follow user'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      child: Icon(Icons.person_add),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          SliverToBoxAdapter(child: SizedBox(height: 20)),

          // Tables Tabs
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppTheme.accentColor,
                indicatorWeight: 3,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                tabs: [
                  Tab(text: 'Upcoming'),
                  Tab(text: 'Past'),
                  Tab(text: 'Hosted'),
                ],
              ),
            ),
          ),

          // Tables Content
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTablesList(_upcomingTables, false),
                _buildTablesList(_pastTables, false),
                _buildTablesList(_hostedTables, true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getDisplayLocation(String fullLocation) {
    // If viewing own profile or is friend, show full location
    if (widget.isOwnProfile) {
      return fullLocation;
    }

    // For non-friends, show only general area (city/neighborhood)
    // Example: "Starbucks, Makati, Metro Manila" -> "Makati, Metro Manila"
    final parts = fullLocation.split(',');
    if (parts.length >= 2) {
      return parts.sublist(1).join(',').trim();
    }
    return fullLocation;
  }

  Widget _buildPassportStat(String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(height: 24, width: 1, color: Colors.grey[300]);
  }

  Widget _buildMainActionButton(BuildContext context) {
    if (widget.isOwnProfile) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () async {
            // Navigate to Edit Profile
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EditProfileScreen(
                  userProfile: _userData!,
                  userPhotos: _userPhotos,
                ),
              ),
            );

            // Refresh if saved
            if (result == true) {
              _loadUserProfile();
            }
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey[300]!),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(vertical: 16),
            foregroundColor: AppTheme.primaryColor,
          ),
          child: const Text(
            'Edit Profile',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    // For other users: Message & Follow Buttons
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              // Placeholder for Follow action
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Follow feature coming soon!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 0,
            ),
            child: const Text(
              'Follow',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              // Placeholder for Message action
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Messaging coming soon!')),
              );
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey[300]!),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: AppTheme.primaryColor,
            ),
            child: const Text(
              'Message',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTablesList(List<Map<String, dynamic>> tables, bool isHosted) {
    if (tables.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 40),
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.restaurant_menu,
                  size: 64,
                  color: Colors.grey.withOpacity(0.3),
                ),
                SizedBox(height: 16),
                Text(
                  'No tables yet',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(20),
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final item = tables[index];
        final table = isHosted ? item : item['tables'];
        final datetime = DateTime.parse(table['datetime']);

        return Container(
          margin: EdgeInsets.only(bottom: 16),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                table['title'],
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: AppTheme.accentColor,
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _getDisplayLocation(table['location_name']),
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    color: AppTheme.accentColor,
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    DateFormat('MMM d, yyyy · h:mm a').format(datetime),
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
