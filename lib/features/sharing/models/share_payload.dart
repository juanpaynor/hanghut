import 'dart:convert';
import 'package:bitemates/core/constants/app_constants.dart';
import 'package:bitemates/features/ticketing/models/event.dart';

/// The kinds of things that can be shared. `slug` is the canonical URL segment
/// in the `https://hanghut.com/{slug}/{id}` deep-link contract (coordinated with
/// web in team_comms — see the Phase 0 share thread).
enum ShareEntityType {
  event('events', 'Event'),
  hangout('hangouts', 'Hangout'),
  experience('experiences', 'Experience'),
  post('posts', 'Post');

  const ShareEntityType(this.slug, this.label);

  final String slug;
  final String label;

  static ShareEntityType? fromSlug(String slug) {
    for (final t in ShareEntityType.values) {
      if (t.slug == slug) return t;
    }
    return null;
  }
}

/// Single source of truth for the share/deep-link URL contract, so link building
/// and link parsing can never drift apart.
class ShareLinks {
  /// Canonical shareable URL for an entity.
  static String build(ShareEntityType type, String id) =>
      '${AppConstants.webBaseUrl}/${type.slug}/$id';

  /// Parses one of our https Universal/App Links into its (type, id). Returns
  /// null for anything that isn't a hanghut.com entity link (so OAuth/other
  /// links fall through untouched).
  static ({ShareEntityType type, String id})? parse(Uri uri) {
    if (uri.scheme != 'https') return null;
    if (uri.host != 'hanghut.com' && !uri.host.endsWith('.hanghut.com')) {
      return null;
    }
    final seg = uri.pathSegments;
    if (seg.length < 2) return null;
    final type = ShareEntityType.fromSlug(seg[0]);
    final id = seg[1].trim();
    if (type == null || id.isEmpty) return null;
    return (type: type, id: id);
  }
}

/// A normalized, render-ready description of something being shared. Every share
/// surface (chat bubble, story sticker, external link preview) consumes this one
/// shape rather than each knowing about Events/Hangouts/etc.
class SharePayload {
  final ShareEntityType type;
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;

  /// Optional caption the sender attaches when sharing (rides with the card as
  /// one message, rendered above it). Null/empty on a bare entity payload.
  final String? note;

  const SharePayload({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.note,
  });

  /// Canonical deep link for this payload.
  String get deepLink => ShareLinks.build(type, id);

  /// Returns a copy carrying [note] (trimmed; blank becomes null). Used at send
  /// time to attach the sender's caption without mutating the source payload.
  SharePayload withNote(String? note) {
    final t = note?.trim();
    return SharePayload(
      type: type,
      id: id,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      note: (t == null || t.isEmpty) ? null : t,
    );
  }

  /// Copy for an external system-share (invite framing for events/hangouts/
  /// experiences, broadcast framing for posts). Ends with the deep link.
  String shareText() {
    final verb = type == ShareEntityType.post ? 'Check this out' : 'Join me at';
    final buf = StringBuffer('$verb: $title');
    if (subtitle != null && subtitle!.isNotEmpty) buf.write('\n$subtitle');
    buf.write('\n\nOpen in HangHut 👇\n$deepLink');
    return buf.toString();
  }

  /// Serialized form stored in a chat message's `content` (with content_type
  /// `'share'`). Compact + versioned so the render side can evolve safely.
  Map<String, dynamic> toMap() => {
        'v': 1,
        'type': type.slug,
        'id': id,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  String toMessageContent() => jsonEncode(toMap());

  /// Rebuilds a payload from a `'share'` message's content. Returns null if the
  /// content isn't a valid share envelope (caller falls back to plain text).
  static SharePayload? tryParseMessageContent(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      final type = ShareEntityType.fromSlug(decoded['type']?.toString() ?? '');
      final id = decoded['id']?.toString();
      final title = decoded['title']?.toString();
      if (type == null || id == null || id.isEmpty || title == null) {
        return null;
      }
      return SharePayload(
        type: type,
        id: id,
        title: title,
        subtitle: decoded['subtitle']?.toString(),
        imageUrl: decoded['imageUrl']?.toString(),
        note: decoded['note']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  factory SharePayload.fromEvent(Event event) {
    return SharePayload(
      type: ShareEntityType.event,
      id: event.id,
      title: event.title,
      subtitle: event.venueName,
      imageUrl: event.coverImageUrl ??
          (event.imageUrls.isNotEmpty ? event.imageUrls.first : null),
    );
  }

  /// Builds a payload from a hangout feed-card map. The shared id is the
  /// underlying `tables` row (metadata.table_id) so the recipient can open it
  /// in-app via TableCompactModal. Returns null if there's no table_id to point
  /// at (nothing to open).
  static SharePayload? fromHangout(Map<String, dynamic> post) {
    final metadata = post['metadata'] as Map<String, dynamic>? ?? {};
    final tableId = metadata['table_id'];
    if (tableId == null || tableId.toString().isEmpty) return null;
    final venue = metadata['venue_name'] as String?;
    final title =
        (metadata['title'] ?? venue ?? 'Hangout').toString();
    final activity = metadata['activity_type'] as String?;
    return SharePayload(
      type: ShareEntityType.hangout,
      id: tableId.toString(),
      title: title,
      subtitle: venue ?? activity,
      imageUrl: metadata['image_url'] as String?,
    );
  }

  /// Builds a payload from an experience map (a `map_ready_tables` row, as used
  /// by ExperienceDetailModal). The id is the experience/table id.
  factory SharePayload.fromExperience(Map<String, dynamic> experience) {
    final rawImages = experience['images'];
    final firstImage = (rawImages is List && rawImages.isNotEmpty)
        ? rawImages.first?.toString()
        : null;
    return SharePayload(
      type: ShareEntityType.experience,
      id: experience['id'].toString(),
      title: (experience['title'] ?? 'Experience').toString(),
      subtitle: experience['venue_name'] as String?,
      imageUrl: firstImage ?? experience['marker_image_url'] as String?,
    );
  }

  /// Builds a payload from a feed post map (as delivered by the feed RPC).
  factory SharePayload.fromPost(Map<String, dynamic> post) {
    final user = post['user'] as Map<String, dynamic>?;
    final author = (user?['display_name'] ?? 'Someone').toString();
    final content = (post['content'] as String?)?.trim() ?? '';
    final images = post['image_urls'] as List?;
    final image = (post['image_url'] as String?) ??
        (images != null && images.isNotEmpty ? images.first.toString() : null);
    return SharePayload(
      type: ShareEntityType.post,
      id: post['id'].toString(),
      title: content.isNotEmpty ? content : "$author's post",
      subtitle: author,
      imageUrl: image,
    );
  }
}
