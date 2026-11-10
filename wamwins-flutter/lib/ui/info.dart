import 'package:flutter/material.dart';

import '../app/theme.dart';

/// (i) control that explains a question or process. Accessible label; the dialog is modal (focus stays inside),
/// closes with "Got it", ESC (keyboard) or Back (Android), and focus returns to the button.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.label, required this.title, required this.body});
  final String label, title;
  final List<String> body;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'More information: $label',
        icon: Icon(Icons.info_outline, color: Brand.redFor(context)),
        onPressed: () => showInfo(context, title: title, body: body),
      );
}

Future<void> showInfo(BuildContext context, {required String title, required List<String> body, List<Widget> extra = const []}) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final p in body) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(p)),
          ...extra,
        ])),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
      ),
    );

/// Question heading with an (i) next to it.
class LabelWithInfo extends StatelessWidget {
  const LabelWithInfo(this.text, {super.key, required this.title, required this.body});
  final String text, title;
  final List<String> body;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        InfoButton(label: text, title: title, body: body),
      ]);
}
