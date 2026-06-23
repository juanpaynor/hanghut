import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitemates/features/home/screens/feed_screen.dart';
import 'package:bitemates/features/map/screens/map_screen.dart';
import 'package:bitemates/features/map/widgets/create_hangout/create_hangout_flow.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/activity/screens/activity_screen.dart';
import 'package:bitemates/features/chat/widgets/draggable_chat_bubble.dart';
import 'package:bitemates/features/activity/widgets/tabbed_inbox.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/location/logic/geofence_engine.dart';
import 'package:bitemates/features/location/widgets/geofence_modal.dart';
import 'package:bitemates/core/services/account_status_service.dart';
import 'package:bitemates/features/auth/screens/account_suspended_screen.dart';
import 'package:bitemates/core/services/push_notification_service.dart';
import 'package:bitemates/core/services/admin_popup_service.dart';
import 'package:bitemates/features/shared/widgets/admin_popup_modal.dart';
import 'package:bitemates/core/services/analytics_service.dart';
import 'package:bitemates/features/camera/screens/story_camera_screen.dart';
import 'package:bitemates/features/home/widgets/create_post_modal.dart';
import 'package:bitemates/core/services/connectivity_service.dart';
import 'package:bitemates/core/widgets/offline_banner.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;
  final String? initialTableId;
  final String? initialEventId;
  final double? flyToLat;
  final double? flyToLng;

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.initialTableId,
    this.initialEventId,
    this.flyToLat,
    this.flyToLng,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late int _selectedIndex;

  final GlobalKey<MapScreenState> _mapScreenKey = GlobalKey<MapScreenState>();
  final GlobalKey<FeedScreenState> _feedScreenKey =
      GlobalKey<FeedScreenState>();
  StreamSubscription<Map<String, dynamic>>? _geofenceSubscription;

  // Speed dial
  bool _fabOpen = false;
  late final AnimationController _dialController;
  late final Animation<double> _dialAnimation;

  // Nav tab animations
  late final List<AnimationController> _navControllers;
  late final List<Animation<double>> _navAnimations;

  // Compact nav on scroll — ValueNotifier so scroll never calls setState on
  // the full screen; only the navbar's ValueListenableBuilder rebuilds.
  final ValueNotifier<bool> navCompactNotifier = ValueNotifier(false);
  double _scrollAccum = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _setupGeofenceListener();
    WidgetsBinding.instance.addObserver(this);

    // Speed dial animation
    _dialController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _dialAnimation = CurvedAnimation(
      parent: _dialController,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInCubic,
    );

    // Nav tab pop animations
    _navControllers = List.generate(
      4,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
      ),
    );
    _navAnimations = _navControllers.map((c) {
      return TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.32), weight: 38),
        TweenSequenceItem(tween: Tween(begin: 1.32, end: 1.0), weight: 62),
      ]).animate(CurvedAnimation(parent: c, curve: Curves.easeOut));
    }).toList();

    // Handle Deep Link for Table
    if (widget.initialTableId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapScreenKey.currentState?.showTableDetails(widget.initialTableId!);
      });
    }

    // Handle Deep Link for Event (from follower_event notification)
    if (widget.initialEventId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEventFromNotification(widget.initialEventId!);
      });
    }

    // Handle Fly-To from story location tap — coordinates are passed
    // directly to MapScreen via constructor to bypass intro animation.

    ConnectivityService().start();

    // Ensure FCM token is saved for already-logged-in users on app re-launch.
    // Auth is guaranteed to be restored by the time MainNavigationScreen mounts.
    PushNotificationService().saveTokenOnLogin();

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

  Future<void> _openEventFromNotification(String eventId) async {
    try {
      final event = await EventService().getEvent(eventId);
      if (event != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EventDetailModal(event: event)),
        );
      }
    } catch (e) {
      print('⚠️ Could not open event from notification: $e');
    }
  }

  @override
  void dispose() {
    navCompactNotifier.dispose();
    _dialController.dispose();
    for (final c in _navControllers) {
      c.dispose();
    }
    _geofenceSubscription?.cancel();
    ConnectivityService().stop();
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
              _selectedIndex = 0; // Switch to Map Tab
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
      MapScreen(
        key: _mapScreenKey,
        initialFlyToLat: widget.flyToLat,
        initialFlyToLng: widget.flyToLng,
      ),
      FeedScreen(
        key: _feedScreenKey,
        onJoinTable: (tableId) {
          setState(() {
            _selectedIndex = 0;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapScreenKey.currentState?.showTableDetails(tableId);
          });
        },
        onStoryTap: (story) {
          setState(() {
            _selectedIndex = 0;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapScreenKey.currentState?.showStoryDetails(story);
          });
        },
        onSeeAllHangouts: () {
          setState(() {
            _selectedIndex = 0;
          });
        },
      ),
      ActivityScreen(
        onHangoutTap: (tableId) {
          setState(() {
            _selectedIndex = 0;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapScreenKey.currentState?.showTableDetails(tableId);
          });
        },
      ),
      currentUserId != null
          ? UserProfileScreen(userId: currentUserId, isOwnProfile: true)
          : const Center(child: Text("Please log in")),
    ];
  }

  void _onItemTapped(int index) {
    // If Feed tab is tapped while already on Feed, scroll back to top
    if (index == 1 && _selectedIndex == 1) {
      _feedScreenKey.currentState?.scrollToTop();
      return;
    }
    _navControllers[index].forward(from: 0.0);
    HapticFeedback.selectionClick();
    navCompactNotifier.value = false;
    _scrollAccum = 0;
    setState(() {
      _selectedIndex = index;
    });
    // Track tab switch
    const tabNames = ['map', 'home_feed', 'activity', 'profile'];
    if (index < tabNames.length) {
      AnalyticsService().logScreenView(tabNames[index]);
    }
  }

  void _showCreateTableModal() {
    _closeDial();
    AnalyticsService().logScreenView('create_hangout_flow');
    final position = _mapScreenKey.currentState?.getCurrentPosition();

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CreateHangoutFlow(
              currentLat: position?.latitude,
              currentLng: position?.longitude,
              onTableCreated: () {
                setState(() {
                  _selectedIndex = 1;
                });
                _mapScreenKey.currentState?.refreshTables();
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _toggleDial() {
    HapticFeedback.lightImpact();
    setState(() => _fabOpen = !_fabOpen);
    if (_fabOpen) {
      _dialController.forward();
    } else {
      _dialController.reverse();
    }
  }

  void _closeDial() {
    if (_fabOpen) {
      setState(() => _fabOpen = false);
      _dialController.reverse();
    }
  }

  void _openShareMoment() {
    _closeDial();
    AnalyticsService().logScreenView('story_camera');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StoryCameraScreen()),
    );
  }

  void _openCreatePost() {
    _closeDial();
    AnalyticsService().logScreenView('create_post');
    Navigator.of(context).push<Map<String, dynamic>?>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const CreatePostModal(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
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
                                        'Inbox',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    const Expanded(child: TabbedInbox()),
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
      body: OfflineBanner(
        child: Stack(
          children: [
            Positioned.fill(
              child: _wrapScrollDetector(
                IndexedStack(index: _selectedIndex, children: _screens),
              ),
            ),

          if (currentUserId != null) DraggableChatBubble(onTap: _showQuickChat),

          // ── Speed Dial Scrim ──
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDial,
                child: AnimatedOpacity(
                  opacity: _fabOpen ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(color: Colors.black.withOpacity(0.45)),
                ),
              ),
            ),

          // ── Speed Dial Arc Buttons ──
          _buildSpeedDialButtons(context),

          // ── Floating Nav Bar ──
          // RepaintBoundary isolates the blur repaint from the rest of the
          // screen; ValueListenableBuilder means only this subtree rebuilds
          // when compact state changes — the IndexedStack never repaints.
          RepaintBoundary(
            child: ValueListenableBuilder<bool>(
              valueListenable: navCompactNotifier,
              builder: (context, navCompact, _) =>
                  _buildFloatingNavBar(context, navCompact),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _wrapScrollDetector(Widget child) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification) {
          if (n.metrics.pixels <= 10) {
            if (navCompactNotifier.value) navCompactNotifier.value = false;
            _scrollAccum = 0;
            return false;
          }
          final delta = n.scrollDelta ?? 0;
          // Reset accumulator when direction flips so the bar reacts promptly
          // to a reversal instead of having to unwind a large built-up value.
          if ((delta > 0 && _scrollAccum < 0) ||
              (delta < 0 && _scrollAccum > 0)) {
            _scrollAccum = 0;
          }
          _scrollAccum += delta;
          if (_scrollAccum > 40 && !navCompactNotifier.value) {
            navCompactNotifier.value = true;
            _scrollAccum = 0;
          } else if (_scrollAccum < -20 && navCompactNotifier.value) {
            navCompactNotifier.value = false;
            _scrollAccum = 0;
          }
        } else if (n is ScrollEndNotification) {
          // Once scrolling settles, spring the bar back to full size.
          if (navCompactNotifier.value) navCompactNotifier.value = false;
          _scrollAccum = 0;
        }
        return false;
      },
      child: child,
    );
  }

  Widget _buildFloatingNavBar(BuildContext context, bool navCompact) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // FAB protrudes 4px above the bar top — pops out slightly without floating away
    const barHeight = 72.0;
    const fabSize = 58.0;
    const protrusion = 4.0;
    const stackHeight = barHeight + protrusion + fabSize / 2; // = 105

    // Compact-on-scroll: bar shrinks width-inward (centered), labels collapse.
    // Height/stackHeight stay constant so the speed-dial geometry is unaffected.
    final availableWidth = MediaQuery.of(context).size.width - 32;
    final compactWidth = (availableWidth * 0.66).clamp(260.0, availableWidth);

    return Positioned(
      bottom: bottomInset + 12,
      left: 16,
      right: 16,
      height: stackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Frosted glass bar — at the bottom of the stack
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                width: navCompact ? compactWidth : availableWidth,
                child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 24,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                Colors.grey[900]!.withOpacity(0.74),
                                Colors.grey[850]!.withOpacity(0.62),
                              ]
                            : [
                                Colors.white.withOpacity(0.58),
                                Colors.white.withOpacity(0.40),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.18)
                            : Colors.white.withOpacity(0.65),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(0, Icons.map_outlined, Icons.map, 'Map', navCompact),
                        _buildNavItem(1, Icons.newspaper_outlined, Icons.newspaper, 'Feed', navCompact),
                        const SizedBox(width: fabSize), // placeholder keeps spacing
                        _buildNavItem(2, Icons.grid_view_outlined, Icons.grid_view, 'Explore', navCompact),
                        _buildNavItem(3, Icons.person_outline, Icons.person, 'Profile', navCompact),
                      ],
                    ),
                  ),
                ),
              ),
                ),
              ),
            ),
          ),
          // FAB — sits above the bar, outside the ClipRRect
          Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: _toggleDial,
              child: Container(
                height: fabSize,
                width: fabSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(Theme.of(context).primaryColor, Colors.white, 0.30)!,
                      Theme.of(context).primaryColor,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: AnimatedBuilder(
                  animation: _dialController,
                  builder: (_, __) => Transform.rotate(
                    angle: _dialController.value * math.pi / 4,
                    child: const Icon(Icons.add, color: Colors.white, size: 34),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedDialButtons(BuildContext context) {
    // Three items: Hangout (right), Moment (top), Trip (left)
    // Arc sweeps from ~40° to ~140° above the FAB centre
    // FAB centre is at the bottom-centre of the screen
    final items = [
      const _DialItem(icon: Icons.table_restaurant, label: 'Hangout', index: 0),
      const _DialItem(
        icon: Icons.camera_alt_outlined,
        label: 'Story',
        index: 1,
      ),
      const _DialItem(icon: Icons.edit_outlined, label: 'Post', index: 2),
    ];

    // Angles in radians from positive x-axis, going counter-clockwise
    // 0 = right, pi/2 = up, pi = left
    final angles = [math.pi * 0.22, math.pi * 0.5, math.pi * 0.78];
    const radius = 110.0;

    return AnimatedBuilder(
      animation: _dialAnimation,
      builder: (context, _) {
        final screenSize = MediaQuery.of(context).size;
        final bottomInset = MediaQuery.of(context).padding.bottom;
        // Stack height=105, bottom=bottomInset+12; FAB at Align.topCenter → center=top+29
        // fabCy = screenHeight - bottomInset - 12 - 105 + 29 = screenHeight - bottomInset - 88
        final fabCx = screenSize.width / 2;
        final fabCy = screenSize.height - bottomInset - 88;

        return Stack(
          children: [
            for (int i = 0; i < items.length; i++)
              _buildDialItem(
                context: context,
                item: items[i],
                angle: angles[i],
                radius: radius,
                fabCx: fabCx,
                fabCy: fabCy,
                stagger: i * 0.12,
              ),
          ],
        );
      },
    );
  }

  Widget _buildDialItem({
    required BuildContext context,
    required _DialItem item,
    required double angle,
    required double radius,
    required double fabCx,
    required double fabCy,
    required double stagger,
  }) {
    // Clamp progress with per-item stagger for the wave effect
    final raw = (_dialAnimation.value - stagger) / (1.0 - stagger);
    final progress = raw.clamp(0.0, 1.0);

    final dx = math.cos(angle) * radius * progress;
    final dy = -math.sin(angle) * radius * progress; // negative = upward

    const btnSize = 64.0;
    final left = fabCx + dx - btnSize / 2;
    final top = fabCy + dy - btnSize / 2;

    final color = Theme.of(context).primaryColor;

    return Positioned(
      left: left,
      top: top,
      child: Opacity(
        opacity: progress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: color,
              shape: const CircleBorder(),
              elevation: 6,
              shadowColor: color.withOpacity(0.4),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  if (item.index == 0) _showCreateTableModal();
                  if (item.index == 1) _openShareMoment();
                  if (item.index == 2) _openCreatePost();
                },
                child: SizedBox(
                  width: btnSize,
                  height: btnSize,
                  child: Icon(item.icon, color: Colors.white, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
    bool navCompact,
  ) {
    final isSelected = _selectedIndex == index;
    final activeColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark ? Colors.white70 : Colors.grey[700]!;

    return InkWell(
      onTap: () => _onItemTapped(index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: navCompact ? 8 : 12,
          vertical: 8,
        ),
        child: ScaleTransition(
          scale: _navAnimations[index],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                scale: navCompact ? 1.14 : 1.0,
                child: Icon(
                  isSelected ? iconFilled : iconOutlined,
                  color: isSelected ? activeColor : inactiveColor,
                  size: 26,
                ),
              ),
              // Label collapses to zero height + fades when compact
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  heightFactor: navCompact ? 0.0 : 1.0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: navCompact ? 0.0 : 1.0,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? activeColor : inactiveColor,
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
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
}

// ── Speed dial data ─────────────────────────────────────────────────────────

class _DialItem {
  const _DialItem({
    required this.icon,
    required this.label,
    required this.index,
  });
  final IconData icon;
  final String label;
  final int index;
}
