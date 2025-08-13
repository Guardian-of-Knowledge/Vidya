// lib/core/storage.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../data/models.dart';

/// NOTE:
/// This module now focuses on **prefs and media assets** (covers).
/// Persistent library data is handled by `lib/data/storage/library_store.dart` (Hive).
/// Keeping library JSON helpers here for backward compatibility if some
/// older code calls them, but app should use LibraryStore going forward.
class Storage {
  Storage._();
  static final Storage instance = Storage._();

  SharedPreferences? _prefs;

  /// Ensure SharedPreferences is ready before use.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// --- Legacy: library JSON (prefer LibraryStore instead) ---

  Future<void> saveLibrary(List<Book> books) async {
    await init();
    final jsonList = books.map((b) => b.toJson()).toList();
    await _prefs!.setString('library', jsonEncode(jsonList));
  }

  Future<List<Book>> loadLibrary() async {
    await init();
    final raw = _prefs!.getString('library');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((m) => Book.fromJson(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save user preferences (font size, theme, etc.).
  Future<void> saveUserPrefs(UserPrefs prefs) async {
    await init();
    await _prefs!.setString('user_prefs', jsonEncode(prefs.toJson()));
  }

  /// Load user preferences, or default values if not set.
  Future<UserPrefs> loadUserPrefs() async {
    await init();
    final raw = _prefs!.getString('user_prefs');
    if (raw == null || raw.isEmpty) {
      return UserPrefs(displayName: '', email: '', defaultFontSize: 18.0);
    }
    try {
      return UserPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return UserPrefs(displayName: '', email: '', defaultFontSize: 18.0);
    }
  }

  // --- AI Generated Covers / Local Covers ---

  /// Save a generated AI cover image to cache and store the local file path.
  static Future<void> saveCoverImage(String bookId, String url) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      if (await file.exists()) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cover_$bookId', file.path);
      }
    } catch (_) {}
  }

  /// Retrieve a saved AI cover image local file path, if exists.
  static Future<String?> getCoverImage(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('cover_$bookId');
    if (path != null) {
      final file = File(path);
      if (await file.exists()) return file.path;
    }
    return null;
  }

  /// Save a default generated cover (black background, white text) from PNG bytes.
  static Future<String?> saveDefaultCoverImage(String bookId, Uint8List pngBytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/default_cover_$bookId.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cover_$bookId', filePath);

      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// Clear all stored data (used for sign-out or reset).
  Future<void> clearAll() async {
    await init();
    await _prefs!.clear();
  }
}
