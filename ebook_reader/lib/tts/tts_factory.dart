// lib/tts/tts_factory.dart
// Picks the right implementation without leaking dart:html into mobile builds.

import 'tts_controller.dart' as base;
import 'tts_controller_io.dart'
    if (dart.library.html) 'tts_controller_web.dart' as impl;

/// Returns the correct platform TTS controller (IO vs Web).
base.TtsController createTtsController() => impl.createTtsController();
