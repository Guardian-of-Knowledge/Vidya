// lib/ui/widgets/import_progress_overlay.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/import/web_book_importer.dart';

class ImportProgressOverlay extends StatefulWidget {
  const ImportProgressOverlay({super.key});

  @override
  State<ImportProgressOverlay> createState() => _ImportProgressOverlayState();
}

class _ImportProgressOverlayState extends State<ImportProgressOverlay> {
  StreamSubscription<ImportProgress>? _sub;

  ImportProgress? _progress;
  bool _visible = false;
  DateTime? _lastChange;
  Timer? _autoHideTimer;
  Timer? _staleTimer;

  static const _hideDelay = Duration(seconds: 2);
  static const _staleAfter = Duration(seconds: 6); // hide if no updates for this long

  @override
  void initState() {
    super.initState();
    _sub = ImportProgressBus.instance.stream.listen(_onEvent);
  }

  void _onEvent(ImportProgress e) {
    setState(() {
      _progress = e;
      _visible = true; // show immediately on any event
      _lastChange = DateTime.now();
    });

    // Kick a stale timer on every event; if nothing else arrives, hide.
    _staleTimer?.cancel();
    _staleTimer = Timer(_staleAfter, () {
      if (!mounted) return;
      final since = _lastChange == null ? Duration.zero : DateTime.now().difference(_lastChange!);
      if (since >= _staleAfter) {
        setState(() {
          _visible = false;
          _progress = null;
        });
      }
    });

    // Also treat "upload fully completed" as terminal (even if no explicit 'done' stage is sent)
    if (_isTerminal(e)) {
      _scheduleAutoHide();
    }
  }

  bool _isTerminal(ImportProgress e) {
    if (e.stage == 'done' || e.stage == 'error') return true;
    if (e.stage == 'upload' && e.total > 0 && e.done >= e.total) return true;
    return false;
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(_hideDelay, () {
      if (!mounted) return;
      final okToHide = _lastChange != null &&
          DateTime.now().difference(_lastChange!) >= _hideDelay;
      if (okToHide) {
        setState(() {
          _visible = false;
          _progress = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _staleTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _progress == null) return const SizedBox.shrink();

    final p = _progress!;
    final cs = Theme.of(context).colorScheme;

    String title;
    Widget trailing;

    switch (p.stage) {
      case 'crawl':
        title = 'Crawling${p.bookTitle != null ? ' ${p.bookTitle}' : ''}';
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 16, width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('${p.done} fetched', style: const TextStyle(fontSize: 12)),
          ],
        );
        break;
      case 'upload':
        final double? percent =
            (p.total <= 0) ? null : (p.done / p.total).clamp(0.0, 1.0);
        final isComplete = p.total > 0 && p.done >= p.total;

        // If we already see completion, schedule a hide (in case terminal never fires)
        if (isComplete) _scheduleAutoHide();

        title = '${isComplete ? 'Uploaded' : 'Uploading'}'
            '${p.bookTitle != null ? ' ${p.bookTitle}' : ''}';
        trailing = SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: percent),
              const SizedBox(height: 4),
              Text(
                '${p.done}/${p.total}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        );
        break;
      case 'done':
        title = 'Import complete${p.bookTitle != null ? ' • ${p.bookTitle}' : ''}';
        trailing = const Icon(Icons.check_circle, size: 18);
        break;
      case 'error':
      default:
        title = 'Import failed';
        trailing = const Icon(Icons.error, size: 18);
        break;
    }

    return IgnorePointer(
      ignoring: true, // don’t block taps underneath
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 18, right: 18),
          child: Material(
            color: cs.surface.withValues(alpha: 0.95),
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    p.stage == 'error'
                        ? Icons.warning
                        : _isTerminal(p)
                            ? Icons.check
                            : Icons.cloud_download,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (p.message.isNotEmpty)
                          Text(
                            p.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
