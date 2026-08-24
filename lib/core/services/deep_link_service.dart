import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:bitemates/main.dart'; // navigatorKey
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/features/sharing/models/share_payload.dart';

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
    // One shared parser (ShareLinks) owns the URL contract, so deep-link routing
    // and share-link building can never drift. Non-entity links (OAuth/Supabase
    // callbacks, unknown paths) parse to null and fall through untouched.
    final target = ShareLinks.parse(uri);
    if (target == null) return;
    routeTarget(target);
  }

  /// Routes an already-parsed deep-link target to the right in-app surface.
  ///
  /// Returns true if it navigated somewhere, false if this entity type isn't
  /// wired up yet — callers that have the original URL (e.g. admin popups) can
  /// then fall back to opening it in the browser so the web landing page shows.
  bool routeTarget(({ShareEntityType type, String id}) target) {
    switch (target.type) {
      case ShareEntityType.event:
        _openEvent(target.id);
        return true;
      case ShareEntityType.hangout:
      case ShareEntityType.experience:
      case ShareEntityType.post:
        // Parsed but not yet routed. These wait on (a) web landing routes so
        // the links don't 404 for non-app users, and (b) an open-by-id surface
        // on our side. Wired per-type in Phase 1/3 as each ships.
        return false;
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
