import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math';

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
import 'package:bitemates/features/map/widgets/event_cluster_sheet.dart';
import 'package:bitemates/features/experiences/widgets/experience_detail_modal.dart';

// Filter enum for toggling between tables and events
enum MapFilter { all, tables, events }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

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

  List<Map<String, dynamic>> _tables = [];
  List<Event> _events = [];
  Map<String, dynamic>? _currentUserData;
  Timer? _debounceTimer;
  CameraState? _lastFetchCameraState;

  Timer? _heartbeatTimer;
  int _activeUserCount = 0;
  bool _isFetching = false;
  bool _showCloudIntro = true;

  // Filter toggle
  MapFilter _currentFilter = MapFilter.all;

  // Optimization: Track added images to avoid re-uploading
  final Set<String> _addedImages = {};
  static const int _maxCachedImages = 200; // Prevent memory leak

  // Experience route polyline
  PolylineAnnotationManager? _routePolylineManager;
  CameraState?
  _preFlyCamera; // To restore camera after dismissing experience sheet

  @override
  bool get wantKeepAlive => true;

  // ... (initState, dispose, etc)

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _loadCurrentUserData();
    _startHeartbeat();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    // _popAnimationTimer?.cancel();
    _heartbeatTimer?.cancel();
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

      // 4. Open Modal
      if (mounted) {
        // Center of screen for morph effect
        final size = MediaQuery.of(context).size;
        final center = Offset(size.width / 2, size.height / 2);

        Navigator.of(context).push(
          LiquidMorphRoute(
            center: center,
            page: TableCompactModal(table: table, matchData: matchData),
          ),
        );
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

      // Update map camera with the user's current location
      if (_mapboxMap != null) {
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

    // Intro Animation
    _playIntroAnimation();
  }

  Future<void> _playIntroAnimation() async {
    // Sync with Cloud Dive (starts at 200ms, takes 3s)
    await Future.delayed(const Duration(milliseconds: 200));
    _mapboxMap?.flyTo(
      CameraOptions(
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
          if (_activeUserCount > 0)
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

          // Map Controls (upper-right)
          Positioned(
            right: 16,
            top: 110, // Below the "active users" pill (which is at top: 60)
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
              ],
            ),
          ),

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
                // Convert Event to Map for Cluster Sheet
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
              } else if (index != null &&
                  index is int &&
                  index < _tables.length) {
                // Add Table
                final table = _tables[index];
                stackedItems.add({
                  ...table,
                  'type': 'table', // specific marker for sheet to know
                });
              }
            }

            if (stackedItems.isNotEmpty && mounted) {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => EventClusterSheet(events: stackedItems),
              );
              return; // Stop processing single tap
            }
          }

          // Single Marker Tap (Fallback)
          final properties =
              feature?.queriedFeature.feature['properties'] as Map?;
          final index = properties?['index'];
          final markerType =
              properties?['type']; // Check if it's an event marker

          if (markerType == 'event' &&
              index != null &&
              index is int &&
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
          } else if (index != null && index is int && index < _tables.length) {
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
        final index = properties?['index'];
        final markerType = properties?['type'];

        print('🔍 Marker properties: index=$index, type=$markerType');
        print(
          '📊 _events.length=${_events.length}, _tables.length=${_tables.length}',
        );

        if ((markerType == 'event' || markerType == 'stack') &&
            index != null &&
            index is int) {
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
                builder: (context) => EventClusterSheet(events: stackedItems),
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
        } else if (index != null && index is int && index < _tables.length) {
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
    // Calculate center offset from tap position
    final center = Offset(tapPosition.x, tapPosition.y);

    Navigator.of(context).push(
      LiquidMorphRoute(
        center: center,
        page: TableCompactModal(table: table, matchData: matchData),
      ),
    );
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
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => EventClusterSheet(events: eventsInCluster),
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

        // Thresholds: 2km or 1.0 zoom level change (increased to reduce DB queries)
        if (dist < 5000 && zoomDiff < 2.0) {
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

      // Parallel Fetch: Get Tables and Events concurrently
      final results = await Future.wait([
        _tableService.getMapReadyTables(
          userLat: _currentPosition?.latitude,
          userLng: _currentPosition?.longitude,
          minLat: minLat,
          maxLat: maxLat,
          minLng: minLng,
          maxLng: maxLng,
          limit: 100,
        ),
        _eventService.getEventsInViewport(
          minLat: minLat,
          maxLat: maxLat,
          minLng: minLng,
          maxLng: maxLng,
        ),
      ]);

      var fetchedTables = results[0] as List<Map<String, dynamic>>;
      final fetchedEvents = results[1] as List<Event>;

      print('📍 Found ${fetchedTables.length} tables in viewport');
      print('📅 Found ${fetchedEvents.length} events in viewport');

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

      // DUMMY DATA FOR TESTING EXPERIENCES
      fetchedTables.add({
        'id': '123e4567-e89b-12d3-a456-426614174000', // Valid UUID format
        'location_lat': 14.5547,
        'location_lng': 121.0244, // Makati
        'venue_name': 'Pottery Workshop',
        'description': 'Learn to make your own mugs!',
        'is_experience': true,
        'experience_type': 'workshop',
        'price_per_person': 2500,
        'currency': 'PHP',
        'images': [
          'https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&q=80',
        ],
        'marker_image_url':
            'https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?ixlib=rb-4.0.3&auto=format&fit=crop&w=200&q=80',
      });

      setState(() {
        _tables = fetchedTables;
        _events = fetchedEvents;
      });

      // 5. Clustering & Native Layers Implementation
      final style = _mapboxMap?.style;
      if (style == null) return;

      if (_tableMarkerManager != null) {
        _tableMarkerManager?.deleteAll();
        _tableMarkerManager = null;
      }

      final features = <Map<String, dynamic>>[];

      // --- Parallel Marker Generation: Tables ---
      // Filter out tables that already have images to avoid re-processing
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
                // --- EXPERIENCE MARKER ---
                markerImage = await _createExperienceMarkerImage(
                  table: table,
                  glowColor: matchData['color'],
                  glowIntensity: matchData['glowIntensity'],
                );
              } else if (markerImageUrl != null &&
                  markerImageUrl.toString().isNotEmpty) {
                markerImage = await _createCustomMarkerImage(
                  imageUrl: markerImageUrl,
                  glowColor: matchData['color'],
                  glowIntensity: matchData['glowIntensity'],
                  count: 1,
                );
              } else if (markerEmoji != null &&
                  markerEmoji.toString().isNotEmpty) {
                markerImage = await _createEmojiMarkerImage(
                  emoji: markerEmoji,
                  glowColor: matchData['color'],
                  glowIntensity: matchData['glowIntensity'],
                );
              } else {
                markerImage = await _createTableMarkerImage(
                  photoUrl: table['host_photo_url'],
                  activityType: table['activityType'],
                  glowColor: matchData['color'],
                  glowIntensity: matchData['glowIntensity'],
                  count: 1,
                );
              }

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
              print('❌ Error generating table marker for ${table['id']}: $e');
            }
          }),
        );
      }

      // Add table features (fast, just data mapping)
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
          },
        });
      }

      // --- Parallel Marker Generation: Events ---
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

      // Tracking groups by coordinate
      final Map<String, List<Event>> eventGroups = {};
      for (final event in _events) {
        final key =
            '${event.latitude.toStringAsFixed(6)},${event.longitude.toStringAsFixed(6)}';
        if (!eventGroups.containsKey(key)) {
          eventGroups[key] = [];
        }
        eventGroups[key]!.add(event);
      }

      // Generate Features based on Hybrid Logic
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
        // 2. Spiderfy (2-5 Events) - "Fan Out"
        else if (count <= 5) {
          final centerLat = firstEvent.latitude;
          final centerLng = firstEvent.longitude;
          final radius = 0.0002; // Approx 20-25 meters

          for (var i = 0; i < count; i++) {
            final event = group[i];
            final imageId = 'event_img_${event.id}';

            // Calculate spiral/circle position
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
                'type': 'event', // Treat as normal event so tap opens detail
                'spiderfied': true, // Tag for potential styling
              },
            });
          }
        }
        // 3. Venue Stack (6+ Events)
        else {
          // Generate a custom "Stack" marker image if not exists
          // We use the first event's ID for the image cache key but append '_stack'
          final stackImageId = 'stack_img_${firstEvent.id}';

          if (!_addedImages.contains(stackImageId)) {
            try {
              // Generate marker with Badge
              final markerImage = await _createEventMarkerImage(
                event: firstEvent,
                badgeCount:
                    count, // We need to update _createEventMarkerImage signature or handle this
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
              'type': 'stack', // Special type for tap handling
              'ids': group
                  .map((e) => e.id)
                  .join(','), // Store IDs to retrieve later
            },
          });
        }
      }

      // B. Update/Create Source
      const sourceId = 'tables-cluster-source';
      final sourceExists = await style.styleSourceExists(sourceId);

      final geoJsonData = jsonEncode({
        'type': 'FeatureCollection',
        'features': features,
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

      // Trigger "Spring Pop" Animation now that data is on map
      // _startPopAnimation(); // DISABLED: Causing crash on iOS Simulator

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

      // 2. Cluster Counts (Text)
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

      // 3. Unclustered Points (Faces) with "Pop" Animation
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
    } catch (e) {
      print('❌ Error in _addClusterLayers: $e');
      print('   Stack: ${StackTrace.current}');
      rethrow;
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

    // Parse hex color
    final color = Color(int.parse(glowColor.replaceFirst('#', '0xFF')));

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

    // White frame fill
    final Paint framePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(markerPath, framePaint);

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

    // 4. Glow border (follows pin shape)
    if (glowIntensity > 0) {
      canvas.drawPath(
        markerPath,
        Paint()
          ..color = color.withOpacity(glowIntensity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
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

  Future<Uint8List> _createCustomMarkerImage({
    required String imageUrl,
    required String glowColor,
    required double glowIntensity,
    int count = 1,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int size = 120; // Slightly larger for custom images

    // Parse hex color
    final color = Color(int.parse(glowColor.replaceFirst('#', '0xFF')));

    // Draw outer glow ring with match-based color
    if (glowIntensity > 0) {
      final Paint ringPaint = Paint()
        ..color = color.withOpacity(glowIntensity)
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

    // Parse hex color
    final color = Color(int.parse(glowColor.replaceFirst('#', '0xFF')));

    // Draw outer glow ring with match-based color
    if (glowIntensity > 0) {
      final Paint ringPaint = Paint()
        ..color = color.withOpacity(glowIntensity)
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
    required String glowColor,
    required double glowIntensity,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int size = 120;

    // Parse hex color
    final color = Color(int.parse(glowColor.replaceFirst('#', '0xFF')));

    // Draw outer glow ring
    if (glowIntensity > 0) {
      final Paint ringPaint = Paint()
        ..color = color.withOpacity(glowIntensity)
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

    // 4. Draw Border Ring
    final Paint borderPaint = Paint()
      ..color = Colors
          .black // Dark border for contrast
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawCircle(Offset(size / 2, size / 2), (size / 2) - 2, borderPaint);

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

  void _drawTicketIconFallback(Canvas canvas, int size) {
    // Draw ticket/event icon (🎟️) as fallback
    final textPainter = TextPainter(
      text: const TextSpan(text: '🎟️', style: TextStyle(fontSize: 50)),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();

    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );
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
          final index = properties?['index'];
          final markerType = properties?['type'];
          print('🔖 Marker tapped with index: $index, type: $markerType');

          if (markerType == 'event' &&
              index != null &&
              index is int &&
              index < _events.length) {
            // Event marker tapped
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
          } else if (index != null && index is int && index < _tables.length) {
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

  // --- MARKER POP ANIMATION LOGIC (DISABLED) ---
  /*
  Timer? _popAnimationTimer;
  double _markerScale = 0.0;
  int _animationStep = 0;

  void _startPopAnimation() {
    print('💥 _startPopAnimation started');
    _popAnimationTimer?.cancel();
    _animationStep = 0;

    // Simple spring simulation 0 -> 1.2 -> 1.0
    // We'll run at 60fps (16ms) for ~500ms
    _popAnimationTimer = Timer.periodic(const Duration(milliseconds: 16), (
      timer,
    ) {
      if (!mounted || _mapboxMap?.style == null) {
        timer.cancel();
        return;
      }

      _animationStep++;

      // Elastic Out Curve Approximation
      // t goes from 0.0 to 1.0 over approx 40 steps (640ms)
      double t = (_animationStep * 16) / 600.0;
      if (t > 1.0) {
        _markerScale = 1.0;
        _updateLayerScale(_markerScale);
        timer.cancel();
        return;
      }

      // Physics: Overshoot
      if (t < 0.3) {
        // First 30% time: Shoot up to 1.2
        _markerScale = (t / 0.3) * 1.2;
      } else if (t < 0.6) {
        // Next 30%: 1.2 down to 0.9
        _markerScale = 1.2 - ((t - 0.3) / 0.3) * 0.3;
      } else {
        // Final: 0.9 up to 1.0
        _markerScale = 0.9 + ((t - 0.6) / 0.4) * 0.1;
      }

      _updateLayerScale(_markerScale);
    });
  }

  void _updateLayerScale(double scale) {
    try {
      final style = _mapboxMap?.style;
      if (style == null) return;

      // 1. Scale Unclustered Points (Icons)
      style.setStyleLayerProperty('unclustered-points', 'icon-size', scale);

      // 2. Scale Clusters (Bubbles)
      // Base radius is 20, so we multiply
      style.setStyleLayerProperty('clusters', 'circle-radius', 20.0 * scale);

      // 3. Scale Cluster Text (Counts)
      style.setStyleLayerProperty('cluster-count', 'text-size', 14.0 * scale);
    } catch (e) {
      // Ignored
    }
  }
  */

  // End of MapScreenState
}
