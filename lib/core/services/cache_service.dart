/// Simple in-memory cache service with TTL support
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final Map<String, _CacheEntry> _cache = {};
  final int _maxSize = 100; // Maximum cache entries
  final Duration _defaultTTL = const Duration(minutes: 5);

  /// Get cached value
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    // Check if expired
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    // Update access time for LRU
    entry.lastAccessed = DateTime.now();
    return entry.value as T?;
  }

  /// Set cached value with optional TTL
  void set(String key, dynamic value, {Duration? ttl}) {
    // Evict oldest entries if cache is full
    if (_cache.length >= _maxSize) {
      _evictOldest();
    }

    _cache[key] = _CacheEntry(value: value, ttl: ttl ?? _defaultTTL);
  }

  /// Remove specific key
  void remove(String key) {
    _cache.remove(key);
  }

  /// Clear all cache
  void clear() {
    _cache.clear();
  }

  /// Clear expired entries
  void clearExpired() {
    _cache.removeWhere((key, entry) => entry.isExpired);
  }

  /// Invalidate cache by prefix (e.g., "feed_*")
  void invalidateByPrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Evict oldest accessed entry (LRU)
  void _evictOldest() {
    if (_cache.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (var entry in _cache.entries) {
      if (oldestTime == null || entry.value.lastAccessed.isBefore(oldestTime)) {
        oldestKey = entry.key;
        oldestTime = entry.value.lastAccessed;
      }
    }

    if (oldestKey != null) {
      _cache.remove(oldestKey);
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    int validCount = 0;
    int expiredCount = 0;

    for (var entry in _cache.values) {
      if (entry.isExpired) {
        expiredCount++;
      } else {
        validCount++;
      }
    }

    return {
      'totalEntries': _cache.length,
      'validEntries': validCount,
      'expiredEntries': expiredCount,
      'maxSize': _maxSize,
    };
  }
}

class _CacheEntry {
  final dynamic value;
  final DateTime createdAt;
  DateTime lastAccessed;
  final Duration ttl;

  _CacheEntry({required this.value, required this.ttl})
    : createdAt = DateTime.now(),
      lastAccessed = DateTime.now();

  bool get isExpired => DateTime.now().difference(createdAt) > ttl;
}
