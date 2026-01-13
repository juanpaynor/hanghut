import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TenorService {
  // IMPORTANT: Replace with your actual Tenor API key!
  static const String _fallbackKey = 'AIzaSyAIw1DLbsu3ksGZuwxi0p3IwkTSozD-u8k';

  static String get _apiKey {
    final envKey = dotenv.env['TENOR_API_KEY'] ?? '';
    if (envKey.isNotEmpty) return envKey;
    return _fallbackKey;
  }

  static const String _baseUrl = 'https://tenor.googleapis.com/v2';

  // Search GIFs
  Future<List<Map<String, dynamic>>> searchGifs(
    String query, {
    int limit = 20,
  }) async {
    try {
      print('🎬 TENOR: Searching for "$query"');
      final url = '$_baseUrl/search?q=$query&key=$_apiKey&limit=$limit';
      final response = await http.get(Uri.parse(url));

      print('🎬 TENOR: Search response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
        print('🎬 TENOR: Found ${results.length} GIFs');
        return results;
      } else {
        print('❌ TENOR: Search failed - Status: ${response.statusCode}');
        print('❌ TENOR: Response body: ${response.body}');
      }
      return [];
    } catch (e) {
      print('❌ TENOR: Error searching GIFs - $e');
      return [];
    }
  }

  // Get trending GIFs (uses Featured endpoint)
  Future<List<Map<String, dynamic>>> getTrendingGifs({int limit = 20}) async {
    try {
      print('🎬 TENOR: Fetching featured GIFs');
      print('🎬 TENOR: API Key present: ${_apiKey.isNotEmpty}');
      final url =
          '$_baseUrl/featured?key=$_apiKey&limit=$limit&contentfilter=off';
      print('🎬 TENOR: Request URL: $url');
      final response = await http.get(Uri.parse(url));

      print('🎬 TENOR: Featured response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
        print('🎬 TENOR: Found ${results.length} featured GIFs');
        return results;
      } else {
        print('❌ TENOR: Featured failed - Status: ${response.statusCode}');
        print('❌ TENOR: Response body: ${response.body}');
      }
      return [];
    } catch (e) {
      print('❌ TENOR: Error getting featured GIFs - $e');
      return [];
    }
  }

  // Get featured GIFs
  Future<List<Map<String, dynamic>>> getFeaturedGifs({int limit = 20}) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/featured?key=$_apiKey&limit=$limit&media_filter=gif',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['results'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error getting featured GIFs: $e');
      return [];
    }
  }

  // Get categories
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/categories?key=$_apiKey'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['tags'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error getting categories: $e');
      return [];
    }
  }

  // Extract GIF URL from Tenor result
  String getGifUrl(Map<String, dynamic> gif, {String quality = 'medium'}) {
    try {
      final mediaFormats = gif['media_formats'];
      if (mediaFormats != null) {
        // Try different quality levels
        if (quality == 'high' && mediaFormats['gif'] != null) {
          return mediaFormats['gif']['url'];
        } else if (mediaFormats['mediumgif'] != null) {
          return mediaFormats['mediumgif']['url'];
        } else if (mediaFormats['tinygif'] != null) {
          return mediaFormats['tinygif']['url'];
        } else if (mediaFormats['gif'] != null) {
          return mediaFormats['gif']['url'];
        }
      }
      return '';
    } catch (e) {
      print('Error extracting GIF URL: $e');
      return '';
    }
  }

  // Get preview image URL
  String getPreviewUrl(Map<String, dynamic> gif) {
    try {
      final mediaFormats = gif['media_formats'];
      if (mediaFormats != null) {
        if (mediaFormats['tinygif'] != null) {
          return mediaFormats['tinygif']['url'];
        } else if (mediaFormats['nanogif'] != null) {
          return mediaFormats['nanogif']['url'];
        }
      }
      return '';
    } catch (e) {
      print('Error extracting preview URL: $e');
      return '';
    }
  }
}
