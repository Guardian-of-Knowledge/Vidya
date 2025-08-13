// lib/auth/auth.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

/// Stream of auth state changes (signed-in user or null).
Stream<User?> authStateChanges() => FirebaseAuth.instance.authStateChanges();

/// Currently signed-in user (or null).
User? get currentUser => FirebaseAuth.instance.currentUser;

/// Google sign-in using Firebase Auth.
/// - On Web: uses signInWithPopup
/// - On Mobile/Desktop: uses signInWithProvider (no separate GoogleSignIn plugin needed)
Future<UserCredential?> signInWithGoogle() async {
  try {
    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      return await FirebaseAuth.instance.signInWithPopup(provider);
    } else {
      return await FirebaseAuth.instance.signInWithProvider(provider);
    }
  } catch (e) {
    // Keep it quiet in release; callers can show a toast/snack.
    debugPrint('Google sign-in failed: $e');
    return null;
  }
}

/// Sign out the current user.
Future<void> signOut() async {
  await FirebaseAuth.instance.signOut();
}
