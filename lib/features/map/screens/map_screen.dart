import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:http/http.dart' as http;
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/matching_service.dart';
import 'package:bitemates/core/services/event_service.dart';
import 'package:bitemates/features/ticketing/models/event.dart';
import 'package:bitemates/features/ticketing/widgets/event_detail_modal.dart';
import 'dart:convert';

import '../widgets/liquid_morph_route.dart';
import '../widgets/table_compact_modal.dart';
import 'package:bitemates/features/map/widgets/active_users_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/features/profile/screens/profile_setup_screen.dart';
import 'package:bitemates/providers/theme_provider.dart';
import 'package:bitemates/features/splash/screens/cloud_opening_screen.dart';
import 'package:bitemates/features/map/widgets/map_cluster_sheet.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';
import 'package:bitemates/features/camera/screens/location_story_viewer_screen.dart';
import 'package:bitemates/core/services/story_service.dart';
import 'package:bitemates/core/services/ably_service.dart';
import 'package:ably_flutter/ably_flutter.dart' as ably;

// Filter enum for toggling marker visibility
enum MapFilter { all, hangouts, events, experiences, stories }

class MapScreen extends StatefulWidget {
  final double? initialFlyToLat;
  final double? initialFlyToLng;

  const MapScreen({super.key, this.initialFlyToLat, this.initialFlyToLng});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen>
    with AutomaticKeepAliveClientMixin {
  MapboxMap? _mapboxMap;
  geo.Position? _currentPosition;
  PointAnnotationManager? _tableMarkerManager;
  final _tableService = TableService();
  final _matchingService = MatchingService();
  final _eventService = EventService();
  final StoryService _storyService = StoryService();

  List<Map<String, dynamic>> _tables = [];
  List<Event> _events = [];
  List<Map<String, dynamic>> _stories = [];
  Map<String, dynamic>? _currentUserData;
  Timer? _debounceTimer;
  CameraState? _lastFetchCameraState;

  Timer? _heartbeatTimer;
  StreamSubscription<ably.Message>? _feedSubscription;
  int _activeUserCount = 0;
  bool _isFetching = false;
  bool _showCloudIntro = true;
  int _lastFeatureCount = 0; // Track marker count for pop animation

  /// Whether we have a flyTo target from a deep link / story location tap
  bool get _hasFlyToTarget =>
      widget.initialFlyToLat != null && widget.initialFlyToLng != null;

  // Filter toggle
  MapFilter _currentFilter = MapFilter.all;

  // Optimization: Track added images to avoid re-uploading
  final Set<String> _addedImages = {};
  static const int _maxCachedImages = 200; // Prevent memory leak

  // Experience route polyline
  PolylineAnnotationManager? _routePolylineManager;
  CameraState?
  _preFlyCamera; // To restore camera after dismissing experience sheet

  // Isochrone layer state
  bool _showIsochrone = false;
  bool _isTableModalOpen = false;
  int _isochroneMinutes = 15;
  Timer? _isochronePulseTimer;
  double _isochronePulsePhase = 0.0;

  // Mystery tables — separate list, only rendered when isochrone pulse is active
  List<Map<String, dynamic>> _mysteryTables = [];

  @override
  bool get wantKeepAlive => true;

  // ... (initState, dispose, etc)

  @override
  void initState() {
    super.initState();
    // Skip cloud intro entirely when we have a direct flyTo target
    if (_hasFlyToTarget) {
      _showCloudIntro = false;
    }
    _getUserLocation();
    _loadCurrentUserData();
    _startHeartbeat();
    _subscribeToFeed();
  }

  void _subscribeToFeed() {
    _feedSubscription = AblyService().subscribeToCityFeed('philippines')?.listen((
      message,
    ) {
      if (message.name == 'post_deleted' && mounted) {
        final data = message.data;
        if (data is Map && data['post_id'] != null) {
          final deletedPostId = data['post_id'];
          setState(() {
            final initialLength = _stories.length;
            _stories.removeWhere((story) => story['id'] == deletedPostId);
            if (_stories.length < initialLength) {
              // Re-fetch map markers to instantly remove the deleted story marker
              _fetchTablesInViewport();
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _popAnimationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _feedSubscription?.cancel();
    _isochronePulseTimer?.cancel();
    super.dispose();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Optimized to 5 minutes based on "Active in last 10m" window
    // This reduces DB load by 80% while keeping data accurate enough
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _updateHeartbeat();
    });
    _updateHeartbeat(); // Initial run
  }

  /// Public method to open story from external screens
  Future<void> showStoryDetails(Map<String, dynamic> story) async {
    final lat = (story['latitude']) as num?;
    final lng = (story['longitude']) as num?;

    if (lat != null && lng != null && _mapboxMap != null) {
      _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(lng.toDouble(), lat.toDouble())),
          zoom: 16.0,
          pitch: 50.0,
        ),
        MapAnimationOptions(duration: 1200),
      );
    }

    if (mounted) {
      // Small delay to let camera start flying
      await Future.delayed(const Duration(milliseconds: 300));
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LocationStoryViewerScreen(
            initialStory: story,
            clusterId:
                story['external_place_id'] ??
                story['event_id'] ??
                story['table_id'],
          ),
        ),
      );
    }
  }

  /// Public method to open table details from external screens (e.g. Feed)
  Future<void> showTableDetails(String tableId) async {
    try {
      // 1. Check if table is already loaded in current view
      var table = _tables.firstWhere(
        (t) => t['id'] == tableId,
        orElse: () => {},
      );

      // 2. If not found locally, fetch from DB
      if (table.isEmpty) {
        final response = await SupabaseConfig.client
            .from('tables')
            .select()
            .eq('id', tableId)
            .single();
        table = response;
      }

      // 3. Prepare match data (needed for modal)
      // Ensure user data is loaded
      if (_currentUserData == null) {
        await _loadCurrentUserData();
      }

      final matchData = _matchingService.calculateMatch(
        currentUser: _currentUserData ?? {}, // Fallback empty if fetch failed
        table: table,
      );

      // 4. Pan camera to the table's location (offset south so marker sits in top half)
      final lat = (table['location_lat'] ?? table['latitude']) as num?;
      final lng = (table['location_lng'] ?? table['longitude']) as num?;

      if (lat != null && lng != null && _mapboxMap != null) {
        // Shift center south by ~0.003° so the marker lands in the upper quarter
        // of the screen (bottom half will be covered by the sheet)
        final offsetLat = lat.toDouble() - 0.0015;
        _mapboxMap?.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(lng.toDouble(), offsetLat)),
            zoom: 17.5,
            pitch: 50.0,
          ),
          MapAnimationOptions(duration: 800),
        );
      }

      // 5. Open Modal
      if (mounted) {
        setState(() => _isTableModalOpen = true);
        final size = MediaQuery.of(context).size;
        final center = Offset(size.width / 2, size.height / 2);

        Navigator.of(context)
            .push(
              LiquidMorphRoute(
                center: center,
                page: TableCompactModal(table: table, matchData: matchData),
              ),
            )
            .then((_) {
              if (mounted) setState(() => _isTableModalOpen = false);
            });
      }
    } catch (e) {
      print('❌ Error showing table details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load table details')),
        );
      }
    }
  }

  Future<void> _updateHeartbeat() async {
    if (!mounted) return;
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        // Update my presence (Fire and forget)
        await SupabaseConfig.client
            .from('users') // Updated from 'profiles' to 'users'
            .update({'last_active_at': DateTime.now().toIso8601String()})
            .eq('id', user.id);
      }

      // Fetch count (Philippines only)
      final count = await SupabaseConfig.client.rpc(
        'get_active_users_philippines_count',
      );
      if (mounted) {
        setState(() => _activeUserCount = count as int);
      }
    } catch (e) {
      print('Error updating heartbeat: $e');
    }
  }

  void _onCameraChangeListener(CameraChangedEventData event) {
    // Debounce the camera change event
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _fetchTablesInViewport();
      }
    });
  }

  Future<void> _getUserLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('📍 Location services are disabled');
        return;
      }

      // Check location permission
      geo.LocationPermission permission =
          await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          print('📍 Location permissions are denied');
          return;
        }
      }

      if (permission == geo.LocationPermission.deniedForever) {
        print('📍 Location permissions are permanently denied');
        return;
      }

      // Get current position
      geo.Position position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );

      print(
        '📍 Got user location: ${position.latitude}, ${position.longitude}',
      );

      setState(() {
        _currentPosition = position;
      });

      // Only set camera to user location if we DON'T have a flyTo target
      // and the cloud intro is already done (avoid interrupting the animation)
      if (_mapboxMap != null && !_hasFlyToTarget && !_showCloudIntro) {
        _mapboxMap?.setCamera(
          CameraOptions(
            center: Point(
              coordinates: Position(position.longitude, position.latitude),
            ),
            zoom: 14.0,
          ),
        );
      }
    } catch (e) {
      print('❌ Error getting location: $e');
    }
  }

  Future<void> _loadCurrentUserData() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;

      final response = await SupabaseConfig.client
          .from('users')
          .select('''
            id,
            display_name,
            user_personality (*),
            user_preferences (*),
            user_interests (
              interest_tag:interest_tags(name)
            )
          ''')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _currentUserData = response;
        });
      }

      print('✅ User data loaded successfully');

      // If map is already created, load markers now
      if (_mapboxMap != null && mounted) {
        _fetchTablesInViewport();
      }
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        print('⚠️ User profile incomplete, redirecting to setup...');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ProfileSetupScreen()),
          );
        }
      } else {
        print('❌ Error loading current user data: $e');
      }
    } catch (e) {
      print('❌ Error loading current user data: $e');
    }
  }

  _onMapCreated(MapboxMap mapboxMap) async {
    print('🗺️ Map created callback triggered');
    _mapboxMap = mapboxMap;
    _addedImages
        .clear(); // Clear local cache to force re-add images to new style

    // Register Tap Listener handled via GestureDetector in build

    // Enable location puck
    await _enableLocationPuck();

    // 3D Models removed - using 2D markers only
    // await _setup3DModels(); // REMOVED

    _fetchTablesInViewport(); // Initial fetch
    // Wait for user data to be ready before adding markers
    await _waitForDataAndLoadMarkers();

    // If we have a flyTo target, skip intro and go directly there
    if (_hasFlyToTarget) {
      flyToCoordinates(widget.initialFlyToLat!, widget.initialFlyToLng!);
    } else {
      // Intro Animation
      _playIntroAnimation();
    }
  }

  Future<void> _playIntroAnimation() async {
    // Wait for user location to be available (up to 5 seconds)
    int waited = 0;
    while (_currentPosition == null && waited < 5000) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }

    // Sync with Cloud Dive (starts at 200ms, takes 3s)
    await Future.delayed(const Duration(milliseconds: 200));

    _mapboxMap?.flyTo(
      CameraOptions(
        center: _currentPosition != null
            ? Point(
                coordinates: Position(
                  _currentPosition!.longitude,
                  _currentPosition!.latitude,
                ),
              )
            : null,
        zoom: 16.0, // Land at street level
        pitch: 60.0,
        bearing: 45.0,
      ),
      MapAnimationOptions(duration: 3000), // Match cloud flight
    );
  }

  Future<void> _enableLocationPuck() async {
    if (_mapboxMap == null) return;

    try {
      await _mapboxMap?.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          pulsingColor: Colors.cyan.value,
          pulsingMaxRadius: 30.0,
        ),
      );
      print('✅ Location puck enabled');
    } catch (e) {
      print('❌ Error enabling location puck: $e');
    }
  }

  Future<void> _waitForDataAndLoadMarkers() async {
    // Wait up to 5 seconds for user data to load
    int attempts = 0;
    while (_currentUserData == null && attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (_currentUserData != null) {
      await _fetchTablesInViewport();
    } else {
      print('⚠️ User data not loaded, retrying markers in 2 seconds...');
      Future.delayed(const Duration(seconds: 2), () {
        if (_currentUserData != null && mounted) {
          _fetchTablesInViewport();
        }
      });
    }
  }

  // Public method to refresh tables from parent
  void refreshTables() {
    if (mounted) {
      _fetchTablesInViewport();
    }
  }

  // Public method to get current position for create table modal
  geo.Position? getCurrentPosition() {
    return _currentPosition;
  }

  /// Public method to fly the camera to specific coordinates (no modal).
  void flyToCoordinates(double lat, double lng, {double zoom = 16.0}) {
    _mapboxMap?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lng, lat)),
        zoom: zoom,
        pitch: 50.0,
      ),
      MapAnimationOptions(duration: 1200),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    // Map Styles
    const lightMapStyle = 'mapbox://styles/swiftdash/cmjwvnoqp001v01rdeseu6fz1';
    const darkMapStyle =
        'mapbox://styles/swiftdash/cmjyv1kco003m01rd6nkjcd27'; // Custom dark style

    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;

    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            onTapUp: _onMapTap,
            child: MapWidget(
              key: ValueKey('mapWidget_${isDarkMode ? 'dark' : 'light'}'),
              styleUri: isDarkMode ? darkMapStyle : lightMapStyle,
              cameraOptions: CameraOptions(
                center: _currentPosition != null
                    ? Point(
                        coordinates: Position(
                          _currentPosition!.longitude,
                          _currentPosition!.latitude,
                        ),
                      )
                    : Point(coordinates: Position(-74.0060, 40.7128)),
                zoom: 11.0, // Start high up for "dive" effect
                pitch: 45.0, // Slight tilt initially
              ),
              onCameraChangeListener: _onCameraChangeListener,
              onMapCreated: _onMapCreated,
              onTapListener: _onMapTapWrapper, // Native tap listener
            ),
          ),

          // Active User Count Pill
          if (_activeUserCount > 0 && !_isTableModalOpen)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () async {
                    // Get current viewport bounds
                    final cameraState = await _mapboxMap?.getCameraState();
                    if (cameraState == null) return;

                    final bounds = await _mapboxMap
                        ?.coordinateBoundsForCameraUnwrapped(
                          CameraOptions(
                            center: cameraState.center,
                            zoom: cameraState.zoom,
                            bearing: cameraState.bearing,
                            pitch: cameraState.pitch,
                          ),
                        );

                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (context) => ActiveUsersBottomSheet(
                        minLat: bounds?.southwest.coordinates.lat.toDouble(),
                        maxLat: bounds?.northeast.coordinates.lat.toDouble(),
                        minLng: bounds?.southwest.coordinates.lng.toDouble(),
                        maxLng: bounds?.northeast.coordinates.lng.toDouble(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isFetching)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        else
                          const Text('👀', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          _isFetching
                              ? 'Updating map...'
                              : '$_activeUserCount people active on map',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Filter Chips Row
          if (!_isTableModalOpen)
            Positioned(
              top: 100,
              left: 0,
              right: 0, // No constraint needed — buttons are lower now
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: MapFilter.values.map((filter) {
                    final isSelected = _currentFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_filterLabel(filter)),
                        avatar: isSelected
                            ? null
                            : Icon(
                                _filterIcon(filter),
                                size: 16,
                                color: Colors.black54,
                              ),
                        selected: isSelected,
                        onSelected: (_) => _onFilterChanged(filter),
                        selectedColor: Theme.of(context).primaryColor,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 2,
                        pressElevation: 4,
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // Map Controls (upper-right)
          if (!_isTableModalOpen)
            Positioned(
              right: 16,
              top: 180, // Lowered to avoid overlapping filter chips
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Refresh Button
                  FloatingActionButton(
                    heroTag: 'map_refresh_btn',
                    mini: true,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    onPressed: _onRefreshTapped,
                    child: const Icon(Icons.refresh, size: 20),
                  ),
                  const SizedBox(height: 12),

                  // Focus Location Button
                  FloatingActionButton(
                    heroTag: 'map_focus_btn',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    onPressed: _onFocusLocationTapped,
                    child: const Icon(Icons.my_location),
                  ),
                  const SizedBox(height: 12),

                  // Isochrone Toggle
                  FloatingActionButton(
                    heroTag: 'map_isochrone_btn',
                    mini: true,
                    backgroundColor: _showIsochrone
                        ? Colors.indigo
                        : Colors.white,
                    foregroundColor: _showIsochrone
                        ? Colors.white
                        : Colors.black87,
                    onPressed: _showIsochrone
                        ? _toggleIsochrone // already on → just turn off
                        : _showIsochroneExplainer, // off → explain first
                    child: Icon(
                      _showIsochrone ? Icons.radar : Icons.radar,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

          // Isochrone is fixed at 15 minutes — no picker needed

          // Cloud Transition (Map Only)
          if (_showCloudIntro)
            Positioned.fill(
              child: CloudOpeningScreen(
                key: ValueKey(
                  'CloudOpening_${DateTime.now().millisecondsSinceEpoch}',
                ),
                onAnimationComplete: () {
                  if (mounted) {
                    setState(() => _showCloudIntro = false);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  // --- Map Controls ---

  void _onRefreshTapped() {
    print('🔄 Manual map refresh triggered');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refreshing map data...'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Reset state to force fetch even if camera hasn't moved
    _lastFetchCameraState = null;
    refreshTables();
  }

  // --- Filter Helpers ---

  String _filterLabel(MapFilter filter) {
    switch (filter) {
      case MapFilter.all:
        return 'All';
      case MapFilter.hangouts:
        return 'Hangouts';
      case MapFilter.events:
        return 'Events';
      case MapFilter.experiences:
        return 'Experiences';
      case MapFilter.stories:
        return 'Stories';
    }
  }

  IconData _filterIcon(MapFilter filter) {
    switch (filter) {
      case MapFilter.all:
        return Icons.layers;
      case MapFilter.hangouts:
        return Icons.restaurant;
      case MapFilter.events:
        return Icons.confirmation_number;
      case MapFilter.experiences:
        return Icons.palette;
      case MapFilter.stories:
        return Icons.camera_alt;
    }
  }

  void _onFilterChanged(MapFilter filter) {
    if (_currentFilter == filter) return;
    setState(() => _currentFilter = filter);
    _rebuildMapSource();
  }

  /// Filters the cached features list based on the active filter.
  /// Called both during initial fetch and on filter toggle.
  List<Map<String, dynamic>> _filterFeatures(
    List<Map<String, dynamic>> features,
  ) {
    if (_currentFilter == MapFilter.all) return features;

    return features.where((f) {
      final type = f['properties']?['type'] as String?;
      switch (_currentFilter) {
        case MapFilter.hangouts:
          // Tables that are NOT experiences
          if (type == 'table') {
            final index = f['properties']?['index'] as int?;
            if (index != null && index < _tables.length) {
              return _tables[index]['is_experience'] != true;
            }
          }
          // Mystery markers are visible hangouts too
          if (type == 'mystery') return true;
          return false;
        case MapFilter.events:
          return type == 'event' || type == 'stack';
        case MapFilter.experiences:
          // Tables that ARE experiences
          if (type == 'table') {
            final index = f['properties']?['index'] as int?;
            if (index != null && index < _tables.length) {
              return _tables[index]['is_experience'] == true;
            }
          }
          return false;
        case MapFilter.stories:
          return type == 'story';
        case MapFilter.all:
          return true;
      }
    }).toList();
  }

  /// Re-encode cached data into GeoJSON with filter applied, without re-fetching.
  Future<void> _rebuildMapSource() async {
    if (_mapboxMap == null) return;
    final style = _mapboxMap?.style;
    if (style == null) return;

    // Rebuild feature list from cached data
    final features = <Map<String, dynamic>>[];

    // Tables
    for (var i = 0; i < _tables.length; i++) {
      final table = _tables[i];
      final imageId = 'table_img_${table['id']}';
      features.add({
        'type': 'Feature',
        'id': table['id'],
        'geometry': {
          'type': 'Point',
          'coordinates': [table['location_lng'], table['location_lat']],
        },
        'properties': {
          'icon_id': imageId,
          'description': table['venue_name'],
          'index': i,
          'type': 'table',
        },
      });
    }

    // Mystery tables (only when isochrone pulse is active)
    if (_showIsochrone && _mysteryTables.isNotEmpty) {
      for (var i = 0; i < _mysteryTables.length; i++) {
        final table = _mysteryTables[i];
        final imageId = 'mystery_img_${table['id']}';
        features.add({
          'type': 'Feature',
          'id': 'mystery_${table['id']}',
          'geometry': {
            'type': 'Point',
            'coordinates': [table['location_lng'], table['location_lat']],
          },
          'properties': {
            'icon_id': imageId,
            'description': 'Mystery Activity',
            'index': i,
            'type': 'mystery',
          },
        });
      }
    }

    // Events (simplified — single markers only for rebuild; full spiderfy happens on fetch)
    for (var i = 0; i < _events.length; i++) {
      final event = _events[i];
      final imageId = 'event_img_${event.id}';
      features.add({
        'type': 'Feature',
        'id': 'event_${event.id}',
        'geometry': {
          'type': 'Point',
          'coordinates': [event.longitude, event.latitude],
        },
        'properties': {
          'icon_id': imageId,
          'description': event.title,
          'index': i,
          'type': 'event',
        },
      });
    }

    // Stories
    for (var i = 0; i < _stories.length; i++) {
      final story = _stories[i];
      final imageId = 'story_img_${story['id']}';
      features.add({
        'type': 'Feature',
        'id': 'story_${story['id']}',
        'geometry': {
          'type': 'Point',
          'coordinates': [story['longitude'], story['latitude']],
        },
        'properties': {
          'icon_id': imageId,
          'description': story['caption'] ?? 'Live Story',
          'index': i,
          'type': 'story',
        },
      });
    }

    final filtered = _filterFeatures(features);
    final geoJsonData = jsonEncode({
      'type': 'FeatureCollection',
      'features': filtered,
    });

    print(
      '🔍 Filter: ${_currentFilter.name} → ${filtered.length}/${features.length} features',
    );

    const sourceId = 'tables-cluster-source';
    final sourceExists = await style.styleSourceExists(sourceId);
    if (sourceExists) {
      await style.setStyleSourceProperty(sourceId, 'data', geoJsonData);
    }
  }

  Future<void> _onFocusLocationTapped() async {
    print('📍 Focus location tapped');

    // If we have a cached position, fly there immediately
    if (_currentPosition != null) {
      _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              _currentPosition!.longitude,
              _currentPosition!.latitude,
            ),
          ),
          zoom: 15.0, // Closer street view
          pitch: 45.0,
        ),
        MapAnimationOptions(duration: 1000),
      );
    }

    // Always request a fresh location update to be sure
    await _getUserLocation();
  }

  // Handle map taps
  Future<void> _onMapTap(TapUpDetails details) async {
    print('👆 Map tapped at ${details.localPosition}');
    if (_mapboxMap == null) return;

    // If an experience route is active, the first tap anywhere clears it and returns to previous view
    if (_routePolylineManager != null) {
      _clearExperienceRoute();
      return;
    }

    try {
      final screenCoordinate = ScreenCoordinate(
        x: details.localPosition.dx,
        y: details.localPosition.dy,
      );

      // PHASE 1: Check for cluster tap first
      final clusterFeatures = await _mapboxMap?.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
        RenderedQueryOptions(layerIds: ['clusters']),
      );

      if (clusterFeatures != null && clusterFeatures.isNotEmpty) {
        await _handleClusterTap(clusterFeatures.first, screenCoordinate);
        return;
      }

      // Check if tap is on unclustered point or 3D layer
      final features = await _mapboxMap?.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
        RenderedQueryOptions(layerIds: ['unclustered-points']),
      );

      print('🔎 Query features found: ${features?.length ?? 0}');

      if (features != null && features.isNotEmpty) {
        final feature = features.first;
        final properties =
            feature?.queriedFeature.feature['properties'] as Map?;
        final isCluster = properties?['cluster'] == true;

        if (isCluster) {
          // Handle Cluster Tap -> Zoom In
          final geometry = feature?.queriedFeature.feature['geometry'] as Map?;
          final coordinates = geometry?['coordinates'] as List?;
          final cameraState = await _mapboxMap?.getCameraState();
          if (cameraState != null) {
            _mapboxMap?.flyTo(
              CameraOptions(
                center: Point(
                  coordinates: Position(
                    (coordinates?[0] as num).toDouble(),
                    (coordinates?[1] as num).toDouble(),
                  ),
                ),
                zoom: cameraState.zoom + 2.0, // Zoom in by 2 levels
                pitch: 60.0,
              ),
              MapAnimationOptions(duration: 500, startDelay: 0),
            );
          }
        } else {
          // Handle Marker Tap (Existing Logic)
          // CHECK FOR STACKED MARKERS (Overlap)
          // If we tapped a stack of markers (e.g. multiple events at same venue),
          // features list will contain all of them.
          if (features.length > 1) {
            print('📚 Stacked markers tapped! Count: ${features.length}');
            final List<Map<String, dynamic>> stackedItems = [];

            for (final stackedFeature in features) {
              final props =
                  stackedFeature?.queriedFeature.feature['properties'] as Map?;
              final index = props?['index'];
              final type = props?['type'];

              if (type == 'event' &&
                  index != null &&
                  index is int &&
                  index < _events.length) {
                final event = _events[index];
                stackedItems.add({
                  'id': event.id,
                  'title': event.title,
                  'datetime': event.startDatetime.toIso8601String(),
                  'current_capacity': event.ticketsSold,
                  'max_guests': event.capacity,
                  'location_name': event.venueName,
                  'type': 'event',
                  'original_object': event,
                });
              } else if (type == 'story' &&
                  index != null &&
                  index is int &&
                  index < _stories.length) {
                final story = _stories[index];
                stackedItems.add({...story, 'type': 'story'});
              } else if (type == 'mystery' &&
                  index != null &&
                  index is int &&
                  index < _mysteryTables.length) {
                final table = _mysteryTables[index];
                stackedItems.add({
                  ...table,
                  'type': 'table',
                }); // Treat as table in sheet
              } else if ((type == 'table' || type == 'experience') &&
                  index != null &&
                  index is int &&
                  index < _tables.length) {
                final table = _tables[index];
                stackedItems.add({...table, 'type': 'table'});
              }
            }

            if (stackedItems.isNotEmpty && mounted) {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => MapClusterSheet(
                  items: stackedItems,
                  currentUserData: _currentUserData,
                  matchingService: _matchingService,
                ),
              );
              return; // Stop processing single tap
            }
          }

          // Single Marker Tap (Fallback)
          final properties =
              feature?.queriedFeature.feature['properties'] as Map?;
          final rawIndex = properties?['index'];
          final index = rawIndex != null
              ? int.tryParse(rawIndex.toString())
              : null;
          final markerType =
              properties?['type']; // Check if it's an event marker

          if (markerType == 'event' &&
              index != null &&
              index < _events.length) {
            // Event marker tapped
            final event = _events[index];
            if (mounted) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => EventDetailModal(event: event),
              );
            }
          } else if (markerType == 'story' &&
              index != null &&
              index < _stories.length) {
            // Story marker tapped
            final story = _stories[index];
            if (mounted) {
              print('📸 Opening Location Story Viewer for: ${story['id']}');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LocationStoryViewerScreen(
                    initialStory: story,
                    clusterId:
                        story['external_place_id'] ??
                        story['event_id'] ??
                        story['table_id'],
                  ),
                ),
              );
            }
            return; // STOP processing
          } else if (markerType == 'mystery' &&
              index != null &&
              index < _mysteryTables.length) {
            // Mystery marker tapped — open as normal table
            final table = _mysteryTables[index];
            final matchData = _matchingService.calculateMatch(
              currentUser: _currentUserData!,
              table: table,
            );
            if (mounted) {
              _openTableModal(context, table, matchData, screenCoordinate);
            }
          } else if (index != null && index < _tables.length) {
            // Table marker tapped
            final table = _tables[index];
            final matchData = _matchingService.calculateMatch(
              currentUser: _currentUserData!,
              table: table,
            );
            if (mounted) {
              if (table['is_experience'] == true) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => ExperienceDetailModal(
                    experience: table,
                    matchData: matchData,
                  ),
                );
              } else {
                _openTableModal(context, table, matchData, screenCoordinate);
              }
            }
          }
        }
        return; // Stop processing if we hit something
      }

      if (features != null && features.isNotEmpty) {
        // We tapped a marker!
        final feature = features.first;
        final properties =
            feature?.queriedFeature.feature['properties'] as Map?;
        final rawIndex = properties?['index'];
        final index = rawIndex != null
            ? int.tryParse(rawIndex.toString())
            : null;
        final markerType = properties?['type'];

        print('🔍 Marker properties: index=$index, type=$markerType');
        print(
          '📊 _events.length=${_events.length}, _tables.length=${_tables.length}',
        );

        if ((markerType == 'event' || markerType == 'stack') && index != null) {
          // Handle Event or Stack
          if (markerType == 'stack') {
            // Stack Tap -> Open Cluster Sheet
            print('📚 Stack Marker Tapped');
            final ids = properties?['ids']?.toString().split(',') ?? [];

            // Find events by ID
            final List<Map<String, dynamic>> stackedItems = [];
            for (final id in ids) {
              final event = _events.firstWhere(
                (e) => e.id == id,
                orElse: () => _events[0],
              ); // Fallback safe
              if (event.id == id) {
                stackedItems.add({
                  'id': event.id,
                  'title': event.title,
                  'datetime': event.startDatetime.toIso8601String(),
                  'current_capacity': event.ticketsSold,
                  'max_guests': event.capacity,
                  'location_name': event.venueName,
                  'type': 'event',
                  'original_object': event,
                  // Pass full object for detailed view
                });
              }
            }

            if (mounted) {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => MapClusterSheet(
                  items: stackedItems,
                  currentUserData: _currentUserData,
                  matchingService: _matchingService,
                ),
              );
            }
          } else {
            // Single Event (or Spiderfied) Tap
            print('🎟️ EVENT MARKER TAPPED! Index: $index');
            // Be careful: index might not match _events index if we have phantom spider markers?
            // Actually, I set index correctly in the loop above.
            if (index < _events.length) {
              final event = _events[index];
              if (mounted) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => EventDetailModal(event: event),
                );
              }
            }
          }
        } else if (markerType == 'story' &&
            index != null &&
            index < _stories.length) {
          final story = _stories[index];
          if (mounted) {
            print('📸 Opening Location Story Viewer for: ${story['id']}');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LocationStoryViewerScreen(
                  initialStory: story,
                  clusterId:
                      story['external_place_id'] ??
                      story['event_id'] ??
                      story['table_id'],
                ),
              ),
            );
          }
          return; // STOP processing
        } else if (markerType == 'mystery' &&
            index != null &&
            index < _mysteryTables.length) {
          // Mystery marker tapped via 3D layer — open as normal table
          final table = _mysteryTables[index];
          final matchData = _matchingService.calculateMatch(
            currentUser: _currentUserData!,
            table: table,
          );
          if (mounted) {
            _openTableModal(context, table, matchData, screenCoordinate);
          }
        } else if (index != null && index < _tables.length) {
          // Table marker tapped
          final table = _tables[index]; // Use index to get full table data
          final matchData = _matchingService.calculateMatch(
            currentUser: _currentUserData!,
            table: table,
          );

          if (mounted) {
            if (table['is_experience'] == true) {
              // Open Experience Detail using LiquidMorphRoute (full screen)
              print('🎨 Launching ExperienceDetailModal via LiquidMorphRoute');
              await _drawExperienceRoute(
                table,
              ); // Draw route before so it's visible after pop
              if (mounted) {
                final center = Offset(screenCoordinate.x, screenCoordinate.y);
                Navigator.of(context).push(
                  LiquidMorphRoute(
                    center: center,
                    page: ExperienceDetailModal(
                      experience: table,
                      matchData: matchData,
                    ),
                  ),
                );
              }
            } else {
              // Open Standard Handout Modal
              _openTableModal(context, table, matchData, screenCoordinate);
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error handling map tap: $e');
    }
  }

  // ───────────────── Experience Route Drawing ─────────────────

  Future<void> _drawExperienceRoute(Map<String, dynamic> table) async {
    if (_mapboxMap == null) return;

    // Save camera state to restore later
    _preFlyCamera = await _mapboxMap!.getCameraState();

    // Parse itinerary coordinates
    final List<Position> route = [];

    if (table['location_lat'] != null && table['location_lng'] != null) {
      route.add(
        Position(
          (table['location_lng'] as num).toDouble(),
          (table['location_lat'] as num).toDouble(),
        ),
      );
    }

    if (table['itinerary'] != null) {
      try {
        List<dynamic> raw = table['itinerary'] is String
            ? jsonDecode(table['itinerary'])
            : table['itinerary'];

        for (var stop in raw) {
          if (stop is Map && stop['lat'] != null && stop['lng'] != null) {
            route.add(
              Position(
                (stop['lng'] as num).toDouble(),
                (stop['lat'] as num).toDouble(),
              ),
            );
          }
        }
      } catch (e) {
        print('Error parsing itinerary: $e');
      }
    }

    // Draw polyline if we have a route
    if (route.length > 1) {
      _routePolylineManager = await _mapboxMap!.annotations
          .createPolylineAnnotationManager();
      await _routePolylineManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: route),
          lineColor: Colors.pink.value,
          lineWidth: 4.0,
        ),
      );
    }

    // Fly camera to the experience location with cinematic swoop
    if (route.isNotEmpty) {
      final target = route.first;
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: target),
          zoom: 15.5,
          pitch: 0.0,
          bearing: 0.0,
        ),
        MapAnimationOptions(duration: 2000, startDelay: 0),
      );
    }
  }

  Future<void> _clearExperienceRoute() async {
    // Remove polyline
    if (_routePolylineManager != null && _mapboxMap != null) {
      await _mapboxMap!.annotations.removeAnnotationManager(
        _routePolylineManager!,
      );
      _routePolylineManager = null;
    }

    // Restore camera
    if (_preFlyCamera != null && _mapboxMap != null) {
      _mapboxMap!.flyTo(
        CameraOptions(
          center: _preFlyCamera!.center,
          zoom: _preFlyCamera!.zoom,
          pitch: _preFlyCamera!.pitch,
          bearing: _preFlyCamera!.bearing,
        ),
        MapAnimationOptions(duration: 1500, startDelay: 0),
      );
      _preFlyCamera = null;
    }
  }

  void _openTableModal(
    BuildContext context,
    Map<String, dynamic> table,
    Map<String, dynamic> matchData,
    ScreenCoordinate tapPosition,
  ) {
    // Route experiences to their own full-screen modal
    if (table['is_experience'] == true) {
      print('🎨 Launching ExperienceDetailModal via LiquidMorphRoute');
      _drawExperienceRoute(table); // Call _drawExperienceRoute here
      final center = Offset(tapPosition.x, tapPosition.y);
      Navigator.of(context).push(
        LiquidMorphRoute(
          center: center,
          page: ExperienceDetailModal(experience: table, matchData: matchData),
        ),
      );
      return;
    }

    print('🚀 Launching TableCompactModal via LiquidMorphRoute');

    // Fly the camera to center the marker in the top half of the screen
    final lat = (table['location_lat'] ?? table['latitude']) as num?;
    final lng = (table['location_lng'] ?? table['longitude']) as num?;

    if (lat != null && lng != null && _mapboxMap != null) {
      // Shift center south by ~0.003° so the marker lands in the upper quarter
      final offsetLat = lat.toDouble() - 0.0015;
      _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(lng.toDouble(), offsetLat)),
          zoom: 17.5,
          pitch: 50.0,
        ),
        MapAnimationOptions(duration: 800),
      );
    }

    // Use screen center for the morph reveal
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);

    setState(() => _isTableModalOpen = true);
    Navigator.of(context)
        .push(
          LiquidMorphRoute(
            center: center,
            page: TableCompactModal(table: table, matchData: matchData),
          ),
        )
        .then((_) {
          if (mounted) setState(() => _isTableModalOpen = false);
        });
  }

  // PHASE 1: Handle cluster tap
  Future<void> _handleClusterTap(
    QueriedRenderedFeature? feature,
    ScreenCoordinate screenCoordinate,
  ) async {
    if (feature == null || _mapboxMap == null) return;

    try {
      final properties = feature.queriedFeature.feature['properties'] as Map?;
      final clusterId = properties?['cluster_id'];
      final pointCount = properties?['point_count'] ?? 0;

      print('📍 Cluster tapped: $clusterId with $pointCount events');

      // Get geometry to find cluster location
      final geometry = feature.queriedFeature.feature['geometry'] as Map?;
      final coordinates = geometry?['coordinates'] as List?;

      if (coordinates == null) return;

      final lng = (coordinates[0] as num).toDouble();
      final lat = (coordinates[1] as num).toDouble();

      // Find all tables at this cluster location (within 50m)
      final eventsInCluster = _tables.where((table) {
        final tableLat = table['latitude'] as double;
        final tableLng = table['longitude'] as double;

        final distance = _calculateDistance(lat, lng, tableLat, tableLng);
        return distance < 50; // 50m threshold for clustering
      }).toList();

      if (eventsInCluster.isEmpty) {
        print('⚠️ No events found in cluster');
        return;
      }

      // Show bottom sheet with events
      if (mounted) {
        // Add type info for MapClusterSheet
        final clusterItems = eventsInCluster
            .map((t) => {...t, 'type': t['type'] ?? 'table'})
            .toList();

        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => MapClusterSheet(
            items: clusterItems,
            currentUserData: _currentUserData,
            matchingService: _matchingService,
          ),
        );
      }
    } catch (e) {
      print('❌ Error handling cluster tap: $e');
    }
  }

  // Helper: Calculate distance between two coordinates (Haversine)
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  Future<void> _fetchTablesInViewport() async {
    if (_mapboxMap == null || _currentUserData == null) return;

    try {
      setState(() => _isFetching = true);

      // 1. Check Zoom Level (Threshold lowered to match minZoom)
      final cameraState = await _mapboxMap?.getCameraState();
      if (cameraState == null) return;

      if (cameraState.zoom < 5.0) {
        print(
          '🔎 Zoom level ${cameraState.zoom} is too low. Clearing markers.',
        );
        if (_tables.isNotEmpty) {
          setState(() => _tables = []);
          // Clear native sources
          final emptyGeoJson = jsonEncode({
            'type': 'FeatureCollection',
            'features': [],
          });
          _mapboxMap?.style.setStyleSourceProperty(
            'tables-cluster-source',
            'data',
            emptyGeoJson,
          );
          _mapboxMap?.style.setStyleSourceProperty(
            'tables-3d-source',
            'data',
            emptyGeoJson,
          );
        }
        return;
      }

      // 2. Check if moved significantly since last fetch
      if (_lastFetchCameraState != null) {
        final double dist = geo.Geolocator.distanceBetween(
          cameraState.center.coordinates.lat.toDouble(),
          cameraState.center.coordinates.lng.toDouble(),
          _lastFetchCameraState!.center.coordinates.lat.toDouble(),
          _lastFetchCameraState!.center.coordinates.lng.toDouble(),
        );

        final double zoomDiff = (cameraState.zoom - _lastFetchCameraState!.zoom)
            .abs();

        // Thresholds: 10km or 2.0 zoom level change (PostGIS makes refetch cheap, but no need to spam)
        if (dist < 10000 && zoomDiff < 2.0) {
          print(
            'Skipping fetch: Moved ${dist.toStringAsFixed(0)}m, Zoom diff ${zoomDiff.toStringAsFixed(2)}',
          );
          return;
        }
      }

      // Update last fetch state
      _lastFetchCameraState = cameraState;

      // 3. Get Viewport Bounds
      double? minLat, maxLat, minLng, maxLng;
      // Get the visible region of the map
      final cameraOptions = CameraOptions(
        center: cameraState.center,
        zoom: cameraState.zoom,
        bearing: cameraState.bearing,
        pitch: cameraState.pitch,
      );

      final bounds = await _mapboxMap?.coordinateBoundsForCameraUnwrapped(
        cameraOptions,
      );

      if (bounds != null) {
        minLat = bounds.southwest.coordinates.lat.toDouble();
        maxLat = bounds.northeast.coordinates.lat.toDouble();
        minLng = bounds.southwest.coordinates.lng.toDouble();
        maxLng = bounds.northeast.coordinates.lng.toDouble();
      } else {
        print('⚠️ Could not get map bounds');
        return;
      }

      // Parallel Fetch: Get Tables, Events, and Stories concurrently
      final results = await Future.wait([
        _tableService.getMapReadyTables(
          userLat: _currentPosition?.latitude,
          userLng: _currentPosition?.longitude,
          minLat: minLat,
          maxLat: maxLat,
          minLng: minLng,
          maxLng: maxLng,
          limit: 50, // Cap marker generation for performance
        ),
        _eventService.getEventsInViewport(
          minLat: minLat,
          maxLat: maxLat,
          minLng: minLng,
          maxLng: maxLng,
        ),
        _storyService.getStoriesInViewport(
          minLat: minLat,
          maxLat: maxLat,
          minLng: minLng,
          maxLng: maxLng,
        ),
      ]);

      var fetchedTables = results[0] as List<Map<String, dynamic>>;
      final fetchedEvents = results[1] as List<Event>;
      final fetchedStories = results[2] as List<Map<String, dynamic>>;

      print('📍 Found ${fetchedTables.length} tables in viewport');
      print('📅 Found ${fetchedEvents.length} events in viewport');
      print('📸 Found ${fetchedStories.length} live stories in viewport');

      // ═══ MYSTERY TABLE SPLIT ═══
      // Separate mystery tables from regular tables before scoring
      final mysteryTablesRaw = fetchedTables
          .where((t) => t['visibility'] == 'mystery')
          .toList();
      fetchedTables = fetchedTables
          .where((t) => t['visibility'] != 'mystery')
          .toList();

      // Filter mystery tables by isochrone proximity when pulse is active
      List<Map<String, dynamic>> activeMysteryTables = [];
      if (_showIsochrone &&
          _currentPosition != null &&
          mysteryTablesRaw.isNotEmpty) {
        final radiusKm =
            (_isochroneMinutes * 80.0) / 1000.0; // walking radius in km
        activeMysteryTables = mysteryTablesRaw.where((table) {
          final lat = table['location_lat'] as num?;
          final lng = table['location_lng'] as num?;
          if (lat == null || lng == null) return false;
          final dist = geo.Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            lat.toDouble(),
            lng.toDouble(),
          );
          return dist <= (radiusKm * 1000); // compare in meters
        }).toList();
        print(
          '🔮 Mystery tables in range: ${activeMysteryTables.length}/${mysteryTablesRaw.length}',
        );
      }

      // 4. Relevance Filtering: Sort by Match Score and Cap
      if (_currentUserData != null) {
        final scoredTables = fetchedTables.map((table) {
          final matchData = _matchingService.calculateMatch(
            currentUser: _currentUserData!,
            table: table,
          );
          return {'table': table, 'score': matchData['score'] as double};
        }).toList();

        scoredTables.sort(
          (a, b) => (b['score'] as double).compareTo(a['score'] as double),
        );

        final int maxMarkers = 50;
        if (scoredTables.length > maxMarkers) {
          fetchedTables = scoredTables
              .take(maxMarkers)
              .map((e) => e['table'] as Map<String, dynamic>)
              .toList();
        } else {
          fetchedTables = scoredTables
              .map((e) => e['table'] as Map<String, dynamic>)
              .toList();
        }
      }

      // DUMMY DATA FOR TESTING EXPERIENCES
      /*
      fetchedTables.add({
        'id': 'dummy_exp_1',
        'location_lat': 14.5547,
        'location_lng': 121.0244, // Makati
        'venue_name': 'Pottery Workshop',
        'description': 'Learn to make your own mugs!',
        'is_experience': true,
        'experience_type': 'workshop',
        'price_per_person': 2500,
        'currency': 'PHP',
        'images': ['https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&q=80'],
        'marker_image_url': 'https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?ixlib=rb-4.0.3&auto=format&fit=crop&w=200&q=80',
      });
      */

      // DUMMY DATA FOR TESTING EXPERIENCES removed here to fix map indices

      setState(() {
        _tables = fetchedTables;
        _mysteryTables = activeMysteryTables;
        _events = fetchedEvents;
        _stories = fetchedStories;
      });

      // 5. Clustering & Native Layers Implementation
      final style = _mapboxMap?.style;
      if (style == null) return;

      if (_tableMarkerManager != null) {
        _tableMarkerManager?.deleteAll();
        _tableMarkerManager = null;
      }

      final features = <Map<String, dynamic>>[];

      // --- ✅ PARALLEL Marker Generation: Tables, Events, Stories all at once ---
      // Previously these 3 blocks ran sequentially. Now they run in parallel
      // to reduce marker generation latency by ~60%.

      final tableImagesFuture = () async {
        final tablesNeedImages = fetchedTables.where((table) {
          final imageId = 'table_img_${table['id']}';
          return !_addedImages.contains(imageId);
        }).toList();

        if (tablesNeedImages.isNotEmpty) {
          print(
            '🎨 Generating ${tablesNeedImages.length} table markers in parallel...',
          );
          await Future.wait(
            tablesNeedImages.map((table) async {
              try {
                final imageId = 'table_img_${table['id']}';
                final matchData = _matchingService.calculateMatch(
                  currentUser: _currentUserData!,
                  table: table,
                );

                final Uint8List markerImage;
                final markerImageUrl = table['marker_image_url'];
                final markerEmoji = table['marker_emoji'];

                if (table['is_experience'] == true) {
                  markerImage = await _createExperienceMarkerImage(
                    table: table,
                    glowColor: matchData['color'],
                    glowIntensity: matchData['glowIntensity'],
                  );
                } else if (markerImageUrl != null &&
                    markerImageUrl.toString().isNotEmpty) {
                  markerImage = await _createCustomMarkerImage(
                    imageUrl: markerImageUrl,
                    activityType: table['cuisine_type'],
                    glowColor: matchData['color'],
                    glowIntensity: matchData['glowIntensity'],
                    count: 1,
                  );
                } else if (markerEmoji != null &&
                    markerEmoji.toString().isNotEmpty) {
                  markerImage = await _createEmojiMarkerImage(
                    emoji: markerEmoji,
                    activityType: table['cuisine_type'],
                    glowColor: matchData['color'],
                    glowIntensity: matchData['glowIntensity'],
                  );
                } else {
                  markerImage = await _createTableMarkerImage(
                    photoUrl: table['host_photo_url'],
                    activityType: table['cuisine_type'],
                    glowColor: matchData['color'],
                    glowIntensity: matchData['glowIntensity'],
                    count: 1,
                  );
                }

                final int imgHeight = table['is_experience'] == true
                    ? 136
                    : 120;

                await style.addStyleImage(
                  imageId,
                  2.0,
                  MbxImage(width: 120, height: imgHeight, data: markerImage),
                  false,
                  [],
                  [],
                  null,
                );
                _addedImages.add(imageId);
              } catch (e) {
                print('❌ Error generating table marker for ${table['id']}: $e');
              }
            }),
          );
        }
      }();

      final eventImagesFuture = () async {
        final eventsNeedImages = _events.where((event) {
          final imageId = 'event_img_${event.id}';
          return !_addedImages.contains(imageId);
        }).toList();

        if (eventsNeedImages.isNotEmpty) {
          print(
            '🎨 Generating ${eventsNeedImages.length} event markers in parallel...',
          );
          await Future.wait(
            eventsNeedImages.map((event) async {
              try {
                final imageId = 'event_img_${event.id}';
                final markerImage = await _createEventMarkerImage(event: event);

                await style.addStyleImage(
                  imageId,
                  2.0,
                  MbxImage(width: 120, height: 120, data: markerImage),
                  false,
                  [],
                  [],
                  null,
                );
                _addedImages.add(imageId);
              } catch (e) {
                print('❌ Error generating event marker for ${event.id}: $e');
              }
            }),
          );
        }
      }();

      final storyImagesFuture = () async {
        final storiesNeedImages = _stories.where((story) {
          final imageId = 'story_img_${story['id']}';
          return !_addedImages.contains(imageId);
        }).toList();

        if (storiesNeedImages.isNotEmpty) {
          print(
            '📸 Generating ${storiesNeedImages.length} story markers in parallel...',
          );
          await Future.wait(
            storiesNeedImages.map((story) async {
              try {
                final imageId = 'story_img_${story['id']}';
                final markerImage = await _createStoryMarkerImage(story: story);

                await style.addStyleImage(
                  imageId,
                  2.0,
                  MbxImage(width: 140, height: 140, data: markerImage),
                  false,
                  [],
                  [],
                  null,
                );
                _addedImages.add(imageId);
              } catch (e) {
                print('❌ Error generating story marker for ${story['id']}: $e');
              }
            }),
          );
        }
      }();

      // ═══ Mystery Marker Image Generation ═══
      final mysteryImagesFuture = () async {
        if (!_showIsochrone || activeMysteryTables.isEmpty) return;
        final mysteryNeedImages = activeMysteryTables.where((table) {
          final imageId = 'mystery_img_${table['id']}';
          return !_addedImages.contains(imageId);
        }).toList();

        if (mysteryNeedImages.isNotEmpty) {
          print('🔮 Generating ${mysteryNeedImages.length} mystery markers...');
          await Future.wait(
            mysteryNeedImages.map((table) async {
              try {
                final imageId = 'mystery_img_${table['id']}';
                final markerImage = await _createMysteryMarkerImage();

                await style.addStyleImage(
                  imageId,
                  2.0,
                  MbxImage(width: 120, height: 120, data: markerImage),
                  false,
                  [],
                  [],
                  null,
                );
                _addedImages.add(imageId);
              } catch (e) {
                print(
                  '❌ Error generating mystery marker for ${table['id']}: $e',
                );
              }
            }),
          );
        }
      }();

      // ✅ Wait for ALL marker types to finish simultaneously
      await Future.wait([
        tableImagesFuture,
        eventImagesFuture,
        storyImagesFuture,
        mysteryImagesFuture,
      ]);

      // --- Build feature data (fast, just data mapping) ---

      // Add table features
      for (var i = 0; i < fetchedTables.length; i++) {
        final table = fetchedTables[i];
        final imageId = 'table_img_${table['id']}';
        features.add({
          'type': 'Feature',
          'id': table['id'],
          'geometry': {
            'type': 'Point',
            'coordinates': [table['location_lng'], table['location_lat']],
          },
          'properties': {
            'icon_id': imageId,
            'description': table['venue_name'],
            'index': i,
            'type': table['is_experience'] == true ? 'experience' : 'table',
          },
        });
      }

      // Add mystery table features (only when pulse is active)
      if (_showIsochrone && activeMysteryTables.isNotEmpty) {
        for (var i = 0; i < activeMysteryTables.length; i++) {
          final table = activeMysteryTables[i];
          final imageId = 'mystery_img_${table['id']}';
          features.add({
            'type': 'Feature',
            'id': 'mystery_${table['id']}',
            'geometry': {
              'type': 'Point',
              'coordinates': [table['location_lng'], table['location_lat']],
            },
            'properties': {
              'icon_id': imageId,
              'description': 'Mystery Activity',
              'index': i,
              'type': 'mystery',
            },
          });
        }
        print('🔮 Added ${activeMysteryTables.length} mystery markers to map');
      }

      // Add event features (with spiderfy grouping logic)
      final Map<String, List<Event>> eventGroups = {};
      for (final event in _events) {
        final key =
            '${event.latitude.toStringAsFixed(6)},${event.longitude.toStringAsFixed(6)}';
        if (!eventGroups.containsKey(key)) {
          eventGroups[key] = [];
        }
        eventGroups[key]!.add(event);
      }

      for (final key in eventGroups.keys) {
        final group = eventGroups[key]!;
        final count = group.length;
        final firstEvent = group.first;

        // 1. Single Event
        if (count == 1) {
          final imageId = 'event_img_${firstEvent.id}';
          features.add({
            'type': 'Feature',
            'id': 'event_${firstEvent.id}',
            'geometry': {
              'type': 'Point',
              'coordinates': [firstEvent.longitude, firstEvent.latitude],
            },
            'properties': {
              'icon_id': imageId,
              'description': firstEvent.title,
              'index': _events.indexOf(firstEvent),
              'type': 'event',
            },
          });
        }
        // 2. Spiderfy (2-5 Events)
        else if (count <= 5) {
          final centerLat = firstEvent.latitude;
          final centerLng = firstEvent.longitude;
          final radius = 0.0002;

          for (var i = 0; i < count; i++) {
            final event = group[i];
            final imageId = 'event_img_${event.id}';
            final angle = (2 * pi * i) / count;
            final offsetLat = radius * cos(angle);
            final offsetLng = radius * sin(angle);

            features.add({
              'type': 'Feature',
              'id': 'event_${event.id}',
              'geometry': {
                'type': 'Point',
                'coordinates': [centerLng + offsetLng, centerLat + offsetLat],
              },
              'properties': {
                'icon_id': imageId,
                'description': event.title,
                'index': _events.indexOf(event),
                'type': 'event',
                'spiderfied': true,
              },
            });
          }
        }
        // 3. Venue Stack (6+ Events)
        else {
          final stackImageId = 'stack_img_${firstEvent.id}';

          if (!_addedImages.contains(stackImageId)) {
            try {
              final markerImage = await _createEventMarkerImage(
                event: firstEvent,
                badgeCount: count,
              );
              await style.addStyleImage(
                stackImageId,
                2.0,
                MbxImage(width: 120, height: 120, data: markerImage),
                false,
                [],
                [],
                null,
              );
              _addedImages.add(stackImageId);
            } catch (e) {
              print('❌ Error generating stack marker: $e');
            }
          }

          features.add({
            'type': 'Feature',
            'id': 'stack_${key}',
            'geometry': {
              'type': 'Point',
              'coordinates': [firstEvent.longitude, firstEvent.latitude],
            },
            'properties': {
              'icon_id': stackImageId,
              'description': '${firstEvent.venueName} (Cluster)',
              'count': count,
              'type': 'stack',
              'ids': group.map((e) => e.id).join(','),
            },
          });
        }
      }

      for (var i = 0; i < _stories.length; i++) {
        final story = _stories[i];
        final imageId = 'story_img_${story['id']}';
        features.add({
          'type': 'Feature',
          'id': 'story_${story['id']}',
          'geometry': {
            'type': 'Point',
            'coordinates': [story['longitude'], story['latitude']],
          },
          'properties': {
            'icon_id': imageId,
            'description': story['caption'] ?? 'Live Story',
            'index': i,
            'type': 'story',
          },
        });
      }

      // ─── Cross-Type Spiderfying ───
      // Group ALL features by rounded coordinate to detect overlaps across types.
      // Events already handle same-type overlap, so we only spiderfy when
      // DIFFERENT types share the same location (e.g. event + table + story).
      final Map<String, List<int>> coordGroups = {};
      for (var i = 0; i < features.length; i++) {
        final coords = features[i]['geometry']?['coordinates'] as List?;
        if (coords == null || coords.length < 2) continue;
        // Round to ~11m precision for grouping
        final key =
            '${(coords[1] as num).toStringAsFixed(4)},${(coords[0] as num).toStringAsFixed(4)}';
        coordGroups.putIfAbsent(key, () => []).add(i);
      }

      // Fan out groups that have mixed types overlapping
      for (final group in coordGroups.values) {
        if (group.length <= 1) continue;

        // Check if this group has multiple different types
        final types = group
            .map((i) => features[i]['properties']?['type'])
            .toSet();
        if (types.length <= 1)
          continue; // Same-type overlaps handled by their own logic

        // Fan them out in a circle
        final first = features[group.first];
        final centerCoords = first['geometry']?['coordinates'] as List;
        final centerLng = (centerCoords[0] as num).toDouble();
        final centerLat = (centerCoords[1] as num).toDouble();
        const radius = 0.00025; // ~25 meters

        for (var i = 0; i < group.length; i++) {
          final angle = (2 * pi * i) / group.length;
          final offsetLat = radius * cos(angle);
          final offsetLng = radius * sin(angle);

          features[group[i]]['geometry'] = {
            'type': 'Point',
            'coordinates': [centerLng + offsetLng, centerLat + offsetLat],
          };
        }

        print(
          '🕸️ Spiderfied ${group.length} mixed markers (${types.join(", ")})',
        );
      }

      // B. Update/Create Source
      const sourceId = 'tables-cluster-source';
      final sourceExists = await style.styleSourceExists(sourceId);

      // Apply active filter before encoding
      final filteredFeatures = _filterFeatures(features);

      final geoJsonData = jsonEncode({
        'type': 'FeatureCollection',
        'features': filteredFeatures,
      });

      print('📊 Generated ${features.length} GeoJSON features for clustering');

      if (!sourceExists) {
        print('🆕 Creating NEW cluster source: $sourceId');
        await style.addSource(
          GeoJsonSource(
            id: sourceId,
            data: geoJsonData,
            cluster: true,
            clusterRadius: 50, // Radius in pixels to cluster points
            clusterMaxZoom: 15, // Stop clustering at this zoom (show faces)
          ),
        );
        print('✅ Cluster source created');

        // C. Add Layers (Only once)
        print('🎨 Adding cluster layers...');
        await _addClusterLayers(style, sourceId);
        print('✅ Cluster layers added');
      } else {
        print('🔄 Updating EXISTING cluster source data');
        await style.setStyleSourceProperty(sourceId, 'data', geoJsonData);
        print('✅ Source data updated');
      }

      // C. Check if layers exist (independent of source - may be missing after hot reload)
      final layerExists = await style.styleLayerExists('unclustered-points');
      if (!layerExists) {
        print('🎨 Adding cluster layers (layers were missing)...');
        await _addClusterLayers(style, sourceId);
        print('✅ Cluster layers added');
      } else {
        print('✅ Cluster layers already exist');
      }

      print('✅ Updated Cluster Source with ${features.length} features');

      // Trigger "Spring Pop" Animation only when marker count changes
      if (features.length != _lastFeatureCount) {
        _lastFeatureCount = features.length;
        _startPopAnimation();
      }

      // 3D Models removed - no longer updating 3D layer
      // await _update3DLayerData(fetchedTables); // REMOVED
    } catch (e) {
      print('❌ Error updating map clusters: $e');
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<void> _addClusterLayers(StyleManager style, String sourceId) async {
    try {
      print(
        '🎨 _addClusterLayers called with style type: ${style.runtimeType}',
      );

      // 1. Cluster Circles (Bubbles)
      final clustersExists = await style.styleLayerExists('clusters');
      if (!clustersExists) {
        print(' Adding clusters layer...');
        await style.addLayer(
          CircleLayer(
            id: 'clusters',
            sourceId: sourceId,
            minZoom: 5.5, // Hide at country level
            maxZoom: 22,
            circleColor: Colors.deepPurpleAccent.value,
            circleRadius: 20.0,
            circleOpacity: 0.9,
            circleStrokeColor: Colors.white.value,
            circleStrokeWidth: 2.0,
            circleEmissiveStrength:
                1.0, // Added based on user request "light emmisive 1"
            filter: ['has', 'point_count'], // List<Object>
          ),
        );
        print('✅ Clusters layer added');
      }

      // 2. Cluster Counts (Text)
      final clusterCountExists = await style.styleLayerExists('cluster-count');
      if (!clusterCountExists) {
        print('➕ Adding cluster-count layer...');
        await style.addLayer(
          SymbolLayer(
            id: 'cluster-count',
            sourceId: sourceId,
            minZoom: 5.5, // Hide at country level
            maxZoom: 22,
            textFieldExpression: ['get', 'point_count_abbreviated'],
            textSize: 14.0,
            textColor: Colors.white.value,
            filter: ['has', 'point_count'], // List<Object>
          ),
        );
        print('✅ Cluster-count layer added');
      }

      // 3. Unclustered Points (Faces) with "Pop" Animation
      final unclusteredExists = await style.styleLayerExists(
        'unclustered-points',
      );
      if (!unclusteredExists) {
        print('➕ Adding unclustered-points layer...');
        await style.addLayer(
          SymbolLayer(
            id: 'unclustered-points',
            sourceId: sourceId,
            minZoom: 5.5, // Hide at country level
            maxZoom: 22,
            filter: [
              '!',
              ['has', 'point_count'],
            ], // List<Object>
            // Use the dynamic image ID we stored in properties
            iconImageExpression: ['get', 'icon_id'],
            iconSize: 1.0, // Base size
            iconAllowOverlap: true,
            iconAnchor: IconAnchor.BOTTOM,
            iconOffset: [0.0, -20.0], // Centered on table location
          ),
        );
        print('✅ Unclustered-points layer added');
      }
    } catch (e) {
      print('❌ Error in _addClusterLayers: $e');
      print('   Stack: ${StackTrace.current}');
      // Don't rethrow — layer errors shouldn't crash the whole map
    }
  }

  // --- EXPERIENCE MARKER (Map Pin with Photo) ---
  Future<Uint8List> _createExperienceMarkerImage({
    required Map<String, dynamic> table,
    required String glowColor,
    required double glowIntensity,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int size = 120; // Same size as other markers
    final double tailHeight = 16.0;
    final double totalHeight = size + tailHeight;
    final double borderRadius = 12.0;

    // Experience markers always use fixed amber — consistent brand color
    const Color color = Color(0xFFFF6F00); // Amber

    // 1. Build pin shape: rounded rect body + triangle tail
    final Path markerPath = Path();
    // Body
    markerPath.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Radius.circular(borderRadius),
      ),
    );
    // Tail
    markerPath.moveTo(size / 2 - 12, size.toDouble());
    markerPath.lineTo(size / 2, size + tailHeight);
    markerPath.lineTo(size / 2 + 12, size.toDouble());
    markerPath.close();

    // Drop shadow
    canvas.drawShadow(markerPath, Colors.black.withOpacity(0.5), 4.0, true);

    // Amber-tinted frame fill (gives experience pins a warm identity)
    final Paint framePaint = Paint()
      ..color =
          const Color(0xFFFFF8F0) // Very light amber tint
      ..style = PaintingStyle.fill;
    canvas.drawPath(markerPath, framePaint);

    // Amber border always visible (not conditional on glowIntensity)
    canvas.drawPath(
      markerPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // 2. Draw image content (clipped inside body)
    String? imageUrl = table['marker_image_url'];
    if (imageUrl == null &&
        table['images'] != null &&
        (table['images'] as List).isNotEmpty) {
      imageUrl = (table['images'] as List)[0];
    }

    try {
      if (imageUrl != null) {
        final response = await http.get(Uri.parse(imageUrl));
        final Uint8List bytes = response.bodyBytes;
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        final ui.Image image = frameInfo.image;

        final double padding = 6.0;
        final double imgSize = size - (padding * 2);

        canvas.save();
        canvas.clipPath(
          Path()..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(padding, padding, imgSize, imgSize),
              Radius.circular(borderRadius - 2),
            ),
          ),
        );
        paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(padding, padding, imgSize, imgSize),
          image: image,
          fit: BoxFit.cover,
        );
        canvas.restore();
      } else {
        _drawPlaceholder(canvas, size, table['activityType']);
      }
    } catch (e) {
      print('❌ Error loading experience image: $e');
      _drawPlaceholder(canvas, size, table['activityType']);
    }

    // 3. Price tag pill (dark, overlaid at bottom of image)
    if (table['price_per_person'] != null) {
      final double priceVal = (table['price_per_person'] as num).toDouble();
      final String currency = table['currency'] ?? 'PHP';
      final String priceText = '$currency ${priceVal.toStringAsFixed(0)}';

      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: priceText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      final double pw = tp.width + 14;
      final double ph = 20.0;
      final double px = (size - pw) / 2;
      final double py = size - ph - 10;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(px, py, pw, ph),
          const Radius.circular(10),
        ),
        Paint()..color = Colors.black.withOpacity(0.7),
      );
      tp.paint(canvas, Offset(px + 7, py + (ph - tp.height) / 2));
    }

    // 4b. Experience type badge in top-right corner
    {
      const double badgeR = 14.0;
      final Offset badgeCenter = Offset(size - 16.0, 16.0);
      canvas.drawCircle(badgeCenter, badgeR + 2, Paint()..color = Colors.white);
      canvas.drawCircle(badgeCenter, badgeR, Paint()..color = color);
      final TextPainter tp = TextPainter(
        text: const TextSpan(
          text: '✦',
          style: TextStyle(fontSize: 14, color: Colors.white),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(badgeCenter.dx - tp.width / 2, badgeCenter.dy - tp.height / 2),
      );
    }

    // Convert to image
    final ui.Image markerImg = await pictureRecorder.endRecording().toImage(
      size,
      totalHeight.toInt(),
    );
    final ByteData? byteData = await markerImg.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return byteData!.buffer.asUint8List();
  }

  // --- STORY MARKER (Round Avatar/Image with Purple Gradient Ring) ---
  Future<Uint8List> _createStoryMarkerImage({
    required Map<String, dynamic> story,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int baseSize = 120;
    final int canvasSize = 140; // Extra room for the attached badge
    final double padding = 8.0;

    final Offset mainCenter = Offset(baseSize / 2, baseSize / 2);

    // 1. Draw solid white background
    final Paint bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(mainCenter, baseSize / 2 - 4, bgPaint);

    // 2. Draw pink→orange→yellow gradient ring (Instagram-style "Moments")
    final double ringRadius = baseSize / 2 - 4;
    final Rect ringRect = Rect.fromCircle(
      center: mainCenter,
      radius: ringRadius,
    );
    final Paint ringPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0xFFFF0080), // Hot pink
          Color(0xFFFF6A00), // Orange
          Color(0xFFFFD600), // Yellow
          Color(0xFFFF0080), // Back to pink
        ],
        stops: const [0.0, 0.33, 0.66, 1.0],
      ).createShader(ringRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    canvas.drawCircle(mainCenter, ringRadius, ringPaint);
    // White gap between ring and content
    canvas.drawCircle(
      mainCenter,
      ringRadius - 5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 3. Draw image content (clipped to inner circle)
    String? imageUrl =
        story['image_url'] ?? story['thumbnail_url'] ?? story['media_url'];

    // Determine placeholder type: 🎬 for videos, 🙂 for others
    final placeholderType = story['video_url'] != null ? 'video' : 'social';

    try {
      if (imageUrl != null) {
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          final Uint8List bytes = response.bodyBytes;
          final ui.Codec codec = await ui.instantiateImageCodec(bytes);
          final ui.FrameInfo frameInfo = await codec.getNextFrame();
          final ui.Image image = frameInfo.image;

          final double imgSize = baseSize - (padding * 2);

          canvas.save();
          canvas.clipPath(
            Path()..addOval(
              Rect.fromCircle(center: mainCenter, radius: imgSize / 2),
            ),
          );
          paintImage(
            canvas: canvas,
            rect: Rect.fromLTWH(padding, padding, imgSize, imgSize),
            image: image,
            fit: BoxFit.cover,
          );
          canvas.restore();
        } else {
          _drawPlaceholder(canvas, baseSize, placeholderType);
        }
      } else {
        _drawPlaceholder(canvas, baseSize, placeholderType);
      }
    } catch (e) {
      print('❌ Error loading story image: $e');
      _drawPlaceholder(canvas, baseSize, placeholderType);
    }

    // 3b. Camera badge in top-left (marks this as a Story/Moment)
    {
      const double badgeR = 14.0;
      const Offset badgeCenter = Offset(22, 22);
      canvas.drawCircle(badgeCenter, badgeR + 2, Paint()..color = Colors.white);
      canvas.drawCircle(
        badgeCenter,
        badgeR,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFFF0080), Color(0xFFFF6A00)],
          ).createShader(Rect.fromCircle(center: badgeCenter, radius: badgeR)),
      );
      final TextPainter tp = TextPainter(
        text: const TextSpan(text: '📸', style: TextStyle(fontSize: 13)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(badgeCenter.dx - tp.width / 2, badgeCenter.dy - tp.height / 2),
      );
    }

    // 4. Draw author avatar overlapping bottom right
    String? authorAvatarUrl = story['author_avatar_url'];
    // Fallback if view doesn't have author_avatar_url yet
    if (authorAvatarUrl == null &&
        story['user_photos'] != null &&
        (story['user_photos'] as List).isNotEmpty) {
      authorAvatarUrl = (story['user_photos'] as List).first.toString();
    }
    authorAvatarUrl ??= story['avatar_url'];

    if (authorAvatarUrl != null) {
      try {
        final avatarResponse = await http.get(Uri.parse(authorAvatarUrl));
        if (avatarResponse.statusCode == 200) {
          final Uint8List aBytes = avatarResponse.bodyBytes;
          final ui.Codec aCodec = await ui.instantiateImageCodec(aBytes);
          final ui.FrameInfo aFrameInfo = await aCodec.getNextFrame();
          final ui.Image aImage = aFrameInfo.image;

          // Position at bottom right
          final Offset avatarCenter = const Offset(105, 105);
          final double avatarRadius = 24.0;

          // Draw white border
          canvas.drawCircle(
            avatarCenter,
            avatarRadius + 3.0,
            Paint()..color = Colors.white,
          );

          // Draw grey background/placeholder
          canvas.drawCircle(
            avatarCenter,
            avatarRadius,
            Paint()..color = Colors.grey.shade300,
          );

          canvas.save();
          canvas.clipPath(
            Path()..addOval(
              Rect.fromCircle(center: avatarCenter, radius: avatarRadius),
            ),
          );
          paintImage(
            canvas: canvas,
            rect: Rect.fromLTWH(
              avatarCenter.dx - avatarRadius,
              avatarCenter.dy - avatarRadius,
              avatarRadius * 2,
              avatarRadius * 2,
            ),
            image: aImage,
            fit: BoxFit.cover,
          );
          canvas.restore();
        }
      } catch (e) {
        print('❌ Error loading story author avatar: $e');
      }
    }

    // Convert to image
    final ui.Image markerImg = await pictureRecorder.endRecording().toImage(
      canvasSize,
      canvasSize,
    );
    final ByteData? byteData = await markerImg.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createCustomMarkerImage({
    required String imageUrl,
    String? activityType,
    required String glowColor,
    required double glowIntensity,
    int count = 1,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int size = 120; // Slightly larger for custom images

    // Default parsed hex color
    Color color = Color(int.parse(glowColor.replaceFirst('#', '0xFF')));

    // Override color based on Activity Type
    if (activityType != null) {
      final typeLower = activityType.toLowerCase();
      if (typeLower == 'experience') {
        color = const Color(0xFFFF9800); // Vibrant Orange for Experiences
      } else if (typeLower == 'event') {
        color = const Color(0xFFE040FB); // Bright Purple for Events
      } else {
        color = const Color(0xFF2979FF); // Bright Blue for default Activities
      }
    }

    // Draw outer glow ring with match-based or type-based color
    if (glowIntensity > 0 || activityType != null) {
      final Paint ringPaint = Paint()
        ..color = color.withOpacity(glowIntensity > 0 ? glowIntensity : 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4, 4, size - 8, size - 8),
          const Radius.circular(16),
        ),
        ringPaint,
      );
    }

    // Try to load custom image
    try {
      final response = await http.get(Uri.parse(imageUrl));
      final Uint8List bytes = response.bodyBytes;
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image customImage = frameInfo.image;

      // Draw rounded rectangle background
      final Paint bgPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(10, 10, size - 20, size - 20),
          const Radius.circular(12),
        ),
        bgPaint,
      );

      // Draw custom image with rounded corners
      canvas.save();
      final Path clipPath = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(12, 12, size - 24, size - 24),
            const Radius.circular(10),
          ),
        );
      canvas.clipPath(clipPath);
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(12, 12, size - 24, size - 24),
        image: customImage,
        fit: BoxFit.cover,
      );
      canvas.restore();
    } catch (e) {
      print('❌ Error loading custom marker image: $e');
      // Fallback to icon
      final Paint fallbackPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(10, 10, size - 20, size - 20),
          const Radius.circular(12),
        ),
        fallbackPaint,
      );
    }

    // Draw count badge if multiple tables
    if (count > 1) {
      final Paint badgePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(size - 20, 20), 15, badgePaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: count > 9 ? '9+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(size - 20 - textPainter.width / 2, 20 - textPainter.height / 2),
      );
    }

    // Convert to image
    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size,
      size,
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createTableMarkerImage({
    String? photoUrl,
    String? activityType, // Added activityType parameter
    required String glowColor,
    required double glowIntensity,
    int count = 1,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int size = 120;

    // Default parsed hex color
    Color color = Color(int.parse(glowColor.replaceFirst('#', '0xFF')));

    // Override color based on Activity Type
    if (activityType != null) {
      final typeLower = activityType.toLowerCase();
      if (typeLower == 'experience') {
        color = const Color(0xFFFF9800); // Vibrant Orange for Experiences
      } else if (typeLower == 'event') {
        color = const Color(0xFFE040FB); // Bright Purple for Events
      } else {
        color = const Color(0xFF2979FF); // Bright Blue for default Activities
      }
    }

    // Draw outer glow ring with match-based or type-based color
    if (glowIntensity > 0 || activityType != null) {
      final Paint ringPaint = Paint()
        ..color = color
            .withOpacity(
              glowIntensity > 0 ? glowIntensity : 0.8,
            ) // Use given intensity or default to strong glow for types
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8;

      canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 4, ringPaint);
    }

    // Draw white background
    final Paint bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 8, bgPaint);

    // Try to load host photo
    if (photoUrl != null) {
      try {
        final response = await http.get(Uri.parse(photoUrl));
        final Uint8List bytes = response.bodyBytes;
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        final ui.Image profileImage = frameInfo.image;

        // Draw circular clipped profile photo
        canvas.save();
        final Path clipPath = Path()
          ..addOval(
            Rect.fromCircle(
              center: Offset(size / 2, size / 2),
              radius: size / 2 - 12,
            ),
          );
        canvas.clipPath(clipPath);

        paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(12, 12, size - 24, size - 24),
          image: profileImage,
          fit: BoxFit.cover,
        );
        canvas.restore();
      } catch (e) {
        print('❌ Error loading host photo for marker: $e');
        _drawPlaceholder(canvas, size, activityType);
      }
    } else {
      _drawPlaceholder(canvas, size, activityType);
    }

    // Draw count badge if multiple tables
    if (count > 1) {
      final Paint badgePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(size - 15, 15), 12, badgePaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: count > 9 ? '9+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(size - 15 - textPainter.width / 2, 15 - textPainter.height / 2),
      );
    }

    // Convert to image
    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size,
      size,
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createEmojiMarkerImage({
    required String emoji,
    String? activityType,
    required String glowColor,
    required double glowIntensity,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int size = 120;

    // Default parsed hex color
    Color color = Color(int.parse(glowColor.replaceFirst('#', '0xFF')));

    // Override color based on Activity Type
    if (activityType != null) {
      final typeLower = activityType.toLowerCase();
      if (typeLower == 'experience') {
        color = const Color(0xFFFF9800); // Vibrant Orange for Experiences
      } else if (typeLower == 'event') {
        color = const Color(0xFFE040FB); // Bright Purple for Events
      } else {
        color = const Color(0xFF2979FF); // Bright Blue for default Activities
      }
    }

    // Draw outer glow ring
    if (glowIntensity > 0 || activityType != null) {
      final Paint ringPaint = Paint()
        ..color = color.withOpacity(glowIntensity > 0 ? glowIntensity : 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4, 4, size - 8, size - 8),
          const Radius.circular(16),
        ),
        ringPaint,
      );
    }

    // Draw white background
    final Paint bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 10, size - 20, size - 20),
        const Radius.circular(12),
      ),
      bgPaint,
    );

    // Draw Emoji
    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: size * 0.5),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();

    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    // Convert to image
    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size,
      size,
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  /// Creates a mystery marker image — purple glow ring with 🔮 emoji center.
  /// Used for tables with visibility = 'mystery', revealed via isochrone pulse.
  Future<Uint8List> _createMysteryMarkerImage() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const int size = 120;
    const mysteryColor = Color(0xFF7C3AED); // Violet-600

    // Outer glow ring — pulsing purple aura
    final Paint outerGlowPaint = Paint()
      ..color = mysteryColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 2, size - 4, size - 4),
        const Radius.circular(18),
      ),
      outerGlowPaint,
    );

    // Inner ring — solid purple
    final Paint ringPaint = Paint()
      ..color = mysteryColor.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 8, size - 16, size - 16),
        const Radius.circular(14),
      ),
      ringPaint,
    );

    // Dark background fill
    final Paint bgPaint = Paint()
      ..color =
          const Color(0xFF1E1033) // Deep purple-black
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 12, size - 24, size - 24),
        const Radius.circular(12),
      ),
      bgPaint,
    );

    // 🔮 Crystal ball emoji
    final textPainter = TextPainter(
      text: const TextSpan(text: '🔮', style: TextStyle(fontSize: 44)),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    // Convert to image
    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size,
      size,
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createEventMarkerImage({
    required Event event,
    int badgeCount = 1,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int size = 120; // Size of the marker

    // 1. Draw White Circle Background
    final Paint bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, bgPaint);

    // 2. Draw Image (Clip to Circle)
    if (event.coverImageUrl != null) {
      try {
        final response = await http.get(Uri.parse(event.coverImageUrl!));
        if (response.statusCode == 200) {
          final Uint8List bytes = response.bodyBytes;
          final ui.Codec codec = await ui.instantiateImageCodec(bytes);
          final ui.FrameInfo frameInfo = await codec.getNextFrame();
          final ui.Image image = frameInfo.image;

          canvas.save();
          final Path clipPath = Path()
            ..addOval(
              Rect.fromCircle(
                center: Offset(size / 2, size / 2),
                radius: (size / 2) - 4, // Slight padding
              ),
            );
          canvas.clipPath(clipPath);
          paintImage(
            canvas: canvas,
            rect: Rect.fromLTWH(4, 4, size - 8, size - 8),
            image: image,
            fit: BoxFit.cover,
          );
          canvas.restore();
        }
      } catch (e) {
        print('Error loading event image: $e');
      }
    }

    // 3. Draw Default Icon if no image
    if (event.coverImageUrl == null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '📅', // Calendar emoji
          style: TextStyle(fontSize: 60),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
      );
    }

    // 4. Draw Purple double-ring border (Events = Purple #7C4DFF)
    // Outer ring
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      (size / 2) - 1,
      Paint()
        ..color = const Color(0xFF7C4DFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    // Inner accent ring
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      (size / 2) - 9,
      Paint()
        ..color = const Color(0xFF7C4DFF).withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 4b. Ticket badge in top-left corner
    {
      const double badgeR = 14.0;
      const Offset badgeCenter = Offset(22, 22);
      // Purple circle bg
      canvas.drawCircle(badgeCenter, badgeR + 2, Paint()..color = Colors.white);
      canvas.drawCircle(
        badgeCenter,
        badgeR,
        Paint()..color = const Color(0xFF7C4DFF),
      );
      // Ticket emoji
      final TextPainter tp = TextPainter(
        text: const TextSpan(text: '🎟', style: TextStyle(fontSize: 14)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(badgeCenter.dx - tp.width / 2, badgeCenter.dy - tp.height / 2),
      );
    }

    // 5. Draw Badge (If count > 1)
    if (badgeCount > 1) {
      final double badgeSize = 40.0;
      final Paint badgeBgPaint = Paint()..color = Colors.red;

      // Draw badge at top-right
      canvas.drawCircle(Offset(size - 20, 20), badgeSize / 2, badgeBgPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: badgeCount > 9 ? '9+' : '$badgeCount',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          size - 20 - (textPainter.width / 2),
          20 - (textPainter.height / 2),
        ),
      );
    }

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size,
      size,
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  void _drawPlaceholder(Canvas canvas, int size, String? activityType) {
    // White background
    final Paint bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 8, bgPaint);

    // Determines emoji based on activity
    final String emoji = _getEmojiForActivity(activityType);

    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: size * 0.5),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();

    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );
  }

  String _getEmojiForActivity(String? activityType) {
    if (activityType == null) return '🙂';
    final lower = activityType.toLowerCase();
    if (lower == 'video') return '🎬';
    if (lower.contains('coffee') || lower.contains('cafe')) return '☕';
    if (lower.contains('work') ||
        lower.contains('coding') ||
        lower.contains('laptop'))
      return '💻';
    if (lower.contains('food') ||
        lower.contains('lunch') ||
        lower.contains('dinner'))
      return '🍔';
    if (lower.contains('drink') ||
        lower.contains('bar') ||
        lower.contains('beer'))
      return '🍺';
    if (lower.contains('study') ||
        lower.contains('read') ||
        lower.contains('book'))
      return '📚';
    if (lower.contains('game') || lower.contains('board')) return '🎲';
    return '🙂'; // Default fallback
  }

  void _onMapTapWrapper(MapContentGestureContext context) {
    print(
      '👆 Native Map Click received at: x=${context.touchPosition.x}, y=${context.touchPosition.y}',
    );
    _handleMapInteraction(context.touchPosition);
  }

  Future<void> _handleMapInteraction(ScreenCoordinate screenCoordinate) async {
    print(
      '🦾 Handling interaction at ${screenCoordinate.x}, ${screenCoordinate.y}',
    );
    if (_mapboxMap == null) return;

    try {
      // Query rendered features using the coordinate directly
      final features = await _mapboxMap?.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
        RenderedQueryOptions(
          layerIds: ['unclustered-points', 'clusters', 'tables-3d-layer'],
        ),
      );

      print('🔎 Query features found: ${features?.length ?? 0}');

      if (features != null && features.isNotEmpty) {
        final feature = features.first;
        final properties =
            feature?.queriedFeature.feature['properties'] as Map?;
        final isCluster = properties?['cluster'] == true;

        if (isCluster) {
          final geometry = feature?.queriedFeature.feature['geometry'] as Map?;
          final coordinates = geometry?['coordinates'] as List?;
          final cameraState = await _mapboxMap?.getCameraState();
          if (cameraState != null) {
            _mapboxMap?.flyTo(
              CameraOptions(
                center: Point(
                  coordinates: Position(
                    (coordinates?[0] as num).toDouble(),
                    (coordinates?[1] as num).toDouble(),
                  ),
                ),
                zoom: cameraState.zoom + 2.0,
                pitch: 60.0,
              ),
              MapAnimationOptions(duration: 500, startDelay: 0),
            );
          }
        } else {
          // CHECK FOR STACKED MARKERS (Overlap)
          // If multiple markers overlap at same location, show unified picker
          if (features.length > 1) {
            print('📚 Stacked markers tapped! Count: ${features.length}');
            final List<Map<String, dynamic>> stackedItems = [];

            for (final stackedFeature in features) {
              final props =
                  stackedFeature?.queriedFeature.feature['properties'] as Map?;
              final rawIdx = props?['index'];
              final idx = rawIdx != null
                  ? int.tryParse(rawIdx.toString())
                  : null;
              final type = props?['type'];

              if (type == 'event' && idx != null && idx < _events.length) {
                final event = _events[idx];
                stackedItems.add({
                  'id': event.id,
                  'title': event.title,
                  'datetime': event.startDatetime.toIso8601String(),
                  'current_capacity': event.ticketsSold,
                  'max_guests': event.capacity,
                  'location_name': event.venueName,
                  'type': 'event',
                  'original_object': event,
                });
              } else if (type == 'story' &&
                  idx != null &&
                  idx < _stories.length) {
                final story = _stories[idx];
                stackedItems.add({...story, 'type': 'story'});
              } else if (type == 'mystery' &&
                  idx != null &&
                  idx < _mysteryTables.length) {
                final table = _mysteryTables[idx];
                stackedItems.add({...table, 'type': 'table'});
              } else if ((type == 'table' || type == 'experience') &&
                  idx != null &&
                  idx < _tables.length) {
                final table = _tables[idx];
                stackedItems.add({...table, 'type': 'table'});
              }
            }

            if (stackedItems.isNotEmpty && mounted) {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => MapClusterSheet(
                  items: stackedItems,
                  currentUserData: _currentUserData,
                  matchingService: _matchingService,
                ),
              );
              return;
            }
          }

          // Single Marker Tap
          final rawIndex = properties?['index'];
          final index = rawIndex != null
              ? int.tryParse(rawIndex.toString())
              : null;
          final markerType = properties?['type'];
          print('🔖 Marker tapped with index: $index, type: $markerType');

          if (markerType == 'event' &&
              index != null &&
              index < _events.length) {
            final event = _events[index];
            print('🎟️ Opening event: ${event.title}');

            if (mounted) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => EventDetailModal(event: event),
              );
            }
          } else if (markerType == 'story' &&
              index != null &&
              index < _stories.length) {
            final story = _stories[index];
            if (mounted) {
              print('📸 Opening Location Story Viewer for: ${story['id']}');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LocationStoryViewerScreen(
                    initialStory: story,
                    clusterId:
                        story['external_place_id'] ??
                        story['event_id'] ??
                        story['table_id'],
                  ),
                ),
              );
            }
            return;
          } else if (markerType == 'mystery' &&
              index != null &&
              index < _mysteryTables.length) {
            final table = _mysteryTables[index];
            print('🔮 Opening mystery table: ${table['title']}');
            final matchData = _matchingService.calculateMatch(
              currentUser: _currentUserData!,
              table: table,
            );
            if (mounted) {
              _openTableModal(context, table, matchData, screenCoordinate);
            }
          } else if ((markerType == 'table' || markerType == 'experience') &&
              index != null &&
              index < _tables.length) {
            final table = _tables[index];
            print('🍽️ Opening table: ${table['title']}');

            final matchData = _matchingService.calculateMatch(
              currentUser: _currentUserData!,
              table: table,
            );
            if (mounted) {
              _openTableModal(context, table, matchData, screenCoordinate);
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error handling map tap: $e');
    }
  }

  // --- MARKER POP ANIMATION ---
  Timer? _popAnimationTimer;

  /// Animates markers from scale 0 → 1.15 → 0.95 → 1.0 (elastic bounce).
  /// Runs at 30fps to avoid overwhelming the Mapbox style engine on iOS.
  void _startPopAnimation() {
    _popAnimationTimer?.cancel();

    // Pre-computed keyframes: elastic overshoot curve sampled at 30fps over 500ms
    // Total ~15 frames. Each value is the iconSize at that frame.
    const List<double> keyframes = [
      0.00, 0.15, 0.35, 0.58, 0.80, // Ramp up (0-166ms)
      1.00, 1.10, 1.15, // Overshoot peak (200-266ms)
      1.10, 1.02, 0.95, // Settle back (300-366ms)
      0.97, 1.00, 1.00, 1.00, // Final settle (400-500ms)
    ];

    int frame = 0;

    // Set initial scale to 0 immediately
    _updateLayerScale(0.0);

    _popAnimationTimer = Timer.periodic(
      const Duration(milliseconds: 33), // ~30fps
      (timer) {
        if (!mounted || _mapboxMap == null) {
          timer.cancel();
          return;
        }

        if (frame >= keyframes.length) {
          _updateLayerScale(1.0); // Ensure final state
          timer.cancel();
          return;
        }

        _updateLayerScale(keyframes[frame]);
        frame++;
      },
    );
  }

  void _updateLayerScale(double scale) {
    try {
      final style = _mapboxMap?.style;
      if (style == null) return;

      // Scale unclustered marker icons
      style.setStyleLayerProperty('unclustered-points', 'icon-size', scale);

      // Scale cluster circles (base radius = 20)
      style.setStyleLayerProperty('clusters', 'circle-radius', 20.0 * scale);

      // Scale cluster count text (base size = 14)
      style.setStyleLayerProperty('cluster-count', 'text-size', 14.0 * scale);
    } catch (e) {
      // Silently ignore — layer may not exist yet during init
    }
  }

  // End of MapScreenState

  // ========================
  // ISOCHRONE CIRCLE LAYER
  // ========================

  /// Generates a GeoJSON Polygon circle with [numPoints] vertices.
  Map<String, dynamic> _buildCircleGeoJson(
    double lat,
    double lng,
    double radiusMeters, {
    int numPoints = 64,
  }) {
    const double earthRadius = 6371000; // meters
    final List<List<double>> coords = [];

    for (int i = 0; i <= numPoints; i++) {
      final angle = (2 * pi * i) / numPoints;
      final dLat = radiusMeters / earthRadius * (180 / pi);
      final dLng =
          radiusMeters / (earthRadius * cos(lat * pi / 180)) * (180 / pi);
      coords.add([lng + dLng * cos(angle), lat + dLat * sin(angle)]);
    }

    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [coords],
          },
          'properties': {},
        },
      ],
    };
  }

  Future<void> _showIsochroneExplainer() async {
    final prefs = await SharedPreferences.getInstance();
    final skip = prefs.getBool('isochrone_explainer_skip') ?? false;
    if (skip) {
      _toggleIsochrone();
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
        bool dontShowAgain = false;
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radar,
                      size: 32,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title
                  const Text(
                    'Unlock Hidden Activities',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  // Description
                  Text(
                    'Some hangouts, experiences, and events are hidden on the map — they only reveal themselves to people who are within walking distance.\n\nActivate your walking zone to uncover what\'s secret nearby.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tip row
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_open,
                          size: 18,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Only visible to people within a 15 min walk',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.indigo[200]
                                  : Colors.indigo[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // CTA button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (dontShowAgain) {
                          await prefs.setBool('isochrone_explainer_skip', true);
                        }
                        Navigator.pop(ctx2);
                        _toggleIsochrone();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Reveal Hidden Activities',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Don't show again
                  GestureDetector(
                    onTap: () =>
                        setModalState(() => dontShowAgain = !dontShowAgain),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: dontShowAgain,
                            onChanged: (v) =>
                                setModalState(() => dontShowAgain = v ?? false),
                            activeColor: Colors.indigo,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Don't show this again",
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleIsochrone({bool forceRefresh = false}) async {
    if (_showIsochrone && !forceRefresh) {
      await _removeIsochrone();
      setState(() {
        _showIsochrone = false;
        _mysteryTables = []; // Clear mystery markers when pulse deactivated
      });
      // Re-render to remove mystery markers from GeoJSON
      _lastFetchCameraState = null; // Force re-fetch
      _fetchTablesInViewport();
      return;
    }

    if (_currentPosition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not available yet')),
        );
      }
      return;
    }

    setState(() => _showIsochrone = true);

    try {
      // ~80 meters per minute walking speed
      final radiusMeters = _isochroneMinutes * 80.0;

      final geoJson = _buildCircleGeoJson(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        radiusMeters,
      );

      if (_mapboxMap == null) return;
      final style = _mapboxMap!.style;
      final geoJsonStr = jsonEncode(geoJson);

      const sourceId = 'isochrone-source';
      const fillLayerId = 'isochrone-fill';
      const lineLayerId = 'isochrone-outline';

      await _removeIsochrone();

      await style.addSource(GeoJsonSource(id: sourceId, data: geoJsonStr));

      // Base fill — subtle indigo wash
      const fillColor = Color(0xFF3F51B5);
      const lineColor = Color(0xCC3F51B5);

      await style.addLayerAt(
        FillLayer(
          id: fillLayerId,
          sourceId: sourceId,
          fillColor: fillColor.value,
          fillOpacity: 0.12,
        ),
        LayerPosition(below: 'clusters'),
      );

      await style.addLayerAt(
        LineLayer(
          id: lineLayerId,
          sourceId: sourceId,
          lineColor: lineColor.value,
          lineWidth: 2.0,
        ),
        LayerPosition(below: 'clusters'),
      );

      // Add 2 ripple ring sources + layers
      for (int i = 0; i < 2; i++) {
        final rippleSourceId = 'isochrone-ripple-$i';
        final rippleLayerId = 'isochrone-ripple-line-$i';

        // Start with a tiny circle (will be expanded by animation)
        final tinyCircle = _buildCircleGeoJson(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          1.0, // 1 meter — basically invisible
        );

        await style.addSource(
          GeoJsonSource(id: rippleSourceId, data: jsonEncode(tinyCircle)),
        );

        await style.addLayerAt(
          LineLayer(
            id: rippleLayerId,
            sourceId: rippleSourceId,
            lineColor: fillColor.value,
            lineWidth: 3.0,
            lineOpacity: 0.0, // Starts invisible
          ),
          LayerPosition(below: 'clusters'),
        );
      }

      print(
        '✅ Isochrone circle: ${_isochroneMinutes}min / ${radiusMeters.toInt()}m radius',
      );

      // Start ripple scan animation
      _startIsochronePulse();

      // ═══ Mystery Tables: Re-fetch to reveal hidden tables in range ═══
      _lastFetchCameraState = null; // Force re-fetch
      _fetchTablesInViewport();
    } catch (e) {
      print('❌ Isochrone toggle error: $e');
    }
  }

  Future<void> _removeIsochrone() async {
    _stopIsochronePulse();
    if (_mapboxMap == null) return;
    final style = _mapboxMap!.style;

    try {
      // Remove ripple layers & sources
      for (int i = 0; i < 2; i++) {
        final rippleLayerId = 'isochrone-ripple-line-$i';
        final rippleSourceId = 'isochrone-ripple-$i';
        if (await style.styleLayerExists(rippleLayerId)) {
          await style.removeStyleLayer(rippleLayerId);
        }
        if (await style.styleSourceExists(rippleSourceId)) {
          await style.removeStyleSource(rippleSourceId);
        }
      }

      if (await style.styleLayerExists('isochrone-fill')) {
        await style.removeStyleLayer('isochrone-fill');
      }
      if (await style.styleLayerExists('isochrone-outline')) {
        await style.removeStyleLayer('isochrone-outline');
      }
      if (await style.styleSourceExists('isochrone-source')) {
        await style.removeStyleSource('isochrone-source');
      }
    } catch (e) {
      print('⚠️ Isochrone remove error: $e');
    }
  }

  // ── Ripple Scanning Animation ──

  void _startIsochronePulse() {
    _stopIsochronePulse();
    _isochronePulsePhase = 0.0;

    final fullRadius = _isochroneMinutes * 80.0;

    // ~15fps — smooth enough, light on the style engine
    _isochronePulseTimer = Timer.periodic(const Duration(milliseconds: 66), (
      _,
    ) {
      if (!mounted ||
          _mapboxMap == null ||
          !_showIsochrone ||
          _currentPosition == null) {
        _stopIsochronePulse();
        return;
      }

      // Advance phase: one full ripple cycle ~4 seconds (60 ticks * 66ms ≈ 4s)
      _isochronePulsePhase += 1.0 / 60.0;
      if (_isochronePulsePhase > 1.0) _isochronePulsePhase -= 1.0;

      try {
        final style = _mapboxMap!.style;

        // Two ripple rings, staggered 50% apart
        for (int i = 0; i < 2; i++) {
          // Each ring's progress: 0 → 1, offset by 0.5
          double progress = (_isochronePulsePhase + i * 0.5) % 1.0;

          // Ring expands from 10% to 100% of full radius
          final radius = fullRadius * (0.1 + 0.9 * progress);

          // Opacity: fade in quickly then fade out as it expands
          // Peak at ~20% progress, gone by 100%
          double opacity;
          if (progress < 0.2) {
            opacity = progress / 0.2 * 0.6; // Ramp up to 0.6
          } else {
            opacity = 0.6 * (1.0 - (progress - 0.2) / 0.8); // Fade to 0
          }

          // Line width: thicker at start, thinner as it expands
          final lineWidth = 4.0 * (1.0 - progress * 0.7);

          // Update the ring's geometry
          final circleGeoJson = _buildCircleGeoJson(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            radius,
          );

          final sourceId = 'isochrone-ripple-$i';
          final layerId = 'isochrone-ripple-line-$i';

          style.setStyleSourceProperty(
            sourceId,
            'data',
            jsonEncode(circleGeoJson),
          );
          style.setStyleLayerProperty(layerId, 'line-opacity', opacity);
          style.setStyleLayerProperty(layerId, 'line-width', lineWidth);
        }
      } catch (_) {
        // Layer may have been removed
      }
    });
  }

  void _stopIsochronePulse() {
    _isochronePulseTimer?.cancel();
    _isochronePulseTimer = null;
  }
}
