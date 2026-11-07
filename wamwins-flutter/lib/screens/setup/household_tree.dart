import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../inquiry/catalog.dart';
import '../../inquiry/draft.dart';

/// "Your household so far" - grows as answers are given (side panel on tablets, sheet on phones).
class HouseholdTreeView extends StatelessWidget {
  const HouseholdTreeView({super.key, required this.draft, required this.catalog});
  final ProfileDraft draft;
  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final t = deriveTree(draft, catalog);
    const soft = TextStyle(color: Brand.onBrandSoft, fontSize: 13);
    Widget node(int depth, Widget marker, String label, {TextStyle? style}) => Padding(
          padding: EdgeInsets.only(left: depth * 18.0, top: 4, bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 6), child: marker),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: style ?? const TextStyle(color: Colors.white))),
          ]),
        );
    Widget dot(Color c, {bool square = false, bool hollow = false}) => Container(width: 10, height: 10,
        decoration: BoxDecoration(color: hollow ? null : c, border: hollow ? Border.all(color: Colors.white70, width: 2) : null,
            borderRadius: BorderRadius.circular(square ? 3.0 : 5.0)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Built from your answers. Only these parts are set up for your household.', style: soft),
      const SizedBox(height: 12),
      node(0, dot(Colors.white), draft.householdName.isEmpty ? 'Your household' : draft.householdName),
      for (final k in t.kitchens) ...[
        node(1, dot(Colors.white), (t.equipment[k.key] ?? 0) > 0 ? '${k.name} (${t.equipment[k.key]} tool${t.equipment[k.key] == 1 ? '' : 's'})' : k.name),
        for (final s in t.storage[k.key] ?? const <StorageRef>[]) ...[
          node(2, dot(Brand.yellow, square: true), s.name),
          node(3, dot(Colors.white, hollow: true, square: true), s.sections.isEmpty ? 'Main area' : s.sections.join(', '), style: soft),
          if (s.items > 0) node(3, dot(const Color(0xFFFFE38A), square: true), '${s.items} food item${s.items > 1 ? 's' : ''}', style: const TextStyle(color: Color(0xFFFFE38A), fontSize: 13)),
        ],
      ],
      if (t.members > 0) node(1, dot(Colors.white), '${t.members} family member${t.members > 1 ? 's' : ''}'),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Modules you’ll get', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(width: 8),
        Text('${t.moduleCount}', style: const TextStyle(color: Brand.yellow, fontWeight: FontWeight.w500)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final m in t.modules.where((m) => m.on))
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Brand.yellow, borderRadius: BorderRadius.circular(999)),
              child: Text(m.name, style: const TextStyle(color: Brand.navy, fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    ]);
  }
}
