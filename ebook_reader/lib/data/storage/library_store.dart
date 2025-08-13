import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart'; // <- correct relative path

/// Box names / keys
const _kBoxLibrary = 'library_v1';          // stores books as Map<String, dynamic>
const _kBoxLibraryMeta = 'library_meta_v1'; // selectedId, etc.
const _kKeySelectedId = 'selected_book_id';

/// SharedPreferences keys used by the OLD storage (for one-time migration).
const _kOldLibKey = 'library_v3';           // { books: [...], selectedId }
const _kOldSelectedKeyV3 = 'selected_book_id_v3';
const _kOldSelectedKeyLegacy = 'selected_book_id';

late Box<Map> _booksBox;
late Box _metaBox;

/// Call once at app start (main.dart).
Future<void> initLibraryStore() async {
  _booksBox = await Hive.openBox<Map>(_kBoxLibrary);
  _metaBox  = await Hive.openBox(_kBoxLibraryMeta);

  // One-time migration from shared_preferences -> Hive
  await _maybeMigrateFromSharedPrefs();
}

/// ========== Public API used by the app ==========

Future<List<Book>> loadLibrary() async {
  final List<Book> books = [];
  for (final key in _booksBox.keys) {
    final m = _booksBox.get(key);
    if (m is Map) {
      books.add(_bookFromMap(Map<String, dynamic>.from(m)));
    }
  }
  books.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return books;
}

Future<void> saveLibrary(List<Book> books, {String? selectedId}) async {
  final Map<dynamic, Map> batch = { for (final b in books) b.id : _bookToMap(b) };

  await _booksBox.clear();
  await _booksBox.putAll(batch);

  if (selectedId != null) {
    await saveSelectedBookId(selectedId);
  }
}

Future<String?> loadSelectedBookId() async {
  final v = _metaBox.get(_kKeySelectedId);
  return v is String ? v : null;
}

Future<void> saveSelectedBookId(String? id) async {
  if (id == null) {
    await _metaBox.delete(_kKeySelectedId);
  } else {
    await _metaBox.put(_kKeySelectedId, id);
  }
}

/// Optional wrapper so code can call `LibraryStore.instance` if it wants.
class LibraryStore {
  LibraryStore._();
  static final instance = LibraryStore._();

  Future<List<Book>> loadAll() => loadLibrary();
  Future<void> saveAll(List<Book> books, {String? selectedId}) =>
      saveLibrary(books, selectedId: selectedId);
  Future<String?> selectedId() => loadSelectedBookId();
  Future<void> setSelectedId(String? id) => saveSelectedBookId(id);
  Future<void> clear() async {
    await _booksBox.clear();
    await _metaBox.clear();
  }
}

/// ========== One-time migration ==========

Future<void> _maybeMigrateFromSharedPrefs() async {
  // If we already have books in Hive, skip.
  if (_booksBox.isNotEmpty) return;

  final sp = await SharedPreferences.getInstance();
  final oldJson = sp.getString(_kOldLibKey);
  if (oldJson == null || oldJson.isEmpty) return;

  try {
    final decoded = jsonDecode(oldJson);

    List<dynamic> bookList;
    String? selected;

    // Accept both shapes:
    // 1) { "books": [...], "selectedId": "abc" }
    // 2) [ {...}, {...} ]
    if (decoded is Map<String, dynamic>) {
      bookList = (decoded['books'] as List<dynamic>? ?? const []);
      selected = decoded['selectedId'] as String?;
    } else if (decoded is List) {
      bookList = decoded;
    } else {
      return;
    }

    // Fallback selected id keys (older builds)
    selected ??= sp.getString(_kOldSelectedKeyV3);
    selected ??= sp.getString(_kOldSelectedKeyLegacy);

    final List<Book> books = [];
    for (final e in bookList) {
      if (e is Map) {
        books.add(_bookFromMap(Map<String, dynamic>.from(e)));
      }
    }

    // Save into Hive
    await saveLibrary(books, selectedId: selected);

    // Clean up old keys
    await sp.remove(_kOldLibKey);
    await sp.remove(_kOldSelectedKeyV3);
    await sp.remove(_kOldSelectedKeyLegacy);
  } catch (_) {
    // noop
  }
}

/// ========== Map serializers (no Hive adapters needed) ==========

Map<String, dynamic> _bookToMap(Book b) => {
  'id': b.id,
  'name': b.name,
  'isFavorite': b.isFavorite,
  'lastChapterIndex': b.lastChapterIndex,
  'lastScrollOffset': b.lastScrollOffset,
  'createdAt': b.createdAt.millisecondsSinceEpoch,
  'bookmarks': b.bookmarks.map((x) => x.toJson()).toList(),
  'coverUrl': b.coverUrl, // persist cover
  'chapters': b.chapters.map((c) => {
    'title': c.title,
    'text':  c.text,
  }).toList(),
};

Book _bookFromMap(Map<String, dynamic> m) {
  final chaptersData = (m['chapters'] as List<dynamic>? ?? []);
  final bookmarksData = (m['bookmarks'] as List<dynamic>? ?? []);

  final createdRaw = m['createdAt'];
  DateTime createdAt;
  if (createdRaw is int) {
    createdAt = DateTime.fromMillisecondsSinceEpoch(createdRaw);
  } else if (createdRaw is String) {
    createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now();
  } else {
    createdAt = DateTime.now();
  }

  return Book(
    id: (m['id'] ?? '') as String,
    name: (m['name'] ?? 'Untitled') as String,
    chapters: chaptersData.map((e) {
      final mm = Map<String, dynamic>.from(e as Map);
      return Chapter(
        title: (mm['title'] ?? '') as String,
        text:  (mm['text'] ?? '') as String,
      );
    }).toList(),
    isFavorite: (m['isFavorite'] ?? false) as bool,
    lastChapterIndex: (m['lastChapterIndex'] ?? 0) as int,
    lastScrollOffset: (m['lastScrollOffset'] ?? 0.0).toDouble(),
    createdAt: createdAt,
    bookmarks: bookmarksData.map((e) {
      return Bookmark.fromJson(Map<String, dynamic>.from(e as Map));
    }).toList(),
    coverUrl: (m['coverUrl'] as String?)?.trim().isEmpty == true ? null : m['coverUrl'] as String?,
  );
}
