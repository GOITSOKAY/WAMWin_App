import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../inquiry/catalog.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final bool busy, expand;
  @override
  Widget build(BuildContext context) {
    final b = FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(backgroundColor: Brand.yellow, foregroundColor: Brand.navy, disabledBackgroundColor: Brand.yellow.withAlpha(140),
          disabledForegroundColor: Brand.navy, minimumSize: const Size(140, 52), shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 16)),
      child: busy ? Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.navy)),
        const SizedBox(width: 10), Text(label)]) : Text(label),
    );
    return expand ? SizedBox(width: double.infinity, child: b) : b;
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.child, required this.onPressed, this.expand = true});
  final Widget child;
  final VoidCallback? onPressed;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final b = OutlinedButton(onPressed: onPressed, style: OutlinedButton.styleFrom(foregroundColor: p.text, side: BorderSide(color: p.line, width: 2),
        minimumSize: const Size(52, 52), shape: const StadiumBorder(), textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 16)), child: child);
    return expand ? SizedBox(width: double.infinity, child: b) : b;
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    final p = Palette.of(context);
    return Semantics(liveRegion: true, child: Container(width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.dangerBg, borderRadius: BorderRadius.circular(10)),
        child: Text(message!, style: TextStyle(color: p.danger))));
  }
}

/// "How many?" row with - / + (44 px targets).
class CounterRow extends StatelessWidget {
  const CounterRow({super.key, required this.label, this.hint, required this.value, required this.onChanged, this.min = 0, this.max = 20});
  final String label;
  final String? hint;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget btn(String sym, String semantic, bool enabled, VoidCallback f) => Semantics(button: true, label: semantic, child: SizedBox(width: 44, height: 44,
        child: OutlinedButton(onPressed: enabled ? f : null, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: const CircleBorder(),
            side: BorderSide(color: p.line, width: 1.5), foregroundColor: p.text), child: Text(sym, style: const TextStyle(fontSize: 22)))));
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: value > 0 ? p.link : p.text)),
          if (hint != null) Text(hint!, style: Theme.of(context).textTheme.bodySmall),
        ])),
        btn('−', 'Fewer $label', value > min, () => onChanged(value - 1)),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
        btn('+', 'More $label', value < max, () => onChanged(value + 1)),
      ]),
    );
  }
}

/// Multi-select chips.
class ChipSelect extends StatelessWidget {
  const ChipSelect({super.key, required this.options, required this.selected, required this.onChanged, this.warn = false, this.enabled = true, this.single = false});
  final List<Option> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool warn, enabled, single;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        FilterChip(
          label: Text(o.name),
          selected: selected.contains(o.code),
          showCheckmark: false,
          onSelected: !enabled ? null : (on) {
            if (single) return onChanged([o.code]);
            final s = [...selected];
            on ? s.add(o.code) : s.remove(o.code);
            onChanged(s);
          },
          labelStyle: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, color: selected.contains(o.code) ? Colors.white : p.text),
          selectedColor: warn ? p.danger : Brand.blue,
          backgroundColor: p.surface,
          side: BorderSide(color: selected.contains(o.code) ? (warn ? p.danger : Brand.blue) : p.line, width: 1.5),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
    ]);
  }
}

/// Single choice list (radio semantics).
class ChoiceList extends StatelessWidget {
  const ChoiceList({super.key, required this.options, required this.value, required this.onChanged});
  final List<Option> options;
  final String? value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(children: [
      for (final o in options)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Semantics(inMutuallyExclusiveGroup: true, checked: o.code == value, child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(o.code),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: o.code == value ? p.tagBlueBg : p.surface,
                border: Border.all(color: o.code == value ? Brand.blue : p.line, width: 1.5)),
            child: Row(children: [
              Icon(o.code == value ? Icons.radio_button_checked : Icons.radio_button_off, color: o.code == value ? Brand.blue : p.line),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                if (o.hint != null) Text(o.hint!, style: Theme.of(context).textTheme.bodySmall),
              ])),
            ]),
          ),
        ))),
    ]);
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.danger = false});
  final String text;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: danger ? p.dangerBg : p.tagBlueBg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: danger ? p.danger : p.link)));
  }
}

/// Section with a heading, separated by a rule (matches the web q-block).
class QBlock extends StatelessWidget {
  const QBlock({super.key, this.title, this.hint, required this.children, this.first = false});
  final String? title, hint;
  final List<Widget> children;
  final bool first;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.only(top: first ? 0.0 : 20.0, bottom: 20),
        decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: Palette.of(context).line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) Text(title!, style: Theme.of(context).textTheme.titleMedium),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint!, style: Theme.of(context).textTheme.bodySmall)),
          if (title != null || hint != null) const SizedBox(height: 12),
          ...children,
        ]),
      );
}

/// Centered content column with a readable maximum width.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.max = 680});
  final Widget child;
  final double max;
  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child));
}

/// Brand text-field style. Applied per field (not through ThemeData) so it compiles on every Flutter
/// version - recent releases renamed the theme classes for inputs and app bars.
InputDecoration wamField(BuildContext context) {
  final p = Palette.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line, width: 1.5));
  return InputDecoration(
    filled: true, fillColor: p.surface, border: border, enabledBorder: border,
    focusedBorder: border.copyWith(borderSide: BorderSide(color: dark ? p.link : Brand.blue, width: 2)),
    errorBorder: border.copyWith(borderSide: BorderSide(color: p.danger, width: 1.5)),
    focusedErrorBorder: border.copyWith(borderSide: BorderSide(color: p.danger, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

/// Brand app bar (flat, no tint), same reason as [wamField].
PreferredSizeWidget wamAppBar(BuildContext context, {Widget? leading, Widget? title, List<Widget>? actions, double? titleSpacing}) {
  final p = Palette.of(context);
  return AppBar(leading: leading, title: title, actions: actions, titleSpacing: titleSpacing, backgroundColor: p.bg, foregroundColor: p.text,
      elevation: 0, scrolledUnderElevation: 0.5, surfaceTintColor: Colors.transparent);
}
