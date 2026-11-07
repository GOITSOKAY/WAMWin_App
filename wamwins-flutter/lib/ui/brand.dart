import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Tablet/desktop = at least 640 x 500 logical px (landscape phones keep the mobile logo) - same rule as the web.
bool isLargeScreen(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.width >= 640 && s.height >= 500;
}

enum LogoKind { hero, bar }

/// App icon on phones; the desktop logo on tablets (compact version, without tagline, in bars).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.kind = LogoKind.hero, this.heroSize = 96});
  final LogoKind kind;
  final double heroSize;
  @override
  Widget build(BuildContext context) {
    final large = isLargeScreen(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!large) {
      return Image.asset('assets/brand/app-icon.png', width: kind == LogoKind.hero ? heroSize : 36.0, height: kind == LogoKind.hero ? heroSize : 36.0,
          semanticLabel: 'WAMWins', filterQuality: FilterQuality.medium);
    }
    if (kind == LogoKind.hero) {
      final w = MediaQuery.sizeOf(context).width;
      return Image.asset('assets/brand/logo-desktop.png', width: (w >= 1024 ? w * 0.34 : w * 0.62).clamp(220.0, 440.0), semanticLabel: 'WAMWins');
    }
    final img = Image.asset('assets/brand/logo-desktop-compact.png', height: 46, semanticLabel: 'WAMWins');
    // On dark bars the blue artwork gets a small white plate so it stays legible.
    return dark ? DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: img)) : img;
  }
}

/// "WAMWins™" set in Poppins (WAM blue/white, Wins yellow).
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 20, this.onBrand = false});
  final double size;
  final bool onBrand;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wam = onBrand || dark ? Colors.white : Brand.blue;
    return Semantics(label: 'WAMWins', excludeSemantics: true, child: Text.rich(TextSpan(children: [
      TextSpan(text: 'WAM', style: TextStyle(color: wam)),
      const TextSpan(text: 'Wins', style: TextStyle(color: Brand.yellow)),
      WidgetSpan(alignment: PlaceholderAlignment.top, child: Text('™', style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w500, color: onBrand || dark ? Colors.white : Brand.blue))),
    ]), style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: size, letterSpacing: -0.4, height: 1)));
  }
}

/// "Welcome to WAMWins™" style titles with a raised ™.
Widget tmTitle(BuildContext context, String text, {TextAlign align = TextAlign.start}) {
  final style = Theme.of(context).textTheme.headlineMedium!;
  return Text.rich(TextSpan(children: [
    TextSpan(text: text),
    WidgetSpan(alignment: PlaceholderAlignment.top, child: Text('™', style: style.copyWith(fontSize: (style.fontSize ?? 28) * 0.45))),
  ]), style: style, textAlign: align);
}
