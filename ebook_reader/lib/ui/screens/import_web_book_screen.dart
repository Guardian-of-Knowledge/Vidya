// lib/ui/screens/import_web_book_screen.dart
import 'dart:async' show unawaited;
// ❌ removed: import 'package:flutter/foundation.dart' show kIsWeb; (unused)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger.dart';
import '../../data/scrape/html_extractor.dart';
import '../../data/import/web_book_importer.dart';

class ImportWebBookScreen extends StatefulWidget {
  const ImportWebBookScreen({super.key});
  @override
  State<ImportWebBookScreen> createState() => _ImportWebBookScreenState();
}

class _ImportWebBookScreenState extends State<ImportWebBookScreen> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _max = TextEditingController(text: '30');

  final _selTitle = TextEditingController(text: 'h1,.chapter-title,.entry-title');
  final _selContent =
      TextEditingController(text: '#chr-content,.chapter-content,.entry-content,article');
  final _selNext =
      TextEditingController(text: 'a#next_chap,a[rel="next"],a.next,.nav-next a');
  final _remove = TextEditingController(
      text:
          '.ads,.ad,.share,.post-meta,.breadcrumbs,.advert,.footer,.chapter-nav,.google-auto-placed,iframe');

  bool _fetchAll = false;

  bool _busy = false;
  String _status = '';

  static const _kUrl = 'iwb_url';
  static const _kTitle = 'iwb_book_title';
  static const _kMax = 'iwb_max';
  static const _kSelTitle = 'iwb_sel_title';
  static const _kSelContent = 'iwb_sel_content';
  static const _kSelNext = 'iwb_sel_next';
  static const _kRemove = 'iwb_remove';
  static const _kFetchAll = 'iwb_fetch_all';

  @override
  void initState() {
    super.initState();
    unawaited(_loadForm());
  }

  Future<void> _loadForm() async {
    final p = await SharedPreferences.getInstance();
    _url.text = p.getString(_kUrl) ?? _url.text;
    _title.text = p.getString(_kTitle) ?? _title.text;
    _max.text = p.getString(_kMax) ?? _max.text;
    _selTitle.text = p.getString(_kSelTitle) ?? _selTitle.text;
    _selContent.text = p.getString(_kSelContent) ?? _selContent.text;
    _selNext.text = p.getString(_kSelNext) ?? _selNext.text;
    _remove.text = p.getString(_kRemove) ?? _remove.text;
    _fetchAll = p.getBool(_kFetchAll) ?? _fetchAll;
    setState(() {});
  }

  Future<void> _saveForm() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, _url.text.trim());
    await p.setString(_kTitle, _title.text.trim());
    await p.setString(_kMax, _max.text.trim());
    await p.setString(_kSelTitle, _selTitle.text.trim());
    await p.setString(_kSelContent, _selContent.text.trim());
    await p.setString(_kSelNext, _selNext.text.trim());
    await p.setString(_kRemove, _remove.text.trim());
    await p.setBool(_kFetchAll, _fetchAll);
  }

  // ❌ removed unused _setStatus()

  Future<void> _start() async {
    final raw = _url.text.trim();
    if (raw.isEmpty) {
      _snack('Enter a starting chapter URL.');
      return;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      _snack('URL must start with http(s)://');
      return;
    }

    final cfg = SiteConfig(
      titleSelector: _selTitle.text.trim(),
      contentSelector: _selContent.text.trim(),
      nextSelector: _selNext.text.trim(),
      removeSelectors:
          _remove.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    );

    final limit = int.tryParse(_max.text.trim()) ?? 30;
    await _saveForm();

    // Immediately background the job and pop back to Library
    setState(() {
      _busy = true;
      _status = 'Starting background import…';
    });

    LogStore.log('Import START (bg) url=$uri max=$limit all=$_fetchAll');
    unawaited(startBackgroundImport(
      start: uri,
      config: cfg,
      fetchAll: _fetchAll,
      limit: limit,
      forcedTitle: _title.text.trim().isEmpty ? null : _title.text.trim(),
    ));

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _showLogs() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Import Logs', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      LogStore.dump().isEmpty ? '(no logs yet)' : LogStore.dump(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete),
                      label: const Text('Clear'),
                      onPressed: () {
                        LogStore.clear();
                        Navigator.pop(context);
                      },
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy all'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Logs copied (use browser select/copy)'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: const Text('Import Web Novel'),
        actions: [
          IconButton(
            tooltip: 'View logs',
            icon: const Icon(Icons.bug_report),
            onPressed: _showLogs,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _url, decoration: const InputDecoration(labelText: 'Starting Chapter URL')),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Book Title (optional)')),
          const SizedBox(height: 12),
          TextField(
            controller: _max,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Max chapters to fetch'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Fetch all chapters (ignore max)'),
            subtitle: const Text('Stops automatically at the site’s last chapter'),
            value: _fetchAll,
            onChanged: (v) => setState(() => _fetchAll = v),
          ),
          const Divider(height: 32),
          Text('Site Selectors (advanced)', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7))),
          const SizedBox(height: 8),
          TextField(controller: _selTitle, decoration: const InputDecoration(labelText: 'Title selector')),
          const SizedBox(height: 8),
          TextField(controller: _selContent, decoration: const InputDecoration(labelText: 'Content selector')),
          const SizedBox(height: 8),
          TextField(controller: _selNext, decoration: const InputDecoration(labelText: '"Next chapter" link selector')),
          const SizedBox(height: 8),
          TextField(controller: _remove, decoration: const InputDecoration(labelText: 'Remove selectors (comma-separated)')),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.menu_book),
            label: Text(_busy ? _status : 'Start Import (background)'),
          ),
          const SizedBox(height: 8),
          Text(
            'Note: Only import from sites that allow it. Respect terms & robots.txt.',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
