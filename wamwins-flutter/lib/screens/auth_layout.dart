import 'package:flutter/material.dart';

import '../ui/widgets.dart';

import '../app/theme.dart';
import '../ui/brand.dart';

/// Brand field + content sheet, matching the web layouts:
///   phone           : blue field (app icon, Wordmark™, tagline) above a rounded sheet
///   landscape phone : blue field left, sheet right
///   tablet          : Light Gray field with the desktop logo above the sheet
///   wide (>= 1024)  : Light Gray field left, sheet right
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final large = isLargeScreen(context);
    final wide = large && size.width >= 1024;
    final landscapePhone = !large && size.width >= 600;
    final p = Palette.of(context);
    final fieldColor = large ? Brand.gray : Brand.blue;
    final brand = Container(
      color: fieldColor,
      padding: EdgeInsets.fromLTRB(24, wide ? 48.0 : 28.0, 24, wide ? 48.0 : 36.0),
      child: SafeArea(bottom: false, right: false, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        BrandLogo(heroSize: landscapePhone ? 64.0 : 96.0),
        if (!large) ...[
          const SizedBox(height: 12),
          const Wordmark(size: 36, onBrand: true),
          const SizedBox(height: 8),
          const Text('Smart Solutions. Better Outcomes.', textAlign: TextAlign.center, style: TextStyle(color: Brand.onBrandSoft, fontSize: 13, letterSpacing: 1)),
        ],
      ]))),
    );
    final sheetContent = ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
    const radius = Radius.circular(28);
    if (wide || landscapePhone) {
      return Scaffold(backgroundColor: fieldColor, body: Row(children: [
        Expanded(flex: wide ? 44 : 34, child: brand),
        Expanded(flex: wide ? 56 : 66, child: Container(
          decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.only(topLeft: radius, bottomLeft: radius)),
          child: SafeArea(left: false, child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: sheetContent))),
        )),
      ]));
    }
    return Scaffold(backgroundColor: fieldColor, body: SingleChildScrollView(child: Column(children: [
      brand,
      Container(
        constraints: BoxConstraints(minHeight: size.height * 0.6),
        decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.only(topLeft: radius, topRight: radius)),
        padding: EdgeInsets.fromLTRB(20, 28, 20, 24 + MediaQuery.paddingOf(context).bottom),
        child: Center(child: sheetContent),
      ),
    ])));
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, required this.label, this.error, this.hint, this.newPassword = false, this.onChanged, this.onSubmitted});
  final TextEditingController controller;
  final String label;
  final String? error, hint;
  final bool newPassword;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _show = false;
  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: !_show,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: wamField(context).copyWith(
          labelText: widget.label,
          helperText: widget.hint,
          helperMaxLines: 3,
          errorText: widget.error,
          suffixIcon: TextButton(onPressed: () => setState(() => _show = !_show), child: Text(_show ? 'Hide' : 'Show')),
        ),
      );
}
