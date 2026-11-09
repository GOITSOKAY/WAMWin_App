import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../core/db.dart';
import '../ui/brand.dart';
import '../ui/widgets.dart';

/// Home after profiling: reads ONE household's structure with scoped queries, held only while shown.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});
  final DbRow user;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  _HomeData(AppDb db, String hh)
      : household = db.first('SELECT name FROM household WHERE id = ?', [hh])!,
        kitchens = db.select('SELECT id, name FROM kitchen WHERE household_id = ? AND deleted_at IS NULL ORDER BY sort_order', [hh]),
        storage = db.select('SELECT id, kitchen_id, name FROM storage_instance WHERE household_id = ? AND deleted_at IS NULL ORDER BY sort_order', [hh]),
        sections = db.select('SELECT storage_instance_id, name FROM storage_section WHERE household_id = ? AND deleted_at IS NULL ORDER BY ordinal', [hh]),
        items = db.select('SELECT i.storage_instance_id, i.quantity, m.canonical_name AS name, u.symbol FROM inventory_item i JOIN item_master m ON m.id = i.item_master_id '
            'JOIN unit_of_measure u ON u.code = i.unit_code WHERE i.household_id = ? AND i.deleted_at IS NULL AND i.quantity > 0 ORDER BY m.search_name LIMIT 200', [hh]),
        members = db.select('SELECT id, display_name, linked_user_id FROM family_member WHERE household_id = ? AND deleted_at IS NULL ORDER BY (linked_user_id IS NULL), created_at', [hh]),
        allergies = db.select('SELECT a.member_id, al.name FROM member_allergy a JOIN allergen al ON al.code = a.allergen_code WHERE a.household_id = ? AND a.deleted_at IS NULL', [hh]),
        diets = db.select('SELECT d.member_id, p.name FROM member_dietary_requirement d JOIN dietary_pattern p ON p.code = d.dietary_pattern_code WHERE d.household_id = ? AND d.deleted_at IS NULL', [hh]),
        modules = db.select("SELECT m.module_code, i.display_name FROM household_module_instance i JOIN module_definition m ON m.id = i.module_id "
            "WHERE i.household_id = ? AND i.resource_id IS NULL AND i.deleted_at IS NULL", [hh]),
        equipment = db.count('SELECT (SELECT COUNT(*) FROM household_appliance WHERE household_id = ?1 AND deleted_at IS NULL) + '
            '(SELECT COUNT(*) FROM household_cookware WHERE household_id = ?1 AND deleted_at IS NULL) + (SELECT COUNT(*) FROM household_utensil WHERE household_id = ?1 AND deleted_at IS NULL) AS n', [hh]);
  final DbRow household;
  final List<DbRow> kitchens, storage, sections, items, members, allergies, diets, modules;
  final int equipment;
}

class _HomeScreenState extends State<HomeScreen> {
  _HomeData? _d;
  static const _order = ['HOUSEHOLD', 'KITCHEN', 'EQUIPMENT', 'FAMILY', 'HEALTH', 'INVENTORY', 'SHOPPING', 'MATCHING', 'MEALS'];
  static const _names = {'HOUSEHOLD': 'Household', 'KITCHEN': 'Kitchens', 'EQUIPMENT': 'Appliances & tools', 'FAMILY': 'Family', 'HEALTH': 'Health & diet',
    'INVENTORY': 'Inventory', 'SHOPPING': 'Shopping list', 'MATCHING': 'Meal matching', 'MEALS': 'Meal history'};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_d != null) return;
    final s = AppScope.of(context);
    final hh = s.profile.householdIdFor(widget.user['id'] as String);
    if (hh != null) _d = _HomeData(s.db, hh);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final d = _d;
    if (d == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final first = (widget.user['display_name'] as String).split(RegExp(r'\s+')).first;
    final mods = d.modules.where((m) => _order.contains(m['module_code'])).toList()
      ..sort((a, b) => _order.indexOf(a['module_code'] as String).compareTo(_order.indexOf(b['module_code'] as String)));

    Widget panel({required Widget child, bool brand = false}) => Container(padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: brand ? Brand.blue : p.surface, border: brand ? null : Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(16)),
        child: child);
    Widget stat(int n, String label) => Container(padding: const EdgeInsets.all(14), color: p.surface, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$n', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: p.link, height: 1.1)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]));
    final kitchens = panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Your kitchens', style: Theme.of(context).textTheme.titleLarge),
      for (final (i, k) in d.kitchens.indexed) ExpansionTile(
        initiallyExpanded: i == 0, tilePadding: EdgeInsets.zero, shape: const Border(), collapsedShape: const Border(),
        leading: const Icon(Icons.home_outlined),
        title: Text(k['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text('${d.storage.where((x) => x['kitchen_id'] == k['id']).length} storage'),
        children: [
          for (final st in d.storage.where((x) => x['kitchen_id'] == k['id'])) Padding(padding: const EdgeInsets.only(left: 16), child: ExpansionTile(
            tilePadding: EdgeInsets.zero, shape: const Border(), collapsedShape: const Border(),
            leading: const Icon(Icons.kitchen_outlined, size: 20),
            title: Text(st['name'] as String),
            subtitle: Builder(builder: (_) { final n = d.items.where((it) => it['storage_instance_id'] == st['id']).length; return Text(n == 0 ? 'empty' : '$n item${n == 1 ? '' : 's'}'); }),
            children: [
              for (final sec in d.sections.where((x) => x['storage_instance_id'] == st['id'])) ListTile(dense: true, title: Text(sec['name'] as String, style: TextStyle(color: p.text2))),
              for (final it in d.items.where((x) => x['storage_instance_id'] == st['id'])) ListTile(dense: true, title: Text(it['name'] as String),
                  trailing: Text('${_qty(it['quantity'])} ${it['symbol']}')),
            ],
          )),
        ],
      ),
    ]));
    final family = panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Family', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final m in d.members) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 22, backgroundColor: Brand.yellow, child: Text((m['display_name'] as String).trim().split(RegExp(r'\s+')).map((x) => x[0]).take(2).join().toUpperCase(),
            style: const TextStyle(color: Brand.navy, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m['display_name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final a in d.allergies.where((x) => x['member_id'] == m['id'])) Tag('No ${(a['name'] as String).toLowerCase()}', danger: true),
            for (final x in d.diets.where((x) => x['member_id'] == m['id'])) Tag(x['name'] as String),
          ]),
        ])),
      ])),
    ]));
    final modules = panel(brand: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Set up for your household', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('${d.equipment} ${d.equipment == 1 ? 'appliance or tool' : 'appliances and tools'} recorded. These parts were created from your answers:',
          style: const TextStyle(color: Brand.onBrandSoft, fontSize: 13)),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final m in mods) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Brand.yellow, borderRadius: BorderRadius.circular(999)),
          child: Text(_names[m['module_code']] ?? m['display_name'] as String, style: const TextStyle(color: Brand.navy, fontSize: 13, fontWeight: FontWeight.w500)))]),
    ]));
    final update = GhostButton(onPressed: () => s.router.go('setup/about'), child: const Text('Update my answers'));
    final hh = s.profile.householdIdFor(widget.user['id'] as String)!;
    final canMatch = s.capabilities.canUse(hh, 'MEAL_MATCHING') && d.members.isNotEmpty;
    final inventoryBtn = !s.capabilities.canUse(hh, 'MANUAL_INVENTORY') ? const SizedBox.shrink()
        : Padding(padding: const EdgeInsets.only(bottom: 20), child: GhostButton(onPressed: () => s.router.go('inventory'),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inventory_2_outlined), SizedBox(width: 8), Text('Open inventory')])));
    final matchCta = !canMatch ? const SizedBox.shrink() : Container(
      margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Brand.yellow50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.yellow, width: 1.5)),
      child: Row(children: [
        const Icon(Icons.restaurant_menu, color: Brand.navy),
        const SizedBox(width: 12),
        const Expanded(child: Text('Find meals that are safe for everyone and use what you have.', style: TextStyle(color: Brand.navy, fontWeight: FontWeight.w500))),
        const SizedBox(width: 12),
        PrimaryButton(label: 'What can we cook?', expand: false, onPressed: () => s.router.go('match')),
      ]),
    );
    final stats = MediaQuery.sizeOf(context).width >= 640 ? 4 : 2;

    return Scaffold(
      appBar: wamAppBar(context, titleSpacing: 20,
          title: Row(children: [const BrandLogo(kind: LogoKind.bar), if (!isLargeScreen(context)) ...[const SizedBox(width: 10), const Wordmark(size: 20)]]),
          actions: [IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () => s.router.go('settings'))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [ContentWidth(max: 1120, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$_greeting, $first', style: TextStyle(color: p.text2, fontWeight: FontWeight.w500)),
        Semantics(header: true, child: Text('Here is what WAMWins knows about your kitchen stuff!', style: Theme.of(context).textTheme.headlineMedium)),
        const SizedBox(height: 4),
        Text('${d.household['name']} is set up. Here’s what WAMWins knows about your home.', style: TextStyle(color: p.text2)),
        const SizedBox(height: 20),
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(color: p.line, padding: const EdgeInsets.all(1.5), child: GridView.count(
          crossAxisCount: stats, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 1.5, crossAxisSpacing: 1.5, childAspectRatio: stats == 4 ? 2.6 : 2.2,
          children: [stat(d.kitchens.length, d.kitchens.length == 1 ? 'Kitchen' : 'Kitchens'), stat(d.storage.length, 'Storage units'),
            stat(d.members.length, 'Family members'), stat(d.items.length, 'Foods on hand')]))),
        const SizedBox(height: 16),
        inventoryBtn,
        matchCta,
        if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 13, child: kitchens), const SizedBox(width: 24),
          Expanded(flex: 10, child: Column(children: [family, const SizedBox(height: 16), modules, const SizedBox(height: 16), update])),
        ]) else ...[kitchens, const SizedBox(height: 16), family, const SizedBox(height: 16), modules, const SizedBox(height: 16), update],
      ]))]),
    );
  }

  static String _qty(Object? v) { final d = (v as num).toDouble(); return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString(); }
}
