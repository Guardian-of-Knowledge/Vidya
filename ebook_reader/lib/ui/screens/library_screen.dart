import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../core/storage.dart';
import '../../secrets.dart';

class LibraryScreen extends StatelessWidget {
  final List<Book> books;
  final Book? selected;

  /// Passed in from higher-level app state (owns the actual import logic)
  final Future<void> Function() onImport;
  final VoidCallback onImportWeb;
  final void Function(Book) onSelect;
  final void Function(Book) onToggleFavorite;
  final Future<void> Function(Book) onDelete;
  final void Function(Book, String) onRename;
  final Future<void> Function(Book) onUpdateFromWeb; // used by card menu
  final VoidCallback onOpenGlobalTab;

  final List<Widget> Function() commonActions;

  const LibraryScreen({
    super.key,
    required this.books,
    required this.selected,
    required this.onImport,
    required this.onImportWeb,
    required this.onSelect,
    required this.onToggleFavorite,
    required this.onDelete,
    required this.onRename,
    required this.onUpdateFromWeb,
    required this.onOpenGlobalTab,
    required this.commonActions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;
    final onSurface = cs.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text('My Library', style: neonText(accent, size: 20, weight: FontWeight.w800)),
        actions: [
          ...commonActions(),
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: 'Explore Global',
            onPressed: onOpenGlobalTab,
          ),
        ],
      ),
      body: books.isEmpty
          ? Center(
              child: Text(
                'No books yet',
                style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = constraints.maxWidth ~/ 160;
                if (crossAxisCount < 2) crossAxisCount = 2;
                if (crossAxisCount > 6) crossAxisCount = 6;

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, i) {
                    final b = books[i];
                    return _BookCard(
                      book: b,
                      isSelected: selected?.id == b.id,
                      onSelect: () => onSelect(b),
                      onRename: (name) => onRename(b, name),
                      onToggleFavorite: () => onToggleFavorite(b),
                      onUpdateFromWeb: () => onUpdateFromWeb(b),
                      onDelete: () => onDelete(b),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final choice = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.description),
                    title: const Text('Import .docx'),
                    subtitle: const Text('Local import • auto-syncs to cloud/global'),
                    onTap: () => Navigator.of(ctx).pop('docx'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('Import from web (crawl)'),
                    subtitle: const Text('Runs in background • shows floating progress'),
                    onTap: () => Navigator.of(ctx).pop('web'),
                  ),
                ],
              ),
            ),
          );
          if (choice == 'docx') {
            await onImport(); // controller handles ensureGlobalBook + user shelf link
          } else if (choice == 'web') {
            onImportWeb(); // navigates to ImportWebBookScreen; returns immediately
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Import'),
      ),
    );
  }
}

class _BookCard extends StatefulWidget {
  final Book book;
  final bool isSelected;
  final VoidCallback onSelect;
  final Future<void> Function() onDelete;
  final VoidCallback onToggleFavorite;
  final Future<void> Function() onUpdateFromWeb;
  final void Function(String) onRename;

  const _BookCard({
    required this.book,
    required this.isSelected,
    required this.onSelect,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onUpdateFromWeb,
    required this.onRename,
  });

  @override
  State<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<_BookCard> with SingleTickerProviderStateMixin {
  String? _coverUrl;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _loadCover();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadCover() async {
    // 1) Book-provided cover
    if (widget.book.coverUrl != null && widget.book.coverUrl!.isNotEmpty) {
      setState(() => _coverUrl = widget.book.coverUrl);
      if (!_coverUrl!.startsWith('/')) {
        if (!mounted) return;
        await precacheImage(NetworkImage(_coverUrl!), context);
      }
      if (!mounted) return;
      _fadeController.forward();
      return;
    }

    // 2) Cached cover
    final cached = await Storage.getCoverImage(widget.book.id);
    if (cached != null) {
      setState(() => _coverUrl = cached);
      if (!_coverUrl!.startsWith('/')) {
        if (!mounted) return;
        await precacheImage(NetworkImage(_coverUrl!), context);
      }
      if (!mounted) return;
      _fadeController.forward();
      return;
    }

    // 3) Try OpenAI (only if key is present)
    if ((openAIApiKey).trim().isNotEmpty) {
      final generated = await _generateBookCover(widget.book.name);
      if (!mounted) return;
      if (generated != null) {
        await Storage.saveCoverImage(widget.book.id, generated);
        setState(() => _coverUrl = generated);
        if (!_coverUrl!.startsWith('/')) {
          if (!mounted) return;
          await precacheImage(NetworkImage(_coverUrl!), context);
        }
        if (!mounted) return;
        _fadeController.forward();
        return;
      }
    }

    // 4) Default decorative cover
    final fallback = await _generateDefaultCover(widget.book.name);
    if (!mounted) return;
    if (fallback != null) {
      await Storage.saveCoverImage(widget.book.id, fallback);
      setState(() => _coverUrl = fallback);
    }
    if (!mounted) return;
    _fadeController.forward();
  }

  Future<String?> _generateBookCover(String title) async {
    try {
      final url = Uri.parse("https://api.openai.com/v1/images/generations");
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $openAIApiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "gpt-image-1",
          "prompt":
              "A modern, artistic, minimalist book cover for a book titled '$title', high quality digital illustration",
          "size": "512x512"
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['data'] is List && data['data'].isNotEmpty) {
          return data['data'][0]['url'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _generateDefaultCover(String title) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      const ui.Size size = ui.Size(512, 768);

      final paint = Paint()..color = Colors.black;
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height), paint);

      final textStyle = GoogleFonts.cinzelDecorative(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      );

      final textSpan = TextSpan(text: title, style: textStyle);
      final tp = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '...',
      );

      tp.layout(maxWidth: size.width - 40);
      tp.paint(canvas, ui.Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final file = await Storage.saveDefaultCoverImage(widget.book.id, pngBytes);
      return file;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.book;

    return GestureDetector(
      onTap: widget.onSelect,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: widget.isSelected ? 6 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: widget.isSelected
                ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: _coverUrl != null
                    ? (_coverUrl!.startsWith('/')
                        ? Image.file(File(_coverUrl!), fit: BoxFit.cover)
                        : Image.network(_coverUrl!, fit: BoxFit.cover))
                    : Container(color: Colors.black),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  icon: Icon(
                    b.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: b.isFavorite ? Colors.red : Colors.white,
                  ),
                  onPressed: widget.onToggleFavorite,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black.withValues(alpha: 0.54),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.name,
                        style: GoogleFonts.cinzelDecorative(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${b.chapters.length} chapter(s)',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (v) async {
                    switch (v) {
                      case 'rename':
                        final name = await _ask(context, 'Rename', 'New name', initial: b.name);
                        if (name != null && name.trim().isNotEmpty) widget.onRename(name.trim());
                        break;
                      case 'favorite':
                        widget.onToggleFavorite();
                        break;
                      case 'update_web':
                        await widget.onUpdateFromWeb();
                        break;
                      case 'delete':
                        await widget.onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: ListTile(leading: Icon(Icons.edit), title: Text('Rename')),
                    ),
                    PopupMenuItem(
                      value: 'favorite',
                      child: ListTile(leading: Icon(Icons.favorite), title: Text('Toggle favorite')),
                    ),
                    PopupMenuItem(
                      value: 'update_web',
                      child: ListTile(leading: Icon(Icons.sync), title: Text('Update from web')),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(leading: Icon(Icons.delete), title: Text('Delete')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<String?> _ask(BuildContext context, String title, String hint,
      {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }
}
