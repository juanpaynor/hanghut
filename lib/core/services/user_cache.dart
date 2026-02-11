import 'package:bitemates/core/config/supabase_config.dart';

/// Cached user profile data
class UserProfile {
  final String id;
  final String displayName;
  final String? photoUrl;
  final DateTime cachedAt;

  UserProfile({
    required this.id,
    required this.displayName,
    this.photoUrl,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  bool get isExpired {
    return DateTime.now().difference(cachedAt) > const Duration(minutes: 30);
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      displayName: map['display_name'] as String,
      photoUrl: map['photo_url'] as String?,
    );
  }
}

/// In-memory cache for user profiles to reduce redundant queries
class UserCache {
  static final UserCache _instance = UserCache._internal();
  factory UserCache() => _instance;
  UserCache._internal();

  final Map<String, UserProfile> _cache = {};

  /// Get a single user profile, fetching from DB if not cached
  Future<UserProfile?> getUser(String userId) async {
    // Check cache first
    if (_cache.containsKey(userId) && !_cache[userId]!.isExpired) {
      return _cache[userId];
    }

    // Fetch from database
    try {
      final userData = await SupabaseConfig.client
          .from('users')
          .select('id, display_name')
          .eq('id', userId)
          .maybeSingle();

      if (userData == null) return null;

      // Fetch primary photo
      final photoData = await SupabaseConfig.client
          .from('user_photos')
          .select('photo_url')
          .eq('user_id', userId)
          .eq('is_primary', true)
          .maybeSingle();

      final profile = UserProfile(
        id: userId,
        displayName: userData['display_name'] as String,
        photoUrl: photoData?['photo_url'] as String?,
      );

      _cache[userId] = profile;
      return profile;
    } catch (e) {
      print('❌ UserCache: Error fetching user $userId - $e');
      return null;
    }
  }

  /// Get multiple user profiles in a single batch query
  Future<Map<String, UserProfile>> getUsers(List<String> userIds) async {
    if (userIds.isEmpty) return {};

    // Separate cached and uncached users
    final Map<String, UserProfile> result = {};
    final List<String> uncachedIds = [];

    for (final userId in userIds) {
      if (_cache.containsKey(userId) && !_cache[userId]!.isExpired) {
        result[userId] = _cache[userId]!;
      } else {
        uncachedIds.add(userId);
      }
    }

    // Fetch uncached users
    if (uncachedIds.isEmpty) return result;

    try {
      // Fetch user data
      final users = await SupabaseConfig.client
          .from('users')
          .select('id, display_name')
          .inFilter('id', uncachedIds);

      // Fetch photos
      final photos = await SupabaseConfig.client
          .from('user_photos')
          .select('user_id, photo_url')
          .inFilter('user_id', uncachedIds)
          .eq('is_primary', true);

      final photoMap = {for (var p in photos) p['user_id']: p['photo_url']};

      // Create profiles and cache them
      for (var userData in users) {
        final profile = UserProfile(
          id: userData['id'] as String,
          displayName: userData['display_name'] as String,
          photoUrl: photoMap[userData['id']] as String?,
        );

        _cache[profile.id] = profile;
        result[profile.id] = profile;
      }

      return result;
    } catch (e) {
      print('❌ UserCache: Error fetching users - $e');
      return result;
    }
  }

  /// Get multiple users with simplified format (for reactions, etc.)
  /// Returns a map of userId -> {displayName, photoUrl}
  Future<Map<String, Map<String, dynamic>>> getMany(
    List<String> userIds,
  ) async {
    final profiles = await getUsers(userIds);
    return profiles.map((userId, profile) {
      return MapEntry(userId, {
        'displayName': profile.displayName,
        'photoUrl': profile.photoUrl,
      });
    });
  }

  /// Preload users into cache (useful for chat participants)
  Future<void> preloadUsers(List<String> userIds) async {
    await getUsers(userIds);
  }

  /// Clear a specific user from cache
  void invalidateUser(String userId) {
    _cache.remove(userId);
  }

  /// Clear all cached users
  void clearCache() {
    _cache.clear();
  }

  /// Remove expired entries from cache
  void cleanupExpired() {
    _cache.removeWhere((key, value) => value.isExpired);
  }
}
