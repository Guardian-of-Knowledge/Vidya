// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// or rerun `flutterfire configure` to regenerate this file.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCFkapg3Q6q7Py5aVS17ELgMman4d4Oqfk',
    appId: '1:827465597764:web:16585e406294ca0f1e0d11',
    messagingSenderId: '827465597764',
    projectId: 'book-reader-e4b18',
    authDomain: 'book-reader-e4b18.firebaseapp.com',
    storageBucket: 'book-reader-e4b18.firebasestorage.app',
    measurementId: 'G-LYW7XFZ98X',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDpR9l1_WEw3XjfjKT3QohCZFUtLuBg3Rc',
    appId: '1:827465597764:android:7e904b13658310901e0d11',
    messagingSenderId: '827465597764',
    projectId: 'book-reader-e4b18',
    storageBucket: 'book-reader-e4b18.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAJVSdG3uuhfzNm9N0HaaUNGuRbV3k0Kgg',
    appId: '1:827465597764:ios:69dded8b1414bf061e0d11',
    messagingSenderId: '827465597764',
    projectId: 'book-reader-e4b18',
    storageBucket: 'book-reader-e4b18.firebasestorage.app',
    iosClientId: '827465597764-ppndsjdq6qb750nt4f8dta4875o6a1gd.apps.googleusercontent.com',
    iosBundleId: 'com.example.ebookReader',
  );


  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAJVSdG3uuhfzNm9N0HaaUNGuRbV3k0Kgg',
    appId: '1:827465597764:ios:69dded8b1414bf061e0d11',
    messagingSenderId: '827465597764',
    projectId: 'book-reader-e4b18',
    storageBucket: 'book-reader-e4b18.firebasestorage.app',
    iosClientId: '827465597764-ppndsjdq6qb750nt4f8dta4875o6a1gd.apps.googleusercontent.com',
    iosBundleId: 'com.example.ebookReader',
  );


  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCFkapg3Q6q7Py5aVS17ELgMman4d4Oqfk',
    appId: '1:827465597764:web:aa7da8b2723693661e0d11',
    messagingSenderId: '827465597764',
    projectId: 'book-reader-e4b18',
    authDomain: 'book-reader-e4b18.firebaseapp.com',
    storageBucket: 'book-reader-e4b18.firebasestorage.app',
    measurementId: 'G-8NGNZM7LL4',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyCFkapg3Q6q7Py5aVS17ELgMman4d4Oqfk',
    appId: '1:827465597764:web:16585e406294ca0f1e0d11',
    messagingSenderId: '827465597764',
    projectId: 'book-reader-e4b18',
    authDomain: 'book-reader-e4b18.firebaseapp.com',
    storageBucket: 'book-reader-e4b18.firebasestorage.app',
    measurementId: 'G-LYW7XFZ98X',
  );
}