import 'package:bitemates/core/utils/image_url.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  const r2 = 'https://pub-0b4b5a2d2c8f4f8286db841ff3a188a1.r2.dev/game-system-covers/OOUWD.jpg';
  test('R2 cover passes through ImageUrl byte-identical', () {
    expect(ImageUrl.avatar(r2, 48), r2);
    expect(ImageUrl.scaled(r2, 300), r2);
    expect(ImageUrl.capped(r2, 1290), r2);
    expect(ImageUrl.sized(r2, width: 10, height: 10), r2);
  });
}
