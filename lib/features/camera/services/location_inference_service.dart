import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class InferredLocation {
  final String name;
  final String? tableId;
  final String? eventId;
  final String? externalPlaceId;
  final double latitude;
  final double longitude;
  final String city;

  InferredLocation({
    required this.name,
    this.tableId,
    this.eventId,
    this.externalPlaceId,
    required this.latitude,
    required this.longitude,
    required this.city,
  });
}

class LocationInferenceService {
  static final _supabase = Supabase.instance.client;

  /// Gets the user's current location and infers the best venue name.
  /// Strategy:
  /// 1. Get GPS Lat/Lng
  /// 2. Check Supabase for active Tables/Events within 100 meters
  /// 3. If none, use Google Places API (Nearby Search) for closest establishment
  static Future<InferredLocation> determineCurrentContext() async {
    // 1. Get Location
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    final Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    final lat = position.latitude;
    final lng = position.longitude;
    final city = 'Metro Manila'; // TODO: Reverse geocode city if needed.

    // 2. Try Supabase Spatial Query (Need an RPC that uses PostGIS to find nearest table/event)
    // For now, we'll try to get ANY table within the database roughly.
    // In production, we assume an RPC `find_nearest_venue(lat, lng, radius_meters)` exists.
    try {
      final nearestVenue = await _supabase
          .rpc(
            'find_nearest_venue',
            params: {'lat': lat, 'lng': lng, 'radius_meters': 100},
          )
          .maybeSingle();

      if (nearestVenue != null) {
        return InferredLocation(
          name: nearestVenue['name'] as String,
          tableId: nearestVenue['type'] == 'table' ? nearestVenue['id'] : null,
          eventId: nearestVenue['type'] == 'event' ? nearestVenue['id'] : null,
          latitude: lat,
          longitude: lng,
          city: city,
        );
      }
    } catch (e) {
      // RPC might not exist yet, fallback to Google Places
    }

    // 3. Fallback: Google Places API (Nearby Search)
    try {
      final apiKey = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
      if (apiKey.isEmpty) throw Exception('No Google Places API Key');

      final url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=$lat,$lng'
          '&radius=50'
          '&type=establishment'
          '&key=$apiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' &&
            data['results'] != null &&
            data['results'].isNotEmpty) {
          final bestMatch = data['results'][0]; // Get the closest/first result

          return InferredLocation(
            name: bestMatch['name'],
            externalPlaceId: bestMatch['place_id'],
            latitude: lat,
            longitude: lng,
            city: city, // Fallback city
          );
        }
      }
    } catch (e) {
      print('Google Places Error: $e');
    }

    // 4. Absolute Fallback: Just Coordinates
    return InferredLocation(
      name: 'Current Location',
      latitude: lat,
      longitude: lng,
      city: city,
    );
  }
}
