import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:http/http.dart' as http;
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/services/matching_service.dart';
import 'package:bitemates/features/map/widgets/table_compact_modal.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  MapboxMap? _mapboxMap;
  geo.Position? _currentPosition;
  PointAnnotationManager? _tableMarkerManager;
  final _tableService = TableService();
  final _matchingService = MatchingService();
  List<Map<String, dynamic>> _tables = [];
  Map<String, dynamic>? _currentUserData;
  final Map<String, int> _annotationToTableIndex = {};
  final Map<String, List<int>> _locationToTableIndices = {};
  Timer? _debounceTimer;
  CameraState? _lastFetchCameraState;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _loadCurrentUserData();
    // Realtime subscription removed in favor of polling
    // _subscribeToTableChanges();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
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
    await Future.delayed(const Duration(milliseconds: 1000));
    _mapboxMap?.flyTo(
      CameraOptions(zoom: 16.0, pitch: 60.0, bearing: 45.0),
      MapAnimationOptions(duration: 3000),
    );
  }

  Future<void> _setup3DModels() async {
    if (_mapboxMap == null) return;

    try {
      final style = _mapboxMap?.style;

      // 1. Try local asset (Robust Method: Copy to temp file)
      try {
        final modelPath = await _copyAssetToTemp(
          'assets/models/coffee_shop_cup.glb',
          'shop_cup.glb',
        );
        print('☕ Coffee model copied to: $modelPath');

        await style?.addStyleModel('coffee-shop-model', 'file://$modelPath');
      } catch (e) {
        print('⚠️ Failed to load local coffee model: $e');
        // Fallback to remote if local fails absolutely
        try {
          await style?.addStyleModel(
            'coffee-shop-model',
            'https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Duck/glTF-Binary/Duck.glb',
          );
        } catch (e2) {
          print('⚠️ Remote fallback failed: $e2');
        }
      }

      // 2. Add GeoJSON Source for 3D markers
      await style?.addSource(
        GeoJsonSource(
          id: 'tables-3d-source',
          data: jsonEncode({'type': 'FeatureCollection', 'features': []}),
        ),
      );

      // 3. Add Model Layer
      await style?.addLayer(
        ModelLayer(
          id: 'tables-3d-layer',
          sourceId: 'tables-3d-source',
          minZoom: 0.0,
          maxZoom: 22.0,
          modelId: 'coffee-shop-model',
          // Massive scale increase
          modelScale: [1500.0, 1500.0, 1500.0],
          // Lift it up significantly + slight tilt
          modelRotation: [0.0, 0.0, 0.0],
          // Lift significantly higher to account for massive scale pushing geometry down
          // Reduced height since we are reducing the scale
          modelTranslation: [0.0, 0.0, 50.0],
          // Using model-scale as main visibility driver first.
          modelOpacity: 1.0,
          modelEmissiveStrength: 1.0,
        ),
      );

      // 4. Update 'model-scale' with an expression to make it responsive
      try {
        await style?.setStyleLayerProperty(
          'tables-3d-layer',
          'model-scale',
          jsonEncode([
            "interpolate",
            ["linear"],
            ["zoom"],
            10.0,
            [800.0, 800.0, 800.0], // Zoom 10 (City): Much smaller (was 4000)
            16.0,
            [300.0, 300.0, 300.0], // Zoom 16 (Street): Smaller (was 1500)
            20.0,
            [20.0, 20.0, 20.0], // Zoom 20 (Close up): Tiny
          ]),
        );
      } catch (e) {
        print('⚠️ Failed to set model-scale expression: $e');
      }

      print('✅ 3D Model Layer initialized');
    } catch (e) {
      print('❌ Error setting up 3D models: $e');
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

  void _drawPlaceholderFace(Canvas canvas, int size) {
    // Draw placeholder face (Gray circle)
    final Paint facePaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 15, facePaint);

    // Draw simple face features
    final Paint featurePaint = Paint()
      ..color = Colors.grey.shade600
      ..style = PaintingStyle.fill;

    // Eyes
    canvas.drawCircle(Offset(size / 2 - 15, size / 2 - 10), 4, featurePaint);
    canvas.drawCircle(Offset(size / 2 + 15, size / 2 - 10), 4, featurePaint);

    // Smile
    final Path smilePath = Path()
      ..moveTo(size / 2 - 20, size / 2 + 10)
      ..quadraticBezierTo(
        size / 2,
        size / 2 + 20,
        size / 2 + 20,
        size / 2 + 10,
      );

    canvas.drawPath(
      smilePath,
      Paint()
        ..color = Colors.grey.shade600
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(
        key: const ValueKey('mapWidget'),
        styleUri: 'mapbox://styles/swiftdash/cmjmzix6300aq01spblcqe7yx',
        cameraOptions: CameraOptions(
          center: _currentPosition != null
              ? Point(
                  coordinates: Position(
                    _currentPosition!.longitude,
                    _currentPosition!.latitude,
                  ),
                )
              : Point(coordinates: Position(-74.0060, 40.7128)),
          zoom: 15.0, // Zoom in closer for 3D effect
          pitch: 60.0, // Tilt camera for 3D view
        ),
        onCameraChangeListener: _onCameraChangeListener,
        onMapCreated: _onMapCreated,
      ),
    );
  }

  Future<void> _fetchTablesInViewport() async {
    if (_mapboxMap == null || _currentUserData == null) return;

    try {
      // 1. Check Zoom Level
      final cameraState = await _mapboxMap?.getCameraState();
      if (cameraState == null) return;

      if (cameraState.zoom < 10) {
        print(
          '🔎 Zoom level ${cameraState.zoom} is too low. Clearing markers.',
        );
        if (_tables.isNotEmpty) {
          setState(() => _tables = []);
          _tableMarkerManager?.deleteAll();
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

        // Thresholds: 500 meters or 0.5 zoom level change
        // Adjust these based on UX preference
        if (dist < 500 && zoomDiff < 0.5) {
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
      if (cameraState == null) return;

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

      // 3. Fetch Tables
      final tables = await _tableService.getMapReadyTables(
        userLat: _currentPosition?.latitude,
        userLng: _currentPosition?.longitude,
        // radiusKm: 30.0, // Removed fixed radius in favor of bounds
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
      );

      print('📍 Found ${tables.length} tables in viewport');

      // Debug: Log scheduled times
      for (var table in tables) {
        print('  Table: ${table['venue_name']}');
        print('    Scheduled: ${table['scheduled_at']}');
        print('    Status: ${table['status']}');
      }

      setState(() {
        _tables = tables;
      });

      // Remove old markers
      _tableMarkerManager?.deleteAll();

      // Create new marker manager
      _tableMarkerManager = await _mapboxMap?.annotations
          .createPointAnnotationManager();

      // Clear annotation mapping
      _annotationToTableIndex.clear();
      _locationToTableIndices.clear();

      // Group tables by location (rounded to 5 decimal places ~1 meter precision)
      final Map<String, List<int>> locationGroups = {};
      for (int i = 0; i < tables.length; i++) {
        final lat = (tables[i]['location_lat'] as double).toStringAsFixed(5);
        final lng = (tables[i]['location_lng'] as double).toStringAsFixed(5);
        final locationKey = '$lat,$lng';

        locationGroups.putIfAbsent(locationKey, () => []);
        locationGroups[locationKey]!.add(i);
      }

      print('📍 Grouped into ${locationGroups.length} unique locations');

      final options = <PointAnnotationOptions>[];
      int markerIndex = 0;

      for (var entry in locationGroups.entries) {
        final tableIndices = entry.value;
        final firstTable = tables[tableIndices[0]];

        // Store mapping for this location
        _locationToTableIndices[markerIndex.toString()] = tableIndices;

        // Calculate best match for this location
        var bestMatchData = _matchingService.calculateMatch(
          currentUser: _currentUserData!,
          table: firstTable,
        );

        // If multiple tables, find the best match
        if (tableIndices.length > 1) {
          for (var idx in tableIndices) {
            final matchData = _matchingService.calculateMatch(
              currentUser: _currentUserData!,
              table: tables[idx],
            );
            if (matchData['score'] > bestMatchData['score']) {
              bestMatchData = matchData;
            }
          }
        }

        // Create marker with count badge if multiple tables
        final Uint8List markerImage;
        final markerImageUrl = firstTable['marker_image_url'];

        if (markerImageUrl != null && markerImageUrl.toString().isNotEmpty) {
          markerImage = await _createCustomMarkerImage(
            imageUrl: markerImageUrl,
            glowColor: bestMatchData['color'],
            glowIntensity: bestMatchData['glowIntensity'],
            count: tableIndices.length,
          );
        } else {
          markerImage = await _createTableMarkerImage(
            photoUrl: firstTable['host_photo_url'],
            glowColor: bestMatchData['color'],
            glowIntensity: bestMatchData['glowIntensity'],
            count: tableIndices.length,
          );
        }

        options.add(
          PointAnnotationOptions(
            geometry: Point(
              coordinates: Position(
                firstTable['location_lng'],
                firstTable['location_lat'],
              ),
            ),
            image: markerImage,
            iconSize: 1.5,
          ),
        );

        markerIndex++;
      }

      /*
      // Disable 2D markers for now to focus on 3D
      if (options.isNotEmpty) {
        final annotations = await _tableMarkerManager?.createMulti(options);
        // ... (rest of logic commented out)
        print('✅ Added ${options.length} table markers to map');
      }
      */

      // Update 3D Layer Data
      _update3DLayerData(tables);
    } catch (e) {
      print('❌ Error adding table markers: $e');
    }
  }

  Future<void> _update3DLayerData(List<Map<String, dynamic>> tables) async {
    if (_mapboxMap == null) return;

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

      final features = tables.map((table) {
        return {
          'type': 'Feature',
          'id': table['id'],
          'geometry': {
            'type': 'Point',
            'coordinates': [table['location_lng'], table['location_lat']],
          },
          'properties': {
            'title': table['title'],
            // 'activity_type': table['activityType'],
            'modelId': 'coffee-model',
            'rotation': [0.0, 0.0, 0.0],
          },
        };
      }).toList();

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

  void _showLocationTables(int markerIndex) async {
    final tableIndices = _locationToTableIndices[markerIndex.toString()];
    if (tableIndices == null || tableIndices.isEmpty) return;

    // If only one table at this location, show it directly
    if (tableIndices.length == 1) {
      _showTableDetails(tableIndices[0]);
      return;
    }

    // Multiple tables - show selection Dialog
    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tableIndices.length} Tables at ${_tables[tableIndices[0]]['venue_name']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: SingleChildScrollView(
                        child: Column(
                          children: tableIndices.map((idx) {
                            final table = _tables[idx];
                            final matchData = _matchingService.calculateMatch(
                              currentUser: _currentUserData!,
                              table: table,
                            );
                            final scheduledAt = DateTime.parse(
                              table['scheduled_time'],
                            );

                            return Card(
                              color: const Color(0xFF2A2A2A),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                onTap: () => Navigator.pop(context, idx),
                                leading: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Color(
                                      int.parse(
                                        matchData['color'].replaceFirst(
                                          '#',
                                          '0xFF',
                                        ),
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${(matchData['score'] * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  table['title'] ?? table['venue_name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${DateFormat('MMM d @ h:mm a').format(scheduledAt)} • ${table['max_capacity']} seats',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white54,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Close button
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedIndex != null && mounted) {
      _showTableDetails(selectedIndex);
    }
  }

  void _showTableDetails(int tableIndex) async {
    if (tableIndex >= _tables.length) return;

    final table = _tables[tableIndex];
    final matchData = _matchingService.calculateMatch(
      currentUser: _currentUserData!,
      table: table,
    );

    final shouldRefresh = await showDialog<bool>(
      context: context,
      builder: (context) =>
          TableCompactModal(table: table, matchData: matchData),
    );

    // Refresh markers if action was taken
    if (shouldRefresh == true && mounted) {
      _fetchTablesInViewport();
    }
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
    required String glowColor,
    required double glowIntensity,
    int count = 1,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final int size = 100;

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
        _drawPlaceholderFace(canvas, size);
      }
    } else {
      _drawPlaceholderFace(canvas, size);
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
}

class _MarkerTapListener extends OnPointAnnotationClickListener {
  final Map<String, int> annotationToTableIndex;
  final Function(int) onTap;

  _MarkerTapListener({
    required this.annotationToTableIndex,
    required this.onTap,
  });

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    final tableIndex = annotationToTableIndex[annotation.id];
    if (tableIndex != null) {
      onTap(tableIndex);
    }
  }
}
