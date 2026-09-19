import 'package:bitemates/core/utils/image_url.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  const obj = 'https://api.hanghut.com/storage/v1/object/public/profile-photos/a.jpg';
  const objT = '$obj?t=123';
  const ren = 'https://api.hanghut.com/storage/v1/render/image/public/profile-photos/a.jpg?t=123&width=80&height=80&resize=cover&quality=70';
  test('nothing produces a render URL', () {
    for (final u in [obj, objT, ren]) {
      for (final out in [
        ImageUrl.avatar(u, 48), ImageUrl.scaled(u, 300), ImageUrl.capped(u, 1200),
        ImageUrl.sized(u, width: 10, height: 10),
      ]) {
        expect(out.contains('/render/image/'), isFalse, reason: out);
      }
    }
    expect(ImageUrl.avatar(objT, 48), objT);      // cache-buster kept
    expect(ImageUrl.avatar(ren, 48), objT);       // persisted render URL mapped back
    expect(ImageUrl.avatar(obj, 48), obj);
  });
}
