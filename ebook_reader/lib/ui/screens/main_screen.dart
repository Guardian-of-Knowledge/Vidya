// lib/ui/screens/main_screen.dart
import 'dart:async' show unawaited, StreamSubscription;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/import_progress_overlay.dart';

import '../../app/theme.dart';
import '../../auth/auth.dart';
import '../../core/debouncer.dart';
import '../../core/prefs.dart';
import '../../data/docx/parser.dart';
import '../../data/firestore/catalog_api.dart' as catalog;
import '../../data/firestore/user_shelf_api.dart';
import '../../data/models.dart';
import '../../sync/sync_manager.dart';
import '../../data/import/web_book_importer.dart';
import '../../data/storage/library_store.dart' as store; // ✅ avoid name clashes

import 'library_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'global_catalog_screen.dart';
import 'import_web_book_screen.dart';

class MainScreen extends StatefulWidget {
  final AppTheme theme;
  final ValueChanged<AppTheme> onThemeChanged;
  final Accent accent;
  final ValueChanged<Accent> onAccentChanged;

  const MainScreen({
    super.key,
    required this.theme,
    required this.onThemeChanged,
    required this.accent,
    required this.onAccentChanged,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _tab = 0; // Library, Reader, Settings, Global
  bool _loading = true;

  final List<Book> _books = [];
  Book? _selected;
  UserPrefs _prefs = UserPrefs(displayName: '', email: '', defaultFontSize: 18);

  User? _user;
  late final Stream<User?> _authStream;

  final _scrollLocalDebounce = Debouncer(const Duration(milliseconds: 600));

  // ---------- Web import progress overlay (modal for "Update from Web" loop) ----------
  bool _isFetching = false;
  bool _cancelFetch = false;
  String _fetchMessage = 'Preparing…';
  int _fetchRounds = 0;
  int _fetchAddedSoFar = 0;

  // ---------- Tiny cloud sync indicator ----------
  bool _cloudSyncing = false;
  double _cloudProgress = 0; // 0..1
  late final AnimationController _spinCtrl;

  // ---------- Listen to background import bus to auto-refresh Library ----------
  StreamSubscription<ImportProgress>? _importSub;

  @override
  void initState() {
    super.initState();

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0,
      upperBound: 1,
    )..stop();

    // Flush personal state on idle / background
    SyncManager.instance.attach(_pushRemoteIfSignedIn);

    // Auth → restore
    _authStream = authStateChanges();
    _authStream.listen((u) async {
      _user = u;
      if (u == null) {
        await _restoreLocal();
      } else {
        await _restoreRemote(u.uid);
        await primeWebMetaForSignedInUserToLocal();
      }
    });

    // Background import progress → refresh Library when done/error
    _importSub = ImportProgressBus.instance.stream.listen((e) async {
      if (!mounted) return;

      // show quick toasts at key milestones
      if (e.stage == 'done') {
        // Reload local Hive library so the new book appears immediately
        await _restoreLocal();
        if (!mounted) return;
        _snack('Import complete${e.bookTitle != null ? ': ${e.bookTitle}' : ''}');
      } else if (e.stage == 'error') {
        _snack(e.message.isNotEmpty ? e.message : 'Import failed');
      }
      // For 'crawl' and 'upload' the floating overlay shows progress.
    });
  }

  @override
  void dispose() {
    _importSub?.cancel();
    SyncManager.instance.detach();
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreLocal() async {
    final books = await store.loadLibrary();                // ✅ namespaced
    final selectedId = await store.loadSelectedBookId();    // ✅ namespaced
    final up = await loadUserPrefs();

    if (!mounted) return;

    setState(() {
      _books
        ..clear()
        ..addAll(books);

      _selected = selectedId != null
          ? _books.where((b) => b.id == selectedId).firstOrNull
          : (_books.isNotEmpty ? _books.first : null);

      _prefs = up;
      _loading = false;
    });
  }

  /// Fast cloud restore (non-destructive):
  /// - Build Book shells using fetchGlobalBookLite (name + chapterCount)
  /// - Merge with any existing local books so we don't wipe chapters
  /// - Then pull full chapters in the background and update state
  Future<void> _restoreRemote(String uid) async {
    // Load whatever we already have locally to merge with shells.
    final existingLocal = await store.loadLibrary();
    final localById = {for (final b in existingLocal) b.id: b};

    final shelf = await userLibraryCol(uid).get();

    final List<Book> merged = [];
    final List<String> idsNeedingPull = [];

    for (final d in shelf.docs) {
      final m = d.data();
      final id = d.id;

      // Lite fetch (server) for name + count
      final lite = await catalog.fetchGlobalBookLite(id);
      final remoteCount = lite?.chapterCount ?? 0;

      // If we have a local copy with chapters, keep them (non-destructive).
      final local = localById[id];

      final initial = Book(
        id: id,
        name: (m['name'] ?? (lite?.name ?? local?.name ?? 'Untitled')) as String,
        // IMPORTANT: keep local chapters if present; otherwise start empty and pull in bg.
        chapters: (local?.chapters.isNotEmpty == true) ? local!.chapters : const <Chapter>[],
        isFavorite: (m['isFavorite'] ?? (local?.isFavorite ?? false)) as bool,
        lastChapterIndex: (m['lastChapterIndex'] ?? (local?.lastChapterIndex ?? 0)) as int,
        lastScrollOffset: (m['lastScrollOffset'] ?? (local?.lastScrollOffset ?? 0.0)).toDouble(),
        createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? (local?.createdAt ?? DateTime.now()),
        bookmarks: ((m['bookmarks'] as List<dynamic>? ?? (local?.bookmarks ?? const [])))
            .map((e) => e is Bookmark ? e : Bookmark.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        coverUrl: local?.coverUrl, // keep cached cover if we had one
      );

      merged.add(initial);

      // Decide whether this ID needs a background chapter pull.
      final haveCount = initial.chapters.length;
      if (remoteCount > haveCount) {
        idsNeedingPull.add(id);
      }
    }

    if (!mounted) return;

    // Update UI state with the merged list; DO NOT wipe chapters we already had.
    setState(() {
      _books
        ..clear()
        ..addAll(merged);

      // Preserve current selection when possible; else pick first.
      if (_selected != null && _books.any((b) => b.id == _selected!.id)) {
        _selected = _books.firstWhere((b) => b.id == _selected!.id);
      } else {
        _selected = _books.isNotEmpty ? _books.first : null;
      }

      _loading = false;
    });

    // Persist merged snapshot locally (safe; still contains real chapters where we had them).
    await store.saveLibrary(_books, selectedId: _selected?.id);
    await saveUserPrefs(_prefs);

    // Background: pull full ordered chapters for any book that needs it, then save.
    for (final id in idsNeedingPull) {
      unawaited(() async {
        try {
          final chapters = await catalog.pullMissingChapters(id);
          if (chapters.isEmpty) return;
          if (!mounted) return;
          setState(() {
            final idx = _books.indexWhere((x) => x.id == id);
            if (idx >= 0) {
              _books[idx] = _books[idx].copyWith(chapters: chapters);
              if (_selected?.id == id) _selected = _books[idx];
            }
          });
          await store.saveLibrary(_books, selectedId: _selected?.id);
        } catch (_) {
          // ignore fetch errors silently to avoid UX noise
        }
      }());
    }
  }

  Future<void> _persistLocal({bool mirrorRemoteOnIdle = false}) async {
    await store.saveLibrary(_books, selectedId: _selected?.id); // ✅
    await saveUserPrefs(_prefs);
    if (mirrorRemoteOnIdle) {
      SyncManager.instance.markDirty();
    }
  }

  // ---- Cloud sync with progress (all books) ----
  Future<void> _pushRemoteIfSignedIn() async {
    final u = _user;
    if (u == null) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final b in _books) {
        batch.set(userBookDoc(u.uid, b.id), {
          'name': b.name,
          'isFavorite': b.isFavorite,
          'lastChapterIndex': b.lastChapterIndex,
          'lastScrollOffset': b.lastScrollOffset,
          'bookmarks': b.bookmarks.map((x) => x.toJson()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();

      if (!mounted) return;

      setState(() {
        _cloudSyncing = true;
        _cloudProgress = 0.01;
      });
      _spinCtrl.repeat();

      final booksToSync = List<Book>.from(_books);
      final n = booksToSync.isEmpty ? 1 : booksToSync.length;

      for (int i = 0; i < booksToSync.length; i++) {
        final base = i / n;
        await catalog.ensureGlobalBook(
          booksToSync[i],
          uid: u.uid,
          onProgress: (done, total) {
            final p = (total <= 0) ? 1.0 : (done / total).clamp(0.0, 1.0);
            if (mounted) {
              setState(() => _cloudProgress = (base + p / n).clamp(0.0, 1.0));
            }
          },
        );
        await Future<void>.delayed(Duration.zero);
      }

      if (mounted) {
        setState(() => _cloudProgress = 1.0);
        _snack('Synced to cloud');
      }
    } on FirebaseException catch (e) {
      if (mounted) _snack('Cloud sync failed: ${e.code}');
    } catch (e) {
      if (mounted) _snack('Cloud sync failed: $e');
    } finally {
      if (mounted) setState(() => _cloudSyncing = false);
      _spinCtrl.stop();
    }
  }

  // ---- Cloud sync with progress (single book) ----
  Future<void> _pushSingleBookToCloudWithProgress(Book b) async {
    final u = _user;
    if (u == null) return;

    if (!mounted) return;
    setState(() {
      _cloudSyncing = true;
      _cloudProgress = 0.01;
    });
    _spinCtrl.repeat();

    try {
      await userBookDoc(u.uid, b.id).set({
        'name': b.name,
        'isFavorite': b.isFavorite,
        'lastChapterIndex': b.lastChapterIndex,
        'lastScrollOffset': b.lastScrollOffset,
        'bookmarks': b.bookmarks.map((x) => x.toJson()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await catalog.ensureGlobalBook(
        b,
        uid: u.uid,
        onProgress: (done, total) {
          final p = (total <= 0) ? 1.0 : (done / total).clamp(0.0, 1.0);
          if (mounted) setState(() => _cloudProgress = p);
        },
      );

      if (mounted) {
        setState(() => _cloudProgress = 1.0);
        _snack('Saved to cloud');
      }
    } on FirebaseException catch (e) {
      if (mounted) _snack('Cloud save failed: ${e.code}');
    } catch (e) {
      if (mounted) _snack('Cloud save failed: $e');
    } finally {
      if (mounted) setState(() => _cloudSyncing = false);
      _spinCtrl.stop();
    }
  }

  // ----- Import actions -----
  Future<void> importDocx() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
      withData: true,
    );
    final f = picked?.files.single;
    final bytes = f?.bytes;
    if (f == null || bytes == null) {
      if (!mounted) return;
      _snack('Could not read file bytes.');
      return;
    }
    try {
      final book = await parseDocxToBook(f.name, bytes);

      final existingIndex = _books.indexWhere((b) => b.id == book.id);
      if (!mounted) return;
      setState(() {
        if (existingIndex >= 0) {
          final prev = _books[existingIndex];
          _books[existingIndex] = Book(
            id: prev.id,
            name: book.name,
            chapters: book.chapters,
            isFavorite: prev.isFavorite,
            lastChapterIndex: prev.lastChapterIndex,
            lastScrollOffset: prev.lastScrollOffset,
            createdAt: prev.createdAt,
            bookmarks: prev.bookmarks,
          );
          _selected = _books[existingIndex];
        } else {
          _books.add(book);
          _selected = book;
        }
        _tab = 1; // Reader
      });

      final u = _user;
      if (u != null) {
        await _pushSingleBookToCloudWithProgress(_selected!);
      }

      await _persistLocal(mirrorRemoteOnIdle: true);

      if (!mounted) return;
      _snack('Imported: ${book.name} • ${book.chapters.length} chapter(s)');
    } catch (e) {
      if (!mounted) return;
      _snack('Import failed: $e');
    }
  }

  Future<void> openImportWeb() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportWebBookScreen()),
    );
    if (!mounted) return;

    if (ok == true) {
      // Quick refresh to show existing books; overlay + bus will refresh again on 'done'
      await _restoreLocal();
      if (!mounted) return;
      _snack('Import started in background');
      setState(() => _tab = 0);

      // Best-effort immediate push if signed in (non-blocking)
      unawaited(_pushRemoteIfSignedIn());
    }
  }

  // ----- Web resume (enhanced) -----
  Future<void> updateFromWeb(Book b) async {
    final hasMeta = await hasWebImportMeta(b.id);

    if (!hasMeta) {
      if (!mounted) return;
      final next = await _askForUrl(
        context,
        title: 'Start / next chapter URL',
        hint: 'https://example.com/chapter-251',
      );
      if (next == null || next.trim().isEmpty) return;

      Uri? override;
      try {
        override = Uri.parse(next.trim());
      } catch (_) {
        if (!mounted) return;
        _snack('Invalid URL');
        return;
      }

      await _resumeWebLoop(b, overrideStart: override);
      return;
    }

    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Update from web'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'auto'),
            child: const ListTile(
              leading: Icon(Icons.refresh),
              title: Text('Resume automatically'),
              subtitle: Text('Continue from the last saved position'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'url'),
            child: const ListTile(
              leading: Icon(Icons.link),
              title: Text('Resume from a specific URL'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const ListTile(
              leading: Icon(Icons.close),
              title: Text('Cancel'),
            ),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == 'cancel') return;

    Uri? override;
    if (action == 'url') {
      if (!mounted) return;
      final next = await _askForUrl(
        context,
        title: 'Next chapter URL',
        hint: 'https://example.com/chapter-251',
      );
      if (next == null || next.trim().isEmpty) return;
      try {
        override = Uri.parse(next.trim());
      } catch (_) {
        if (!mounted) return;
        _snack('Invalid URL');
        return;
      }
    }

    await _resumeWebLoop(b, overrideStart: override);
  }

  Future<String?> _askForUrl(BuildContext context,
      {required String title, required String hint}) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _resumeWebLoop(Book b, {Uri? overrideStart}) async {
    if (!mounted) return;

    setState(() {
      _isFetching = true;
      _cancelFetch = false;
      _fetchMessage = 'Fetching more chapters…';
      _fetchRounds = 0;
      _fetchAddedSoFar = 0;
    });

    int rounds = 0;
    int addedTotal = 0;
    const maxRounds = 50;
    const chaptersPerPass = 25;

    try {
      while (mounted && !_cancelFetch && rounds < maxRounds) {
        final current = _books.firstWhere((x) => x.id == b.id, orElse: () => b);
        final before = current.chapters.length;

        setState(() {
          _fetchMessage = 'Pass ${rounds + 1}…';
          _fetchRounds = rounds + 1;
        });

        try {
          await resumeWebImport(
            current,
            overrideStart: rounds == 0 ? overrideStart : null,
            maxChapters: chaptersPerPass,
          );
        } catch (e, st) {
          debugPrint('[UpdateFromWeb] resume failed: $e\n$st');
          if (mounted) _snack('Update from web failed: $e');
          break;
        }

        if (!mounted) break;

        await _restoreLocal();
        final after =
            _books.firstWhere((x) => x.id == b.id, orElse: () => current).chapters.length;

        final added = (after - before).clamp(0, 1 << 30);
        addedTotal += added;
        rounds += 1;

        setState(() {
          _fetchAddedSoFar = addedTotal;
          _fetchMessage = added > 0
              ? 'Pass $rounds • +$added new chapter(s) (total +$addedTotal)'
              : 'Pass $rounds • no new chapters';
        });

        if (added == 0) break;
        if (_cancelFetch) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }

    final latest = _books.firstWhere((x) => x.id == b.id, orElse: () => b);

    if (addedTotal > 0) {
      await _pushSingleBookToCloudWithProgress(latest);
    }

    if (!mounted) return;

    if (_cancelFetch) {
      _snack('Fetch cancelled.');
    } else if (addedTotal > 0) {
      _snack('Updated "${latest.name}" • +$addedTotal chapter(s) • now ${latest.chapters.length}');
    } else {
      _snack('No new chapters found.');
    }
  }

  // ----- Library actions -----
  void selectBook(Book b) {
    setState(() {
      _selected = b;
      _tab = 1;
    });
    unawaited(_refreshBookFromGlobalIfStale(b));
    unawaited(_persistLocal(mirrorRemoteOnIdle: true));
  }

  Future<void> _refreshBookFromGlobalIfStale(Book b) async {
    final lite = await catalog.fetchGlobalBookLite(b.id);
    if (lite == null) return;
    if (lite.chapterCount <= b.chapters.length) return;

    try {
      final chapters = await catalog.pullMissingChapters(b.id);
      if (chapters.isEmpty) return;
      if (!mounted) return;
      setState(() {
        final idx = _books.indexWhere((x) => x.id == b.id);
        if (idx >= 0) _books[idx] = _books[idx].copyWith(chapters: chapters);
        if (_selected?.id == b.id) {
          _selected = _books[idx];
        }
      });
      await store.saveLibrary(_books, selectedId: _selected?.id); // ✅
    } catch (_) {}
  }

  void renameBook(Book b, String newName) {
    setState(() => b.name = newName.trim().isEmpty ? b.name : newName.trim());
    unawaited(_persistLocal(mirrorRemoteOnIdle: true));
  }

  void toggleFavorite(Book b) {
    setState(() => b.isFavorite = !b.isFavorite);
    unawaited(_persistLocal(mirrorRemoteOnIdle: true));
  }

  Future<void> deleteBook(Book b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete book?'),
        content: Text('Remove "${b.name}" from your library?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted) return;

    if (ok != true) return;
    setState(() {
      _books.removeWhere((x) => x.id == b.id);
      if (_selected?.id == b.id) _selected = _books.isNotEmpty ? _books.first : null;
      if (_tab == 1 && _selected == null) _tab = 0;
    });
    final u = _user;
    if (u != null) {
      await removeUserBook(u.uid, b.id);
    }
    await _persistLocal(mirrorRemoteOnIdle: true);
  }

  Future<void> addGlobalToMyLibrary(String id) async {
  final u = _user;
  if (u == null) {
    if (!mounted) return;
    _snack('Sign in to add from Global.');
    return;
  }

  final b = await catalog.fetchGlobalBook(id);
  if (!mounted) return;

  final idx = _books.indexWhere((x) => x.id == b.id);
  setState(() {
    if (idx >= 0) {
      final prev = _books[idx];
      _books[idx] = Book(
        id: prev.id,
        name: b.name,
        chapters: b.chapters,
        isFavorite: prev.isFavorite,
        lastChapterIndex: prev.lastChapterIndex,
        lastScrollOffset: prev.lastScrollOffset,
        createdAt: prev.createdAt,
        bookmarks: prev.bookmarks,
      );
      _selected = _books[idx];
    } else {
      _books.add(b);
      _selected = b;
    }
    _tab = 1;
  });

  await linkBookToUserShelf(u.uid, _selected!);
  await _persistLocal(mirrorRemoteOnIdle: true);

  if (!mounted) return;
  _snack('Added to My Library: ${_selected!.name}');
}


  // ----- Reader actions -----
  void updateChapter(int newIndex) {
    if (_selected == null) return;
    setState(() => _selected!.lastChapterIndex = newIndex);
    unawaited(_persistLocal(mirrorRemoteOnIdle: true));
  }

  void updateScroll(double offset) {
    if (_selected == null) return;
    _selected!.lastScrollOffset = offset;
    _scrollLocalDebounce(() {
      unawaited(store.saveLibrary(_books, selectedId: _selected?.id)); // ✅
    });
  }

  void addBookmarkHere({String? label}) {
    final b = _selected;
    if (b == null) return;
    final bm = Bookmark(
      chapterIndex: b.lastChapterIndex,
      offset: b.lastScrollOffset,
      label: (label?.trim().isNotEmpty == true)
          ? label!.trim()
          : 'Ch ${b.lastChapterIndex + 1} @ ${b.lastScrollOffset.toStringAsFixed(0)}',
    );
    setState(() => b.bookmarks.add(bm));
    unawaited(_persistLocal(mirrorRemoteOnIdle: true));
    _snack('Bookmark added');
  }

  void removeBookmark(Bookmark bm) {
    final b = _selected;
    if (b == null) return;
    setState(() => b.bookmarks.removeWhere((x) =>
        x.chapterIndex == bm.chapterIndex &&
        (x.offset - bm.offset).abs() < 1.0 &&
        x.label == bm.label));
    unawaited(_persistLocal(mirrorRemoteOnIdle: true));
  }

  // ----- Settings / prefs -----
  void savePrefs(UserPrefs p) async {
    setState(() => _prefs = p);
    await _persistLocal(mirrorRemoteOnIdle: true);
    _snack('Preferences saved');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----- Auth UI -----
  List<Widget> _actions() {
    final user = _user;
    final accent = accentColor(widget.accent);

    final syncPill = !_cloudSyncing
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RotationTransition(
                  turns: _spinCtrl,
                  child: Icon(Icons.cloud_upload, size: 16, color: accent),
                ),
                const SizedBox(width: 4),
                Text(
                  '${(_cloudProgress * 100).clamp(0, 100).round()}%',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ],
            ),
          );

    return [
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Center(
          child: Text('VIDYA', style: neonText(accent, size: 16, weight: FontWeight.w800)),
        ),
      ),
      syncPill,
      if (user == null)
        IconButton(
          tooltip: 'Sign in with Google',
          icon: const Icon(Icons.login),
          onPressed: () async {
            final cred = await signInWithGoogle();
            if (!mounted) return;
            if (cred != null) _snack('Signed in as ${cred.user?.displayName ?? 'User'}');
          },
        )
      else
        PopupMenuButton<String>(
          tooltip: 'Account',
          icon: CircleAvatar(
            radius: 14,
            foregroundImage: (user.photoURL != null) ? NetworkImage(user.photoURL!) : null,
            onForegroundImageError: (_, __) {},
            child: const Icon(Icons.account_circle),
          ),
          onSelected: (v) async {
            switch (v) {
              case 'sync_up':
                await _pushRemoteIfSignedIn();
                break;
              case 'sync_down':
                final u = _user;
                if (u != null) {
                  await _restoreRemote(u.uid);
                  await primeWebMetaForSignedInUserToLocal();
                }
                if (!mounted) return;
                _snack('Restored from cloud');
                break;
              case 'signout':
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                _snack('Signed out');
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'sync_up', child: ListTile(leading: Icon(Icons.backup), title: Text('Sync to cloud'))),
            PopupMenuItem(value: 'sync_down', child: ListTile(leading: Icon(Icons.download), title: Text('Restore from cloud'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'signout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'))),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Text('Vidya', style: neonText(accentColor(widget.accent), size: 28)),
        ),
      );
    }

    final pages = [
      LibraryScreen(
        books: _books,
        selected: _selected,
        onImport: importDocx,
        onImportWeb: openImportWeb,
        onSelect: selectBook,
        onToggleFavorite: toggleFavorite,
        onDelete: deleteBook,
        onRename: renameBook,
        onUpdateFromWeb: updateFromWeb,
        onOpenGlobalTab: () => setState(() => _tab = 3),
        commonActions: _actions,
      ),
      ReaderScreen(
        key: ValueKey('${_selected?.id}-${_prefs.defaultFontSize}-${_prefs.lineHeight}-${_prefs.useSerif}'),
        book: _selected,
        prefs: _prefs,
        onBackToLibrary: () => setState(() => _tab = 0),
        onChapterChange: updateChapter,
        onScrollChange: updateScroll,
        onDeleteCurrent: _selected == null ? null : () => deleteBook(_selected!),
        onUpdatePrefs: savePrefs,
        onAddBookmark: addBookmarkHere,
        onRemoveBookmark: removeBookmark,
        commonActions: _actions,
        accent: widget.accent,
        onUpdateFromWeb: _selected == null ? null : () => updateFromWeb(_selected!),
      ),
      SettingsScreen(
        theme: widget.theme,
        onThemeChanged: widget.onThemeChanged,
        accent: widget.accent,
        onAccentChanged: widget.onAccentChanged,
        prefs: _prefs,
        onSavePrefs: savePrefs,
        commonActions: _actions,
      ),
      GlobalCatalogScreen(
        isSignedIn: _user != null,
        onBack: () => setState(() => _tab = 0),
        onAddToMyLibrary: addGlobalToMyLibrary,
        commonActions: _actions,
        accent: widget.accent,
      ),
    ];

    final content = Scaffold(
      body: pages[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.library_books), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Reader'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'Global'),
        ],
      ),
    );

    return Stack(
      children: [
        content,

        // 👇 Floating, non-blocking background import/progress indicator
        const ImportProgressOverlay(),

        // Modal overlay specifically for the interactive "Update from Web" loop
        if (_isFetching)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Updating from web',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      _fetchMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (_fetchRounds > 0)
                      Text(
                        'Pass $_fetchRounds • Total +$_fetchAddedSoFar',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _cancelFetch ? null : () => setState(() => _cancelFetch = true),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

extension FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
