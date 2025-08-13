// lib/core/prefs.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
// NEW: delegate large library storage to Hive (IndexedDB on web)
import '../data/storage/library_store.dart';

/// Keys (kept identical to your original app to preserve data)
const String kLibraryKey = 'library_v3';            // legacy: was storing entire library JSON
const String kSelectedBookKey = 'selected_book_id_v3';
const String kUserPrefsKey = 'user_prefs_v2';

/// ------------------------
/// LIBRARY (books/chapters)
/// ------------------------
/// Now backed by Hive via [LibraryStore]. We keep these wrappers so the rest
/// of the app doesn’t need to change. On first load, we auto-migrate from the
/// old SharedPreferences blob if found.

/// Save the full in-memory library to Hive. Optionally persist the selectedId.
Future<void> saveLibrary(List<Book> books, {String? selectedId}) async {
  // Store heavy content in Hive (IndexedDB on web)
  await LibraryStore.instance.saveAll(books);

  // Selected book id is tiny; we keep it in SharedPreferences
  if (selectedId != null) {
    await saveSelectedBookId(selectedId);
  }
}

/// Load the full library from Hive. If nothing in Hive yet, migrate once from
/// the legacy SharedPreferences JSON blob (kLibraryKey), then clear that blob.
Future<List<Book>> loadLibrary() async {
  // Prefer Hive
  final hiveBooks = await LibraryStore.instance.loadAll();
  if (hiveBooks.isNotEmpty) return hiveBooks;

  // Legacy migration path (first run after upgrade)
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kLibraryKey);
  if (raw == null || raw.isEmpty) {
    return <Book>[];
  }

  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = (decoded['books'] as List<dynamic>? ?? [])
        .map((e) => Book.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Write to Hive and clear the legacy blob to free space
    if (list.isNotEmpty) {
      await LibraryStore.instance.saveAll(list);
    }
    await prefs.remove(kLibraryKey);

    return list;
  } catch (_) {
    // If something goes wrong, don’t crash—just return empty
    return <Book>[];
  }
}

/// ------------------------
/// SELECTED BOOK POINTER
/// ------------------------

/// Get previously selected book id (tiny string) from SharedPreferences.
Future<String?> loadSelectedBookId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(kSelectedBookKey);
}

/// Persist selected book id.
Future<void> saveSelectedBookId(String? id) async {
  final prefs = await SharedPreferences.getInstance();
  if (id == null) {
    await prefs.remove(kSelectedBookKey);
  } else {
    await prefs.setString(kSelectedBookKey, id);
  }
}

/// ------------------------
/// USER PREFERENCES (small)
/// ------------------------

/// Load user preferences; falls back to sensible defaults on error.
Future<UserPrefs> loadUserPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kUserPrefsKey);
  if (raw == null || raw.isEmpty) {
    return UserPrefs(displayName: '', email: '', defaultFontSize: 18.0);
  }
  try {
    return UserPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return UserPrefs(displayName: '', email: '', defaultFontSize: 18.0);
  }
}

/// Persist user preferences (small JSON).
Future<void> saveUserPrefs(UserPrefs p) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kUserPrefsKey, jsonEncode(p.toJson()));
}
