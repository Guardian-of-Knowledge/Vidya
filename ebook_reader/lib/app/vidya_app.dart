import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';
import '../ui/screens/main_screen.dart';

class VidyaApp extends StatefulWidget {
  const VidyaApp({super.key});

  @override
  State<VidyaApp> createState() => _VidyaAppState();
}

class _VidyaAppState extends State<VidyaApp> {
  AppTheme _theme = AppTheme.neon;
  Accent _accent = Accent.orange;

  static const _kThemeKey = '_theme_v1';
  static const _kAccentKey = '_accent_v1';

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kThemeKey) ?? AppTheme.neon.index;
    final ax = prefs.getInt(_kAccentKey) ?? Accent.orange.index;
    setState(() {
      _theme = AppTheme.values[idx.clamp(0, AppTheme.values.length - 1)];
      _accent = Accent.values[ax.clamp(0, Accent.values.length - 1)];
    });
  }

  Future<void> _saveTheme(AppTheme t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeKey, t.index);
    setState(() => _theme = t);
  }

  Future<void> _saveAccent(Accent a) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAccentKey, a.index);
    setState(() => _accent = a);
  }

  @override
  Widget build(BuildContext context) {
    final themeData = themeFor(_theme, _accent);

    return MaterialApp(
      title: 'Vidya',
      theme: themeFor(AppTheme.light, _accent),
      darkTheme: themeFor(AppTheme.dark, _accent),
      themeMode: (_theme == AppTheme.dark)
          ? ThemeMode.dark
          : (_theme == AppTheme.light ? ThemeMode.light : ThemeMode.system),
      builder: (context, child) {
        final isSepia = _theme == AppTheme.sepia;
        final isNeon = _theme == AppTheme.neon;
        final accent = accentColor(_accent);
        Widget wrapped = child!;
        if (isSepia) {
          wrapped = Theme(data: themeFor(AppTheme.sepia, _accent), child: child);
        } else if (isNeon) {
          wrapped = Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF06070B),
                  const Color(0xFF0A0B10),
                  accent.withValues(alpha: 0.08),
                ],
              ),
            ),
            child: child,
          );
        }
        return Theme(data: themeData, child: wrapped);
      },
      home: MainScreen(
        theme: _theme,
        onThemeChanged: _saveTheme,
        accent: _accent,
        onAccentChanged: _saveAccent,
      ),
    );
  }
}
