import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/services/gamification_service.dart';
import 'package:intl/intl.dart';

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
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _userPhotos = [];
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _upcomingTables = [];
  List<Map<String, dynamic>> _pastTables = [];
  List<Map<String, dynamic>> _hostedTables = [];
  List<Map<String, dynamic>> _badges = [];
  final _gamificationService = GamificationService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);

    try {
      // Load user data
      final user = await SupabaseConfig.client
          .from('users')
          .select('*')
          .eq('id', widget.userId)
          .single();

      // Load user photos
      final photos = await SupabaseConfig.client
          .from('user_photos')
          .select('*')
          .eq('user_id', widget.userId)
          .order('is_primary', ascending: false);

      // Load stats
      final hostedCount = await SupabaseConfig.client
          .from('tables')
          .select('id')
          .eq('host_id', widget.userId);

      final joinedCount = await SupabaseConfig.client
          .from('table_participants')
          .select('id')
          .eq('user_id', widget.userId)
          .eq('status', 'confirmed');

      // Load upcoming tables
      final upcoming = await SupabaseConfig.client
          .from('table_participants')
          .select('''
            status,
            joined_at,
            tables!inner(
              id,
              title,
              location_name,
              datetime,
              max_guests
            )
          ''')
          .eq('user_id', widget.userId)
          .gte('tables.datetime', DateTime.now().toIso8601String())
          .limit(5);

      // Load past tables
      final past = await SupabaseConfig.client
          .from('table_participants')
          .select('''
            status,
            joined_at,
            tables!inner(
              id,
              title,
              location_name,
              datetime,
              max_guests
            )
          ''')
          .eq('user_id', widget.userId)
          .lt('tables.datetime', DateTime.now().toIso8601String())
          .limit(5);

      // Load hosted tables
      final hosted = await SupabaseConfig.client
          .from('tables')
          .select('*')
          .eq('host_id', widget.userId)
          .eq('host_id', widget.userId)
          .limit(5);

      // Load Badges
      final badges = await _gamificationService.getUserBadges(widget.userId);

      if (mounted) {
        setState(() {
          _userData = user;
          _userPhotos = List<Map<String, dynamic>>.from(photos);
          _stats = {
            'hosted': (hostedCount as List).length,
            'joined': (joinedCount as List).length,
            'friends': 0, // TODO: Implement friends count
            'rating': user['trust_score'] ?? 0,
          };
          _upcomingTables = List<Map<String, dynamic>>.from(upcoming);
          _pastTables = List<Map<String, dynamic>>.from(past);
          _hostedTables = List<Map<String, dynamic>>.from(hosted);
          _badges = badges;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: const Color(0xFF00FFD1)),
        ),
      );
    }

    if (_userData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text('User not found', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final primaryPhoto = _userPhotos.firstWhere(
      (p) => p['is_primary'] == true,
      orElse: () => {},
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Hero Header with Profile Photo
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Background Image with Gradient
                  if (primaryPhoto['photo_url'] != null)
                    Image.network(primaryPhoto['photo_url'], fit: BoxFit.cover)
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF00FFD1), Colors.white],
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
                  // User Info
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _userData!['display_name'] ?? 'Unknown',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.verified,
                              color: Color(0xFF00FFD1),
                              size: 24,
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.star,
                              color: Color(0xFF00FFD1),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            leading: widget.isOwnProfile
                ? SizedBox(
                    width: 120,
                    child: Row(
                      children: [
                        IconButton(
                          icon: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.arrow_back, color: Colors.white),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        IconButton(
                          icon: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.edit, color: Colors.white),
                          ),
                          onPressed: () {
                            print('🔵 EDIT BUTTON PRESSED!');
                            // TODO: Navigate to edit profile screen
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: Color(0xFF2A2A3E),
                                title: Text(
                                  'Edit Profile',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: Text(
                                  'Profile editing feature coming soon!',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(
                                      'OK',
                                      style: TextStyle(
                                        color: Color(0xFF00FFD1),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : IconButton(
                    icon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
            leadingWidth: widget.isOwnProfile ? 120 : 56,
            actions: [
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
                color: Color(0xFF2A2A3E),
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
                  Text(
                    'About',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    _userData!['bio'] ?? 'No bio yet',
                    style: TextStyle(
                      color: _userData!['bio'] != null
                          ? Colors.white70
                          : Colors.white38,
                      fontSize: 16,
                      height: 1.5,
                      fontStyle: _userData!['bio'] != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
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
                        color: Colors.white,
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
                        color: Colors.white,
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
                            color: Color(0xFF2A2A3E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: badge['color'].withOpacity(0.3),
                            ),
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
                                  color: Colors.white,
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
                          backgroundColor: Color(0xFF00FFD1),
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
                      onPressed: () {
                        // TODO: Add friend
                      },
                      child: Icon(Icons.person_add),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2A2A3E),
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
                labelColor: Color(0xFF00FFD1),
                unselectedLabelColor: Colors.white54,
                indicatorColor: Color(0xFF00FFD1),
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
        Icon(icon, color: Color(0xFF00FFD1), size: 24),
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
        Text(label, style: TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildTablesList(List<Map<String, dynamic>> tables, bool isHosted) {
    if (tables.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'No tables yet',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
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
            color: Color(0xFF2A2A3E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                table['title'],
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on, color: Color(0xFF00FFD1), size: 16),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _getDisplayLocation(table['location_name']),
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    color: Color(0xFF00FFD1),
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    DateFormat('MMM d, yyyy · h:mm a').format(datetime),
                    style: TextStyle(color: Colors.white70, fontSize: 14),
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
