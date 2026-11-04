import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF6C5CE7);

  // Palet mode terang: navy blue + purple + white smoke.
  static const _navy = Color(0xFF1E2A78);
  static const _purple = Color(0xFF7C4DFF);
  static const _whiteSmoke = Color(0xFFF5F5F5);

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: _navy,
      brightness: Brightness.light,
    );
    final scheme = base.copyWith(
      primary: _navy,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDDE1FF),
      onPrimaryContainer: const Color(0xFF0B1450),
      secondary: _purple,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE9DDFF),
      onSecondaryContainer: const Color(0xFF2A0A7A),
      tertiary: const Color(0xFF9B6BFF),
      onTertiary: Colors.white,
      surface: _whiteSmoke,
      onSurface: const Color(0xFF1A1B2E),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: const Color(0xFFEFEFF6),
      surfaceContainerHigh: const Color(0xFFE8E8F2),
      surfaceContainerHighest: const Color(0xFFE2E2EE),
      outlineVariant: const Color(0xFFD9D9E8),
    );
    return _build(Brightness.light, scheme: scheme).copyWith(
      scaffoldBackgroundColor: _whiteSmoke,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: _whiteSmoke,
        foregroundColor: _navy,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness, {ColorScheme? scheme}) {
    scheme ??= ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final outline = scheme.outlineVariant;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
