// lib/ui/screens/global_catalog_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../data/firestore/catalog_api.dart';
import '../../core/storage.dart';
import '../../secrets.dart';
import '../widgets/neon_bar.dart';

class GlobalCatalogScreen extends StatelessWidget {
  final bool isSignedIn;
  final VoidCallback onBack;
  final Future<void> Function(String bookId) onAddToMyLibrary;
  final List<Widget> Function() commonActions;
  final Accent accent;

  const GlobalCatalogScreen({
    super.key,
    required this.isSignedIn,
    required this.onBack,
    required this.onAddToMyLibrary,
    required this.commonActions,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final ac = accentColor(accent);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Global Catalog', style: neonText(ac, size: 20, weight: FontWeight.w800)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
        actions: commonActions(),
        flexibleSpace: NeonBar(accent: ac),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // ✅ Use restored `books` collection
        stream: booksCol().limit(200).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error loading catalog: ${snap.error}',
                style: TextStyle(color: cs.error),
              ),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No books in catalog yet.'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final m = d.data();
              final name = (m['name'] ?? 'Untitled.docx') as String;
              final count = (m['chapterCount'] is int) ? m['chapterCount'] as int : 0;
              final coverUrl = (m['coverUrl'] as String?)?.trim();

              return _CatalogCard(
                id: d.id,
                name: name,
                chapterCount: count,
                fireCoverUrl: (coverUrl?.isEmpty ?? true) ? null : coverUrl,
                isSignedIn: isSignedIn,
                onAddToMyLibrary: () => onAddToMyLibrary(d.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _CatalogCard extends StatefulWidget {
  final String id;
  final String name;
  final int chapterCount;
  final String? fireCoverUrl;
  final bool isSignedIn;
  final Future<void> Function() onAddToMyLibrary;

  const _CatalogCard({
    required this.id,
    required this.name,
    required this.chapterCount,
    required this.fireCoverUrl,
    required this.isSignedIn,
    required this.onAddToMyLibrary,
  });

  @override
  State<_CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<_CatalogCard> with SingleTickerProviderStateMixin {
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
    // 1) Firestore-provided cover
    if (widget.fireCoverUrl != null && widget.fireCoverUrl!.isNotEmpty) {
      setState(() => _coverUrl = widget.fireCoverUrl);
      if (!_coverUrl!.startsWith('/')) {
        await precacheImage(NetworkImage(_coverUrl!), context);
        if (!mounted) return;
      }
      _fadeController.forward();
      return;
    }

    // 2) Cached cover
    final cached = await Storage.getCoverImage('global_${widget.id}');
    if (cached != null) {
      if (!mounted) return;
      setState(() => _coverUrl = cached);
      if (!_coverUrl!.startsWith('/')) {
        await precacheImage(NetworkImage(_coverUrl!), context);
        if (!mounted) return;
      }
      _fadeController.forward();
      return;
    }

    // 3) Generate via OpenAI API
    final generated = await _generateBookCover(widget.name);
    if (generated != null) {
      await Storage.saveCoverImage('global_${widget.id}', generated);
      if (!mounted) return;
      setState(() => _coverUrl = generated);
      if (!_coverUrl!.startsWith('/')) {
        await precacheImage(NetworkImage(_coverUrl!), context);
        if (!mounted) return;
      }
      _fadeController.forward();
    } else {
      // 4) Fallback
      final fallback = await _generateFallbackCover(widget.name, widget.id);
      setState(() => _coverUrl = fallback);
      _fadeController.forward();
    }
  }

  Future<String?> _generateBookCover(String title) async {
    try {
      final url = Uri.parse('https://api.openai.com/v1/images/generations');
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $openAIApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-image-1',
          'prompt':
              "A beautiful, modern, dreamy book cover for a story titled '$title'. Loóna-like, soft glow, dark background, magical highlights, clean typography area.",
          'size': '512x512',
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        if (list.isNotEmpty) {
          return (list.first as Map<String, dynamic>)['url'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String> _generateFallbackCover(String title, String id) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.black;
    const size = Size(512, 512);

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: title,
        style: GoogleFonts.cinzelDecorative(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '...',
    );
    textPainter.layout(maxWidth: size.width - 40);
    final textOffset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    textPainter.paint(canvas, textOffset);

    final picture = recorder.endRecording();
    final img = await picture.toImage(512, 512);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/fallback_$id.png';
    final file = File(filePath);
    await file.writeAsBytes(pngBytes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cover_global_$id', filePath);

    return filePath;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overlayStart = Colors.black.withValues(alpha: 0.7);
    final overlayEnd = Colors.transparent;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: _coverUrl != null
                  ? (_coverUrl!.startsWith('/')
                      ? Image.file(File(_coverUrl!), fit: BoxFit.cover)
                      : Image.network(_coverUrl!, fit: BoxFit.cover))
                  : Container(color: cs.surfaceContainerHighest),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [overlayStart, overlayEnd],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cinzelDecorative(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.chapterCount > 0
                          ? '${widget.chapterCount} chapter(s)'
                          : 'Shared book',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: widget.isSignedIn
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: widget.onAddToMyLibrary,
                      icon: const Icon(Icons.library_add),
                      label: const Text('Add'),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: overlayStart,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Sign in to add', style: TextStyle(color: Colors.white)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
