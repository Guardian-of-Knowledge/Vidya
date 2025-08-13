// lib/core/logger.dart
import 'package:flutter/foundation.dart';

class LogStore {
  static final List<String> _lines = <String>[];

  static void clear() => _lines.clear();

  static void log(String msg) {
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $msg';
    _lines.add(line);
    debugPrint(line);
  }

  static List<String> lines() => List.unmodifiable(_lines);

  static String dump() => _lines.join('\n');
}
