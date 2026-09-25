import 'package:bitemates/features/ticketing/services/registration_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// team_comms #334: the answer for a `file` question is JSON-in-text with the
/// shape web writes, so one organizer Responses tab renders both platforms.
void main() {
  group('content type', () {
    test('maps the allowlisted extensions', () {
      expect(RegistrationFileService.contentTypeFor('id.JPG'), 'image/jpeg');
      expect(RegistrationFileService.contentTypeFor('id.jpeg'), 'image/jpeg');
      expect(RegistrationFileService.contentTypeFor('scan.png'), 'image/png');
      expect(RegistrationFileService.contentTypeFor('a.webp'), 'image/webp');
      expect(RegistrationFileService.contentTypeFor('IMG_1.heic'), 'image/heic');
      expect(RegistrationFileService.contentTypeFor('form.pdf'), 'application/pdf');
    });

    test('anything else is refused before an upload starts', () {
      expect(RegistrationFileService.contentTypeFor('virus.exe'), isNull);
      expect(RegistrationFileService.contentTypeFor('noextension'), isNull);
      expect(RegistrationFileService.contentTypeFor('clip.mp4'), isNull);
    });

    test('every mapped type is on the allowlist we send', () {
      for (final name in ['a.jpg', 'a.png', 'a.webp', 'a.heic', 'a.pdf']) {
        expect(
          RegistrationFileService.allowedTypes
              .contains(RegistrationFileService.contentTypeFor(name)),
          isTrue,
          reason: name,
        );
      }
    });

    test('the cap matches the documented 10 MB', () {
      expect(RegistrationFileService.maxBytes, 10 * 1024 * 1024);
    });
  });

  group('answer encoding', () {
    final answer = {
      'path': '<event>/<question>/abc.png',
      'name': 'id.png',
      'size': 12345,
      'type': 'image/png',
    };

    test('round-trips through the text column', () {
      final encoded = RegistrationFileService.encodeAnswer(answer);
      expect(encoded, isA<String>());
      expect(RegistrationFileService.decodeAnswer(encoded), answer);
    });

    test('accepts a map that never went through the DB', () {
      expect(RegistrationFileService.decodeAnswer(answer), answer);
    });

    test('a sentence from the old text fallback decodes to null, not a throw', () {
      expect(RegistrationFileService.decodeAnswer('I will bring it on the day'),
          isNull);
      expect(RegistrationFileService.decodeAnswer(''), isNull);
      expect(RegistrationFileService.decodeAnswer(null), isNull);
    });
  });
}
