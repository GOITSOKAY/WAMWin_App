import 'package:flutter/material.dart';

import '../inquiry/catalog.dart';
import 'widgets.dart';

/// "Add a new food": the few facts WAMWins needs to store, count and keep it safe (shared by onboarding and inventory).
const newFoodUnits = ['PIECE', 'OZ', 'LB', 'FL_OZ', 'CUP', 'G', 'KG', 'ML', 'L', 'PACK', 'CAN', 'BOTTLE', 'BUNCH', 'DOZEN', 'SLICE'];
const newFoodZones = [Option('AMBIENT', 'Room temperature'), Option('CHILLED', 'Fridge'), Option('FROZEN', 'Freezer')];

Future<({String name, String category, String unit, String zone, List<String> allergens})?> showNewFoodDialog(BuildContext context, Catalog c,
    {String name = '', String zone = 'AMBIENT', String unit = 'PIECE'}) async {
  final ctl = TextEditingController(text: name);
  var group = 'OTHER', u = unit, z = zone;
  var allergens = <String>[];
  String? err;
  final units = [for (final code in newFoodUnits) ...c.units.where((x) => x.code == code)];
  if (!units.any((x) => x.code == u)) u = units.first.code;
  final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
    title: const Text('Add a new food'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('It’s saved as your household’s own food, so you can find it again next time.', style: Theme.of(ctx).textTheme.bodySmall),
      const SizedBox(height: 12),
      TextField(controller: ctl, autofocus: true, maxLength: 80, textCapitalization: TextCapitalization.sentences,
          decoration: wamField(ctx).copyWith(labelText: 'Name', errorText: err), onChanged: (_) { if (err != null) setLocal(() => err = null); }),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(value: group, isExpanded: true, decoration: wamField(ctx).copyWith(labelText: 'Food group'),
          items: [for (final g in c.foodGroups) DropdownMenuItem(value: g.code, child: Text(g.name))], onChanged: (v) => setLocal(() => group = v ?? group)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: u, isExpanded: true, decoration: wamField(ctx).copyWith(labelText: 'Measured in'),
          items: [for (final x in units) DropdownMenuItem(value: x.code, child: Text(x.code == 'PIECE' ? 'each' : x.symbol))], onChanged: (v) => setLocal(() => u = v ?? u)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: z, isExpanded: true, decoration: wamField(ctx).copyWith(labelText: 'Usually kept'),
          items: [for (final x in newFoodZones) DropdownMenuItem(value: x.code, child: Text(x.name))], onChanged: (v) => setLocal(() => z = v ?? z)),
      const SizedBox(height: 16),
      const Text('Does it contain any of these? (optional)', style: TextStyle(fontWeight: FontWeight.w500)),
      Text('Helps keep meal suggestions safe for people with allergies.', style: Theme.of(ctx).textTheme.bodySmall),
      const SizedBox(height: 8),
      ChipSelect(options: c.allergens, selected: allergens, warn: true, onChanged: (v) => setLocal(() => allergens = v)),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      FilledButton(onPressed: () { if (ctl.text.trim().isEmpty) { setLocal(() => err = 'Enter the food’s name.'); return; } Navigator.pop(ctx, true); }, child: const Text('Add food')),
    ],
  )));
  final n = ctl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  ctl.dispose();
  if (ok != true || n.isEmpty) return null;
  return (name: n, category: group, unit: u, zone: z, allergens: allergens);
}
