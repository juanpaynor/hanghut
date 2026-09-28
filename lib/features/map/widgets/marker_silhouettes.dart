import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

/// The shape language for map markers.
///
/// Extracted from map_screen.dart so the geometry has one definition and can be
/// verified in a test — a clipped stroke, or a seam where the tail meets the
/// body, is invisible in code review and obvious in a rendered bitmap.
class MarkerSilhouettes {
  const MarkerSilhouettes._();

  // ═══════════════════════ MARKER SILHOUETTES ═══════════════════════
  //
  // Marker type is read from SHAPE first and colour second.
  //
  // Colour alone could not carry it. Markers render at 60 logical pixels (a
  // 120px bitmap registered at scale 2.0), where a ring is thin, sits against
  // an arbitrary photo, and is invisible to roughly 1 in 12 men. Four of the
  // five types also sat inside a 44° band of blue-violet — hangout 218°,
  // story 239°, event 256°, mystery 262° — at near-identical saturation and
  // lightness. Worse, THREE of them drew the same rounded rectangle: 171 of
  // 176 hangouts (the emoji and custom-image variants) were the same
  // silhouette as Experience and Mystery.
  //
  // Each type now owns a unique COMBINATION of head shape, tail and frame:
  //
  //   Hangout     round head  + tail    — a person, pinned to a place
  //   Experience  square head + tail    — curated, pinned to a place
  //   Event       ticket stub, notched  — a thing you buy into
  //   Mystery     square head, no tail  + "?"
  //   Story       no frame at all, aura — ephemeral
  //
  // The test is whether they are still distinguishable as black-and-white
  // blobs. No two of those five are. Keep it that way: if you add a type, give
  // it a new combination rather than a new colour.

  /// Height of the pointer below a pinned marker's body.
  static const double kMarkerTail = 20.0;

  /// The square body every marker bitmap is drawn into.
  static const double kMarkerBody = 120.0;

  /// Bitmap height for the pinned (tailed) hangout markers.
  static const double kHangoutMarkerHeight = kMarkerBody + kMarkerTail; // 140

  /// Round-headed pin — the hangout silhouette.
  ///
  /// The tail's upper corners are placed ON the circle rather than at its
  /// bounding box, so body and tail fuse into one outline with no seam for the
  /// stroke to trace. [inset] shrinks the whole shape so a stroke drawn along
  /// it stays inside the bitmap instead of being clipped at the edges.
  static Path roundPinPath({double inset = 0}) {
    final double r = kMarkerBody / 2 - inset;
    final Offset c = const Offset(kMarkerBody / 2, kMarkerBody / 2);
    const double halfWidth = 13.0;
    // Vertical offset from the centre at which the tail meets the circle.
    final double dy = sqrt(max(0.0, r * r - halfWidth * halfWidth));

    return Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..moveTo(c.dx - halfWidth, c.dy + dy)
      ..lineTo(c.dx, kMarkerBody + kMarkerTail - inset)
      ..lineTo(c.dx + halfWidth, c.dy + dy)
      ..close();
  }

  /// The circle a round pin's content (photo, emoji) is drawn inside, leaving
  /// room for the white frame and its coloured stroke.
  static Rect roundPinContentRect({double inset = 12}) => Rect.fromCircle(
        center: const Offset(kMarkerBody / 2, kMarkerBody / 2),
        radius: kMarkerBody / 2 - inset,
      );

  /// Paints the shared round-pin frame: shadow, white body, coloured edge.
  /// Content is drawn on top, clipped to [roundPinContentRect].
  static void paintRoundPinFrame(Canvas canvas, Color edge) {
    final Path pin = roundPinPath(inset: 3);
    canvas.drawShadow(pin, Colors.black.withOpacity(0.5), 4.0, true);
    canvas.drawPath(pin, Paint()..color = Colors.white);
    canvas.drawPath(
      pin,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
  }

  /// Ticket stub — the event silhouette.
  ///
  /// A rounded square with a semicircular notch bitten out of each side at
  /// mid-height, the way a torn ticket looks. Events previously drew a plain
  /// circle, which left them sharing a head shape with the hangout pin; the
  /// notches are what make the two tell apart as black-and-white blobs.
  static Path ticketPath({double inset = 0}) {
    final double s = kMarkerBody - inset * 2;
    final Rect body = Rect.fromLTWH(inset, inset, s, s);
    const double notch = 11.0;

    final Path path = Path()
      ..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(10)));

    // Subtract a notch from each side, centred vertically.
    final Path notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(body.left, body.center.dy), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(body.right, body.center.dy), radius: notch));

    return Path.combine(PathOperation.difference, path, notches);
  }

  /// The square a ticket's cover image is drawn inside, clear of the stroke.
  static Rect ticketContentRect({double inset = 9}) =>
      Rect.fromLTWH(inset, inset, kMarkerBody - inset * 2, kMarkerBody - inset * 2);
}
