// lib/sync/sync_manager.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

/// Idle sync manager — batches personal state push to remote storage.
/// Attach it to your widget tree root and call [markDirty] when local state changes.
/// When the app goes to background, it tries to flush pending changes.
class SyncManager with WidgetsBindingObserver {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  static const Duration _idleDelay = Duration(seconds: 20);

  bool _dirty = false;
  Timer? _idleTimer;
  Future<void> Function()? _push;

  /// Mark state as changed; schedules an idle push after [_idleDelay] of inactivity.
  void markDirty() {
    _dirty = true;
    _scheduleIdlePush();
  }

  void _scheduleIdlePush() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDelay, () => pushIfNeeded());
  }

  /// Forces an immediate best-effort push if something is dirty.
  Future<void> pushIfNeeded() async {
    _idleTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;

    final fn = _push;
    if (fn == null) return;

    try {
      await fn();
    } catch (_) {
      // swallow — add your logger if needed
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(pushIfNeeded());
    }
  }

  /// Attach a callback that will be called on idle/lifecycle events.
  void attach(Future<void> Function() doPush) {
    _push = doPush;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Detach the sync manager (stop observing lifecycle) and try to flush.
  void detach() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(pushIfNeeded());
    _push = null;
    _idleTimer?.cancel();
    _idleTimer = null;
  }
}
