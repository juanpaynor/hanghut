import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Position;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    as mapbox
    show Position;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LocationPickerModal extends StatefulWidget {
  final Position? initialPosition;

  const LocationPickerModal({super.key, this.initialPosition});

  @override
  State<LocationPickerModal> createState() => _LocationPickerModalState();
}

class _LocationPickerModalState extends State<LocationPickerModal> {
  MapboxMap? _mapboxMap;
  Point? _centerPoint;
  String _address = 'Move map to select location';
  bool _isLoadingAddress = false;
  Timer? _debounceTimer;

  // Default to Manila if no position provided
  static const double _defaultLat = 14.5995;
  static const double _defaultLng = 120.9842;

  @override
  void initState() {
    super.initState();
    // Initialize center point
    final lat = widget.initialPosition?.latitude ?? _defaultLat;
    final lng = widget.initialPosition?.longitude ?? _defaultLng;
    _centerPoint = Point(coordinates: mapbox.Position(lng, lat));

    // Initial reverse geocode if we have a position
    if (widget.initialPosition != null) {
      _reverseGeocode(lat, lng);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  void _onCameraChangeListener(CameraChangedEventData event) {
    // We only care about the center position, which we can get derived
    // or we can debounce and ask the map for its camera state.

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (_mapboxMap == null) return;

      try {
        final cameraState = await _mapboxMap!.getCameraState();
        final center = cameraState.center;

        // Update standard Point object for return
        _centerPoint = center;

        // Reverse Geocode
        // Mapbox Points are (lng, lat)
        final lng = center.coordinates.lng;
        final lat = center.coordinates.lat;

        await _reverseGeocode(lat as double, lng as double);
      } catch (e) {
        print('Error getting camera center: $e');
      }
    });

    // While dragging, show loading or "Selecting..."
    if (!_isLoadingAddress) {
      setState(() {
        _isLoadingAddress = true;
        _address = 'Locating...';
      });
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    // We should get the token from Info.plist or .env.
    // Assuming .env or a known public token for client side.
    // For now, I will try to read it from the configured MapboxOptions or use a constant/env if available.
    // Actually, `mapbox_maps_flutter` uses the token from Info.plist/Manifest automatically for the map,
    // but for HTTP request we need to access it.
    // Let's check if we have access to it. If not, I'll use a placeholder or check config.
    // Typically it's in .env for Dart access.

    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];

    if (accessToken == null) {
      setState(() {
        _address = '$lat, $lng'; // Fallback
        _isLoadingAddress = false;
      });
      return;
    }

    try {
      final url = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json?access_token=$accessToken&types=poi,address,place',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        if (features.isNotEmpty) {
          final primary = features.first;
          final placeName = primary['place_name'] as String;

          if (mounted) {
            setState(() {
              _address = placeName;
              _isLoadingAddress = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _address = 'Unknown location';
              _isLoadingAddress = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _address = 'Error fetching address';
            _isLoadingAddress = false;
          });
        }
      }
    } catch (e) {
      print('Geocoding error: $e');
      if (mounted) {
        setState(() {
          _address = 'Network error';
          _isLoadingAddress = false;
        });
      }
    }
  }

  void _confirmSelection() {
    if (_centerPoint == null) return;

    Navigator.pop(context, {
      'point': _centerPoint,
      'address': _address,
      'latitude': _centerPoint!.coordinates.lat,
      'longitude': _centerPoint!.coordinates.lng,
    });
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.initialPosition?.latitude ?? _defaultLat;
    final lng = widget.initialPosition?.longitude ?? _defaultLng;

    return Scaffold(
      body: Stack(
        children: [
          // Map
          MapWidget(
            key: const ValueKey("mapWidget"),
            cameraOptions: CameraOptions(
              center: Point(coordinates: mapbox.Position(lng, lat)),
              zoom: 15.0,
            ),
            onMapCreated: _onMapCreated,
            onCameraChangeListener: _onCameraChangeListener,
          ),

          // Center Pin (Fixed)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: 35.0,
              ), // Lift pin slightly so tip is at center
              child: Icon(
                Icons.location_on_rounded,
                size: 50,
                color: Theme.of(context).primaryColor,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),

          // Back Button
          Positioned(
            top: 50,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Bottom Sheet / Confirmation
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selected Location',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _isLoadingAddress
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _address,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoadingAddress ? null : _confirmSelection,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Confirm Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
