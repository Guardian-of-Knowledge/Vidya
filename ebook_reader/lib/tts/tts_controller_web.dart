// lib/tts/tts_controller_web.dart
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'tts_controller.dart' as base;

/// Web TTS implementation using the browser SpeechSynthesis API.
class _WebTtsController implements base.TtsController {
  base.TtsState _state = base.TtsState.stopped;

  @override
  base.TtsState get state => _state;

  @override
  Future<void> speak(String text) async {
    final engine = html.window.speechSynthesis;
    if (engine == null || text.trim().isEmpty) return;
    engine.cancel();
    final utter = html.SpeechSynthesisUtterance(text);
    _state = base.TtsState.playing;
    utter.onEnd.listen((_) => _state = base.TtsState.stopped);
    engine.speak(utter);
  }

  @override
  Future<void> pause() async {
    final engine = html.window.speechSynthesis;
    if (engine != null && _state == base.TtsState.playing) {
      engine.pause();
      _state = base.TtsState.paused;
    }
  }

  @override
  Future<void> resume() async {
    final engine = html.window.speechSynthesis;
    if (engine != null && _state == base.TtsState.paused) {
      engine.resume();
      _state = base.TtsState.playing;
    }
  }

  @override
  Future<void> stop() async {
    html.window.speechSynthesis?.cancel();
    _state = base.TtsState.stopped;
  }
}

/// Factory function used by conditional import.
base.TtsController createTtsController() => _WebTtsController();
