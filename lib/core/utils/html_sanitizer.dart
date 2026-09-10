import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Cleans organizer-authored `events.description_html` before it is rendered.
///
/// The server stores that column **raw** — sanitising happens in the web
/// renderer, not on write (team_comms #302). So the value reaching the app is
/// untrusted input written by any approved partner, and the web team's
/// allow-list protects their renderer only; it is not in the data.
///
/// Scope, honestly stated: `flutter_widget_from_html_core` has no JavaScript
/// engine, so `<script>` is inert, and [_openDescriptionUrl] in the event modal
/// already restricts tapped links to http/https/mailto/tel. What remains is
/// lower severity — tracking pixels via remote `<img>`, layout abuse via CSS,
/// and embeds if an HtmlWidget extension is ever added. This is defence in
/// depth on a column we do not control, not a patch for an open hole.
///
/// Parsed with a real DOM rather than regexes: regex HTML sanitisers fail on
/// exactly the malformed markup an attacker supplies on purpose.
class HtmlSanitizer {
  /// Structural and typographic tags. Deliberately excludes `script`, `style`,
  /// `iframe`, `object`, `embed`, `form`, `input`, `video`, `audio` and
  /// `source` — none of which the app's renderer needs, and each of which is a
  /// liability the day the renderer gains an extension that honours it.
  static const _allowedTags = {
    'p', 'br', 'hr', 'div', 'span', 'section', 'article',
    'header', 'footer', 'main', 'aside', 'nav',
    'strong', 'b', 'em', 'i', 'u', 's', 'del', 'ins', 'mark', 'sup', 'sub',
    'small', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'ul', 'ol', 'li', 'blockquote', 'pre', 'code',
    'a', 'img', 'figure', 'figcaption',
    'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th',
  };

  /// Attributes kept, per tag. Everything else is dropped — including every
  /// `on*` handler, and `id`/`class`, which only matter to a stylesheet we do
  /// not ship.
  static const _allowedAttributes = <String, Set<String>>{
    'a': {'href', 'title'},
    'img': {'src', 'alt', 'width', 'height'},
    'td': {'colspan', 'rowspan'},
    'th': {'colspan', 'rowspan'},
  };

  static const _allowedSchemes = {'http', 'https', 'mailto', 'tel'};

  /// CSS properties allowed through `style`.
  ///
  /// Mirrors the web team's own exclusions: `position`, `z-index`, `inset`,
  /// offsets, `float`, `content` and `pointer-events` are absent, because a
  /// description that can position itself can cover the buy button. `opacity`
  /// and `display` are absent for the same reason — both can hide UI.
  static const _allowedStyleProps = {
    'color', 'background-color',
    'font-size', 'font-weight', 'font-style', 'font-family',
    'text-align', 'text-decoration', 'text-transform',
    'line-height', 'letter-spacing', 'vertical-align', 'white-space',
    'margin', 'margin-top', 'margin-bottom', 'margin-left', 'margin-right',
    'padding', 'padding-top', 'padding-bottom', 'padding-left', 'padding-right',
    'border', 'border-radius', 'border-color', 'border-width', 'border-style',
    'width', 'max-width', 'height', 'max-height',
    'list-style', 'list-style-type',
  };

  /// Returns HTML safe to hand to `HtmlWidget`. Empty in, empty out.
  static String sanitize(String? input) {
    final raw = input?.trim() ?? '';
    if (raw.isEmpty) return '';

    try {
      final doc = html_parser.parseFragment(raw);
      _clean(doc);
      return doc.outerHtml;
    } catch (_) {
      // Unparseable markup is not worth rendering at any fidelity. The caller
      // falls back to the plain-text `description` column on empty.
      return '';
    }
  }

  static void _clean(dom.Node node) {
    // Copy first: _clean mutates the child list while walking it.
    for (final child in List<dom.Node>.from(node.nodes)) {
      if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';

        if (!_allowedTags.contains(tag)) {
          // Unwrap rather than delete, so a stray <font> or <center> loses its
          // tag but keeps the words inside it. `script` and `style` are the
          // exception — their text content is code, not prose.
          // `node` is the parent, deliberately — NOT `child.parent`, which is
          // null for nodes sitting directly under a DocumentFragment. Relying
          // on it silently skipped every disallowed TOP-LEVEL tag, so a bare
          // <iframe> passed straight through.
          final index = node.nodes.indexOf(child);
          if (index < 0) continue;

          if (tag == 'script' || tag == 'style') {
            node.nodes.removeAt(index);
          } else {
            _clean(child);
            final orphans = List<dom.Node>.from(child.nodes);
            node.nodes.removeAt(index);
            node.nodes.insertAll(index, orphans);
          }
          continue;
        }

        _cleanAttributes(child, tag);
        _clean(child);
      }
    }
  }

  static void _cleanAttributes(dom.Element el, String tag) {
    final allowed = _allowedAttributes[tag] ?? const <String>{};

    for (final key in el.attributes.keys.toList()) {
      final name = key.toString().toLowerCase();

      if (name == 'style') {
        final safe = _cleanStyle(el.attributes[key] ?? '');
        if (safe.isEmpty) {
          el.attributes.remove(key);
        } else {
          el.attributes[key] = safe;
        }
        continue;
      }

      if (!allowed.contains(name)) {
        el.attributes.remove(key);
        continue;
      }

      if (name == 'href' || name == 'src') {
        if (!_isSafeUrl(el.attributes[key] ?? '')) el.attributes.remove(key);
      }
    }

    // Anything that leaves the app opens in a browser; say so to the OS.
    if (tag == 'a' && el.attributes.containsKey('href')) {
      el.attributes['rel'] = 'nofollow noopener noreferrer';
    }
  }

  static bool _isSafeUrl(String value) {
    final url = value.trim();
    if (url.isEmpty) return false;
    // Relative URLs have no host to reach and nothing to resolve against here.
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    return _allowedSchemes.contains(uri.scheme.toLowerCase());
  }

  /// Drops disallowed declarations from a `style` attribute.
  ///
  /// Property names are simple tokens, so splitting is safe here in a way that
  /// parsing HTML with regexes would not be. `url()` is refused outright — it
  /// is how a stylesheet fetches a remote asset.
  static String _cleanStyle(String style) {
    final kept = <String>[];
    for (final decl in style.split(';')) {
      final i = decl.indexOf(':');
      if (i <= 0) continue;
      final prop = decl.substring(0, i).trim().toLowerCase();
      final value = decl.substring(i + 1).trim();
      if (value.isEmpty) continue;
      if (!_allowedStyleProps.contains(prop)) continue;
      final lowered = value.toLowerCase();
      if (lowered.contains('url(') ||
          lowered.contains('expression(') ||
          lowered.contains('javascript:')) {
        continue;
      }
      kept.add('$prop: $value');
    }
    return kept.join('; ');
  }
}
