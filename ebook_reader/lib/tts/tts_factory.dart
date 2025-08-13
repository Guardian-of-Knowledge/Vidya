// lib/tts/tts_factory.dart
export 'tts_controller_web.dart' if (dart.library.html) 'tts_controller_web.dart';

import 'tts_controller.dart' as base;
import 'tts_controller_io.dart'
    if (dart.library.html) 'tts_controller_web.dart' as platform;

/// Returns the correct platform TTS controller (IO vs Web).
base.TtsController createTtsController() => platform.createTtsController();
