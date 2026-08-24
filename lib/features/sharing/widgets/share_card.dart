import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bitemates/features/sharing/models/share_payload.dart';

/// One reusable presentation of a [SharePayload], used everywhere something is
/// shared — a chat bubble, a link preview, a story sticker. Keeps every share
/// surface visually consistent and entity-agnostic.
///
/// Pure presentation: give it a payload, an optional [onTap] (open the entity),
/// and an optional [action] (e.g. an inline RSVP/Buy button for chat bubbles).
class ShareCard extends StatelessWidget {
  final SharePayload payload;
  final VoidCallback? onTap;
  final Widget? action;

  /// Compact removes the large image (for tight spaces / dense lists).
  final bool compact;

  const ShareCard({
    super.key,
    required this.payload,
    this.onTap,
    this.action,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;

    return Material(
      color: isDark ? const Color(0xFF23232E) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact && payload.imageUrl != null)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: payload.imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: primary.withValues(alpha: 0.08),
                    ),
                    errorWidget: (_, __, ___) => _imageFallback(primary),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Type label — the "what kind of thing is this" eyebrow.
                    Text(
                      payload.type.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      payload.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (payload.subtitle != null &&
                        payload.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        payload.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: 10),
                      action!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageFallback(Color primary) => Container(
        color: primary.withValues(alpha: 0.10),
        alignment: Alignment.center,
        child: Icon(
          Icons.workspace_premium_rounded,
          color: primary.withValues(alpha: 0.5),
          size: 32,
        ),
      );
}
