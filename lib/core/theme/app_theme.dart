import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF25D366);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.light,
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  static Color avatarColorFor(int? seed) {
    const palette = [
      Color(0xFF25D366),
      Color(0xFF34B7F1),
      Color(0xFFEE6352),
      Color(0xFFF4A259),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
    ];
    final s = seed ?? 0;
    return palette[s.abs() % palette.length];
  }
}
