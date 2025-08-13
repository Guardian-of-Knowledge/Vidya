// lib/data/firestore/user_shelf_api.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models.dart';

/// users/{uid}/library (per-user shelf)
CollectionReference<Map<String, dynamic>> userLibraryCol(String uid) =>
    FirebaseFirestore.instance.collection('users').doc(uid).collection('library');

/// users/{uid}/library/{bookId}
DocumentReference<Map<String, dynamic>> userBookDoc(String uid, String id) =>
    userLibraryCol(uid).doc(id);

/// Link or refresh a book entry on the user's shelf with personal state.
/// - Merge-safe: preserves existing fields unless overwritten
/// - Sets `createdAt` only on first create; always bumps `updatedAt`
Future<void> linkBookToUserShelf(String uid, Book b) async {
  final ref = userBookDoc(uid, b.id);
  final db = FirebaseFirestore.instance;

  await db.runTransaction((tx) async {
    final snap = await tx.get(ref);
    final hasCreatedAt = snap.exists && (snap.data()?['createdAt'] != null);

    final data = <String, dynamic>{
      'name': b.name,
      'isFavorite': b.isFavorite,
      'lastChapterIndex': b.lastChapterIndex,
      'lastScrollOffset': b.lastScrollOffset,
      'bookmarks': b.bookmarks.map((x) => x.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!hasCreatedAt) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    tx.set(ref, data, SetOptions(merge: true));
  });
}

/// Remove a book entry from the user's shelf (does NOT touch global catalog).
Future<void> removeUserBook(String uid, String bookId) async {
  await userBookDoc(uid, bookId).delete();
}

/// Optional: Update just the user’s reading progress (lightweight write).
Future<void> updateUserReadingProgress(
  String uid,
  String bookId, {
  required int lastChapterIndex,
  required double lastScrollOffset,
}) async {
  await userBookDoc(uid, bookId).set({
    'lastChapterIndex': lastChapterIndex,
    'lastScrollOffset': lastScrollOffset,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Optional: Toggle favorite flag.
Future<void> toggleFavorite(String uid, String bookId, bool isFavorite) async {
  await userBookDoc(uid, bookId).set({
    'isFavorite': isFavorite,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
