import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stream_feeds/stream_feeds.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class StreamService {
  static final StreamService _instance = StreamService._internal();
  factory StreamService() => _instance;
  StreamService._internal();

  late StreamFeedsClient _client;
  StreamFeedsClient get client => _client;

  bool _isInitialized = false;

  Future<void> init(String userId) async {
    if (_isInitialized) return;

    final apiKey = dotenv.env['STREAM_API_KEY'];
    final secretKey = dotenv.env['STREAM_SECRET_KEY'];

    if (apiKey == null || secretKey == null) {
      print('❌ Stream credentials missing in .env');
      return;
    }

    // ⚠️ SECURITY WARNING: Token generation should happen server-side.
    // We are doing it client-side ONLY for prototyping/speed.
    final token = _generateToken(userId, secretKey);

    // Initialize Client
    _client = StreamFeedsClient(
      apiKey: apiKey,
      user: User(id: userId),
      tokenProvider: TokenProvider.static(UserToken(token)),
    );

    // Connect to websocket
    await _client.connect();

    _isInitialized = true;
    print('✅ Stream Client Initialized for user: $userId');
  }

  /// Generates a JWT token for the user using the Secret Key.
  /// Uses HMAC SHA256 signature.
  String _generateToken(String userId, String secret) {
    // Header
    final header = base64Url
        .encode(utf8.encode(json.encode({'typ': 'JWT', 'alg': 'HS256'})))
        .replaceAll('=', '');

    // Payload
    final payload = base64Url
        .encode(utf8.encode(json.encode({'user_id': userId})))
        .replaceAll('=', '');

    // Signature
    final data = '$header.$payload';
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(data));
    final signature = base64Url.encode(digest.bytes).replaceAll('=', '');

    return '$data.$signature';
  }

  /// Helper to get the Timeline feed (flat)
  Feed get timelineFeed => _client.feedFromId(FeedId.timeline(_client.user.id));

  /// Helper to get the User feed (where I post my activities)
  Feed get userFeed => _client.feedFromId(FeedId.user(_client.user.id));

  /// Helper to get the Notification feed
  Feed get notificationFeed =>
      _client.feedFromId(FeedId.notification(_client.user.id));

  /// Follows a target user's feed
  Future<void> followUser(String targetUserId) async {
    try {
      final myFeed = _client.feedFromId(FeedId.user(_client.user.id));
      await myFeed.follow(targetFid: FeedId.user(targetUserId));
      print('✅ Followed user: $targetUserId');
    } catch (e) {
      print('❌ Error following user: $e');
      rethrow;
    }
  }

  /// Unfollows a target user's feed
  Future<void> unfollowUser(String targetUserId) async {
    try {
      final myFeed = _client.feedFromId(FeedId.user(_client.user.id));
      await myFeed.unfollow(targetFid: FeedId.user(targetUserId));
      print('✅ Unfollowed user: $targetUserId');
    } catch (e) {
      print('❌ Error unfollowing user: $e');
      rethrow;
    }
  }

  /// Checks if the current user is following the target user
  Future<bool> isFollowing(String targetUserId) async {
    try {
      // TODO: Implement proper following check
      // The stream_feeds 0.5.0 doesn't expose a 'following' method on Feed
      // For now, we'll return false and track follows client-side or via Supabase
      // This will be enhanced in a future update
      print('⚠️ isFollowing check not implemented - returning false');
      return false;
    } catch (e) {
      print('⚠️ Error checking follow status: $e');
      return false;
    }
  }
}
