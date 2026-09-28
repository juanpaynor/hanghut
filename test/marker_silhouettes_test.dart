import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/features/map/widgets/marker_silhouettes.dart';

/// Geometry only — no rasterising. Path.getBounds and Path.contains are pure
/// CPU, so these run in milliseconds and still catch the failures that matter:
/// a shape clipped at the bitmap edge, a tail that does not reach the point it
/// claims, or notches that were never actually subtracted.
void main() {
  const body = MarkerSilhouettes.kMarkerBody;          // 120
  const tall = MarkerSilhouettes.kHangoutMarkerHeight; // 140

  group('hangout — round head + tail', () {
    test('fits inside the bitmap it is registered at', () {
      final b = MarkerSilhouettes.roundPinPath(inset: 3).getBounds();
      expect(b.left, greaterThanOrEqualTo(0.0));
      expect(b.top, greaterThanOrEqualTo(0.0));
      expect(b.right, lessThanOrEqualTo(body));
      expect(b.bottom, lessThanOrEqualTo(tall));
    });

    test('uses the full height the caller reserves for it', () {
      // If the tail stopped short, every hangout would float above its pin.
      expect(MarkerSilhouettes.roundPinPath().getBounds().bottom, tall);
    });

    test('is solid from head centre down to the tail tip', () {
      final pin = MarkerSilhouettes.roundPinPath();
      for (double y = body / 2; y < tall - 1; y += 2) {
        expect(pin.contains(Offset(body / 2, y)), isTrue,
            reason: 'hole in the outline at y=$y');
      }
    });

    test('leaves the bitmap corners empty', () {
      final pin = MarkerSilhouettes.roundPinPath();
      for (final c in const [
        Offset(2, 2), Offset(118, 2), Offset(2, 138), Offset(118, 138),
      ]) {
        expect(pin.contains(c), isFalse, reason: 'opaque corner at $c');
      }
    });

    test('content sits inside the head, clear of the stroke', () {
      final r = MarkerSilhouettes.roundPinContentRect();
      final pin = MarkerSilhouettes.roundPinPath(inset: 3);
      expect(pin.contains(r.topCenter), isTrue);
      expect(pin.contains(r.centerLeft), isTrue);
      expect(r.width, lessThan(body - 12));
    });
  });

  group('event — ticket stub', () {
    test('fits inside its 120x120 bitmap', () {
      final b = MarkerSilhouettes.ticketPath(inset: 3).getBounds();
      expect(b.left, greaterThanOrEqualTo(0.0));
      expect(b.top, greaterThanOrEqualTo(0.0));
      expect(b.right, lessThanOrEqualTo(body));
      expect(b.bottom, lessThanOrEqualTo(body));
    });

    test('the side notches are really cut out', () {
      // This is the whole point of the shape. If Path.combine silently failed
      // the event marker would be a plain rounded square again.
      final t = MarkerSilhouettes.ticketPath(inset: 3);
      expect(t.contains(const Offset(60, 60)), isTrue, reason: 'body missing');
      expect(t.contains(const Offset(5, 60)), isFalse,
          reason: 'left notch not cut');
      expect(t.contains(const Offset(115, 60)), isFalse,
          reason: 'right notch not cut');
      // …and the sides are still solid away from the notch.
      expect(t.contains(const Offset(6, 25)), isTrue);
      expect(t.contains(const Offset(114, 95)), isTrue);
    });

    test('has no tail — that is what separates it from a hangout', () {
      expect(MarkerSilhouettes.ticketPath().getBounds().bottom,
          lessThanOrEqualTo(body));
    });
  });

  group('the types stay distinguishable', () {
    test('hangout and event differ below the body, not just in colour', () {
      final pin = MarkerSilhouettes.roundPinPath();
      final ticket = MarkerSilhouettes.ticketPath();
      expect(pin.getBounds().height, greaterThan(ticket.getBounds().height));
    });

    test('hangout is round-headed where the ticket is square', () {
      final pin = MarkerSilhouettes.roundPinPath();
      final ticket = MarkerSilhouettes.ticketPath();
      // Top-left of the head: inside a square, outside a circle.
      const corner = Offset(12, 12);
      expect(ticket.contains(corner), isTrue);
      expect(pin.contains(corner), isFalse);
    });
  });
}
