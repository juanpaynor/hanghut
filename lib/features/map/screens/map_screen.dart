import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:http/http.dart' as http;
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/matching_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../widgets/liquid_morph_route.dart';
import '../widgets/table_compact_modal.dart';
import 'package:bitemates/features/map/widgets/active_users_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/features/profile/screens/profile_setup_screen.dart';
import 'package:bitemates/providers/theme_provider.dart';
import 'package:bitemates/core/constants/model_registry.dart';
import 'package:bitemates/features/splash/screens/cloud_opening_screen.dart';

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
  List<Map<String, dynamic>> _tables = [];
  Map<String, dynamic>? _currentUserData;
  Timer? _debounceTimer;
  CameraState? _lastFetchCameraState;

  Timer? _heartbeatTimer;
  int _activeUserCount = 0;
  bool _isFetching = false; // Added loading state
  Set<String> _last3DTableIds = {}; // Cache to prevent unnecessary 3D rebuilds
  bool _showCloudIntro = true; // For cloud transition

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
    _popAnimationTimer?.cancel();
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

      // Fetch count
      final count = await SupabaseConfig.client.rpc('get_active_user_count');
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

      setState(() {
        _currentUserData = response;
      });

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

  Future<String> _copyAssetToTemp(String assetName, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    // Always overwrite to ensure latest version
    final data = await rootBundle.load(assetName);
    final bytes = data.buffer.asUint8List();
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  _onMapCreated(MapboxMap mapboxMap) async {
    print('🗺️ Map created callback triggered');
    _mapboxMap = mapboxMap;
    _addedImages
        .clear(); // Clear local cache to force re-add images to new style

    // Register Tap Listener handled via GestureDetector in build

    // Enable location puck
    await _enableLocationPuck();

    // Initialize 3D Models
    await _setup3DModels();

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

  Future<void> _setup3DModels() async {
    if (_mapboxMap == null) return;

    try {
      final style = _mapboxMap?.style;

      // 1. Load ALL Models from Registry
      // We iterate through our known assets and load them into the style
      // This is efficient because we only load unique models once
      final modelsToLoad = {
        'tennis_racket.glb': 'tennis-racket-model',
        'basketball.glb': 'basketball-model',
        'soccer_ball.glb': 'soccer-ball-model',
        'burger.glb': 'burger-model',
        'pizza.glb': 'pizza-model',
        'chinese_food_box.glb': 'chinese-food-model',
        'creamed_coffee.glb': 'creamed-coffee-model',
        'coffee_shop_cup.glb': 'coffee-shop-model',
        'arrow.glb': 'arrow-model',
      };

      for (final entry in modelsToLoad.entries) {
        final assetName = entry.key;
        final modelId = entry.value;

        try {
          // Check if model already exists (optional optimization, but addStyleModel handles duplicates gracefully usually)
          // Actually, Mapbox style API throws if you add duplicate ID.
          // There isn't a direct 'hasModel' check exposed easily in this SDK wrapper typically,
          // avoiding complex checks by wrapping in try-catch or just adding.
          // Let's use the temp file approach for robustness

          final modelPath = await _copyAssetToTemp(
            'assets/models/$assetName',
            assetName,
          );
          print('📦 Loaded 3D Model: $assetName -> $modelId');
          await style?.addStyleModel(modelId, 'file://$modelPath');
        } catch (e) {
          // Ignore "already exists" errors or similar
          print('⚠️ Note loading $assetName: $e');
        }
      }

      // 2. Add GeoJSON Source for 3D markers
      if (await style?.styleSourceExists('tables-3d-source') == false) {
        await style?.addSource(
          GeoJsonSource(
            id: 'tables-3d-source',
            data: jsonEncode({'type': 'FeatureCollection', 'features': []}),
          ),
        );
      }

      // 3. Add Model Layer
      if (await style?.styleLayerExists('tables-3d-layer') == false) {
        await style?.addLayer(
          ModelLayer(
            id: 'tables-3d-layer',
            sourceId: 'tables-3d-source',
            minZoom: 5.5, // Hide at country level
            maxZoom: 22.0,
            modelId:
                'coffee-shop-model', // Default; overridden by property below
            // Massive scale increase
            modelScale: [1500.0, 1500.0, 1500.0],
            // Lift it up significantly + slight tilt
            modelRotation: [0.0, 0.0, 0.0],
            // Lift significantly higher to account for massive scale pushing geometry down
            // Reduced height since we are reducing the scale
            // Lift significantly higher (50m vertical offset)
            modelTranslation: [0.0, 0.0, 50.0],
            // Using model-scale as main visibility driver first.
            modelOpacity: 1.0,
            modelEmissiveStrength: 1.0,
          ),
        );

        // 5. Update 'model-id' with expression for dynamic switching
        await style?.setStyleLayerProperty(
          'tables-3d-layer',
          'model-id',
          jsonEncode(['get', 'modelId']),
        );
      }

      // 4. Update 'model-scale' with Fixed Scaling.
      // NOTE: Mapbox does NOT support zoom interpolation for model-scale with GeoJSON sources!
      // Using fixed scale values instead.

      final fixedScales = {
        'tennis-racket-model': [
          1.0,
          1.0,
          1.0,
        ], // No scaling - using base model size
        'basketball-model': [500.0, 500.0, 500.0],
        'soccer-ball-model': [500.0, 500.0, 500.0],
        'arrow-model': [4000.0, 4000.0, 4000.0],
        'burger-model': [800.0, 800.0, 800.0],
        'pizza-model': [800.0, 800.0, 800.0],
        'chinese-food-model': [800.0, 800.0, 800.0],
        'creamed-coffee-model': [800.0, 800.0, 800.0],
        'coffee-shop-model': [800.0, 800.0, 800.0],
      };

      final matchCases = <Object>[];
      fixedScales.forEach((id, scale) {
        matchCases.add(id);
        matchCases.add(scale);
      });

      // Default Fallback
      matchCases.add([1000.0, 1000.0, 1000.0]);

      try {
        await style?.setStyleLayerProperty(
          'tables-3d-layer',
          'model-scale',
          jsonEncode([
            "match",
            ["get", "modelId"],
            ...matchCases,
          ]),
        );
      } catch (e) {
        print('⚠️ Failed to set model-scale expression: $e');
      }

      print('✅ 3D Model Layer initialized');

      // Manual listener removed in favor of MapWidget.onTapListener
    } catch (e) {
      print('❌ Error setting up 3D models: $e');
      print('   Stack: ${StackTrace.current}');
      rethrow;
    }
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
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (context) => const ActiveUsersBottomSheet(),
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

  // Handle map taps
  Future<void> _onMapTap(TapUpDetails details) async {
    print('👆 Map tapped at ${details.localPosition}');
    if (_mapboxMap == null) return;

    try {
      // Use local position from GestureDetector
      final screenCoordinate = ScreenCoordinate(
        x: details.localPosition.dx,
        y: details.localPosition.dy,
      );

      // Query rendered features for both clusters and points
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
          final properties =
              feature?.queriedFeature.feature['properties'] as Map?;
          final index = properties?['index'];
          // ... rest of existing marker logic falls through naturally if I structure it right
          // actually, better to separate the blocks to be clean
          if (index != null && index is int && index < _tables.length) {
            final table = _tables[index];
            final matchData = _matchingService.calculateMatch(
              currentUser: _currentUserData!,
              table: table,
            );
            if (mounted) {
              _openTableModal(context, table, matchData, screenCoordinate);
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

        if (index != null && index is int && index < _tables.length) {
          final table = _tables[index]; // Use index to get full table data
          final matchData = _matchingService.calculateMatch(
            currentUser: _currentUserData!,
            table: table,
          );

          if (mounted) {
            _openTableModal(context, table, matchData, screenCoordinate);
          }
        }
      }
    } catch (e) {
      print('❌ Error handling map tap: $e');
    }
  }

  void _openTableModal(
    BuildContext context,
    Map<String, dynamic> table,
    Map<String, dynamic> matchData,
    ScreenCoordinate tapPosition,
  ) {
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
        // Fallback or just return if we can't get bounds
        print('⚠️ Could not get map bounds');
        return;
      }

      var fetchedTables = await _tableService.getMapReadyTables(
        userLat: _currentPosition?.latitude,
        userLng: _currentPosition?.longitude,
        // radiusKm: 30.0, // Removed fixed radius in favor of bounds
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
        limit: 100, // Smart server-side limit
      );

      print('📍 Found ${fetchedTables.length} tables in viewport');

      // 4. Relevance Filtering: Sort by Match Score and Cap
      if (_currentUserData != null) {
        // Calculate score for each table
        final scoredTables = fetchedTables.map((table) {
          final matchData = _matchingService.calculateMatch(
            currentUser: _currentUserData!,
            table: table,
          );
          return {'table': table, 'score': matchData['score'] as double};
        }).toList();

        // Sort descending by score
        scoredTables.sort(
          (a, b) => (b['score'] as double).compareTo(a['score'] as double),
        );

        // Take top 50 max (to prevent saturation)
        // If "Explore All" mode logic existed, we might skip this, but for now defaults to smart cap.
        final int maxMarkers = 50;
        if (scoredTables.length > maxMarkers) {
          print(
            '⚠️ Capping markers to top $maxMarkers most relevant (from ${scoredTables.length})',
          );
          fetchedTables = scoredTables
              .take(maxMarkers)
              .map((e) => e['table'] as Map<String, dynamic>)
              .toList();
        } else {
          // Even if not capped, we use the sorted list so best matches render LAST (on top)
          // or we might want them first. Usually Z-order isn't strict here but good to have sorted data.
          fetchedTables = scoredTables
              .map((e) => e['table'] as Map<String, dynamic>)
              .toList();
        }
      }

      setState(() {
        _tables = fetchedTables;
      });
      // Ghosts cleared, replaced by Pop Animation later

      // 5. Clustering & Native Layers Implementation
      final style = _mapboxMap?.style;
      if (style == null) return;

      // A. Remove Annotation Manager (Switching to Native Layers)
      if (_tableMarkerManager != null) {
        _tableMarkerManager?.deleteAll();
        _tableMarkerManager = null;
      }

      // A. Prepare Images & GeoJSON Features
      final features = <Map<String, dynamic>>[];

      for (var i = 0; i < fetchedTables.length; i++) {
        final table = fetchedTables[i];
        final matchData = _matchingService.calculateMatch(
          currentUser: _currentUserData!,
          table: table,
        );

        final imageId = 'table_img_${table['id']}';

        // Generate and Add Image to Style (if not exists)
        // Note: For performance, we should track which images are already added.
        // But for <100, checking/adding is acceptable.
        if (!_addedImages.contains(imageId)) {
          final Uint8List markerImage;
          final markerImageUrl = table['marker_image_url'];
          final markerEmoji = table['marker_emoji'];

          if (markerImageUrl != null && markerImageUrl.toString().isNotEmpty) {
            markerImage = await _createCustomMarkerImage(
              imageUrl: markerImageUrl,
              glowColor: matchData['color'],
              glowIntensity: matchData['glowIntensity'],
              count: 1, // Individual marker, count handled by cluster
            );
          } else if (markerEmoji != null && markerEmoji.toString().isNotEmpty) {
            markerImage = await _createEmojiMarkerImage(
              emoji: markerEmoji,
              glowColor: matchData['color'],
              glowIntensity: matchData['glowIntensity'],
            );
          } else {
            markerImage = await _createTableMarkerImage(
              photoUrl: table['host_photo_url'],
              activityType: table['activityType'], // Pass activity type
              glowColor: matchData['color'],
              glowIntensity: matchData['glowIntensity'],
              count: 1,
            );
          }

          // Add to style
          await style.addStyleImage(
            imageId,
            2.0, // Scale factor
            MbxImage(width: 120, height: 120, data: markerImage),
            false,
            [],
            [],
            null,
          );
          _addedImages.add(imageId);
        }

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
            'index': i, // Store index to lookup table data later
          },
        });
        print(
          '✅ Added feature ${i + 1}/${fetchedTables.length}: icon_id=$imageId',
        );
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
      _startPopAnimation();

      // Update 3D Layer Data
      _update3DLayerData(fetchedTables);
    } catch (e) {
      print('❌ Error updating map clusters: $e');
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  // Track added images to avoid re-adding to style
  final Set<String> _addedImages = {};

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
          iconOffset: [0.0, -70.0], // Float above 3D model
        ),
      );
      print('✅ Unclustered-points layer added');
    } catch (e) {
      print('❌ Error in _addClusterLayers: $e');
      print('   Stack: ${StackTrace.current}');
      rethrow;
    }

    // Add tap interaction is handled via Global map click if desired
  }

  Future<void> _update3DLayerData(List<Map<String, dynamic>> tables) async {
    if (_mapboxMap == null) return;

    // Skip rebuild if table IDs haven't changed (prevents flicker on pan)
    final currentTableIds = tables.map((t) => t['id'].toString()).toSet();
    if (_last3DTableIds.isNotEmpty && currentTableIds == _last3DTableIds) {
      return; // Data unchanged, skip rebuild
    }
    _last3DTableIds = currentTableIds;

    try {
      final style = _mapboxMap?.style;
      final sourceExists =
          await style?.styleSourceExists('tables-3d-source') ?? false;

      if (!sourceExists) {
        print('⚠️ 3D Source missing, attempting to re-initialize...');
        await _setup3DModels();
        // Check again
        if (!(await style?.styleSourceExists('tables-3d-source') ?? false)) {
          print('❌ Failed to re-initialize 3D source. Aborting update.');
          return;
        }
      }

      // Group tables by location to detect overlaps
      // Round to ~1 meter precision (5 decimal places ≈ 1.1m)
      Map<String, List<MapEntry<int, Map<String, dynamic>>>> locationGroups =
          {};

      for (var entry in tables.asMap().entries) {
        final table = entry.value;
        final lat = table['location_lat'] as double;
        final lng = table['location_lng'] as double;

        // Create location key with 5 decimal precision
        String locationKey =
            '${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}';
        locationGroups.putIfAbsent(locationKey, () => []).add(entry);
      }

      // Build features with radial expansion for overlapping tables
      final features = <Map<String, dynamic>>[];

      for (var group in locationGroups.values) {
        if (group.length == 1) {
          // Single table at this location - use exact coordinates
          final entry = group.first;
          final table = entry.value;
          features.add({
            'type': 'Feature',
            'id': table['id'],
            'geometry': {
              'type': 'Point',
              'coordinates': [table['location_lng'], table['location_lat']],
            },
            'properties': {
              'title': table['title'],
              'index': entry.key,
              'modelId': _getModelIdForAsset(table['marker_model']),
              'modelScale': ModelRegistry.getScaleFactor(
                table['marker_model'] ?? '',
              ),
              'rotation': [0.0, 0.0, 0.0],
            },
          });
        } else {
          // Multiple tables at same location - apply radial expansion
          final baseLat = group.first.value['location_lat'] as double;
          final baseLng = group.first.value['location_lng'] as double;
          const double radiusMeters = 15.0; // 15 meter radius

          for (int i = 0; i < group.length; i++) {
            final entry = group[i];
            final table = entry.value;

            // Calculate angle for this table in the circle
            double angle = (2 * pi * i) / group.length;

            // Convert meters to degrees
            // 1 degree latitude ≈ 111,320 meters
            double offsetLat = radiusMeters / 111320;
            // Longitude degrees vary by latitude
            double offsetLng =
                radiusMeters / (111320 * cos(baseLat * pi / 180));

            // Calculate new position
            double newLat = baseLat + (offsetLat * cos(angle));
            double newLng = baseLng + (offsetLng * sin(angle));

            features.add({
              'type': 'Feature',
              'id': table['id'],
              'geometry': {
                'type': 'Point',
                'coordinates': [newLng, newLat],
              },
              'properties': {
                'title': table['title'],
                'index': entry.key,
                'modelId': _getModelIdForAsset(table['marker_model']),
                'modelScale': ModelRegistry.getScaleFactor(
                  table['marker_model'] ?? '',
                ),
                'rotation': [0.0, 0.0, 0.0],
              },
            });
          }
        }
      }

      final geoJson = {'type': 'FeatureCollection', 'features': features};

      await style?.setStyleSourceProperty(
        'tables-3d-source',
        'data',
        jsonEncode(geoJson),
      );
    } catch (e) {
      print('⚠️ Error updating 3D layer source: $e');
    }
  }

  // Helper to map DB asset path to Mapbox Style Model ID
  String _getModelIdForAsset(String? assetPath) {
    if (assetPath == null) return 'arrow-model'; // Default

    // Map asset filenames to our internal IDs
    if (assetPath.contains('tennis')) return 'tennis-racket-model';
    if (assetPath.contains('basketball')) return 'basketball-model';
    if (assetPath.contains('soccer')) return 'soccer-ball-model';
    if (assetPath.contains('burger')) return 'burger-model';
    if (assetPath.contains('pizza')) return 'pizza-model';
    if (assetPath.contains('chinese')) return 'chinese-food-model';
    if (assetPath.contains('creamed')) return 'creamed-coffee-model';
    if (assetPath.contains('coffee_shop')) return 'coffee-shop-model';

    return 'arrow-model'; // Fallback
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
          print('🔖 Marker tapped with index: $index');

          if (index != null && index is int && index < _tables.length) {
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

  // --- MARKER POP ANIMATION LOGIC ---

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
      // f(t) = 1 + 2^(-10t) * sin((t - 0.3/4) * (2pi/0.3)) ... roughly
      // Let's use a simpler "boing" function directly:
      // sin(t * pi * (0.2 + 2.5 * t * t * t)) * pow(1 - t, 2.2) + t
      // Actually let's just use a simple dampened sine wave for "spring"
      // Val = Target + Amplitude * sin(freq * t) * decay^t

      // Or manually keyframe for simplicity and control:
      // 0-200ms: 0 -> 1.2
      // 200-400ms: 1.2 -> 0.9
      // 400-600ms: 0.9 -> 1.0

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

  // End of MapScreenState
}
