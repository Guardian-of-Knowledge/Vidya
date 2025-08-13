// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/vidya_app.dart';
import 'firebase_options.dart';
// NEW: Hive-backed library store (IndexedDB on web)
import 'data/storage/library_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive everywhere (uses IndexedDB on web)
  await Hive.initFlutter();
  // Open boxes + migrate existing library from shared_preferences (one-time)
  await initLibraryStore();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const VidyaApp());
}
