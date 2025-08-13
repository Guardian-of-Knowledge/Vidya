// lib/core/html_clean.dart
// Minimal HTML → plain text normalizer for chapter bodies.
// Dependency-free; makes web-imported chapters look like DOCX text.

String htmlToPlain(String input) {
  if (input.isEmpty) return input;
  var s = input;

  // Normalize line endings
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Drop script/style content entirely
  s = s.replaceAll(RegExp(r'<\s*(script|style)[\s\S]*?<\/\s*\1\s*>', caseSensitive: false), '');

  // Turn common block tags into line breaks (open & close)
  final openBlock = RegExp(
    r'<\s*(?:p|div|section|article|header|footer|h[1-6]|blockquote|pre|ul|ol|li|table|thead|tbody|tr|td|th|hr)\b[^>]*>',
    caseSensitive: false,
  );
  final closeBlock = RegExp(
    r'<\s*\/\s*(?:p|div|section|article|header|footer|h[1-6]|blockquote|pre|ul|ol|li|table|thead|tbody|tr|td|th)\s*>',
    caseSensitive: false,
  );
  s = s.replaceAll(openBlock, '\n');
  s = s.replaceAll(closeBlock, '\n');

  // <br> variants → newlines
  s = s.replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n');

  // Bullet for list items (before stripping remaining tags)
  s = s.replaceAll(RegExp(r'<\s*li\b[^>]*>\s*', caseSensitive: false), '• ');

  // Strip any remaining tags
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');

  // Decode common named entities
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");

  // Decode numeric entities: decimal (e.g., &#8212;) and hex (e.g., &#x2014;)
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  s = s.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });

  // Collapse whitespace & tidy blank lines
  s = s.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  s = s.split('\n').map((line) => line.trimRight()).join('\n').trim();

  return s;
}

bool looksLikeHtml(String s) {
  if (!s.contains('<') || !s.contains('>')) return false;
  return RegExp(r'</?(?:p|div|h\d|br|ul|ol|li)\b', caseSensitive: false).hasMatch(s);
}
