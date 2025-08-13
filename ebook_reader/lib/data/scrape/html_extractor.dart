import 'package:html/parser.dart' as hp;
import 'package:html/dom.dart';

class SiteConfig {
  final String titleSelector;
  final String contentSelector;
  final String nextSelector;
  final List<String> removeSelectors;
  const SiteConfig({
    this.titleSelector = '',
    this.contentSelector = '',
    this.nextSelector = '',
    this.removeSelectors = const [],
  });

  Map<String, dynamic> toJson() => {
        'titleSelector': titleSelector,
        'contentSelector': contentSelector,
        'nextSelector': nextSelector,
        'removeSelectors': removeSelectors,
      };

  factory SiteConfig.fromJson(Map<String, dynamic> j) => SiteConfig(
        titleSelector: j['titleSelector'] ?? '',
        contentSelector: j['contentSelector'] ?? '',
        nextSelector: j['nextSelector'] ?? '',
        removeSelectors:
            (j['removeSelectors'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
      );

  bool get hasCustoms =>
      titleSelector.trim().isNotEmpty ||
      contentSelector.trim().isNotEmpty ||
      nextSelector.trim().isNotEmpty ||
      removeSelectors.isNotEmpty;
}

class WebChapter {
  final String title;
  final String contentHtml;
  final Uri? nextUrl;
  WebChapter({required this.title, required this.contentHtml, required this.nextUrl});
}

Element? _longestParagraphContainer(Document doc) {
  Element? best;
  int bestLen = 0;
  for (final e in doc.querySelectorAll('div,section,article,main')) {
    final textLen = e.querySelectorAll('p').fold<int>(0, (n, p) => n + p.text.trim().length);
    if (textLen > bestLen) {
      bestLen = textLen;
      best = e;
    }
  }
  return best;
}

Element? _pickMain(Document doc) {
  Element? firstNonEmpty(Iterable<Element> xs) =>
      xs.firstWhere((e) => e.text.trim().isNotEmpty, orElse: () => Element.tag(''));

  final candidates = <Element?>[
    doc.querySelector('article'),
    doc.querySelector('main'),
    doc.querySelector('[role="main"]'),
    firstNonEmpty(doc.querySelectorAll('.post,.entry,.chapter,.content,.article,.read')),
    firstNonEmpty(doc.querySelectorAll('#content,#main,#article,#chr-content')),
    _longestParagraphContainer(doc),
  ].whereType<Element>().toList();

  return candidates.isNotEmpty ? candidates.first : null;
}

String _cleanHtml(Element node, List<String> removeSelectors) {
  for (final sel in removeSelectors) {
    for (final e in node.querySelectorAll(sel)) {
      e.remove();
    }
  }
  for (final e in node.querySelectorAll('script,style,noscript,iframe')) {
    e.remove();
  }
  return node.innerHtml.trim();
}

String _norm(String s, {String? bookTitleHint}) {
  var t = s.trim();
  t = t.replaceAll(RegExp(r'\s*[-–|]\s*NovelBin.*$', caseSensitive: false), '');
  if (bookTitleHint != null && bookTitleHint.trim().isNotEmpty) {
    final hint = RegExp.escape(bookTitleHint.trim());
    t = t.replaceFirst(RegExp('^$hint\\s*[:\\-–]*\\s*', caseSensitive: false), '');
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? 'Chapter' : t;
}

String? _text(Element? e) => e?.text.trim().isEmpty == true ? null : e?.text.trim();
String? _meta(Document doc, String sel) => doc.querySelector(sel)?.attributes['content']?.trim();

String? _pickTitle(Document doc, {String? explicitSel, String? bookTitleHint}) {
  if (explicitSel != null && explicitSel.trim().isNotEmpty) {
    final el = doc.querySelector(explicitSel);
    final t = _text(el);
    if (t != null) return _norm(t, bookTitleHint: bookTitleHint);
  }

  final og = _meta(doc, 'meta[property="og:title"]') ?? _meta(doc, 'meta[name="twitter:title"]');
  if (og != null && og.toLowerCase().contains('chapter')) {
    return _norm(og, bookTitleHint: bookTitleHint);
  }

  final heading =
      doc.querySelector('h1,h2,#chr-title,.chapter-title,.entry-title,#chapter-title');
  if (heading != null) {
    final ht = _text(heading);
    if (ht != null && ht.toLowerCase().contains('chapter')) {
      return _norm(ht, bookTitleHint: bookTitleHint);
    }
  }

  final tTag = _text(doc.querySelector('title'));
  if (tTag != null && tTag.toLowerCase().contains('chapter')) {
    return _norm(tTag, bookTitleHint: bookTitleHint);
  }

  if (heading != null) {
    final ht = _text(heading);
    if (ht != null) return _norm(ht, bookTitleHint: bookTitleHint);
  }
  if (tTag != null) return _norm(tTag, bookTitleHint: bookTitleHint);

  return null;
}

Uri? _findNext(Document doc, Uri base, {String? selector}) {
  if (selector != null && selector.trim().isNotEmpty) {
    final el = doc.querySelector(selector);
    final href = el?.attributes['href'];
    if (href != null && href.trim().isNotEmpty) {
      return base.resolve(href.trim());
    }
  }

  final options = <Element>[
    ...doc.querySelectorAll('a#next_chap'),
    ...doc.querySelectorAll('a[rel="next"]'),
    ...doc.querySelectorAll('link[rel="next"]'),
    ...doc.querySelectorAll('a.next, a[aria-label="Next"], .nav-next a, .next-chapter a, .next a'),
  ];

  if (options.isEmpty) {
    for (final a in doc.querySelectorAll('a')) {
      final txt = a.text.trim().toLowerCase();
      if (txt == 'next' ||
          txt == 'next »' ||
          txt == '»' ||
          txt.contains('next chapter') ||
          txt.contains('next »')) {
        options.add(a);
        break;
      }
    }
  }

  for (final el in options) {
    final href = el.attributes['href'];
    if (href != null && href.trim().isNotEmpty) {
      return base.resolve(href.trim());
    }
  }
  return null;
}

WebChapter? extractChapter(
  String html,
  Uri pageUrl, {
  SiteConfig? config,
  String? bookTitleHint,
}) {
  final doc = hp.parse(html);
  final cfg = config ?? const SiteConfig();

  final titleText = _pickTitle(
    doc,
    explicitSel: cfg.titleSelector.trim().isNotEmpty ? cfg.titleSelector : null,
    bookTitleHint: bookTitleHint,
  );

  Element? contentEl;
  if (cfg.contentSelector.trim().isNotEmpty) {
    contentEl = doc.querySelector(cfg.contentSelector);
  }
  contentEl ??= _pickMain(doc);
  if (contentEl == null) return null;

  final content = _cleanHtml(contentEl, cfg.removeSelectors);
  final title = (titleText == null || titleText.isEmpty) ? 'Chapter' : titleText;
  final next = _findNext(doc, pageUrl, selector: cfg.nextSelector);

  return WebChapter(title: title, contentHtml: content, nextUrl: next);
}
