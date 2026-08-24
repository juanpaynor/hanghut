import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// A single autocomplete suggestion from the Places API (New).
class PlacePrediction {
  final String placeId;
  final String description; // full text, e.g. "Cafe X, Makati, Metro Manila"
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}

/// Resolved details for a place (from Place Details or Nearby Search).
class PlaceDetails {
  final String? placeId;
  final String name;
  final String formattedAddress;
  final double latitude;
  final double longitude;

  /// City (locality, falling back to administrative_area_level_2). Empty when
  /// unavailable. Parsed from addressComponents — available for surfaces that
  /// need a city field.
  final String city;

  const PlaceDetails({
    this.placeId,
    required this.name,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.city = '',
  });
}

/// Thin client over the **Places API (New)** (`places.googleapis.com/v1`).
///
/// The legacy web service (`maps.googleapis.com/maps/api/place/*`) is
/// deprecated and unavailable to new Google customers, so all app-side place
/// search/details/nearby calls go through here. The New API uses POST bodies,
/// an `X-Goog-Api-Key` header and mandatory field masks — the request/response
/// shapes differ from legacy, so callers use the typed models above rather than
/// raw JSON.
///
/// Session tokens: pass a token (from [newSessionToken]) to [autocomplete] for
/// every keystroke of one search AND to the [details] call that closes it, then
/// discard it. This groups the search into a single, cheaper billing session.
class PlacesService {
  PlacesService._();
  static final PlacesService instance = PlacesService._();

  static const String _base = 'https://places.googleapis.com/v1';

  /// HangHut is PH-first; autocomplete restricts to this region by default.
  /// Pass `regionCode: ''` to a call to opt out.
  static const String defaultRegionCode = 'ph';

  static const _uuid = Uuid();

  // The Places API key is sourced from Dart ON PURPOSE, not from .env.
  // .env is a bundled Flutter asset, and Shorebird patches do NOT include
  // asset changes — so a key here can be rotated via `shorebird patch`, whereas
  // a key in .env would require a full `shorebird release`. This is the key with
  // Places API (New) + billing enabled (same one the web team uses).
  static const String _placesApiKey =
      'AIzaSyDOIku975W5J2mTaCwqgahOQcbRhw-iRaA';

  String get _apiKey => _placesApiKey;

  /// A fresh autocomplete session token. Create one when a search starts, reuse
  /// it across that search's autocomplete + details calls, then drop it.
  String newSessionToken() => _uuid.v4();

  /// Autocomplete predictions for [input]. Optionally biased toward [lat]/[lng]
  /// within [radiusMeters]. Restricted to [regionCode] (defaults to PH; pass
  /// `''` to disable). Returns an empty list on any error.
  Future<List<PlacePrediction>> autocomplete(
    String input, {
    double? lat,
    double? lng,
    double radiusMeters = 30000,
    String? regionCode,
    String? sessionToken,
  }) async {
    if (input.trim().isEmpty) return [];
    try {
      final body = <String, dynamic>{'input': input};
      if (lat != null && lng != null) {
        body['locationBias'] = {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': radiusMeters,
          },
        };
      }
      final region = regionCode ?? defaultRegionCode;
      if (region.isNotEmpty) body['includedRegionCodes'] = [region];
      if (sessionToken != null) body['sessionToken'] = sessionToken;

      final res = await http.post(
        Uri.parse('$_base/places:autocomplete'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
        },
        body: json.encode(body),
      );
      if (res.statusCode != 200) {
        debugPrint('PlacesService.autocomplete ${res.statusCode}: ${res.body}');
        return [];
      }
      final data = json.decode(res.body) as Map<String, dynamic>;
      final suggestions = data['suggestions'] as List? ?? [];
      final out = <PlacePrediction>[];
      for (final s in suggestions) {
        final p = (s as Map)['placePrediction'];
        if (p == null) continue; // skip query-only suggestions
        final sf = p['structuredFormat'] as Map?;
        final full = (p['text']?['text'] as String?) ?? '';
        out.add(
          PlacePrediction(
            placeId: (p['placeId'] as String?) ?? '',
            description: full,
            mainText: (sf?['mainText']?['text'] as String?) ?? full,
            secondaryText: (sf?['secondaryText']?['text'] as String?) ?? '',
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('PlacesService.autocomplete error: $e');
      return [];
    }
  }

  /// Full details for a place id. Pass the same [sessionToken] used for the
  /// autocomplete calls to close (and bill) the session. Returns null on error.
  Future<PlaceDetails?> details(String placeId, {String? sessionToken}) async {
    try {
      var url = '$_base/places/$placeId';
      if (sessionToken != null) url += '?sessionToken=$sessionToken';
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'id,displayName,formattedAddress,location,addressComponents',
        },
      );
      if (res.statusCode != 200) {
        debugPrint('PlacesService.details ${res.statusCode}: ${res.body}');
        return null;
      }
      final data = json.decode(res.body) as Map<String, dynamic>;
      final loc = data['location'] as Map?;
      if (loc == null) return null;
      return PlaceDetails(
        placeId: (data['id'] as String?) ?? placeId,
        name: (data['displayName']?['text'] as String?) ?? '',
        formattedAddress: (data['formattedAddress'] as String?) ?? '',
        latitude: (loc['latitude'] as num).toDouble(),
        longitude: (loc['longitude'] as num).toDouble(),
        city: _extractCity(data['addressComponents'] as List?),
      );
    } catch (e) {
      debugPrint('PlacesService.details error: $e');
      return null;
    }
  }

  /// Nearest places to [lat]/[lng] within [radiusMeters], nearest first.
  /// Returns an empty list on any error.
  Future<List<PlaceDetails>> nearbySearch({
    required double lat,
    required double lng,
    double radiusMeters = 50,
    int maxResults = 1,
    List<String>? includedTypes,
    bool rankByDistance = true,
  }) async {
    try {
      final body = <String, dynamic>{
        'maxResultCount': maxResults,
        'locationRestriction': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': radiusMeters,
          },
        },
      };
      if (includedTypes != null && includedTypes.isNotEmpty) {
        body['includedTypes'] = includedTypes;
      }
      if (rankByDistance) body['rankPreference'] = 'DISTANCE';

      final res = await http.post(
        Uri.parse('$_base/places:searchNearby'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'places.id,places.displayName,places.formattedAddress,places.location,places.addressComponents',
        },
        body: json.encode(body),
      );
      if (res.statusCode != 200) {
        debugPrint('PlacesService.nearbySearch ${res.statusCode}: ${res.body}');
        return [];
      }
      final data = json.decode(res.body) as Map<String, dynamic>;
      final places = data['places'] as List? ?? [];
      return places.map((p) {
        final m = p as Map;
        final loc = m['location'] as Map?;
        return PlaceDetails(
          placeId: m['id'] as String?,
          name: (m['displayName']?['text'] as String?) ?? '',
          formattedAddress: (m['formattedAddress'] as String?) ?? '',
          latitude: (loc?['latitude'] as num?)?.toDouble() ?? lat,
          longitude: (loc?['longitude'] as num?)?.toDouble() ?? lng,
          city: _extractCity(m['addressComponents'] as List?),
        );
      }).toList();
    } catch (e) {
      debugPrint('PlacesService.nearbySearch error: $e');
      return [];
    }
  }

  /// Pull a city name out of REST v1 addressComponents: prefer `locality`,
  /// fall back to `administrative_area_level_2`. Note the New API uses
  /// `longText`/`shortText` (not `long_name`/`short_name`).
  String _extractCity(List? components) {
    if (components == null) return '';
    Map? admin2;
    for (final c in components) {
      final types = ((c as Map)['types'] as List?)?.cast<String>() ?? const [];
      if (types.contains('locality')) {
        return (c['longText'] as String?) ?? '';
      }
      if (types.contains('administrative_area_level_2')) admin2 ??= c;
    }
    return (admin2?['longText'] as String?) ?? '';
  }
}
