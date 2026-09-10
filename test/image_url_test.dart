import 'package:flutter_test/flutter_test.dart';

import 'package:bitemates/core/utils/image_url.dart';

/// These tests encode facts verified against production storage, not guesses.
/// The two that matter most are "params on the object path do nothing" and
/// "width without height is a 20x miss" — both were real traps, and both would
/// have shipped a patch that appeared to work and changed nothing.
void main() {
  const supa =
      'https://rahhezqtkpvkialnduft.supabase.co/storage/v1/object/public/profile-photos/u1/a.jpg';
  const custom =
      'https://api.hanghut.com/storage/v1/object/public/profile-photos/u1/a.jpg';

  group('ImageUrl.sized', () {
    test('rewrites the object path to the render endpoint', () {
      final out = ImageUrl.sized(supa, width: 80, height: 80);
      expect(out, contains('/storage/v1/render/image/public/'));
      expect(out, isNot(contains('/storage/v1/object/public/')));
    });

    test('always emits both axes and a resize mode', () {
      // The whole point: width alone returned 36,637 bytes against prod where
      // width+height+resize returned 2,382.
      final out = ImageUrl.sized(supa, width: 80, height: 80, quality: 70);
      expect(out, contains('width=80'));
      expect(out, contains('height=80'));
      expect(out, contains('resize=cover'));
      expect(out, contains('quality=70'));
    });

    test('works on the custom domain as well as the supabase.co host', () {
      // 91 stored URLs use api.hanghut.com, 63 use <ref>.supabase.co.
      final out = ImageUrl.sized(custom, width: 48, height: 48);
      expect(out, startsWith('https://api.hanghut.com/storage/v1/render/image/public/'));
    });

    test('leaves non-Supabase URLs completely alone', () {
      const google = 'https://lh3.googleusercontent.com/a/ACg8ocK=s96-c';
      expect(ImageUrl.sized(google, width: 80, height: 80), google);
    });

    test('is idempotent — never stacks params on an already-rendered URL', () {
      final once = ImageUrl.sized(supa, width: 80, height: 80);
      final twice = ImageUrl.sized(once, width: 400, height: 400);
      expect(twice, once);
      expect(twice.split('width=').length - 1, 1);
    });

    test('preserves an existing cache-busting query', () {
      // group_service appends ?t=<millis> at upload time; the filename is
      // fixed via upsert, so dropping it pins the group to its first image.
      const busted = '$supa?t=1725900000000';
      final out = ImageUrl.sized(busted, width: 48, height: 48);
      expect(out, contains('t=1725900000000'));
      expect(out, contains('width=48'));
      expect(out, contains('/render/image/public/'));
    });

    test('clamps an absurd request rather than asking for a full render', () {
      final out = ImageUrl.sized(supa, width: 99999, height: 99999);
      expect(out, contains('width=1600'));
      expect(out, contains('height=1600'));
    });

    test('empty string is returned unchanged', () {
      expect(ImageUrl.sized('', width: 80, height: 80), '');
    });
  });

  group('ImageUrl.avatar', () {
    test('applies the assumed 3x device ratio with no context', () {
      // 48 logical px on a 3x screen needs 144 real px.
      final out = ImageUrl.avatar(supa, 48);
      expect(out, contains('width=144'));
      expect(out, contains('height=144'));
      expect(out, contains('resize=cover'));
    });

    test('a 20px inbox avatar asks for 60px, not 4.5 MB', () {
      final out = ImageUrl.avatar(supa, 20);
      expect(out, contains('width=60'));
      expect(out, contains('height=60'));
    });

    test('avatarOrNull passes null and empty through', () {
      expect(ImageUrl.avatarOrNull(null, 48), isNull);
      expect(ImageUrl.avatarOrNull('', 48), '');
      expect(ImageUrl.avatarOrNull('   ', 48), '   ');
    });
  });

  group('ImageUrl.scaled', () {
    test('derives height from the aspect ratio so both axes are sent', () {
      final out = ImageUrl.scaled(supa, 400, aspectRatio: 16 / 9);
      expect(out, contains('width=1200')); // 400 logical x 3 DPR
      expect(out, contains('height=675')); // 1200 / (16/9)
      expect(out, contains('resize=contain'));
    });

    test('falls back to 4:3 when handed a nonsense ratio', () {
      final out = ImageUrl.scaled(supa, 300, aspectRatio: 0);
      expect(out, contains('width=900'));
      expect(out, contains('height=675'));
    });

    test('does not crop — contain, never cover', () {
      expect(ImageUrl.scaled(supa, 400), contains('resize=contain'));
    });

    test('scaledOrNull passes null through', () {
      expect(ImageUrl.scaledOrNull(null, 400), isNull);
    });
  });

  group('ImageUrl.capped', () {
    const supa2 =
        'https://rahhezqtkpvkialnduft.supabase.co/storage/v1/object/public/post_images/p1/a.jpg';

    test('bounds the longest edge with a square contain box', () {
      // Verified against the render endpoint: contain fits inside the box, so
      // an equal width/height caps whichever edge is longer, orientation-free.
      final out = ImageUrl.capped(supa2, 1200);
      expect(out, contains('width=1200'));
      expect(out, contains('height=1200'));
      expect(out, contains('resize=contain'));
    });

    test('takes physical pixels — no DPR multiplication', () {
      // memCacheWidth is already physical; multiplying again would ask for 3x
      // more than the decoder will ever keep.
      expect(ImageUrl.capped(supa2, 400), contains('width=400'));
    });

    test('cappedOrNull passes null and empty through', () {
      expect(ImageUrl.cappedOrNull(null, 1200), isNull);
      expect(ImageUrl.cappedOrNull('', 1200), '');
    });
  });
}
