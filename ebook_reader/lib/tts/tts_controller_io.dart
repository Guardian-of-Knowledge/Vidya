// lib/tts/tts_controller_io.dart
import 'package:flutter_tts/flutter_tts.dart';
import 'tts_controller.dart' as base;

/// Mobile/desktop (non-web) implementation using flutter_tts.
class _IoTtsController implements base.TtsController {
  final FlutterTts _tts = FlutterTts();
  base.TtsState _state = base.TtsState.stopped;

  _IoTtsController() {
    _tts.setStartHandler(() => _state = base.TtsState.playing);
    _tts.setCompletionHandler(() => _state = base.TtsState.stopped);
    _tts.setCancelHandler(() => _state = base.TtsState.stopped);
    _tts.setPauseHandler(() => _state = base.TtsState.paused);
    _tts.setContinueHandler(() => _state = base.TtsState.playing);
  }

  @override
  base.TtsState get state => _state;

  @override
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _state = base.TtsState.playing;
    await _tts.speak(text);
  }

  @override
  Future<void> pause() async {
    if (_state == base.TtsState.playing) {
      await _tts.pause();
      _state = base.TtsState.paused;
    }
  }

  @override
  Future<void> resume() async {
    // flutter_tts on mobile doesn't expose resume; no-op.
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _state = base.TtsState.stopped;
  }
}

/// Factory function used by conditional import.
base.TtsController createTtsController() => _IoTtsController();
