import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bitemates/core/services/places_service.dart';

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

    // Reverse geocode to get city name
    String city = 'Unknown City';
    try {
      final apiKey = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
      if (apiKey.isNotEmpty) {
        final geocodeUrl =
            'https://maps.googleapis.com/maps/api/geocode/json'
            '?latlng=$lat,$lng'
            '&result_type=locality|administrative_area_level_1'
            '&key=$apiKey';
        final geoResponse = await http.get(Uri.parse(geocodeUrl));
        if (geoResponse.statusCode == 200) {
          final geoData = json.decode(geoResponse.body);
          if (geoData['status'] == 'OK' &&
              geoData['results'] != null &&
              geoData['results'].isNotEmpty) {
            // Extract the formatted city name
            city = geoData['results'][0]['formatted_address'] ?? city;
            // Try to get a cleaner locality from address_components
            final components = geoData['results'][0]['address_components'] as List?;
            if (components != null) {
              for (final comp in components) {
                final types = List<String>.from(comp['types'] ?? []);
                if (types.contains('locality')) {
                  city = comp['long_name'] as String;
                  break;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      // Silently fallback to 'Unknown City'
    }

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

    // 3. Fallback: Google Places API (New) — nearest establishment
    try {
      final results = await PlacesService.instance.nearbySearch(
        lat: lat,
        lng: lng,
        radiusMeters: 50,
        maxResults: 1,
      );
      if (results.isNotEmpty) {
        final best = results.first; // nearest
        return InferredLocation(
          name: best.name,
          externalPlaceId: best.placeId,
          latitude: lat,
          longitude: lng,
          city: city, // Fallback city
        );
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
