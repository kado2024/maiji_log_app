import 'package:flutter/material.dart';

/// Color tokens shared by the whole app (mirrors the web prototype).
class Palette {
  final Color bg, surface, ink, muted, line, accent, accentInk;
  const Palette({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentInk,
  });

  static const light = Palette(
    bg: Color(0xFFF3F1F7),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF1B1830),
    muted: Color(0xFF6B6784),
    line: Color(0xFFDCD8E6),
    accent: Color(0xFFFF5A36),
    accentInk: Color(0xFFFFFFFF),
  );
  static const dark = Palette(
    bg: Color(0xFF110F1C),
    surface: Color(0xFF1C1930),
    ink: Color(0xFFF1EEFA),
    muted: Color(0xFFA29DBB),
    line: Color(0xFF2F2B47),
    accent: Color(0xFFFF6A48),
    accentInk: Color(0xFF1A0A05),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

const kDisplay = 'DelaGothicOne';
const kBody = 'ZenKakuGothicNew';
const kMono = 'IBMPlexMono';

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: kBody,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: b,
      primary: p.accent,
      onPrimary: p.accentInk,
      surface: p.surface,
      onSurface: p.ink,
    ),
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          fontFamily: kBody, fontWeight: FontWeight.w700, fontSize: 17, color: p.ink),
    ),
    dividerColor: p.line,
  );
}
