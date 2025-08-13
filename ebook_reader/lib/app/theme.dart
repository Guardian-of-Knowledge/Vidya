// lib/app/theme.dart
import 'package:flutter/material.dart';

enum AppTheme { light, dark, sepia, neon }
enum Accent { orange, yellow, green, red, gold }

Color accentColor(Accent a) {
  switch (a) {
    case Accent.orange:
      return const Color(0xFFFF6A00);
    case Accent.yellow:
      return const Color(0xFFFFD400);
    case Accent.green:
      return const Color(0xFF00FFA3);
    case Accent.red:
      return const Color(0xFFFF1744);
    case Accent.gold:
      return const Color(0xFFFFC107);
  }
}

/// Common CardThemeData for all themes.
CardThemeData _cardTheme() {
  return CardThemeData(
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.antiAlias,
  );
}

ThemeData themeFor(AppTheme t, Accent accent) {
  final seed = accentColor(accent);

  final filledStyle = FilledButton.styleFrom(
    backgroundColor: seed,
    foregroundColor: Colors.black,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
  final elevatedStyle = ElevatedButton.styleFrom(
    backgroundColor: seed,
    foregroundColor: Colors.black,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  ThemeData base;
  switch (t) {
    case AppTheme.dark:
      base = ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        cardTheme: _cardTheme(),
        useMaterial3: true,
      );
      break;
    case AppTheme.sepia:
      const bg = Color(0xFFF4ECD8);
      const onBg = Colors.black;
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFFB08968),
        brightness: Brightness.light,
      ).copyWith(
        surface: bg,
        onSurface: onBg,
      );
      base = ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: bg,
        cardTheme: _cardTheme(),
        useMaterial3: true,
      );
      break;
    case AppTheme.neon:
      base = ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark).copyWith(
          surface: const Color(0xFF0A0B10),
          primary: seed,
        ),
        cardTheme: _cardTheme(),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      );
      break;
    case AppTheme.light:
      base = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        cardTheme: _cardTheme(),
        useMaterial3: true,
      );
      break;
  }

  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: filledStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: elevatedStyle),
    bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
      backgroundColor: (t == AppTheme.neon || t == AppTheme.dark)
          ? const Color(0xFF0E1018)
          : Colors.white,
      selectedItemColor: seed,
      unselectedItemColor:
          (t == AppTheme.neon || t == AppTheme.dark) ? Colors.white70 : Colors.black54,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: seed.withValues(alpha: 0.18),
      side: BorderSide(color: seed.withValues(alpha: 0.6)),
      labelStyle: TextStyle(
        color: (t == AppTheme.neon || t == AppTheme.dark) ? Colors.white : Colors.black,
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: seed, width: 2),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: seed,
      thumbColor: seed,
    ),
  );
}

TextStyle neonText(Color accent, {double size = 22, FontWeight weight = FontWeight.w700}) {
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: 0.5,
    color: Colors.white,
    shadows: [
      Shadow(color: accent.withValues(alpha: 0.7), blurRadius: 12, offset: const Offset(0, 0)),
      Shadow(color: accent.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 0)),
    ],
  );
}
