import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:bitemates/main.dart'; // navigatorKey
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';

/// Handles incoming iOS Universal Links / Android App Links.
///
/// Only acts on our own https://*.hanghut.com links so it never interferes with
/// supabase_flutter's OAuth callback handling (which uses app_links internally
/// for the custom-scheme / auth redirect). Anything that isn't a hanghut.com
/// https link is ignored here.
///
/// Routing mirrors the push-notification deep-link pattern in
/// [PushNotificationService] so behaviour is consistent: we open
/// MainNavigationScreen with the relevant initial* argument, which then opens
/// the detail surface on top.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Cold start: app was launched by tapping a link.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (e) {
      print('⚠️ Deep link initial fetch failed: $e');
    }

    // Warm: app already running when the link is tapped.
    _sub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => print('⚠️ Deep link stream error: $e'),
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }

  void _handleUri(Uri uri) {
    // Strictly scope to our own Universal Links. OAuth/Supabase callbacks use a
    // different scheme/host and must fall through untouched.
    if (uri.scheme != 'https') return;
    if (uri.host != 'hanghut.com' && !uri.host.endsWith('.hanghut.com')) return;

    final segments = uri.pathSegments;
    if (segments.isEmpty) return;

    switch (segments.first) {
      case 'events':
        if (segments.length >= 2 && segments[1].trim().isNotEmpty) {
          _openEvent(segments[1]);
        }
        break;
      // '/posts/*' is intentionally not handled yet — web has no public post
      // route, so those links 404. Add a case here once the post contract +
      // web fallback page ship (see team_comms #158/#159).
    }
  }

  void _openEvent(String eventId) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigationScreen(
          initialIndex: 0,
          initialEventId: eventId,
        ),
      ),
      (route) => false,
    );
  }
}
