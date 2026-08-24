import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/services/deep_link_service.dart';
import 'package:bitemates/core/services/admin_popup_service.dart';
import 'package:bitemates/features/sharing/models/share_payload.dart';

class AdminPopupModal extends StatelessWidget {
  final Map<String, dynamic> popupData;
  final VoidCallback onDismissed;

  const AdminPopupModal({
    super.key,
    required this.popupData,
    required this.onDismissed,
  });

  Future<void> _handleAction(BuildContext context) async {
    final url = popupData['action_url'] as String?;

    // Always dismiss the modal first
    onDismissed();
    Navigator.of(context).pop();

    if (url == null || url.isEmpty) return;

    // A real action tap (not a bare dismiss) — count it. Fire-and-forget.
    AdminPopupService().recordTap(popupData['id'] as String);

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // Prefer opening our own links natively: a hanghut.com (or partner
    // subdomain) event link routes to the in-app event page via the shared
    // deep-link parser, instead of kicking the user out to the browser.
    final target = ShareLinks.parse(uri);
    if (target != null && DeepLinkService.instance.routeTarget(target)) return;

    // Anything else (external promo, form, non-routed entity) → system browser.
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = popupData['title'] as String? ?? 'Announcement';
    final body = popupData['body'] as String? ?? '';
    final imageUrl = popupData['image_url'] as String?;
    final actionText = popupData['action_text'] as String? ?? 'Learn More';
    final hasAction =
        popupData['action_url'] != null &&
        popupData['action_url'].toString().isNotEmpty;
    final layout = popupData['layout'] as String? ?? 'standard';

    void dismiss() {
      onDismissed();
      Navigator.of(context).pop();
    }

    // Image-only "poster" layout: the whole image is the button (tap = action),
    // a floating X dismisses. Falls back to the standard card if there's no
    // image to show.
    if (layout == 'image' && imageUrl != null && imageUrl.isNotEmpty) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28.0),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: hasAction ? () => _handleAction(context) : dismiss,
              child: _PopupHeaderImage(
                imageUrl: imageUrl,
                borderRadius: BorderRadius.circular(28.0),
                showBottomFade: false,
                maxHeightFactor: 0.72,
              ),
            ),
            _FloatingClose(onTap: dismiss),
          ],
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.0)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.78,
            ),
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 40.0,
                    spreadRadius: -8.0,
                    offset: const Offset(0.0, 20.0),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (imageUrl != null) _PopupHeaderImage(imageUrl: imageUrl),
                    Padding(
                      padding: EdgeInsets.only(
                        top: imageUrl != null ? 20.0 : 34.0,
                        bottom: 22.0,
                        left: 24.0,
                        right: 24.0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 23.0,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              height: 1.15,
                              color: const Color(0xFF17151C),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 10.0),
                            Text(
                              body,
                              style: GoogleFonts.inter(
                                fontSize: 15.0,
                                color: const Color(0xFF6A6672),
                                height: 1.45,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 24.0),
                          hasAction
                              ? _PopupButton(
                                  label: actionText,
                                  onTap: () => _handleAction(context),
                                  primary: true,
                                )
                              : _PopupButton(
                                  label: 'Got it',
                                  onTap: dismiss,
                                  primary: false,
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _FloatingClose(onTap: dismiss),
        ],
      ),
    );
  }
}

/// The popup's call-to-action. [primary] gets the Nebula gradient (coral→violet)
/// with a trailing arrow — for a real action; the dismiss variant is a quiet
/// tonal button so it never competes with a genuine CTA.
class _PopupButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _PopupButton({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(colors: AppTheme.brandGradient)
              : null,
          color: primary ? null : const Color(0xFFF1EFF5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: primary ? Colors.white : const Color(0xFF3A3740),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (primary) ...[
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Header image for the announcement popup. Renders at the image's NATURAL
/// aspect ratio (capped to a max height) so portrait/square uploads are shown
/// in full instead of being cropped into a fixed 16:9 frame. Any leftover space
/// for very tall images falls on the dialog's white background, so there are no
/// visible letterbox bars.
class _PopupHeaderImage extends StatefulWidget {
  final String imageUrl;

  /// Corner rounding. Header use rounds only the top; the image-only poster
  /// rounds all four corners since it is the whole dialog.
  final BorderRadiusGeometry borderRadius;

  /// The soft white fade at the bottom edge — wanted when a white card sits
  /// below the image, unwanted for a full-bleed poster.
  final bool showBottomFade;

  /// Cap on image height as a fraction of screen height.
  final double maxHeightFactor;

  const _PopupHeaderImage({
    required this.imageUrl,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(24.0)),
    this.showBottomFade = true,
    this.maxHeightFactor = 0.34,
  });

  @override
  State<_PopupHeaderImage> createState() => _PopupHeaderImageState();
}

class _PopupHeaderImageState extends State<_PopupHeaderImage> {
  late final ImageProvider _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _ratio; // width / height, resolved once the image loads
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    _provider = CachedNetworkImageProvider(widget.imageUrl);
    _stream = _provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        final h = info.image.height.toDouble();
        if (h > 0) {
          setState(() => _ratio = info.image.width.toDouble() / h);
        }
      },
      onError: (_, __) {
        if (mounted) setState(() => _errored = true);
      },
    );
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.grey[200],
            child: const Icon(Icons.error, color: Colors.grey),
          ),
        ),
      );
    }

    // Reserve a 16:9 space with a spinner until the real dimensions arrive.
    if (_ratio == null) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    final maxHeight =
        MediaQuery.of(context).size.height * widget.maxHeightFactor;
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Center(
              // The box matches the image's own ratio, so BoxFit.cover fills it
              // exactly with zero cropping. Center handles the narrower width
              // that a portrait image takes once height is capped.
              child: AspectRatio(
                aspectRatio: _ratio!,
                child: Image(
                  image: _provider,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: Colors.grey[200],
                    child: const Icon(Icons.error, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
          // Soft fade into the card's white body — kills the hard image edge.
          if (widget.showBottomFade)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 40,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withOpacity(0), Colors.white],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The floating dismiss (X) button shared by both popup layouts.
class _FloatingClose extends StatelessWidget {
  final VoidCallback onTap;

  const _FloatingClose({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 10,
      top: 10,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8),
            ],
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
