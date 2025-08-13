// lib/data/firestore/web_import_meta_api.dart
import 'package:cloud_firestore/cloud_firestore.dart';

CollectionReference<Map<String, dynamic>> _col(String uid) =>
    FirebaseFirestore.instance.collection('users').doc(uid).collection('webImportMeta');

/// Get meta JSON for a single book (or null if missing)
Future<Map<String, dynamic>?> getWebImportMeta(String uid, String bookId) async {
  final snap = await _col(uid).doc(bookId).get();
  if (!snap.exists) return null;
  return snap.data();
}

/// Upsert meta JSON for a single book
Future<void> upsertWebImportMeta(String uid, String bookId, Map<String, dynamic> meta) async {
  await _col(uid).doc(bookId).set({
    ...meta,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Fetch all meta docs for the user. Returns bookId -> json
Future<Map<String, Map<String, dynamic>>> getAllWebImportMeta(String uid) async {
  final q = await _col(uid).get();
  final out = <String, Map<String, dynamic>>{};
  for (final d in q.docs) {
    out[d.id] = d.data();
  }
  return out;
}
