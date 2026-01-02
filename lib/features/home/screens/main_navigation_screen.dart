import 'package:flutter/material.dart';
import 'package:bitemates/features/home/screens/feed_screen.dart';
import 'package:bitemates/features/map/screens/map_screen.dart';
import 'package:bitemates/features/map/widgets/create_table_modal.dart';
import 'package:bitemates/features/tables/screens/my_tables_screen.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/auth/screens/login_screen.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  final GlobalKey<MapScreenState> _mapScreenKey = GlobalKey<MapScreenState>();

  List<Widget> get _screens {
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

    return [
      const FeedScreen(),
      MapScreen(key: _mapScreenKey),
      const MyTablesScreen(), // My Tables / Trips
      currentUserId != null
          ? UserProfileScreen(userId: currentUserId, isOwnProfile: true)
          : const Center(
              child: Text("Please log in to view profile"),
            ), // Profile
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showCreateTableModal() {
    // Get user's current location from map screen
    final position = _mapScreenKey.currentState?.getCurrentPosition();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateTableModal(
        currentLat: position?.latitude,
        currentLng: position?.longitude,
        onTableCreated: () {
          // Switch to map view and refresh
          setState(() {
            _selectedIndex = 1;
          });
          // Trigger map refresh if possible
          _mapScreenKey.currentState?.refreshTables();
        },
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.black),
              title: const Text(
                'Settings',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline, color: Colors.black),
              title: const Text(
                'Help & Support',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Help center coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.black),
              title: const Text('About', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('About page coming soon!')),
                );
              },
            ),
            const Divider(color: Colors.white24, height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Log Out', style: TextStyle(color: Colors.red)),
              onTap: () => _confirmLogout(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    Navigator.pop(context); // Close settings menu
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF000000),
        title: const Text('Log Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog

              try {
                // Sign out from Supabase
                await SupabaseConfig.client.auth.signOut();

                // Update auth provider state
                if (context.mounted) {
                  context.read<AuthProvider>().signOut();

                  // Navigate to login screen
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error logging out: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Allow body to extend behind navbar/fab
      body: Stack(
        children: [
          // Full screen content
          Positioned.fill(
            child: IndexedStack(index: _selectedIndex, children: _screens),
          ),

          // Floating menu button - top right (Settings)
          if (_selectedIndex != 3)
            Positioned(
              top: 60,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => _showSettingsMenu(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      child: const Icon(
                        Icons.menu,
                        color: Color(0xFF000000),
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Container(
        height: 64,
        width: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).primaryColor.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: 'main_fab', // Unique tag to prevent collisions
          onPressed: _showCreateTableModal,
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 0,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white, size: 32),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        height: 80, // Taller bar
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
            _buildNavItem(1, Icons.map_outlined, Icons.map, 'Map'),
            const SizedBox(width: 48), // Spacer for FAB
            _buildNavItem(
              2,
              Icons.flight_outlined,
              Icons.flight,
              'Trips',
            ), // Assuming index 2 is still Trips in _screens logic (which is NOT true anymore, see logic check)
            _buildNavItem(3, Icons.person_outline, Icons.person, 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData iconOutlined,
    IconData iconFilled,
    String label,
  ) {
    final isSelected = _selectedIndex == index;
    // Use primary color for selected item
    final activeColor = Theme.of(context).primaryColor;

    return InkWell(
      onTap: () => _onItemTapped(index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? iconFilled : iconOutlined,
              color: isSelected ? activeColor : Colors.grey[400],
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : Colors.grey[400],
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
