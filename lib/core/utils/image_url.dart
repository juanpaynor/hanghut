import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Resize modes the Storage render endpoint accepts.
///
/// `cover` crops to fill the box (right for a circle); `contain` fits inside
/// it (right for a photo you must not crop). `fill` stretches and is
/// deliberately not offered.
enum ImageFit { cover, contain }

/// Rewrites Supabase Storage URLs to request a correctly-sized image.
///
/// ## Why this exists
///
/// Nothing in the app resized images. Stored objects are whatever the phone
/// produced — the largest object in `profile-photos` is **4.5 MB**, painted
/// into a 48-pixel circle (and a 20-pixel one in the inbox). Measured against
/// production storage:
///
/// ```
/// original                                     4,523,625 bytes
/// width=80                                        46,867
/// width=80&quality=70                             36,637
/// width=80&height=80&resize=cover&quality=70       2,382   ← 1,899x smaller
/// ```
///
/// ## Two traps this class exists to avoid
///
/// 1. **Appending params to the `object` path does nothing.** Verified against
///    prod: `/storage/v1/object/public/...?width=80` returns the full
///    4,523,625 bytes with a 200. It fails *silently*, so the naive fix looks
///    shipped and changes nothing. Transformation only happens on the
///    `/storage/v1/render/image/public/` endpoint.
/// 2. **`width` alone is a 20x miss.** Without a `height` and a `resize` mode
///    the result is 36,637 bytes rather than 2,382. Both axes and the mode are
///    always emitted together; there is no partial-transform path.
///
/// Host-agnostic by construction: it rewrites on the `/storage/v1/object/`
/// path segment, so it covers both hosts present in the data
/// (`api.hanghut.com`, 91 rows; `<ref>.supabase.co`, 63 rows).
///
/// Non-Supabase URLs pass through untouched — Google Sign-In avatars, Mapbox,
/// third-party GIFs — so it is safe to wrap around any image URL in the app.
class ImageUrl {
  ImageUrl._();

  static const _objectMarker = '/storage/v1/object/public/';
  static const _renderMarker = '/storage/v1/render/image/public/';

  /// Upper bound on the device-pixel multiplier. A 3x phone asking for a 48pt
  /// avatar wants 144px; past 3x the extra bytes buy nothing anyone can see,
  /// and 4x screens would otherwise double egress for no visible gain.
  static const _maxPixelRatio = 3.0;

  /// Largest edge we will ever request, guarding against a caller passing an
  /// unbounded constraint and silently asking for a full-size render.
  static const _maxEdge = 1600;

  /// Fallback DPR when no [BuildContext] is available.
  ///
  /// 3x, deliberately the maximum rather than a middle guess. A 48pt avatar at
  /// 3x is ~5 kB where the untransformed original is 4,523,625 — so choosing
  /// 2x to "save bytes" would save two kilobytes out of four and a half
  /// megabytes, while making every avatar visibly soft on most phones in the
  /// Philippines. Softness is the one regression a user would actually notice
  /// and report, so it is the one we refuse to risk.
  static const _assumedPixelRatio = 3.0;

  /// A square, cropped render — avatars, thumbnails, map markers.
  ///
  /// [logicalSize] is in logical pixels (the number you passed to the widget);
  /// device pixel ratio is applied internally, so pass the size you laid out.
  static String avatar(String url, double logicalSize, {BuildContext? context}) {
    final px = _toDevicePx(logicalSize, context);
    return sized(url, width: px, height: px, fit: ImageFit.cover, quality: 70);
  }

  /// [avatar] for a URL that may be null or empty; returns it unchanged.
  static String? avatarOrNull(String? url, double logicalSize, {BuildContext? context}) {
    if (url == null || url.trim().isEmpty) return url;
    return avatar(url, logicalSize, context: context);
  }

  /// A width-constrained render that keeps its aspect ratio — feed images,
  /// event covers, story frames.
  ///
  /// Height is derived from [aspectRatio] (width / height) so both axes are
  /// always sent; see trap 2. `contain` means the origin never crops, so an
  /// imprecise ratio costs a little height, never content.
  static String scaled(
    String url,
    double logicalWidth, {
    double aspectRatio = 4 / 3,
    BuildContext? context,
    int quality = 75,
  }) {
    final w = _toDevicePx(logicalWidth, context);
    final safeRatio = (aspectRatio.isFinite && aspectRatio > 0) ? aspectRatio : 4 / 3;
    final h = (w / safeRatio).round().clamp(1, _maxEdge);
    return sized(url, width: w, height: h, fit: ImageFit.contain, quality: quality);
  }

  /// [scaled] for a URL that may be null or empty; returns it unchanged.
  static String? scaledOrNull(
    String? url,
    double logicalWidth, {
    double aspectRatio = 4 / 3,
    BuildContext? context,
    int quality = 75,
  }) {
    if (url == null || url.trim().isEmpty) return url;
    return scaled(url, logicalWidth,
        aspectRatio: aspectRatio, context: context, quality: quality);
  }

  /// Caps the image's **longest edge** at [longestEdgePx] physical pixels,
  /// preserving aspect ratio and never cropping.
  ///
  /// Preferred over [scaled] for photos of unknown shape. Verified against the
  /// render endpoint: `resize=contain` fits the image inside the box, so an
  /// equal width and height bounds whichever edge is longer without needing to
  /// know the orientation. Asking for `1200x900 contain` on a square source
  /// returned 900x900 — bounded, never stretched, never cropped.
  ///
  /// Takes physical pixels, not logical: call sites for this are photos that
  /// already declare a decode cap (`memCacheWidth`), which is also physical.
  static String capped(String url, int longestEdgePx, {int quality = 75}) {
    return sized(url,
        width: longestEdgePx,
        height: longestEdgePx,
        fit: ImageFit.contain,
        quality: quality);
  }

  /// [capped] for a URL that may be null or empty; returns it unchanged.
  static String? cappedOrNull(String? url, int longestEdgePx, {int quality = 75}) {
    if (url == null || url.trim().isEmpty) return url;
    return capped(url, longestEdgePx, quality: quality);
  }

  /// The primitive. Returns [url] unchanged when it is not a transformable
  /// Supabase object URL.
  static String sized(
    String url, {
    required int width,
    required int height,
    ImageFit fit = ImageFit.cover,
    int quality = 75,
  }) {
    final raw = url.trim();
    if (raw.isEmpty) return url;

    // Already rendered: leave it alone rather than stacking a second set of
    // params on the first, where the earlier (larger) width could win
    // depending on how the origin resolves duplicate keys.
    if (raw.contains(_renderMarker)) return raw;
    if (!raw.contains(_objectMarker)) return raw;

    final w = width.clamp(1, _maxEdge);
    final h = height.clamp(1, _maxEdge);

    // Preserve any existing query. `group_service` appends `?t=<millis>` at
    // upload time — the filename is fixed via upsert, so that timestamp is the
    // only thing distinguishing a new group photo from the old one. Dropping
    // it would pin every group to its first-ever image.
    final split = raw.indexOf('?');
    final path = split == -1 ? raw : raw.substring(0, split);
    final existing = split == -1 ? '' : raw.substring(split + 1);

    final rendered = path.replaceFirst(_objectMarker, _renderMarker);
    final params = <String>[
      if (existing.isNotEmpty) existing,
      'width=$w',
      'height=$h',
      'resize=${fit.name}',
      'quality=${quality.clamp(20, 100)}',
    ];

    return '$rendered?${params.join('&')}';
  }

  static int _toDevicePx(double logical, BuildContext? context) {
    if (!logical.isFinite || logical <= 0) return 96;
    final dpr = context == null
        ? _assumedPixelRatio
        : MediaQuery.devicePixelRatioOf(context).clamp(1.0, _maxPixelRatio);
    return math.max(1, (logical * dpr).round()).clamp(1, _maxEdge);
  }
}
