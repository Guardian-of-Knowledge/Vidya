// lib/data/import/web_book_importer.dart
import 'dart:async' show unawaited, StreamController;
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;

import '../models.dart';
import '../scrape/crawler.dart';
import '../scrape/html_extractor.dart';
// ❌ removed: '../../core/prefs.dart' (caused loadLibrary/saveLibrary name clash)
import '../firestore/catalog_api.dart';
import '../firestore/user_shelf_api.dart';
import '../firestore/web_import_meta_api.dart'
    show getWebImportMeta, upsertWebImportMeta, getAllWebImportMeta;
import '../../core/html_clean.dart'; // HTML -> plain text
import '../storage/library_store.dart' as store; // ✅ use namespace to avoid clashes

// ===================== GLOBAL IMPORT/UPLOAD PROGRESS BUS =====================

class ImportProgress {
  final String stage; // 'crawl' | 'upload' | 'done' | 'error'
  final int done;
  final int total;
  final String message;
  final String? bookTitle;

  const ImportProgress({
    required this.stage,
    required this.done,
    required this.total,
    required this.message,
    this.bookTitle,
  });
}

class ImportProgressBus {
  ImportProgressBus._();
  static final ImportProgressBus instance = ImportProgressBus._();
  final _ctrl = StreamController<ImportProgress>.broadcast();

  Stream<ImportProgress> get stream => _ctrl.stream;

  void emit(ImportProgress e) {
    try {
      _ctrl.add(e);
    } catch (_) {}
  }
}

// Helper emitters
void _emitCrawl({required int fetched, required String msg}) {
  ImportProgressBus.instance.emit(
    ImportProgress(stage: 'crawl', done: fetched, total: 0, message: msg),
  );
}

void _emitUpload({required int done, required int total, required String book}) {
  ImportProgressBus.instance.emit(
    ImportProgress(stage: 'upload', done: done, total: total, message: 'Uploading…', bookTitle: book),
  );
}

void _emitDone(String title) {
  ImportProgressBus.instance.emit(
    ImportProgress(stage: 'done', done: 1, total: 1, message: 'Completed', bookTitle: title),
  );
}

void _emitError(String msg) {
  ImportProgressBus.instance.emit(
    ImportProgress(stage: 'error', done: 0, total: 1, message: msg),
  );
}

// ===================== WEB IMPORT META (RESUME) ==============================

class _WebImportMeta {
  final String startUrl;
  final SiteConfig config;
  final bool fetchAll;

  final String? lastUrl;
  final int? lastFetchedCount;

  const _WebImportMeta({
    required this.startUrl,
    required this.config,
    required this.fetchAll,
    this.lastUrl,
    this.lastFetchedCount,
  });

  Map<String, dynamic> toJson() => {
        'startUrl': startUrl,
        'config': {
          'title': config.titleSelector,
          'content': config.contentSelector,
          'next': config.nextSelector,
          'remove': config.removeSelectors,
        },
        'fetchAll': fetchAll,
        'lastUrl': lastUrl,
        'lastFetchedCount': lastFetchedCount,
      };

  factory _WebImportMeta.fromJson(Map<String, dynamic> j) => _WebImportMeta(
        startUrl: j['startUrl'] as String,
        config: SiteConfig(
          titleSelector: (j['config']?['title'] ?? '') as String,
          contentSelector: (j['config']?['content'] ?? '') as String,
          nextSelector: (j['config']?['next'] ?? '') as String,
          removeSelectors: ((j['config']?['remove'] as List?) ?? [])
              .map((e) => e.toString())
              .toList(),
        ),
        fetchAll: (j['fetchAll'] ?? false) as bool,
        lastUrl: j['lastUrl'] as String?,
        lastFetchedCount:
            (j['lastFetchedCount'] is num) ? (j['lastFetchedCount'] as num).toInt() : null,
      );

  _WebImportMeta copyWith({String? lastUrl, int? lastFetchedCount}) => _WebImportMeta(
        startUrl: startUrl,
        config: config,
        fetchAll: fetchAll,
        lastUrl: lastUrl ?? this.lastUrl,
        lastFetchedCount: lastFetchedCount ?? this.lastFetchedCount,
      );
}

String _metaKeyForBook(String bookId) => 'web_meta_$bookId';
String _metaKeyForStart(String startUrl) =>
    'web_meta_by_start_${md5.convert(utf8.encode(startUrl)).toString()}';

Future<void> _cacheMetaLocal(String bookId, _WebImportMeta meta) async {
  final p = await SharedPreferences.getInstance();
  final s = jsonEncode(meta.toJson());
  await p.setString(_metaKeyForBook(bookId), s);
  await p.setString(_metaKeyForStart(meta.startUrl), s);
}

Future<_WebImportMeta?> _loadMetaLocal(String bookId) async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_metaKeyForBook(bookId));
  if (s == null) return null;
  try {
    return _WebImportMeta.fromJson(jsonDecode(s) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<bool> hasWebImportMeta(String bookId) async {
  return (await _loadMetaForBook(bookId)) != null;
}

Future<void> _saveMetaForBook(String bookId, _WebImportMeta meta) async {
  await _cacheMetaLocal(bookId, meta);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    try {
      await upsertWebImportMeta(uid, bookId, meta.toJson());
    } catch (e) {
      debugPrint('[WebImport] Cloud meta mirror failed: $e');
    }
  }
}

Future<_WebImportMeta?> _loadMetaForBook(String bookId) async {
  final local = await _loadMetaLocal(bookId);
  if (local != null) return local;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;

  try {
    final json = await getWebImportMeta(uid, bookId);
    if (json == null) return null;
    final meta = _WebImportMeta.fromJson(json);
    await _cacheMetaLocal(bookId, meta);
    return meta;
  } catch (e) {
    debugPrint('[WebImport] Cloud meta fetch failed: $e');
    return null;
  }
}

// ========================= HASHING / CLEANING =================================

String _hashChapters(List<Chapter> chapters) {
  final b = BytesBuilder();
  for (final c in chapters) {
    b.add(utf8.encode(c.title));
    b.addByte(0);
    b.add(utf8.encode(c.text));
    b.addByte(1);
  }
  return md5.convert(b.takeBytes()).toString(); // 32-hex for rules ✅
}

String _stripExt(String s) =>
    s.replaceAll(RegExp(r'\.(docx|pdf|txt)$', caseSensitive: false), '');
String _norm(String s) {
  var t = s.toLowerCase().trim();
  t = t.replaceAll(RegExp(r'[_\-\s]+'), ' ');
  t = t.replaceAll(RegExp(r'[^a-z0-9 ]+'), '');
  return t.trim();
}
String _cleanChapterTitle(String rawTitle, String bookTitle) {
  var candidate = rawTitle.trim();
  if (candidate.isEmpty) return '';
  final bookStripped = _stripExt(bookTitle).trim();

  if (candidate.toLowerCase().startsWith(bookStripped.toLowerCase())) {
    candidate = candidate
        .substring(math.min(candidate.length, bookStripped.length))
        .replaceFirst(RegExp(r'^[\s\-\–\—:|–—]+'), '')
        .trim();
  }

  final bookNorm = _norm(bookStripped);
  final candNorm = _norm(candidate);
  if (candNorm.isEmpty || candNorm == bookNorm) return '';
  return candidate;
}

Book _toBook(WebBookDraft draft, {String? previousId}) {
  final chapters = draft.chapters.map((w) {
    final rawHtml = w.contentHtml;
    final cleanedText = looksLikeHtml(rawHtml)
        ? htmlToPlain(rawHtml)
        : rawHtml.replaceAll(RegExp(r'\s+\n'), '\n');
    final title = _cleanChapterTitle(w.title, draft.title);
    return Chapter(title: title, text: cleanedText.trim());
  }).toList();

  final id = previousId ?? _hashChapters(chapters);
  return Book(id: id, name: draft.title, chapters: chapters);
}

List<Chapter> _mergeChapters(List<Chapter> existing, List<Chapter> incoming) {
  if (existing.isEmpty) return incoming;

  String textKey(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return md5.convert(utf8.encode(normalized)).toString();
  }

  final out = <Chapter>[...existing];
  final seenText = <String>{for (final e in existing) textKey(e.text)};

  bool isDup(Chapter ch) {
    final t = ch.title.trim();
    final dupByTitle = t.isNotEmpty && out.any((e) => e.title.trim() == t);
    final dupByText = seenText.contains(textKey(ch.text));
    return dupByTitle || dupByText;
  }

  for (final ch in incoming) {
    if (isDup(ch)) continue;
    out.add(ch);
    seenText.add(textKey(ch.text));
  }
  return out;
}

bool _looksLikeNullPage(String url) {
  final u = url.toLowerCase().trim();
  if (u.isEmpty) return false;
  if (u.endsWith('/null')) return true;
  final seg = Uri.tryParse(u)?.pathSegments;
  return seg != null && seg.isNotEmpty && seg.last == 'null';
}

Uri _pickSafeStartUri(_WebImportMeta? meta, Uri? override) {
  String seed = override?.toString() ?? meta?.lastUrl ?? meta?.startUrl ?? '';
  if (seed.isEmpty) {
    throw StateError('No start URL available for resume.');
  }
  if (_looksLikeNullPage(seed) && meta?.startUrl != null) {
    debugPrint('[WebImport] Ignoring bad lastUrl="$seed"; using startUrl instead.');
    seed = meta!.startUrl;
  }
  return Uri.parse(seed);
}

// ========================== LOCAL LIBRARY HELPER ==============================

Future<Book> _upsertLocal(Book book) async {
  final books = await store.loadLibrary(); // ✅ namespaced
  final idx = books.indexWhere((b) => b.id == book.id);
  if (idx >= 0) {
    books[idx] = Book(
      id: book.id,
      name: book.name,
      chapters: book.chapters,
      isFavorite: books[idx].isFavorite,
      lastChapterIndex: books[idx].lastChapterIndex,
      lastScrollOffset: books[idx].lastScrollOffset,
      createdAt: books[idx].createdAt,
      bookmarks: books[idx].bookmarks,
    );
  } else {
    books.add(book);
  }
  await store.saveLibrary(books, selectedId: book.id); // ✅ namespaced
  return book;
}

// =========================== CLOUD MIRROR (BG) ================================

Future<void> _mirrorToGlobalInBackground(Book book) async {
  Future<bool> attempt() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('[WebImport] Skipping Global mirror (not signed in)');
        return true; // nothing to do
      }
      await ensureGlobalBook(
        book,
        uid: uid,
        onProgress: (done, total) => _emitUpload(done: done, total: total, book: book.name),
      );
      await linkBookToUserShelf(uid, book);
      return true;
    } catch (e) {
      debugPrint('[WebImport] Global mirror failed: $e');
      return false;
    }
  }

  if (await attempt()) return;
  await Future.delayed(const Duration(seconds: 2));
  await attempt();
}

// =========================== PUBLIC API ======================================

/// Import a freshly crawled draft, save locally + meta, then mirror in background.
Future<Book> importWebDraft(
  WebBookDraft draft, {
  required Uri start,
  required SiteConfig config,
  required bool fetchAll,
}) async {
  final local = _toBook(draft);
  final saved = await _upsertLocal(local);

  await _saveMetaForBook(
    saved.id,
    _WebImportMeta(
      startUrl: start.toString(),
      config: config,
      fetchAll: fetchAll,
      lastUrl: start.toString(),
      lastFetchedCount: draft.chapters.length,
    ),
  );

  // Background cloud mirror so UI can pop immediately
  unawaited(_mirrorToGlobalInBackground(saved));
  _emitDone(saved.name);

  debugPrint('[WebImport] Imported "${saved.name}" • ${saved.chapters.length} chapters (local ok, cloud in bg)');
  return saved;
}

/// Background end-to-end crawl + import, emitting progress via the bus.
Future<void> startBackgroundImport({
  required Uri start,
  required SiteConfig config,
  required bool fetchAll,
  required int limit,
  String? forcedTitle,
}) async {
  try {
    final crawler = Crawler(
      proxyBase: kIsWeb ? 'http://localhost:8080' : null,
      politenessDelay: const Duration(milliseconds: 800),
    );

    // quick preview to validate selectors
    final preview = await crawler.crawl(
      start: start,
      forcedTitle: forcedTitle?.trim().isEmpty == true ? null : forcedTitle,
      config: config,
      maxChapters: 3,
      onProgress: (p) => _emitCrawl(
        fetched: (p.fetched as num).toInt(),
        msg: '${p.status} ${p.current ?? ''}',
      ),
    );

    if (preview.chapters.isEmpty) {
      _emitError('Could not detect content. Adjust selectors.');
      return;
    }

    final fullMax = fetchAll ? 999999 : limit;
    final fullDraft = await crawler.crawl(
      start: start,
      forcedTitle: forcedTitle?.trim().isEmpty == true ? null : forcedTitle,
      config: config,
      maxChapters: fullMax,
      onProgress: (p) => _emitCrawl(
        fetched: (p.fetched as num).toInt(),
        msg: 'Fetched ${p.fetched} • ${p.status}',
      ),
    );

    if (fullDraft.chapters.isEmpty) {
      _emitError('No chapters imported.');
      return;
    }

    await importWebDraft(
      fullDraft,
      start: start,
      config: config,
      fetchAll: fetchAll,
    );
  } catch (e) {
    _emitError('Import failed: $e');
  }
}

/// Resume/update an already imported book using stored meta.
Future<Book?> resumeWebImport(
  Book book, {
  Uri? overrideStart,
  int? maxChapters,
}) async {
  final meta = await _loadMetaForBook(book.id);

  if (meta == null && overrideStart == null) {
    debugPrint('[WebImport] No saved meta/config for "${book.name}" (${book.id}); cannot resume.');
    return null;
  }

  late final Uri startUri;
  try {
    startUri = _pickSafeStartUri(meta, overrideStart);
  } catch (e) {
    debugPrint('[WebImport] $e');
    return null;
  }

  final effectiveConfig = meta?.config;
  if (effectiveConfig == null) {
    debugPrint('[WebImport] Missing site config for "${book.name}".');
    return null;
  }

  final crawler = Crawler(
    proxyBase: kIsWeb ? 'http://localhost:8080' : null,
    politenessDelay: const Duration(milliseconds: 800),
  );

  String? lastSeenUrl;
  String? lastValidUrl;
  int lastSeenCount = 0;

  final draft = await crawler.crawl(
    start: startUri,
    config: effectiveConfig,
    maxChapters: maxChapters ?? (meta?.fetchAll == true ? 999999 : 300),
    onProgress: (p) {
      final cur = p.current;
      if (cur != null) {
        final curStr = cur.toString();
        lastSeenUrl = curStr;
        if (!_looksLikeNullPage(curStr)) lastValidUrl = curStr;
      }
      final fetchedVal = p.fetched as num;
      lastSeenCount = fetchedVal.toInt();
      _emitCrawl(fetched: lastSeenCount, msg: '${p.status} ${cur ?? ''}');
      debugPrint('[WebImport][resume] ${p.status} ${cur ?? ''} (${p.fetched})');
    },
  );

  if (draft.chapters.isEmpty) {
    debugPrint('[WebImport] Resume found no chapters.');
    if (meta != null) {
      await _saveMetaForBook(
        book.id,
        meta.copyWith(
          lastUrl: lastValidUrl ?? meta.lastUrl ?? meta.startUrl,
          lastFetchedCount: lastSeenCount,
        ),
      );
    }
    return null;
  }

  final incoming = _toBook(draft, previousId: book.id);
  final merged = Book(
    id: book.id,
    name: incoming.name,
    chapters: _mergeChapters(book.chapters, incoming.chapters),
    isFavorite: book.isFavorite,
    lastChapterIndex: book.lastChapterIndex,
    lastScrollOffset: book.lastScrollOffset,
    createdAt: book.createdAt,
    bookmarks: book.bookmarks,
  );

  if (merged.chapters.length == book.chapters.length) {
    debugPrint('[WebImport] Resume: no new chapters.');
    if (meta != null) {
      await _saveMetaForBook(
        book.id,
        meta.copyWith(
          lastUrl: lastValidUrl ?? meta.lastUrl ?? meta.startUrl,
          lastFetchedCount: lastSeenCount,
        ),
      );
    }
    return null;
  }

  final saved = await _upsertLocal(merged);

  final newMeta = (meta ??
      _WebImportMeta(
        startUrl: startUri.toString(),
        config: effectiveConfig,
        fetchAll: true,
      )).copyWith(
        lastUrl: lastValidUrl ?? lastSeenUrl ?? startUri.toString(),
        lastFetchedCount: draft.chapters.length,
      );
  await _saveMetaForBook(book.id, newMeta);

  unawaited(_mirrorToGlobalInBackground(saved));
  _emitDone(saved.name);

  debugPrint('[WebImport] Updated (local) "${saved.name}" • now ${saved.chapters.length} chapters');
  return saved;
}

// ---------------- DEBUG / CROSS-DEVICE HELPERS ----------------

Future<void> primeWebMetaForSignedInUserToLocal() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    final all = await getAllWebImportMeta(uid); // bookId -> json
    if (all.isEmpty) return;
    for (final entry in all.entries) {
      final meta = _WebImportMeta.fromJson(entry.value);
      await _cacheMetaLocal(entry.key, meta);
    }
    debugPrint('[WebImport] Primed ${all.length} web-meta docs to local cache.');
  } catch (e) {
    debugPrint('[WebImport] Priming web-meta failed: $e');
  }
}

Future<void> debugDumpWebMeta() async {
  final p = await SharedPreferences.getInstance();
  final keys = p.getKeys().where((k) => k.startsWith('web_meta_'));
  if (keys.isEmpty) {
    debugPrint('[WebImport][debug] No web_meta_* keys.');
    return;
  }
  for (final k in keys) {
    debugPrint('[WebImport][debug] $k = ${p.getString(k)}');
  }
}

Future<void> removeWebMetaForBook(String bookId) async {
  final p = await SharedPreferences.getInstance();
  await p.remove(_metaKeyForBook(bookId));
  debugPrint('[WebImport][debug] Cleared meta for bookId=$bookId (local only)');
}

Future<void> attachWebMetaToBook({
  required String bookId,
  required Uri start,
  required SiteConfig config,
  bool fetchAll = true,
}) async {
  final meta = _WebImportMeta(
    startUrl: start.toString(),
    config: config,
    fetchAll: fetchAll,
    lastUrl: start.toString(),
    lastFetchedCount: 0,
  );
  await _saveMetaForBook(bookId, meta);
  debugPrint('[WebImport][debug] Attached meta for bookId=$bookId start=$start');
}

// ---------------- SIGN-IN SYNC: LOCAL ↔ CLOUD (Objective #2) ------------------

Future<void> reconcileLocalAndCloudOnSignIn() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final localBooks = await store.loadLibrary(); // ✅ namespaced

  for (final b in localBooks) {
    try {
      final remoteLite = await fetchGlobalBookLite(b.id);

      if (remoteLite == null) {
        await ensureGlobalBook(
          b,
          uid: uid,
          onProgress: (d, t) => _emitUpload(done: d, total: t, book: b.name),
        );
        await linkBookToUserShelf(uid, b);
        continue;
      }

      final remoteCount = remoteLite.chapterCount;
      final localCount = b.chapters.length;

      if (remoteCount >= localCount) {
        final chapters = await pullMissingChapters(b.id);
        final updated = Book(
          id: b.id,
          name: remoteLite.name,
          chapters: chapters,
          isFavorite: b.isFavorite,
          lastChapterIndex: b.lastChapterIndex,
          lastScrollOffset: b.lastScrollOffset,
          createdAt: b.createdAt,
          bookmarks: b.bookmarks,
        );
        await _upsertLocal(updated);
        await linkBookToUserShelf(uid, updated);
      } else {
        await ensureGlobalBook(
          b,
          uid: uid,
          onProgress: (d, t) => _emitUpload(done: d, total: t, book: b.name),
        );
        await linkBookToUserShelf(uid, b);
      }
    } catch (e) {
      debugPrint('[Sync] Error syncing "${b.name}": $e');
    }
  }
}
