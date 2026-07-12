import 'package:bitemates/core/config/supabase_config.dart';

/// One row of the server-driven `event_categories` lookup (team_comms #174).
class EventCategoryItem {
  final String key; // e.g. 'live_music' — matches events.category
  final String label; // e.g. 'Live Music'
  final String emoji; // e.g. '🎵'

  const EventCategoryItem({
    required this.key,
    required this.label,
    required this.emoji,
  });

  factory EventCategoryItem.fromJson(Map<String, dynamic> j) {
    return EventCategoryItem(
      key: j['key'] as String,
      label: (j['label'] ?? j['key']) as String,
      emoji: (j['emoji'] as String?) ?? '',
    );
  }

  /// Emoji-prefixed display label, e.g. "🎵 Live Music" (label only if no emoji).
  String get display => emoji.isEmpty ? label : '$emoji $label';
}

/// Fetches the event category taxonomy from the server so the map + Discover
/// render one identical, always-current list — never hardcoded (team_comms
/// #173/#174). Cached in-memory for the app session.
class EventCategoryService {
  EventCategoryService._();
  static final EventCategoryService _instance = EventCategoryService._();
  factory EventCategoryService() => _instance;

  List<EventCategoryItem>? _cache;

  /// Active categories ordered by `sort_order`. Cached after the first call;
  /// pass [forceRefresh] to re-fetch. Returns the cache (or empty) on error so
  /// the UI degrades gracefully instead of throwing.
  Future<List<EventCategoryItem>> getCategories({
    bool forceRefresh = false,
  }) async {
    if (_cache != null && !forceRefresh) return _cache!;
    try {
      final rows = await SupabaseConfig.client
          .from('event_categories')
          .select('key, label, emoji, sort_order')
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final list = (rows as List)
          .map((e) => EventCategoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache = list;
      return list;
    } catch (e) {
      print('❌ EventCategoryService.getCategories: $e');
      return _cache ?? const [];
    }
  }
}
