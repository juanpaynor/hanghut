import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bitemates/features/home/screens/feed_screen.dart';
import 'package:bitemates/features/map/screens/map_screen.dart';
import 'package:bitemates/features/map/widgets/create_table_modal.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/activity/screens/activity_screen.dart';
import 'package:bitemates/features/chat/widgets/draggable_chat_bubble.dart';
import 'package:bitemates/features/activity/widgets/active_chats_list.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/location/logic/geofence_engine.dart';
import 'package:bitemates/features/location/widgets/geofence_modal.dart';
import 'package:bitemates/core/services/account_status_service.dart';
import 'package:bitemates/features/auth/screens/account_suspended_screen.dart';
import 'package:bitemates/core/services/push_notification_service.dart';
import 'package:bitemates/core/services/admin_popup_service.dart';
import 'package:bitemates/features/shared/widgets/admin_popup_modal.dart';
import 'package:bitemates/core/services/analytics_service.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;
  final String? initialTableId; // Add this

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.initialTableId,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  late int _selectedIndex;

  final GlobalKey<MapScreenState> _mapScreenKey = GlobalKey<MapScreenState>();
  StreamSubscription<Map<String, dynamic>>? _geofenceSubscription;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _setupGeofenceListener();
    WidgetsBinding.instance.addObserver(this);

    // Handle Deep Link for Table
    if (widget.initialTableId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapScreenKey.currentState?.showTableDetails(widget.initialTableId!);
      });
    }

    // Check for Admin Popups on Startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAdminPopups();
    });
  }

  Future<void> _checkAdminPopups() async {
    final activePopup = await AdminPopupService().checkAndGetActivePopup();
    if (activePopup != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // Force them to interact with the modal
        builder: (context) => AdminPopupModal(
          popupData: activePopup,
          onDismissed: () {
            AdminPopupService().markPopupAsSeen(activePopup['id']);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _geofenceSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime? _lastStatusCheck;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Skip status check entirely during payment flow — main thread is under
      // heavy load from Mapbox re-render + FCM background isolate
      if (PushNotificationService.suppressNotifications) return;

      // Debounce: skip if checked within last 30 seconds
      final now = DateTime.now();
      if (_lastStatusCheck != null &&
          now.difference(_lastStatusCheck!).inSeconds < 30) {
        return;
      }
      _lastStatusCheck = now;

      // Delay to let Mapbox and other services stabilize on resume
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _checkAccountStatus();
      });
    }
  }

  Future<void> _checkAccountStatus() async {
    final statusData = await AccountStatusService.checkStatus();
    final status = statusData['status'] ?? 'active';

    if (status == 'suspended' || status == 'banned' || status == 'deleted') {
      if (mounted) {
        // Navigate to suspended screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => AccountSuspendedScreen(
              status: status,
              reason: statusData['reason'],
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  void _setupGeofenceListener() {
    _geofenceSubscription = GeofenceEngine().eventStream.listen((event) {
      if (mounted) {
        GeofenceModal.show(
          context,
          eventData: event,
          onCheckIn: () {
            setState(() {
              _selectedIndex = 1; // Switch to Map Tab
            });
            // Small delay to ensure tab switch
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _mapScreenKey.currentState?.showTableDetails(event['id']!);
            });
          },
        );
      }
    });
  }

  List<Widget> get _screens {
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

    return [
      FeedScreen(
        onJoinTable: (tableId) {
          setState(() {
            _selectedIndex = 1;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapScreenKey.currentState?.showTableDetails(tableId);
          });
        },
        onStoryTap: (story) {
          setState(() {
            _selectedIndex = 1;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapScreenKey.currentState?.showStoryDetails(story);
          });
        },
        onSeeAllHangouts: () {
          setState(() {
            _selectedIndex = 1;
          });
        },
      ),
      MapScreen(key: _mapScreenKey),
      const ActivityScreen(),
      currentUserId != null
          ? UserProfileScreen(userId: currentUserId, isOwnProfile: true)
          : const Center(child: Text("Please log in")),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Track tab switch
    const tabNames = ['home_feed', 'map', 'activity', 'profile'];
    if (index < tabNames.length) {
      AnalyticsService().logScreenView(tabNames[index]);
    }
  }

  void _showCreateTableModal() {
    AnalyticsService().logScreenView('create_table_modal');
    final position = _mapScreenKey.currentState?.getCurrentPosition();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateTableModal(
        currentLat: position?.latitude,
        currentLng: position?.longitude,
        onTableCreated: () {
          setState(() {
            _selectedIndex = 1;
          });
          _mapScreenKey.currentState?.refreshTables();
        },
      ),
    );
  }

  void _showQuickChat() {
    AnalyticsService().logScreenView('chat_inbox');
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.transparent),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Hero(
                  tag: 'quick_chat_bubble',
                  child: Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    clipBehavior: Clip.antiAlias,
                    elevation: 16,
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return OverflowBox(
                            minHeight: 0,
                            maxHeight: double.infinity,
                            minWidth: 0,
                            maxWidth: double.infinity,
                            alignment: Alignment.topCenter,
                            child: Opacity(
                              opacity: constraints.maxHeight < 200 ? 0.0 : 1.0,
                              child: SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.7,
                                width: constraints.maxWidth,
                                child: Column(
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      width: 40,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Text(
                                        'Active Chats',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    const Expanded(child: ActiveChatsList()),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(index: _selectedIndex, children: _screens),
          ),

          if (currentUserId != null) DraggableChatBubble(onTap: _showQuickChat),
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
          heroTag: 'main_fab',
          onPressed: _showCreateTableModal,
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 0,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white, size: 32),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
            _buildNavItem(1, Icons.map_outlined, Icons.map, 'Map'),
            const SizedBox(width: 48),
            _buildNavItem(
              2,
              Icons.grid_view_outlined,
              Icons.grid_view,
              'Activity',
            ),
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
