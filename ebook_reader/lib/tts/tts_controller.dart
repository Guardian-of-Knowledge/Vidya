// lib/tts/tts_controller.dart
// Platform-agnostic TTS interface (no platform imports here).

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
