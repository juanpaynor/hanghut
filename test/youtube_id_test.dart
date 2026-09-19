import 'package:flutter_test/flutter_test.dart';

// Mirrors _CoverVideo.youtubeId (private to the storefront screen). The URL
// shapes are the ones actually in partners.branding.video_url on prod.
String? youtubeId(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return null;
  final host = u.host.toLowerCase();
  if (host.endsWith('youtu.be')) {
    return u.pathSegments.isEmpty ? null : u.pathSegments.first;
  }
  if (!host.contains('youtube.')) return null;
  final v = u.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v;
  final segs = u.pathSegments;
  for (var i = 0; i + 1 < segs.length; i++) {
    if (segs[i] == 'shorts' || segs[i] == 'embed' || segs[i] == 'v') {
      return segs[i + 1];
    }
  }
  return null;
}

void main() {
  test('prod URL shapes', () {
    expect(youtubeId('https://www.youtube.com/watch?v=3TlJWoM69ww&t=543s'), '3TlJWoM69ww');
    expect(youtubeId('https://www.youtube.com/watch?v=yiSU_DEUw1s'), 'yiSU_DEUw1s');
    expect(youtubeId('https://youtu.be/83EQ2D3J_dQ'), '83EQ2D3J_dQ');
    expect(youtubeId('https://youtube.com/shorts/abc123XYZ_-'), 'abc123XYZ_-');
    expect(youtubeId('https://api.hanghut.com/storage/v1/object/public/event-videos/x/1.mp4'), isNull);
    expect(youtubeId('not a url at all'), isNull);
  });
}
