// lib/data/docx/parser.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:xml/xml.dart';

import '../../core/hashing.dart';
import '../models.dart';

/// Public entrypoint (spawns an isolate via `compute`)
Future<Book> parseDocxToBook(String fileName, Uint8List bytes) {
  return compute<_ParseInput, Book>(_parseDocxToBookIsolate, _ParseInput(fileName, bytes));
}

class _ParseInput {
  final String fileName;
  final Uint8List bytes;
  const _ParseInput(this.fileName, this.bytes);
}

/// Isolate body: unzip DOCX, parse XML, detect chapters, build [Book].
Future<Book> _parseDocxToBookIsolate(_ParseInput input) async {
  final archive = ZipDecoder().decodeBytes(input.bytes);

  final entry = archive.files.firstWhere(
    (f) => f.name == 'word/document.xml',
    orElse: () => throw Exception('Invalid DOCX: word/document.xml not found'),
  );

  final xmlString = utf8.decode(entry.content as List<int>);
  final doc = XmlDocument.parse(xmlString);
  final paragraphs = doc.findAllElements('p', namespace: '*');

  final List<Chapter> chapters = [];
  final StringBuffer currentText = StringBuffer();
  String currentTitle = 'Untitled';
  bool hasAnyHeading = false;

  void pushChapterIfAny() {
    final text = currentText.toString().trim();
    if (text.isNotEmpty || chapters.isEmpty) {
      chapters.add(Chapter(title: currentTitle, text: text));
      currentText.clear();
    }
  }

  String? extractChapterTitle(String pText) {
    final t = pText.trim();
    if (RegExp(r'^[-–—_]{2,}$').hasMatch(t)) return null;
    final m = RegExp(
      r'^\s*(chapter|part|section)\s+([0-9ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten)\s*[:.\-–—]?\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final lead = m.group(1)!;
      final num = m.group(2)!;
      final rest = (m.group(3) ?? '').trim();
      final leadC = '${lead[0].toUpperCase()}${lead.substring(1).toLowerCase()}';
      final numU = num.toUpperCase();
      return rest.isNotEmpty ? '$leadC $numU: $rest' : '$leadC $numU';
    }
    return null;
  }

  bool isHeadingStyle(String styleVal) {
    final s1 = styleVal.replaceAll('_', ' ').trim();
    final s2 = styleVal.replaceAll('_', '').trim();
    return RegExp(r'^heading\s*\d+$', caseSensitive: false).hasMatch(s1) ||
        RegExp(r'^heading\d+$', caseSensitive: false).hasMatch(s2);
  }

  for (final p in paragraphs) {
    final pPr = _firstOrNull(p.findElements('pPr', namespace: '*'));
    final pStyle = pPr == null ? null : _firstOrNull(pPr.findElements('pStyle', namespace: '*'));
    final styleVal = pStyle?.getAttribute('val', namespace: '*') ?? '';

    final pText = p.findAllElements('t', namespace: '*').map((t) => t.innerText).join().trim();
    if (pText.isEmpty) continue;

    final extracted = extractChapterTitle(pText);
    final styleHeading = isHeadingStyle(styleVal);
    final styleHeadingValid = styleHeading && !RegExp(r'^[-–—_]{2,}$').hasMatch(pText);

    if (extracted != null || styleHeadingValid) {
      hasAnyHeading = true;
      if (currentText.isNotEmpty) pushChapterIfAny();
      currentTitle = extracted ?? pText;
    } else {
      if (currentText.isNotEmpty) currentText.write('\n\n');
      currentText.write(pText);
    }
  }

  pushChapterIfAny();

  final id = fnv32x2Hash(input.bytes);

  // If no headings were detected, collapse into a single chapter
  if (!hasAnyHeading && chapters.isNotEmpty) {
    final whole = chapters.map((c) => c.text).join('\n\n').trim();
    return Book(id: id, name: input.fileName, chapters: [Chapter(title: 'Document', text: whole)]);
  }

  return Book(id: id, name: input.fileName, chapters: chapters);
}

/// Tiny helper to avoid depending on a global extension.
T? _firstOrNull<T>(Iterable<T> it) => it.isEmpty ? null : it.first;
