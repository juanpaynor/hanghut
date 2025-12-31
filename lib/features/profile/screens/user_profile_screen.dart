import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/core/services/gamification_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/profile/screens/edit_profile_screen.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/core/services/stream_service.dart';

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

      if (mounted) {
        setState(() {
          _userData = userResponse;
          _userPhotos = List<Map<String, dynamic>>.from(photosResponse);
          _stats = {
            'hosted': tablesHosted,
            'joined': tablesJoined,
            'friends': 0, // Mock for now
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
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (widget.isOwnProfile) {
                  // If on own profile tab, go to Map Screen
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
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppTheme.primaryColor,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Carousel or Placeholder
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

                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),

                  // Indicator Dots
                  if (showCarousel && _userPhotos.length > 1)
                    Positioned(
                      top: 100,
                      right: 20,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentCarouselIndex + 1}/${_userPhotos.length}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // User Info Layer
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name & Verified
                        Row(
                          children: [
                            Text(
                              _userData!['display_name'] ?? 'Unknown',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                              ),
                            ),
                            SizedBox(width: 8),
                            if ((_userData!['trust_score'] ?? 0) > 80)
                              Icon(
                                Icons.verified,
                                color: AppTheme.accentColor,
                                size: 28,
                              ),
                          ],
                        ),
                        /* Trust Score Removed
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.star,
                              color: AppTheme.accentColor,
                              size: 18,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Trust Score: ${_userData!['trust_score'] ?? 0}',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        */
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (widget.isOwnProfile)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Colors.white),
                  ),
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
                ),
              if (!widget.isOwnProfile)
                IconButton(
                  icon: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.more_vert, color: Colors.white),
                  ),
                  onPressed: () {
                    // Show options menu (report, block, etc)
                  },
                ),
            ],
          ),

          // Stats Row
          SliverToBoxAdapter(
            child: Container(
              margin: EdgeInsets.all(20),
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Hosted',
                    '${_stats!['hosted']}',
                    Icons.restaurant,
                  ),
                  _buildStatItem(
                    'Joined',
                    '${_stats!['joined']}',
                    Icons.people,
                  ),
                  _buildStatItem(
                    'Friends',
                    '${_stats!['friends']}',
                    Icons.favorite,
                  ),
                  _buildStatItem('Rating', '${_stats!['rating']}', Icons.star),
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
                          final streamService = StreamService();
                          // For now, always follow (since isFollowing returns false)
                          // In the future, this will toggle based on follow status
                          await streamService.followUser(widget.userId);
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

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.accentColor, size: 24),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
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
