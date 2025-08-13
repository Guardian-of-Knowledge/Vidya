// lib/ui/screens/reader_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // RenderAbstractViewport
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import '../../core/html_clean.dart';
import '../../core/prefs.dart';
import '../../data/models.dart';
import '../../tts/tts_controller.dart';
import '../../tts/tts_factory.dart' as tts_factory;
import '../widgets/neon_bar.dart';

class ReaderScreen extends StatefulWidget {
  final Book? book;
  final UserPrefs prefs;

  final VoidCallback onBackToLibrary;
  final void Function(int chapterIndex) onChapterChange;
  final void Function(double offset) onScrollChange;
  final VoidCallback? onDeleteCurrent;

  // kept for API compatibility; we save silently in Reader
  final ValueChanged<UserPrefs> onUpdatePrefs;

  final void Function({String? label}) onAddBookmark;
  final void Function(Bookmark) onRemoveBookmark;

  final List<Widget> Function() commonActions;
  final Accent accent;

  final VoidCallback? onUpdateFromWeb;

  const ReaderScreen({
    super.key,
    required this.book,
    required this.prefs,
    required this.onBackToLibrary,
    required this.onChapterChange,
    required this.onScrollChange,
    required this.onDeleteCurrent,
    required this.onUpdatePrefs,
    required this.onAddBookmark,
    required this.onRemoveBookmark,
    required this.commonActions,
    required this.accent,
    this.onUpdateFromWeb,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late double _fontSize;
  late double _lineHeight;
  late bool _useSerif;

  final ScrollController _scroll = ScrollController();

  // Chips row controller + keys to center the active chip
  final ScrollController _chipsCtrl = ScrollController();
  final List<GlobalKey> _chipKeys = <GlobalKey>[];

  late TtsController _tts;

  bool _showFind = false;
  final TextEditingController _findCtrl = TextEditingController();
  int _currentMatchIdx = 0;
  List<int> _matchPositions = const [];

  // We still auto-hide only the BOTTOM control bar
  bool _showBottomUI = true;
  Timer? _hideTimer;

  // debounce silent prefs saves
  Timer? _prefsSaveDebounce;

  Book? get book => widget.book;

  // ---------- Helpers ----------
  int _safeChapterIndex(Book b) {
    // If no chapters, return 0; otherwise clamp to [0, len-1].
    if (b.chapters.isEmpty) return 0;
    final idx = b.lastChapterIndex;
    if (idx.isNaN) return 0; // very defensive (JS interop/web)
    return idx.clamp(0, b.chapters.length - 1);
  }

  String _currentText(Book b) {
    final idx = _safeChapterIndex(b);
    final txt = b.chapters[idx].text;
    final cleaned = looksLikeHtml(txt) ? htmlToPlain(txt) : txt;
    return cleaned.isEmpty ? '(This chapter has no text)' : cleaned;
  }

  String _normalize(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\.(docx|pdf|txt)$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'[_\-\s]+'), ' ');
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]+'), '');
    return t.trim();
  }

  String _displayChapterTitle(Book b, int index) {
    if (b.chapters.isEmpty) return 'No chapters';
    final safe = index.clamp(0, b.chapters.length - 1);
    final raw = (b.chapters[safe].title).trim();
    if (raw.isEmpty) return 'Chapter ${safe + 1}';
    final bookNorm = _normalize(b.name);
    final chapNorm = _normalize(raw);
    if (chapNorm.isEmpty || chapNorm == bookNorm) {
      return 'Chapter ${safe + 1}';
    }
    return raw;
  }

  // -------------------------------------------

  @override
  void initState() {
    super.initState();
    _tts = tts_factory.createTtsController();
    _fontSize = widget.prefs.defaultFontSize.clamp(12.0, 40.0);
    _lineHeight = widget.prefs.lineHeight.clamp(1.2, 2.0);
    _useSerif = widget.prefs.useSerif;

    // First-frame setup: scroll content & center active chip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final b = book;
      if (b != null && _scroll.hasClients && b.lastScrollOffset > 0) {
        _scroll.jumpTo(b.lastScrollOffset);
      }
      _ensureChipKeys();
      _centerActiveChip(); // initial centering (includes "Chapter 1" on first open)
      _startHideTimer();
    });

    _scroll.addListener(() {
      final b = book;
      if (b == null) return;
      widget.onScrollChange(_scroll.offset);
    });
  }

  @override
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If book or selected chapter changed outside (e.g., via Library/Bookmarks), recenter
    if (widget.book?.id != oldWidget.book?.id ||
        widget.book?.lastChapterIndex != oldWidget.book?.lastChapterIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureChipKeys();
        _centerActiveChip();
      });
    }
  }

  void _ensureChipKeys() {
    final b = book;
    if (b == null) return;
    if (_chipKeys.length != b.chapters.length) {
      _chipKeys
        ..clear()
        ..addAll(List.generate(b.chapters.length, (_) => GlobalKey()));
    }
  }

  /// Robust centering that works for horizontal lists/web using viewport math.
  void _centerActiveChip() {
    final b = book;
    if (b == null || !_chipsCtrl.hasClients || b.chapters.isEmpty) return;

    final idx = _safeChapterIndex(b);
    if (idx >= _chipKeys.length) return;

    final ctx = _chipKeys[idx].currentContext;
    if (ctx == null) return;

    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox) return;

    final RenderAbstractViewport viewport = RenderAbstractViewport.of(renderObject);
    final reveal = viewport.getOffsetToReveal(renderObject, 0.5); // 0.5 = center
    final target = reveal.offset;

    final min = _chipsCtrl.position.minScrollExtent;
    final max = _chipsCtrl.position.maxScrollExtent;
    final clamped = target.clamp(min, max);

    _chipsCtrl.animateTo(
      clamped,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showBottomUI = false);
    });
  }

  void _onUserActivity() {
    if (!_showBottomUI) setState(() => _showBottomUI = true);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _prefsSaveDebounce?.cancel();
    _scroll.dispose();
    _chipsCtrl.dispose();
    _findCtrl.dispose();
    super.dispose();
  }

  // silent, debounced save (no toast)
  void _queueSilentPrefsSave() {
    _prefsSaveDebounce?.cancel();
    _prefsSaveDebounce = Timer(const Duration(milliseconds: 400), () async {
      final updated = widget.prefs.copyWith(
        defaultFontSize: _fontSize,
        lineHeight: _lineHeight,
        useSerif: _useSerif,
      );
      await saveUserPrefs(updated);
    });
  }

  Future<void> _speak(Book b) async {
    final text = _currentText(b).trim();
    if (text.isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
    setState(() {});
  }

  Future<void> _pause() async {
    await _tts.pause();
    setState(() {});
  }

  Future<void> _resume() async {
    await _tts.resume();
    setState(() {});
  }

  Future<void> _stop() async {
    await _tts.stop();
    setState(() {});
  }

  void _rebuildMatches() {
    final b = book;
    if (b == null) return;
    final q = _findCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _matchPositions = const [];
        _currentMatchIdx = 0;
      });
      return;
    }
    final text = _currentText(b);
    final lower = text.toLowerCase();
    final ql = q.toLowerCase();
    final pos = <int>[];
    int i = 0;
    while (true) {
      final idx = lower.indexOf(ql, i);
      if (idx < 0) break;
      pos.add(idx);
      i = idx + (ql.isEmpty ? 1 : ql.length);
    }
    setState(() {
      _matchPositions = pos;
      _currentMatchIdx = 0;
    });
  }

  void _jumpToMatch(int which) {
    if (_matchPositions.isEmpty || book == null) return;
    final b = book!;
    final text = _currentText(b);
    final totalLen = text.isEmpty ? 1 : text.length;
    final targetChar = _matchPositions[which].clamp(0, totalLen - 1);
    if (_scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final maxScroll = _scroll.position.maxScrollExtent;
        final proportion = targetChar / totalLen;
        _scroll.jumpTo(proportion * maxScroll);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = book;
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor(widget.accent);

    // Base style + GoogleFonts for reliable web font swap
    final base = const TextStyle(
      color: Colors.black,
    ).copyWith(fontSize: _fontSize, height: _lineHeight);

    final bodyStyle = _useSerif
        ? GoogleFonts.notoSerif(textStyle: base) // serif
        : GoogleFonts.notoSans(textStyle: base); // sans

    final highlightStyle = bodyStyle.copyWith(
      backgroundColor: Colors.yellow.withValues(alpha: 0.4),
      fontWeight: FontWeight.w600,
    );

    TextSpan highlightSpans({required String text, required String query}) {
      if (query.trim().isEmpty) return TextSpan(text: text, style: bodyStyle);
      final lower = text.toLowerCase();
      final q = query.toLowerCase();
      final spans = <TextSpan>[];
      int i = 0;
      while (true) {
        final idx = lower.indexOf(q, i);
        if (idx < 0) {
          spans.add(TextSpan(text: text.substring(i), style: bodyStyle));
          break;
        }
        if (idx > i) spans.add(TextSpan(text: text.substring(i, idx), style: bodyStyle));
        spans.add(TextSpan(text: text.substring(idx, idx + q.length), style: highlightStyle));
        i = idx + q.length;
      }
      return TextSpan(children: spans);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        title: Text(
          b?.name ?? 'Reader',
          style: neonText(accent, size: 20, weight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBackToLibrary,
        ),
        actions: [
          IconButton(
            tooltip: 'Find in chapter',
            icon: const Icon(Icons.find_in_page),
            onPressed: () {
              setState(() {
                _showFind = !_showFind;
                if (_showFind) _rebuildMatches();
              });
            },
          ),
          if (widget.onUpdateFromWeb != null)
            IconButton(
              tooltip: 'Update from web',
              icon: const Icon(Icons.sync),
              onPressed: widget.onUpdateFromWeb,
            ),
          ...widget.commonActions(),
        ],
        flexibleSpace: NeonBar(accent: accent),
      ),
      body: MouseRegion(
        onHover: (_) => _onUserActivity(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _onUserActivity,
          child: b == null
              ? Center(
                  child: Text(
                    'No book selected.\nGo to Library and import/select a .docx.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: cs.onSurface.withValues(alpha: 0.8)),
                  ),
                )
              : SafeArea(
                  child: Column(
                    children: [
                      // CHIPS ROW — dynamic side padding lets first/last chip center cleanly.
                      if (b.chapters.length > 1)
                        SizedBox(
                          height: 56,
                          child: LayoutBuilder(
                            builder: (context, c) {
                              final sidePad = c.maxWidth / 2; // half viewport to allow centering
                              return ListView.separated(
                                controller: _chipsCtrl,
                                padding: EdgeInsets.fromLTRB(sidePad, 8, sidePad, 8),
                                scrollDirection: Axis.horizontal,
                                itemCount: b.chapters.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (_, i) => ChoiceChip(
                                  key: _chipKeys.length == b.chapters.length ? _chipKeys[i] : null,
                                  label: Text(
                                    _displayChapterTitle(b, i),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  selected: i == _safeChapterIndex(b),
                                  onSelected: (_) {
                                    _stop();
                                    widget.onChapterChange(i);
                                    if (_scroll.hasClients) _scroll.jumpTo(0);
                                    _rebuildMatches();
                                    // after parent updates, center the chip
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      _centerActiveChip();
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                        ),

                      // Bookmarks (optional) — when jumping, also recenter the chip
                      if (b.bookmarks.isNotEmpty)
                        SizedBox(
                          height: 48,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            scrollDirection: Axis.horizontal,
                            itemCount: b.bookmarks.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final bm = b.bookmarks[i];
                              final isCurrent = bm.chapterIndex == _safeChapterIndex(b);
                              return InputChip(
                                avatar: const Icon(Icons.bookmark, size: 18),
                                label: Text(bm.label),
                                selected: isCurrent,
                                onPressed: () {
                                  if (bm.chapterIndex != _safeChapterIndex(b)) {
                                    widget.onChapterChange(bm.chapterIndex);
                                  }
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (_scroll.hasClients) _scroll.jumpTo(bm.offset);
                                    _centerActiveChip();
                                  });
                                },
                                onDeleted: () => widget.onRemoveBookmark(bm),
                              );
                            },
                          ),
                        ),

                      if (_showFind) _buildFindBar(),

                      // CONTENT — stretches horizontally (no fixed/max width)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.2),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            controller: _scroll,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _displayChapterTitle(b, _safeChapterIndex(b)),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                RichText(
                                  text: highlightSpans(
                                    text: _currentText(b),
                                    query: _showFind ? _findCtrl.text : '',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // BOTTOM CONTROLS — still auto-hide
                      if (_showBottomUI) _buildControls(accent),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFindBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findCtrl,
              decoration: InputDecoration(
                hintText: 'Find text in this chapter',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _findCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _findCtrl.clear();
                          _rebuildMatches();
                        },
                      ),
              ),
              onChanged: (_) => _rebuildMatches(),
            ),
          ),
          const SizedBox(width: 8),
          Text('${_matchPositions.isEmpty ? 0 : _currentMatchIdx + 1}/${_matchPositions.length}'),
          IconButton(
            tooltip: 'Previous',
            onPressed: _matchPositions.isEmpty
                ? null
                : () {
                    setState(() {
                      _currentMatchIdx =
                          (_currentMatchIdx - 1 + _matchPositions.length) %
                              _matchPositions.length;
                    });
                    _jumpToMatch(_currentMatchIdx);
                  },
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: 'Next',
            onPressed: _matchPositions.isEmpty
                ? null
                : () {
                    setState(() {
                      _currentMatchIdx = (_currentMatchIdx + 1) % _matchPositions.length;
                    });
                    _jumpToMatch(_currentMatchIdx);
                  },
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: book?.chapters.isEmpty == true ? null : () => _speak(book!),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _tts.state == TtsState.playing ? _pause : null,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: (kIsWeb && _tts.state == TtsState.paused) ? _resume : null,
            icon: const Icon(Icons.play_circle),
            label: const Text('Resume'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _tts.state != TtsState.stopped ? _stop : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
          const Spacer(),
          const Icon(Icons.format_size, color: Colors.white),
          SizedBox(
            width: 120,
            child: Slider(
              value: _fontSize,
              min: 12,
              max: 40,
              divisions: 14,
              label: _fontSize.toStringAsFixed(0),
              onChanged: (v) {
                setState(() => _fontSize = v);
                _queueSilentPrefsSave();
              },
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.format_line_spacing, color: Colors.white),
          SizedBox(
            width: 120,
            child: Slider(
              value: _lineHeight,
              min: 1.2,
              max: 2.0,
              divisions: 8,
              label: _lineHeight.toStringAsFixed(1),
              onChanged: (v) {
                setState(() => _lineHeight = v);
                _queueSilentPrefsSave();
              },
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<bool>(
            value: _useSerif,
            dropdownColor: Colors.black87,
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: false, child: Text('Sans')),
              DropdownMenuItem(value: true, child: Text('Serif')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _useSerif = v);
                _queueSilentPrefsSave();
              }
            },
          ),
        ],
      ),
    );
  }
}
