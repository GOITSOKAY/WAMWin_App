import 'package:flutter/material.dart';

/// Brand board: Poppins; Royal Blue #0B49D1, Golden Yellow #FFC107, Clean White, Light Gray #E8EEF7.
class Brand {
  static const blue = Color(0xFF0B49D1);
  static const blue50 = Color(0xFFEEF3FD);
  static const yellow = Color(0xFFFFC107);
  static const yellow600 = Color(0xFFE6A900);
  static const yellow50 = Color(0xFFFFF6D9);
  static const white = Color(0xFFFFFFFF);
  static const gray = Color(0xFFE8EEF7);
  static const navy = Color(0xFF0A2463);
  static const onBrandSoft = Color(0xFFDCE6FB);
  // Brand red: (i) buttons, notifications and higher-tier notices. #C62828 behind white text = 5.6:1;
  // #D32F2F as text on white = 5.0:1; dark mode uses #FF8A80 on dark surfaces.
  static const red = Color(0xFFD32F2F);
  static const redStrong = Color(0xFFC62828);
  static const redOnDark = Color(0xFFFF8A80);
  static const redSoft = Color(0xFFFFEBEE);
  static Color redFor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? redOnDark : red;
}

/// Light/dark palette (same tokens as the web client's CSS).
class Palette {
  const Palette({required this.bg, required this.surface, required this.surface2, required this.text, required this.text2,
      required this.line, required this.danger, required this.dangerBg, required this.ok, required this.okBg, required this.link, required this.tagBlueBg});
  final Color bg, surface, surface2, text, text2, line, danger, dangerBg, ok, okBg, link, tagBlueBg;
  static const light = Palette(bg: Brand.white, surface: Brand.white, surface2: Brand.gray, text: Brand.navy, text2: Color(0xFF4A5878),
      line: Color(0xFFD3DCEB), danger: Color(0xFFC62828), dangerBg: Color(0xFFFDECEC), ok: Color(0xFF13795B), okBg: Color(0xFFE6F5EF),
      link: Brand.blue, tagBlueBg: Brand.blue50);
  static const dark = Palette(bg: Color(0xFF071433), surface: Color(0xFF0D1E47), surface2: Color(0xFF13285C), text: Color(0xFFEEF3FD),
      text2: Color(0xFFA9B8D9), line: Color(0xFF24396E), danger: Color(0xFFFF8A80), dangerBg: Color(0xFF3B1416), ok: Color(0xFF6FDBB3),
      okBg: Color(0xFF0E3327), link: Color(0xFF8FB0FF), tagBlueBg: Color(0xFF13285C));
  static Palette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(useMaterial3: true, brightness: brightness, fontFamily: 'Poppins');
  final text = base.textTheme.apply(bodyColor: p.text, displayColor: p.text, fontFamily: 'Poppins');
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: Brand.blue, brightness: brightness, primary: brightness == Brightness.dark ? p.link : Brand.blue,
        secondary: Brand.yellow, surface: p.surface, error: p.danger),
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 28, height: 1.2, letterSpacing: -0.2),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 22, height: 1.25),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      bodySmall: text.bodySmall?.copyWith(fontSize: 13, color: p.text2, height: 1.45),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w500, fontSize: 16),
    ),
    dividerColor: p.line,
    checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.blue : null)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: Brand.redStrong,
        contentTextStyle: TextStyle(fontFamily: 'Poppins', color: Colors.white), actionTextColor: Colors.white),
  );
}
