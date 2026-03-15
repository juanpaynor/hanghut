import 'package:firebase_analytics/firebase_analytics.dart';

/// Centralized analytics service wrapping Firebase Analytics.
/// Usage: AnalyticsService().logEvent('event_name', {'key': 'value'});
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Get the observer for MaterialApp's navigatorObservers
  /// This automatically tracks screen views on navigation.
  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  // ─── Screen Tracking ───

  Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }

  // ─── Auth Events ───

  Future<void> logLogin(String method) async {
    await _analytics.logLogin(loginMethod: method);
  }

  Future<void> logSignUp(String method) async {
    await _analytics.logSignUp(signUpMethod: method);
  }

  Future<void> setUserId(String? userId) async {
    await _analytics.setUserId(id: userId);
  }

  Future<void> setUserProperty(String name, String value) async {
    await _analytics.setUserProperty(name: name, value: value);
  }

  // ─── Social Events ───

  Future<void> logJoinTable(String tableId) async {
    await _analytics.logJoinGroup(groupId: tableId);
  }

  Future<void> logCreateTable(String tableId) async {
    await _analytics.logEvent(
      name: 'create_table',
      parameters: {'table_id': tableId},
    );
  }

  Future<void> logSendMessage(String chatType) async {
    await _analytics.logEvent(
      name: 'send_message',
      parameters: {'chat_type': chatType},
    );
  }

  Future<void> logSendDM(String recipientId) async {
    await _analytics.logEvent(
      name: 'send_dm',
      parameters: {'recipient_id': recipientId},
    );
  }

  // ─── Map & Discovery Events ───

  Future<void> logMapFilter(String filterName) async {
    await _analytics.logEvent(
      name: 'map_filter',
      parameters: {'filter': filterName},
    );
  }

  Future<void> logViewStory(String storyId) async {
    await _analytics.logEvent(
      name: 'view_story',
      parameters: {'story_id': storyId},
    );
  }

  Future<void> logCreateStory() async {
    await _analytics.logEvent(name: 'create_story');
  }

  // ─── Event & Experience Events ───

  Future<void> logViewEvent(String eventId) async {
    await _analytics.logEvent(
      name: 'view_event',
      parameters: {'event_id': eventId},
    );
  }

  Future<void> logPurchaseTicket(String eventId, double price, String currency) async {
    await _analytics.logPurchase(
      currency: currency,
      value: price,
      items: [AnalyticsEventItem(itemId: eventId, itemCategory: 'event_ticket')],
    );
  }

  Future<void> logViewExperience(String experienceId) async {
    await _analytics.logEvent(
      name: 'view_experience',
      parameters: {'experience_id': experienceId},
    );
  }

  // ─── Trip Events ───

  Future<void> logCreateTrip(String destination) async {
    await _analytics.logEvent(
      name: 'create_trip',
      parameters: {'destination': destination},
    );
  }

  Future<void> logJoinTripChat(String chatId) async {
    await _analytics.logEvent(
      name: 'join_trip_chat',
      parameters: {'chat_id': chatId},
    );
  }

  // ─── Feed Events ───

  Future<void> logLikePost(String postId) async {
    await _analytics.logEvent(
      name: 'like_post',
      parameters: {'post_id': postId},
    );
  }

  Future<void> logCommentPost(String postId) async {
    await _analytics.logEvent(
      name: 'comment_post',
      parameters: {'post_id': postId},
    );
  }

  Future<void> logSharePost(String postId) async {
    await _analytics.logShare(
      contentType: 'post',
      itemId: postId,
      method: 'in_app',
    );
  }

  // ─── Profile Events ───

  Future<void> logViewProfile(String userId) async {
    await _analytics.logEvent(
      name: 'view_profile',
      parameters: {'viewed_user_id': userId},
    );
  }

  Future<void> logEditProfile() async {
    await _analytics.logEvent(name: 'edit_profile');
  }

  // ─── Generic Event ───

  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    await _analytics.logEvent(name: name, parameters: parameters);
  }
}
