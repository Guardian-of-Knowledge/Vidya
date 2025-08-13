// lib/tts/tts_controller_mobile.dart
import 'package:flutter_tts/flutter_tts.dart';
import 'tts_controller.dart';

/// Mobile/desktop TTS implementation using flutter_tts.
class TtsControllerImpl implements TtsController {
  final FlutterTts _tts = FlutterTts();
  TtsState _state = TtsState.stopped;

  @override
  TtsState get state => _state;

  TtsControllerImpl() {
    _tts.setStartHandler(() => _state = TtsState.playing);
    _tts.setCompletionHandler(() => _state = TtsState.stopped);
    _tts.setCancelHandler(() => _state = TtsState.stopped);
    _tts.setPauseHandler(() => _state = TtsState.paused);
    _tts.setContinueHandler(() => _state = TtsState.playing);
  }

  @override
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _state = TtsState.playing;
    await _tts.speak(text);
  }

  @override
  Future<void> pause() async {
    if (_state == TtsState.playing) {
      await _tts.pause();
      _state = TtsState.paused;
    }
  }

  @override
  Future<void> resume() async {
    // flutter_tts doesn't support resume() on mobile; no-op
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _state = TtsState.stopped;
  }
}
