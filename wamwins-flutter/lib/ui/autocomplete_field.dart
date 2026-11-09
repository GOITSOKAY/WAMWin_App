import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'widgets.dart';

/// AutocompleteField / MasterDataSearch: suggestions only from 3 characters, after a 300 ms pause. `search` returns a
/// SCOPED result (a few items) - nothing large is kept in screen state. Works for foods, brands, dietary terms, etc.
class Suggestion {
  const Suggestion(this.name, {this.note = '', this.value});
  final String name, note;
  final Object? value;
}

class AutocompleteField extends StatefulWidget {
  const AutocompleteField({super.key, required this.label, required this.search, required this.onPick, this.onAddNew, this.hint = '',
      this.addLabel, this.minChars = 3, this.debounce = const Duration(milliseconds: 300)});
  final String label, hint;
  final Future<List<Suggestion>> Function(String q) search;
  final void Function(Suggestion s) onPick;
  final void Function(String q)? onAddNew;
  final String Function(String q)? addLabel;
  final int minChars;
  final Duration debounce;
  @override
  State<AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<AutocompleteField> {
  final _ctl = TextEditingController();
  Timer? _timer;
  List<Suggestion> _hits = [];
  String _q = '';
  int _seq = 0;
  @override
  void dispose() { _timer?.cancel(); _ctl.dispose(); super.dispose(); }

  void _changed(String v) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () async {
      final q = v.trim(), mine = ++_seq;
      if (q.length < widget.minChars) { if (mounted) setState(() { _hits = []; _q = q; }); return; }
      final hits = await widget.search(q);
      if (mounted && mine == _seq) setState(() { _hits = hits; _q = q; });
    });
  }

  void _done() { _ctl.clear(); setState(() { _hits = []; _q = ''; }); }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final show = _q.length >= widget.minChars;
    final exact = _hits.any((h) => h.name.toLowerCase() == _q.toLowerCase());
    final remaining = widget.minChars - _q.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _ctl, onChanged: _changed, textInputAction: TextInputAction.search,
          decoration: wamField(context).copyWith(labelText: widget.label, hintText: widget.hint, prefixIcon: const Icon(Icons.search),
              helperText: _q.isNotEmpty && remaining > 0 ? 'Type $remaining more character${remaining == 1 ? '' : 's'} to see suggestions.' : null)),
      if (show) Container(margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(10)),
        child: Semantics(container: true, label: '${widget.label} suggestions', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_hits.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('“$_q” isn’t in the WAMWins list yet.', style: Theme.of(context).textTheme.bodySmall)),
          for (final h in _hits) ListTile(title: Text(h.name), trailing: Text(h.note, style: Theme.of(context).textTheme.bodySmall), onTap: () { widget.onPick(h); _done(); }),
          if (widget.onAddNew != null && !exact) ListTile(leading: Icon(Icons.add, color: p.link), onTap: () { final q = _q; _done(); widget.onAddNew!(q); },
              title: Text(widget.addLabel?.call(_q) ?? 'Add “$_q” as new', style: TextStyle(color: p.link, fontWeight: FontWeight.w500))),
        ]))),
    ]);
  }
}

/// Scoped search over a small in-memory list.
Future<List<Suggestion>> Function(String) searchSuggestions(List<Suggestion> list, {int limit = 8}) => (q) async {
      final s = q.toLowerCase();
      final hits = list.where((x) => x.name.toLowerCase().contains(s)).toList()
        ..sort((a, b) => a.name.toLowerCase().indexOf(s).compareTo(b.name.toLowerCase().indexOf(s)));
      return hits.take(limit).toList();
    };
