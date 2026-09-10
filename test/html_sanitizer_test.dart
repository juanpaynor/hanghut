import 'package:flutter_test/flutter_test.dart';
import 'package:bitemates/core/utils/html_sanitizer.dart';

void main() {
  test('keeps ordinary formatting', () {
    final out = HtmlSanitizer.sanitize(
        '<p>Hello <strong>world</strong></p><ul><li>One</li></ul>');
    expect(out, contains('<strong>world</strong>'));
    expect(out, contains('<li>One</li>'));
  });

  test('drops script entirely, content included', () {
    final out = HtmlSanitizer.sanitize('<p>ok</p><script>alert(1)</script>');
    expect(out, contains('ok'));
    expect(out.toLowerCase(), isNot(contains('alert')));
  });

  test('strips event handlers', () {
    final out = HtmlSanitizer.sanitize('<p onclick="steal()">hi</p>');
    expect(out, contains('hi'));
    expect(out.toLowerCase(), isNot(contains('onclick')));
  });

  test('drops javascript: hrefs but keeps the text', () {
    final out = HtmlSanitizer.sanitize('<a href="javascript:alert(1)">tap</a>');
    expect(out, contains('tap'));
    expect(out.toLowerCase(), isNot(contains('javascript:')));
  });

  test('keeps https links and adds rel', () {
    final out = HtmlSanitizer.sanitize('<a href="https://x.com">x</a>');
    expect(out, contains('https://x.com'));
    expect(out, contains('noopener'));
  });

  test('removes iframes', () {
    final out = HtmlSanitizer.sanitize('<iframe src="https://evil"></iframe>');
    expect(out.toLowerCase(), isNot(contains('iframe')));
  });

  test('unwraps unknown tags but keeps their words', () {
    final out = HtmlSanitizer.sanitize('<center><font>keep me</font></center>');
    expect(out, contains('keep me'));
    expect(out.toLowerCase(), isNot(contains('<font')));
  });

  test('style: keeps colour, drops position and url()', () {
    final out = HtmlSanitizer.sanitize(
        '<p style="color: red; position: fixed; background-color: url(http://x)">t</p>');
    expect(out, contains('color: red'));
    expect(out.toLowerCase(), isNot(contains('position')));
    expect(out.toLowerCase(), isNot(contains('url(')));
  });

  test('malformed markup does not throw', () {
    expect(() => HtmlSanitizer.sanitize('<p><b>unclosed'), returnsNormally);
  });

  test('empty and null in, empty out', () {
    expect(HtmlSanitizer.sanitize(null), '');
    expect(HtmlSanitizer.sanitize('   '), '');
  });
}
