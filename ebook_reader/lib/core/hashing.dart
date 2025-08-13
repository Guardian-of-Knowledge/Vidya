// lib/core/hashing.dart
import 'dart:typed_data';

/// Computes a 32-bit FNV-1a hash in both forward and reverse directions,
/// then concatenates them into a 16-character hex string.
/// 
/// Firestore rules accept 16–32 hex for global book IDs, so this is valid.
/// Not cryptographically secure; intended for lightweight content IDs.
///
/// Example:
/// ```dart
/// final hash = fnv32x2Hash(bytes);
/// ```
String fnv32x2Hash(Uint8List bytes) {
  const int offset = 0x811C9DC5;
  const int prime = 0x01000193;

  int h1 = offset;
  for (final b in bytes) {
    h1 ^= b;
    h1 = (h1 * prime) & 0xFFFFFFFF;
  }

  int h2 = offset;
  for (int i = bytes.length - 1; i >= 0; i--) {
    h2 ^= bytes[i];
    h2 = (h2 * prime) & 0xFFFFFFFF;
  }

  return h1.toRadixString(16).padLeft(8, '0') +
      h2.toRadixString(16).padLeft(8, '0');
}
