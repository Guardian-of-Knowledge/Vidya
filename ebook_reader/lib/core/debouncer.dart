// lib/core/debouncer.dart
import 'dart:async';

/// Simple debounce helper to coalesce rapid calls into one.
/// Call it like:
///   final d = Debouncer(const Duration(milliseconds: 200));
///   d(() { /* do work */ });
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  /// Schedule [action] to run after [delay]. If called again before
  /// the timer fires, the previous one is canceled.
  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Immediately cancel any pending action.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Run the pending action immediately (if any) by canceling the timer
  /// and **not** invoking the action (keeps semantics simple).
  /// Use when you just want to clear pending work.
  void flush() => cancel();

  /// Dispose when no longer needed.
  void dispose() => cancel();
}
