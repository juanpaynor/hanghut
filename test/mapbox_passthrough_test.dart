import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/core/utils/image_url.dart';

void main() {
  // The hangout card's map cover is a Mapbox Static Images URL, not a Supabase
  // object URL. ImageUrl must hand it back byte-identical: appending width/
  // height/resize/quality would corrupt the path-encoded size and drop or
  // mangle ?access_token, and the card's errorWidget is an opaque grey box,
  // so the breakage would look like a deliberately blank card.
  const mapbox =
      'https://api.mapbox.com/styles/v1/mapbox/light-v11/static/'
      'pin-l+3F51B5(122.5591148,10.7301854)/122.5591148,10.7301854,15,0/600x800@2x'
      '?access_token=pk.eyJ1IjoiZXhhbXBsZSIsImEiOiJhYmMifQ.ZmFrZQ';

  test('capped() passes a Mapbox static URL through untouched', () {
    expect(ImageUrl.capped(mapbox, 1200), mapbox);
  });

  test('avatar() passes a Mapbox static URL through untouched', () {
    expect(ImageUrl.avatar(mapbox, 40), mapbox);
  });

  test('scaled() passes a Mapbox static URL through untouched', () {
    expect(ImageUrl.scaled(mapbox, 300), mapbox);
  });

  test('the access_token survives verbatim', () {
    final out = ImageUrl.capped(mapbox, 1200);
    expect(out, contains('?access_token=pk.eyJ1IjoiZXhhbXBsZSIsImEiOiJhYmMifQ.ZmFrZQ'));
    expect(out, isNot(contains('width=')));
    expect(out, isNot(contains('resize=')));
  });
}
