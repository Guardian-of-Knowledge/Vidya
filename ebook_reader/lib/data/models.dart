import 'scrape/html_extractor.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

// ---- Chapter and Bookmark (unchanged) ----

class Chapter {
  final String title;
  final String text;
  Chapter({required this.title, required this.text});
  Map<String, dynamic> toJson() => {'title': title, 'text': text};
  factory Chapter.fromJson(Map<String, dynamic> j) =>
      Chapter(title: j['title'] ?? 'Untitled', text: j['text'] ?? '');
}

class Bookmark {
  final int chapterIndex;
  final double offset;
  final String label;
  Bookmark({required this.chapterIndex, required this.offset, required this.label});
  Map<String, dynamic> toJson() =>
      {'chapterIndex': chapterIndex, 'offset': offset, 'label': label};
  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        chapterIndex: (j['chapterIndex'] ?? 0) as int,
        offset: (j['offset'] ?? 0.0).toDouble(),
        label: j['label'] ?? '',
      );
}

// ---- Persisted meta so we can resume/update imports ----
class WebImportMeta {
  final String startUrl;
  final String? lastUrl;
  final SiteConfig config;
  final bool fetchAll;
  final DateTime updatedAt;

  WebImportMeta({
    required this.startUrl,
    required this.config,
    this.lastUrl,
    this.fetchAll = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'startUrl': startUrl,
        'lastUrl': lastUrl,
        'config': config.toJson(),
        'fetchAll': fetchAll,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WebImportMeta.fromJson(Map<String, dynamic> j) => WebImportMeta(
        startUrl: j['startUrl'] ?? '',
        lastUrl: j['lastUrl'],
        config: SiteConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map)),
        fetchAll: (j['fetchAll'] ?? false) as bool,
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
      );
}

class Book {
  final String id;
  String name;
  final List<Chapter> chapters;
  bool isFavorite;
  int lastChapterIndex;
  double lastScrollOffset;
  final DateTime createdAt;
  final List<Bookmark> bookmarks;
  final WebImportMeta? webMeta;
  final String? coverUrl;

  Book({
    required this.id,
    required this.name,
    required this.chapters,
    this.isFavorite = false,
    this.lastChapterIndex = 0,
    this.lastScrollOffset = 0.0,
    DateTime? createdAt,
    List<Bookmark>? bookmarks,
    this.webMeta,
    this.coverUrl,
  })  : createdAt = createdAt ?? DateTime.now(),
        bookmarks = bookmarks ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'isFavorite': isFavorite,
        'lastChapterIndex': lastChapterIndex,
        'lastScrollOffset': lastScrollOffset,
        'createdAt': createdAt.toIso8601String(),
        'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
        if (webMeta != null) 'webMeta': webMeta!.toJson(),
        if (coverUrl != null) 'coverUrl': coverUrl,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] ?? '',
        name: j['name'] ?? 'Untitled',
        chapters: (j['chapters'] as List<dynamic>? ?? [])
            .map((e) => Chapter.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        isFavorite: (j['isFavorite'] ?? false) as bool,
        lastChapterIndex: (j['lastChapterIndex'] ?? 0) as int,
        lastScrollOffset: (j['lastScrollOffset'] ?? 0.0).toDouble(),
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        bookmarks: (j['bookmarks'] as List<dynamic>? ?? [])
            .map((e) => Bookmark.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        webMeta: (j['webMeta'] == null)
            ? null
            : WebImportMeta.fromJson(Map<String, dynamic>.from(j['webMeta'] as Map)),
        coverUrl: j['coverUrl'],
      );

  Book copyWith({
    String? name,
    List<Chapter>? chapters,
    bool? isFavorite,
    int? lastChapterIndex,
    double? lastScrollOffset,
    List<Bookmark>? bookmarks,
    WebImportMeta? webMeta,
    String? coverUrl,
  }) =>
      Book(
        id: id,
        name: name ?? this.name,
        chapters: chapters ?? this.chapters,
        isFavorite: isFavorite ?? this.isFavorite,
        lastChapterIndex: lastChapterIndex ?? this.lastChapterIndex,
        lastScrollOffset: lastScrollOffset ?? this.lastScrollOffset,
        createdAt: createdAt,
        bookmarks: bookmarks ?? this.bookmarks,
        webMeta: webMeta ?? this.webMeta,
        coverUrl: coverUrl ?? this.coverUrl,
      );

  /// Deterministic ID from content hash (fallback to title if no chapters).
  static String computeId(String title, List<Chapter> chapters) {
    if (chapters.isNotEmpty) {
      final buffer = StringBuffer();
      for (final ch in chapters) {
        buffer.write(ch.title.trim().toLowerCase());
        buffer.write(ch.text.trim().toLowerCase());
      }
      return md5.convert(utf8.encode(buffer.toString())).toString();
    }
    return md5.convert(utf8.encode(title.trim().toLowerCase())).toString();
  }
}

class UserPrefs {
  final String displayName;
  final String email;
  final double defaultFontSize;
  final double lineHeight;
  final bool useSerif;

  UserPrefs({
    required this.displayName,
    required this.email,
    required this.defaultFontSize,
    this.lineHeight = 1.5,
    this.useSerif = false,
  });

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'email': email,
        'defaultFontSize': defaultFontSize,
        'lineHeight': lineHeight,
        'useSerif': useSerif,
      };

  factory UserPrefs.fromJson(Map<String, dynamic> j) => UserPrefs(
        displayName: j['displayName'] ?? '',
        email: j['email'] ?? '',
        defaultFontSize: (j['defaultFontSize'] ?? 18.0).toDouble(),
        lineHeight: (j['lineHeight'] ?? 1.5).toDouble(),
        useSerif: (j['useSerif'] ?? false) as bool,
      );

  UserPrefs copyWith({
    String? displayName,
    String? email,
    double? defaultFontSize,
    double? lineHeight,
    bool? useSerif,
  }) =>
      UserPrefs(
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        defaultFontSize: defaultFontSize ?? this.defaultFontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        useSerif: useSerif ?? this.useSerif,
      );
}
