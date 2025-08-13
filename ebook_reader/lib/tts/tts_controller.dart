// lib/tts/tts_controller.dart

// Public API for TTS in Vidya.
// We conditionally export the correct implementation so there’s no platform import leakage.

export 'tts_controller_mobile.dart'
  if (dart.library.html) 'tts_controller_web.dart';

/// States for TTS playback.
enum TtsState { stopped, playing, paused }

/// Platform-agnostic TTS interface.
abstract class TtsController {
  TtsState get state;
  Future<void> speak(String text);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}
