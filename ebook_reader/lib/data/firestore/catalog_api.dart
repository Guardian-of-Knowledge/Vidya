// lib/data/firestore/catalog_api.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models.dart';

CollectionReference<Map<String, dynamic>> booksCol() =>
    FirebaseFirestore.instance.collection('books');

DocumentReference<Map<String, dynamic>> bookDoc(String id) => booksCol().doc(id);

CollectionReference<Map<String, dynamic>> bookChapters(String id) =>
    bookDoc(id).collection('chapters');

/// Create/update the global book and its chapters:
/// - Parent book doc is upserted with name/importedBy/chapterCount + timestamps.
/// - Chapter docs use deterministic ids = `index.toString()` and `merge:true`
///   so retries/partial uploads are **idempotent** (no dupes).
/// - Writes are batched (<=400 ops) to respect Firestore limits.
/// - Calls [onProgress(done,total)] so UI can show %; emits a final tick.
Future<void> ensureGlobalBook(
  Book book, {
  required String uid,
  void Function(int done, int total)? onProgress,
}) async {
  final bRef = bookDoc(book.id);

  // Upsert parent shell
  await bRef.set({
    'name': book.name,
    'createdAt': FieldValue.serverTimestamp(), // harmless on update
    'updatedAt': FieldValue.serverTimestamp(),
    'importedBy': FieldValue.arrayUnion([uid]),
    'chapterCount': book.chapters.length,
  }, SetOptions(merge: true));

  // Determine next index to append from (optimization; safe even if we write with merge:true)
  int nextIndex = 0;
  final last = await bookChapters(book.id)
      .orderBy('index', descending: true)
      .limit(1)
      .get(const GetOptions(source: Source.server));
  if (last.docs.isNotEmpty) {
    final data = last.docs.first.data();
    final existingMax = (data['index'] as num?)?.toInt() ?? -1;
    nextIndex = existingMax + 1;
  }

  final totalOps =
      (book.chapters.length - nextIndex).clamp(0, book.chapters.length);
  int doneOps = 0;
  onProgress?.call(0, totalOps == 0 ? 1 : totalOps);

  if (totalOps == 0) {
    // Still touch parent to refresh timestamps/counts
    await bRef.set({
      'chapterCount': book.chapters.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    onProgress?.call(1, 1);
    return;
  }

  // Append chapters [nextIndex .. end), using deterministic doc ids and merge:true
  const int kMaxOpsPerBatch = 400; // keep headroom under 500
  WriteBatch batch = FirebaseFirestore.instance.batch();
  int opsInBatch = 0;

  Future<void> flush() async {
    if (opsInBatch == 0) return;
    await batch.commit();
    opsInBatch = 0;
    batch = FirebaseFirestore.instance.batch();
    // Yield on web
    await Future<void>.delayed(Duration.zero);
  }

  for (int i = nextIndex; i < book.chapters.length; i++) {
    final ch = book.chapters[i];
    final cRef = bookChapters(book.id).doc(i.toString()); // deterministic
    batch.set(
      cRef,
      {
        'index': i,
        'title': ch.title,
        'text': ch.text,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    opsInBatch++;
    doneOps++;
    onProgress?.call(doneOps, totalOps);

    if ((doneOps % 40) == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    if (opsInBatch >= kMaxOpsPerBatch) {
      await flush();
    }
  }

  await flush();

  // Finalize parent doc with accurate counts
  await bRef.set({
    'chapterCount': book.chapters.length,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // Final progress tick
  onProgress?.call(totalOps == 0 ? 1 : totalOps, totalOps == 0 ? 1 : totalOps);
}

/// Fetch a global book fresh (server source) and assemble a [Book].
/// Respects `chapterCount` to ignore any extra chapter docs.
Future<Book> fetchGlobalBook(String id) async {
  final metaSnap =
      await bookDoc(id).get(const GetOptions(source: Source.server));
  final meta = metaSnap.data() ?? const <String, dynamic>{};

  final name = (meta['name'] ?? 'Untitled') as String;
  final count = (meta['chapterCount'] is num)
      ? (meta['chapterCount'] as num).toInt()
      : null;

  Query<Map<String, dynamic>> q = bookChapters(id).orderBy('index');

  if (count != null && count >= 0) {
    q = q.limit(count);
  }

  final chaptersSnap = await q.get(const GetOptions(source: Source.server));

  final chapters = chaptersSnap.docs.map((c) {
    final m = c.data();
    return Chapter(
      title: (m['title'] ?? '') as String,
      text: (m['text'] ?? '') as String,
    );
  }).toList();

  return Book(id: id, name: name, chapters: chapters);
}

/// Lightweight view used to check remote freshness without pulling chapters.
class GlobalBookLite {
  final String id;
  final String name;
  final int chapterCount;
  GlobalBookLite({
    required this.id,
    required this.name,
    required this.chapterCount,
  });
}

/// Returns name + chapterCount (server) to decide if local is stale.
Future<GlobalBookLite?> fetchGlobalBookLite(String id) async {
  final snap = await bookDoc(id).get(const GetOptions(source: Source.server));
  if (!snap.exists) return null;
  final d = snap.data()!;
  final name = (d['name'] ?? 'Untitled') as String;
  final count =
      (d['chapterCount'] is num) ? (d['chapterCount'] as num).toInt() : 0;
  return GlobalBookLite(id: id, name: name, chapterCount: count);
}

/// Pulls all chapters from Firestore ordered by index.
/// If server has `chapterCount`, we clamp to it.
Future<List<Chapter>> pullMissingChapters(String id, {int from = 0}) async {
  final metaSnap =
      await bookDoc(id).get(const GetOptions(source: Source.server));
  final meta = metaSnap.data();

  int? count;
  if (meta != null && meta['chapterCount'] is num) {
    count = (meta['chapterCount'] as num).toInt();
  }

  Query<Map<String, dynamic>> q = bookChapters(id).orderBy('index');
  if (count != null && count >= 0) {
    q = q.limit(count);
  }

  final chaptersSnap = await q.get(const GetOptions(source: Source.server));

  final chapters = chaptersSnap.docs.map((c) {
    final m = c.data();
    return Chapter(
      title: (m['title'] ?? '') as String,
      text: (m['text'] ?? '') as String,
    );
  }).toList();

  return chapters;
}
