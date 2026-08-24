class AppConstants {
  static const String privacyPolicyUrl = 'https://hanghut.com/privacy-policy';
  static const String termsOfServiceUrl =
      'https://hanghut.com/terms-of-service';

  /// Canonical web origin. Shared links use this so they resolve as iOS
  /// Universal Links / Android App Links and open the app (see
  /// DeepLinkService — paths here must match the routes it handles).
  static const String webBaseUrl = 'https://hanghut.com';

  /// Public link to an event detail page. Opens the app when installed,
  /// falls back to the web event page otherwise.
  static String eventUrl(String eventId) => '$webBaseUrl/events/$eventId';

  /// Organizer web dashboard — the full event builder (custom email templates,
  /// seat maps, page design, subscriber access) lives here; the app exposes a
  /// simpler subset. Route group `(dashboard)` is omitted from the URL.
  static const String organizerDashboardUrl = '$webBaseUrl/organizer';
  static const String organizerCreateEventUrl =
      '$webBaseUrl/organizer/events/create';
}
