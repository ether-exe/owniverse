import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The design language of SPEC.md §14, as code.
///
/// Canvas, ink, muted, hairline, one accent. No shadows, no gradients, no
/// glass, no glow. Depth is a hairline.
abstract final class Palette {
  static const Color canvas = Color(0xFF0C0C0D);
  static const Color ink = Color(0xFFEDEBE6);
  static const Color muted = Color(0xFF8C8880);
  static const Color hairline = Color(0xFF222224);
  static const Color accent = Color(0xFFFF4D2E);
}

/// Three families, no fourth. Newsreader for titles, Plex Sans for UI,
/// Plex Mono for every number and every URL.
abstract final class AppType {
  static TextStyle serif({
    double size = 32,
    double height = 1.15,
    Color color = Palette.ink,
    FontWeight weight = FontWeight.w400,
  }) => GoogleFonts.newsreader(
    fontSize: size,
    height: height,
    color: color,
    fontWeight: weight,
  );

  static TextStyle sans({
    double size = 15,
    double height = 1.55,
    Color color = Palette.ink,
    FontWeight weight = FontWeight.w400,
  }) => GoogleFonts.ibmPlexSans(
    fontSize: size,
    height: height,
    color: color,
    fontWeight: weight,
  );

  static TextStyle mono({
    double size = 13,
    Color color = Palette.muted,
    double spacing = 0.4,
  }) => GoogleFonts.ibmPlexMono(
    fontSize: size,
    color: color,
    letterSpacing: spacing,
  );
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: Palette.canvas,
    onSurface: Palette.ink,
    primary: Palette.accent,
    onPrimary: Palette.canvas,
    outline: Palette.hairline,
    error: Palette.accent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.canvas,
    canvasColor: Palette.canvas,
    dividerColor: Palette.hairline,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: TextTheme(
      displayLarge: AppType.serif(size: 44),
      headlineMedium: AppType.serif(size: 26),
      titleMedium: AppType.sans(size: 16, weight: FontWeight.w500),
      bodyLarge: AppType.sans(size: 15),
      bodyMedium: AppType.sans(size: 14, color: Palette.muted),
      labelLarge: AppType.mono(size: 13, color: Palette.ink),
      labelSmall: AppType.mono(size: 11),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      hintStyle: AppType.sans(size: 15, color: Palette.muted),
      labelStyle: AppType.mono(size: 11),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Palette.hairline),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Palette.ink),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Palette.accent),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Palette.accent),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.ink,
        textStyle: AppType.sans(size: 15),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        shape: const RoundedRectangleBorder(),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.accent,
      linearTrackColor: Palette.hairline,
    ),
  );
}
