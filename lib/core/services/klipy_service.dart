import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:bitemates/core/config/supabase_config.dart';

/// KLIPY GIF API (migrated from Tenor). Docs: https://docs.klipy.com/gifs-api
///
/// NOTE: despite KLIPY's "just swap the base URL" pitch, the request shape and
/// response are quite different from Tenor:
///   - the API key ("app_key") is a URL PATH segment, not a `?key=` param
///   - results live at data.data[] (nested), each item's media at
///     file.{hd|md|sm|xs}.{gif|webp|jpg|mp4|webm}.url
///   - a stable per-user `customer_id` is expected for personalization
///
/// This service exposes the same public methods the old TenorService did
/// (searchGifs / getTrendingGifs / getGifUrl / getPreviewUrl) so call sites are
/// unchanged, but parses the KLIPY shape internally.
class KlipyService {
  static String get _appKey => dotenv.env['KLIPY_API_KEY'] ?? '';

  static const String _baseUrl = 'https://api.klipy.com/api/v1';

  /// Stable per-user id for KLIPY personalization/recents. Consistent for the
  /// same signed-in user; falls back to 'anonymous' when logged out.
  static String get _customerId =>
      SupabaseConfig.client.auth.currentUser?.id ?? 'anonymous';

  /// Per-media format filter. MUST only list formats the media type actually
  /// has: KLIPY's *trending* endpoint returns 0 results if you request a
  /// format that doesn't exist for that type (e.g. png on gifs). GIFs have
  /// gif/webp, stickers gif/webp/png, memes png/webp only.
  static String _formatFilterFor(String media) => switch (media) {
        'stickers' => 'gif,webp,png',
        'static-memes' => 'webp,png',
        _ => 'gif,webp', // gifs
      };

  // ── Fetch ──────────────────────────────────────────────────────────────────

  /// Search GIFs by keyword. Returns the raw KLIPY item maps (parse URLs with
  /// [getGifUrl] / [getPreviewUrl]).
  Future<List<Map<String, dynamic>>> searchGifs(
    String query, {
    int limit = 24,
  }) =>
      _search('gifs', query, limit: limit);

  /// Trending GIFs (used as the default view before the user searches).
  Future<List<Map<String, dynamic>>> getTrendingGifs({int limit = 24}) =>
      _trending('gifs', limit: limit);

  /// Search stickers (transparent). Same item shape as GIFs — use
  /// [getGifUrl] / [getPreviewUrl] to pull URLs. Stickers ship a transparent
  /// animated `gif` at every tier, so they flow through the existing gif_url
  /// pipeline and render on both app and web with no schema changes.
  Future<List<Map<String, dynamic>>> searchStickers(
    String query, {
    int limit = 24,
  }) =>
      _search('stickers', query, limit: limit);

  /// Trending stickers (default sticker view before searching).
  Future<List<Map<String, dynamic>>> getTrendingStickers({int limit = 24}) =>
      _trending('stickers', limit: limit);

  /// Search memes (static images, png/webp). Same item shape; the endpoint
  /// path is `static-memes`. Resolve URLs with [getGifUrl] / [getPreviewUrl].
  Future<List<Map<String, dynamic>>> searchMemes(
    String query, {
    int limit = 24,
  }) =>
      _search('static-memes', query, limit: limit);

  /// Trending memes (default meme view before searching).
  Future<List<Map<String, dynamic>>> getTrendingMemes({int limit = 24}) =>
      _trending('static-memes', limit: limit);

  // media == 'gifs' | 'stickers'
  Future<List<Map<String, dynamic>>> _search(
    String media,
    String query, {
    int limit = 24,
  }) async {
    if (_appKey.isEmpty) {
      print('❌ KLIPY: no KLIPY_API_KEY set in .env');
      return [];
    }
    final uri = Uri.parse('$_baseUrl/$_appKey/$media/search').replace(
      queryParameters: {
        'q': query,
        'per_page': '$limit',
        'page': '1',
        'customer_id': _customerId,
        'format_filter': _formatFilterFor(media),
      },
    );
    return _fetchItems(uri, context: '$media search "$query"');
  }

  Future<List<Map<String, dynamic>>> _trending(
    String media, {
    int limit = 24,
  }) async {
    if (_appKey.isEmpty) {
      print('❌ KLIPY: no KLIPY_API_KEY set in .env');
      return [];
    }
    final uri = Uri.parse('$_baseUrl/$_appKey/$media/trending').replace(
      queryParameters: {
        'per_page': '$limit',
        'page': '1',
        'customer_id': _customerId,
        'format_filter': _formatFilterFor(media),
      },
    );
    return _fetchItems(uri, context: '$media trending');
  }

  Future<List<Map<String, dynamic>>> _fetchItems(
    Uri uri, {
    required String context,
  }) async {
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        print('❌ KLIPY: $context failed - ${response.statusCode}: ${response.body}');
        return [];
      }
      final decoded = json.decode(response.body);
      // Shape: { result: true, data: { data: [ ...items ], has_next, ... } }
      final data = decoded is Map ? decoded['data'] : null;
      final items = data is Map ? data['data'] : null;
      if (items is! List) return [];
      // Skip any injected ad objects (type == 'ad') — we don't render ads.
      return items
          .whereType<Map>()
          .where((e) => e['type'] != 'ad')
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('❌ KLIPY: error fetching $context - $e');
      return [];
    }
  }

  // ── URL extraction ──────────────────────────────────────────────────────────

  /// The URL to actually send/store (chat message, hangout hero, etc.).
  /// Prefers a mid-size animated GIF; [quality] == 'high' opts into a larger one.
  /// Returns '' if no usable URL is present.
  String getGifUrl(Map<String, dynamic> gif, {String quality = 'medium'}) {
    // (tier, format) priority — sm gif (~220px, ~314KB) is the sweet spot;
    // hd/md gifs are 2-4 MB so they're last-resort only. webp is a fallback.
    // webp/png tail covers static memes (png/webp only — no gif).
    final priority = quality == 'high'
        ? const [
            ['md', 'gif'], ['hd', 'gif'], ['sm', 'gif'],
            ['md', 'webp'], ['sm', 'webp'], ['xs', 'gif'],
            ['md', 'png'], ['sm', 'png'],
          ]
        : const [
            ['sm', 'gif'], ['md', 'gif'], ['hd', 'gif'],
            ['sm', 'webp'], ['xs', 'gif'], ['xs', 'webp'],
            ['sm', 'png'], ['md', 'png'],
          ];
    return _firstUrl(gif, priority);
  }

  /// The lightweight URL for the picker grid thumbnail. Prefers small webp
  /// (~220px, ~80KB) for fast loading; falls back through smaller variants.
  String getPreviewUrl(Map<String, dynamic> gif) {
    const priority = [
      ['sm', 'webp'], ['xs', 'webp'], ['xs', 'gif'], ['sm', 'gif'],
      ['xs', 'png'], ['sm', 'png'],
    ];
    final url = _firstUrl(gif, priority);
    return url.isNotEmpty ? url : getGifUrl(gif);
  }

  /// Walks a (tier, format) priority list and returns the first present URL.
  String _firstUrl(Map<String, dynamic> gif, List<List<String>> priority) {
    final file = gif['file'];
    if (file is! Map) return '';
    for (final pair in priority) {
      final tier = file[pair[0]];
      if (tier is! Map) continue;
      final fmt = tier[pair[1]];
      if (fmt is! Map) continue;
      final url = fmt['url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return '';
  }
}
