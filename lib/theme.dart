import 'package:flutter/material.dart';

/// A dark, cyan-accented "arc reactor" theme to match the JARVIS aesthetic.
class JarvisColors {
  static const background = Color(0xFF0A0E14);
  static const surface = Color(0xFF10161F);
  static const surfaceAlt = Color(0xFF161D28);
  static const accent = Color(0xFF38D6FF);
  static const accentDim = Color(0xFF1F8FB0);
  static const textPrimary = Color(0xFFE7F6FB);
  static const textSecondary = Color(0xFF8FA3B0);
  static const danger = Color(0xFFFF6B6B);
  static const success = Color(0xFF52E39A);
}

ThemeData buildJarvisTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: JarvisColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: JarvisColors.accent,
      secondary: JarvisColors.accentDim,
      surface: JarvisColors.surface,
      error: JarvisColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: JarvisColors.background,
      elevation: 0,
      foregroundColor: JarvisColors.textPrimary,
      centerTitle: false,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: JarvisColors.textPrimary,
      displayColor: JarvisColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JarvisColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: JarvisColors.textSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: JarvisColors.accent,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? JarvisColors.accent
            : JarvisColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? JarvisColors.accentDim
            : JarvisColors.surfaceAlt,
      ),
    ),
  );
}
