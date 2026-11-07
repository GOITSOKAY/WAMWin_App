import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../core/db.dart';
import '../core/ids.dart';
import '../inquiry/catalog.dart';
import '../inventory/inventory_service.dart';
import '../ui/widgets.dart';

/// Inventory (manual encoding, WAMWins Basic) - same views and actions as the website:
/// list (needs attention, search, place, status, 50 at a time) / item (use, add, throw away, correct, move, open,
/// expire, return, details, history, remove) / add food / your own foods. Every quantity change is a ledger transaction.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.user});
  final DbRow user;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late InventoryService _inv;
  late Catalog _catalog;
  late String _hh, _userId;
  late bool _history, _soonAlerts, _lowAlerts;
  bool _loaded = false;
  String _view = 'list';
  String? _itemId, _place, _panel;
  String _q = '', _show = 'IN_STOCK';
  int _limit = 50;

  static const _wasteReasons = ['Spoiled', 'Past its date', 'Leftovers thrown out', 'Spilled or damaged', 'Other'];
  static const _units = ['PIECE', 'G', 'KG', 'ML', 'L', 'PACK', 'CAN', 'BOTTLE', 'BUNCH', 'DOZEN', 'SLICE', 'CUP'];
  static const _zones = [Option('AMBIENT', 'Room temperature'), Option('CHILLED', 'Fridge'), Option('FROZEN', 'Freezer')];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = AppScope.of(context);
    _userId = widget.user['id'] as String;
    _hh = s.profile.householdIdFor(_userId)!;
    _inv = InventoryService(s.db);
    _catalog = Catalog.load(s.db, householdId: _hh);
    _history = s.capabilities.canUse(_hh, 'INVENTORY_HISTORY');
    _soonAlerts = s.capabilities.canUse(_hh, 'USE_SOON_ALERTS');
    _lowAlerts = s.capabilities.canUse(_hh, 'LOW_STOCK_ALERTS');
  }

  void _go(String view, [String? itemId]) => setState(() { _view = view; _itemId = itemId; _panel = null; });
  void _toast(String m) => AppScope.of(context).toast(m);
  String _unitName(String code) => _catalog.units.where((u) => u.code == code).map((u) => u.symbol).firstOrNull ?? code.toLowerCase();
  String _date(String? iso) => iso == null ? '' : MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(iso));

  /// Runs a change; shows the friendly message on success, returns the error text on failure.
  String? _do(void Function() change, String ok) {
    try {
      change();
      _catalog = Catalog.load(AppScope.of(context).db, householdId: _hh);
      _toast(ok);
      return null;
    } on InventoryException catch (e) {
      return e.message;
    } catch (e) {
      return 'That couldn’t be saved. Nothing was changed.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final title = const {'list': 'Inventory', 'item': 'Food details', 'add': 'Add food', 'foods': 'Your foods'}[_view]!;
    return Scaffold(
        appBar: wamAppBar(context, title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            leading: IconButton(tooltip: _view == 'list' ? 'Back to home' : 'Back to inventory', icon: const Icon(Icons.arrow_back),
                onPressed: () => _view == 'list' ? s.router.go('home', replace: true) : _go('list'))),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [ContentWidth(max: 820, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (_view) { 'item' => _itemView(), 'add' => [_AddFood(inv: _inv, catalog: _catalog, hh: _hh, userId: _userId, initialPlace: _place,
                onDone: (msg) { _catalog = Catalog.load(s.db, householdId: _hh); _toast(msg); _go('list'); }, foodForm: _foodForm)],
              'foods' => _foodsView(), _ => _listView() }))]),
    );
  }

  // ===================================================================================== list
  List<Widget> _badges(DbRow it) {
    final f = Flags(it, todayIso());
    return [
      if (f.expired) const Tag('Expired', danger: true),
      if (_soonAlerts && f.useSoon) _WarnTag('Use by ${_date(it['use_soon_on'] as String)}'),
      if (_lowAlerts && f.low) const Tag('Running low'),
      if (f.opened) const Tag('Opened'),
      if (f.usedUp) Tag(const {'DISCARDED': 'Thrown away', 'EXPIRED': 'Expired'}[it['lifecycle_status']] ?? 'Used up'),
    ];
  }

  List<Widget> _listView() {
    final p = Palette.of(context);
    final today = todayIso();
    final places = _inv.places(_hh);
    final rows = _inv.items(_hh, storageId: _place, query: _q, show: _show, limit: _limit, today: today);
    final more = rows.length > _limit;
    final shown = rows.take(_limit).toList();
    final a = _inv.attention(_hh, today);
    final chips = <(String, String, bool)>[
      if (_soonAlerts && a.expired > 0) ('EXPIRED', 'Expired (${a.expired})', true),
      if (_soonAlerts && a.soon > 0) ('USE_SOON', 'Use soon (${a.soon})', false),
      if (_lowAlerts && a.low > 0) ('LOW', 'Running low (${a.low})', false),
    ];
    final list = <Widget>[];
    String? group;
    for (final it in shown) {
      if (it['storage_instance_id'] != group) {
        group = it['storage_instance_id'] as String;
        list.add(Padding(padding: const EdgeInsets.only(top: 18, bottom: 4),
            child: Text(places.where((x) => x['id'] == group).map((x) => x['label'] as String).firstOrNull ?? 'Storage', style: TextStyle(color: p.text2, fontWeight: FontWeight.w500))));
      }
      list.add(InkWell(
        onTap: () => _go('item', it['id'] as String),
        child: Semantics(button: true, label: '${it['food_name']}, ${fmtQty(it['quantity'] as num)} ${it['symbol']}', excludeSemantics: true, child: Container(
          constraints: const BoxConstraints(minHeight: 56), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it['food_name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (it['section_name'] != null) Text(it['section_name'] as String, style: Theme.of(context).textTheme.bodySmall), ..._badges(it)]),
            ])),
            Text('${fmtQty(it['quantity'] as num)} ${it['symbol']}', style: TextStyle(color: p.link, fontWeight: FontWeight.w500)),
            Icon(Icons.chevron_right, color: p.text2),
          ]),
        )),
      ));
    }
    return [
      Wrap(spacing: 12, runSpacing: 12, children: [
        PrimaryButton(label: 'Add food', expand: false, onPressed: () => _go('add')),
        GhostButton(expand: false, onPressed: () => _go('foods'), child: const Text('Your foods')),
      ]),
      if (chips.isNotEmpty) Container(margin: const EdgeInsets.only(top: 16), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Brand.yellow50, border: Border.all(color: Brand.yellow, width: 1.5), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Needs attention', style: TextStyle(color: Brand.navy, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final c in chips) ActionChip(label: Text(c.$2, style: TextStyle(color: c.$3 ? p.danger : Brand.navy)),
              backgroundColor: Colors.white, side: BorderSide(color: c.$3 ? p.danger : Brand.yellow600), shape: const StadiumBorder(),
              onPressed: () => setState(() { _show = c.$1; _place = null; _limit = 50; }))]),
        ])),
      const SizedBox(height: 16),
      TextField(decoration: wamField(context).copyWith(labelText: 'Search your food', prefixIcon: const Icon(Icons.search)),
          onChanged: (v) => setState(() { _q = v; _limit = 50; })),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String?>(value: _place, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Place'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('All places')), for (final pl in places) DropdownMenuItem<String?>(value: pl['id'] as String, child: Text(pl['label'] as String))],
            onChanged: (v) => setState(() { _place = v; _limit = 50; }))),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<String>(value: _show, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Show'),
            items: const [DropdownMenuItem(value: 'IN_STOCK', child: Text('In stock')), DropdownMenuItem(value: 'USE_SOON', child: Text('Use soon')),
              DropdownMenuItem(value: 'EXPIRED', child: Text('Expired')), DropdownMenuItem(value: 'LOW', child: Text('Running low')), DropdownMenuItem(value: 'USED_UP', child: Text('Used up'))],
            onChanged: (v) => setState(() { _show = v ?? 'IN_STOCK'; _limit = 50; }))),
      ]),
      if (shown.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(
          _inv.items(_hh, show: 'IN_STOCK', limit: 1, today: today).isEmpty && _show == 'IN_STOCK' && _q.isEmpty && _place == null
              ? 'No food yet. Tap “Add food” to start your inventory.' : 'Nothing matches. Try another place, filter or search.',
          textAlign: TextAlign.center, style: TextStyle(color: p.text2))),
      ...list,
      if (more) Padding(padding: const EdgeInsets.only(top: 12), child: GhostButton(onPressed: () => setState(() => _limit += 50), child: const Text('Show more'))),
    ];
  }

  // ===================================================================================== item
  List<Widget> _itemView() {
    final p = Palette.of(context);
    final it = _inv.item(_hh, _itemId!);
    if (it == null) { WidgetsBinding.instance.addPostFrameCallback((_) => _go('list')); return const []; }
    final u = it['symbol'] as String, qty = (it['quantity'] as num).toDouble(), has = qty > 0;
    final food = it['food_name'] as String;
    Widget act(String label, IconData icon, VoidCallback onTap, {bool primary = false}) => SizedBox(height: 48, child: primary
        ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label),
            style: FilledButton.styleFrom(backgroundColor: Brand.yellow, foregroundColor: Brand.navy, shape: const StadiumBorder()))
        : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label),
            style: OutlinedButton.styleFrom(foregroundColor: p.text, side: BorderSide(color: p.line, width: 2), shape: const StadiumBorder())));
    void open(String panel) => setState(() => _panel = panel);
    final actions = has ? [
      act('Use some', Icons.remove, () => open('use'), primary: true),
      act('Add more', Icons.add, () => open('add')),
      act('Throw away', Icons.delete_outline, () => open('waste')),
      act('Correct amount', Icons.edit_outlined, () => open('correct')),
      act('Move', Icons.move_down, () => open('move')),
      if (it['opened_on'] == null) act('Mark as opened', Icons.check, () { final e = _do(() => _setDetails(it, openedOn: todayIso()), 'Marked as opened.'); setState(() {}); if (e != null) _toast(e); }),
      act('Mark as expired', Icons.schedule, () { final e = _do(() => _inv.post(hh: _hh, itemId: it['id'] as String, type: 'EXPIRED', delta: -qty, userId: _userId), '$food marked as expired.'); setState(() {}); if (e != null) _toast(e); }),
      act('Returned to store', Icons.undo, () => open('return')),
    ] : [
      act('Add more', Icons.add, () => open('add'), primary: true),
      act('Remove from the list', Icons.delete_outline, () { final e = _do(() => _inv.remove(_hh, it['id'] as String), '$food removed from the list.'); if (e != null) { _toast(e); } else { _go('list'); } }),
    ];
    final history = _history ? _inv.history(_hh, it['id'] as String) : const <DbRow>[];
    return [
      Text(food, style: Theme.of(context).textTheme.headlineMedium),
      Text([it['storage_name'], it['section_name']].whereType<String>().join(' · '), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      Text('${fmtQty(qty)} $u', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: p.link, height: 1.1)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: _badges(it)),
      const SizedBox(height: 6),
      Text([if (it['purchased_on'] != null) 'Added ${_date(it['purchased_on'] as String)}', if (it['opened_on'] != null) 'opened ${_date(it['opened_on'] as String)}',
        if (it['expires_on'] != null) 'use by ${_date(it['expires_on'] as String)}', if (it['use_soon_on'] != null) 'best used by ${_date(it['use_soon_on'] as String)}'].join(' · '),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (_, c) {
        final cols = c.maxWidth >= 600 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final a in actions) SizedBox(width: w, child: a)]);
      }),
      if (_panel != null) _ActionPanel(key: ValueKey('$_panel-${it['id']}'), kind: _panel!, item: it, unit: u, inv: _inv, places: _inv.places(_hh),
          wasteReasons: _wasteReasons, onCancel: () => setState(() => _panel = null),
          onSubmit: (kind, amount, reason, toStorage, toSection) {
            final id = it['id'] as String;
            String? movedTo;
            final e = _do(() {
              switch (kind) {
                case 'use': _inv.post(hh: _hh, itemId: id, type: 'OTHER', delta: -amount, reason: reason, userId: _userId, unitLabel: u);
                case 'add': _inv.post(hh: _hh, itemId: id, type: 'PURCHASE', delta: amount, reason: reason, userId: _userId, unitLabel: u);
                case 'waste': _inv.post(hh: _hh, itemId: id, type: 'WASTE', delta: -amount, reason: reason, userId: _userId, unitLabel: u);
                case 'return': _inv.post(hh: _hh, itemId: id, type: 'RETURN', delta: -amount, userId: _userId, unitLabel: u);
                case 'correct':
                  final d = r4(amount - qty);
                  if (d == 0) throw InventoryException('It’s already ${fmtQty(qty)} $u.');
                  _inv.post(hh: _hh, itemId: id, type: 'CORRECTION', delta: d, reason: reason, userId: _userId, unitLabel: u);
                case 'move': movedTo = _inv.transfer(hh: _hh, userId: _userId, itemId: id, toStorageId: toStorage!, toSectionId: toSection, quantity: amount);
              }
            }, const {'use': 'Used.', 'add': 'Added.', 'waste': 'Thrown away.', 'return': 'Returned.', 'correct': 'Amount corrected.', 'move': 'Moved.'}[kind]!);
            if (e == null) setState(() { _panel = null; if (movedTo != null) _itemId = movedTo; });
            return e;
          }),
      const SizedBox(height: 8),
      _Details(key: ValueKey('details-${it['id']}-${it['row_version']}'), item: it, sections: _inv.sections(it['storage_instance_id'] as String), unit: u,
          onSave: (section, useBy, bought, low, notes) {
            final e = _do(() => _setDetails(it, sectionId: section, expiresOn: useBy, purchasedOn: bought, lowStock: low, notes: notes, keepOthers: false), 'Details saved.');
            if (e == null) setState(() {});
            return e;
          }),
      if (_history) ExpansionTile(initiallyExpanded: true, tilePadding: EdgeInsets.zero, shape: const Border(), collapsedShape: const Border(),
        title: const Text('History', style: TextStyle(fontWeight: FontWeight.w500)),
        children: [for (final h in history) Container(
          padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: Text(typeNames[h['transaction_type_code']] ?? h['transaction_type_code'] as String)),
              Text('${(h['quantity_delta'] as num) > 0 ? '+' : ''}${fmtQty(h['quantity_delta'] as num)} ${_unitName(h['unit_code'] as String)}',
                  style: TextStyle(fontWeight: FontWeight.w500, color: (h['quantity_delta'] as num) < 0 ? p.danger : p.ok))]),
            Text('${MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(h['occurred_at'] as String).toLocal())} · '
                '${fmtQty(h['quantity_before'] as num)} → ${fmtQty(h['quantity_after'] as num)}${h['reason'] != null ? ' · ${h['reason']}' : ''}',
                style: Theme.of(context).textTheme.bodySmall),
          ]))]),
    ];
  }

  void _setDetails(DbRow it, {String? sectionId, String? expiresOn, String? purchasedOn, double? lowStock, String? notes, String? openedOn, bool keepOthers = true}) =>
      _inv.setDetails(hh: _hh, itemId: it['id'] as String,
          sectionId: keepOthers ? it['storage_section_id'] as String? : sectionId,
          expiresOn: keepOthers ? it['expires_on'] as String? : expiresOn,
          purchasedOn: keepOthers ? it['purchased_on'] as String? : purchasedOn,
          lowStock: keepOthers ? (it['low_stock_threshold'] as num?)?.toDouble() : lowStock,
          notes: keepOthers ? it['notes'] as String? : notes,
          openedOn: openedOn ?? it['opened_on'] as String?);

  // ===================================================================================== your foods
  Future<({String name, String category, String unit, String zone, List<String> allergens})?> _foodForm({String title = 'Add a new food', String name = '',
      String category = 'OTHER', String unit = 'PIECE', String zone = 'AMBIENT', List<String> allergens = const [], bool lockUnit = false, String saveLabel = 'Add food'}) async {
    final c = _catalog;
    final nameCtl = TextEditingController(text: name);
    var g = category, un = unit, z = zone;
    var al = [...allergens];
    String? err;
    final units = [for (final code in _units) ...c.units.where((x) => x.code == code)];
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: nameCtl, autofocus: true, maxLength: 80, decoration: wamField(context).copyWith(labelText: 'Name', errorText: err)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(value: g, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Food group'),
            items: [for (final x in c.foodGroups) DropdownMenuItem(value: x.code, child: Text(x.name))], onChanged: (v) => setLocal(() => g = v ?? g)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: un, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Measured in',
            helperText: lockUnit ? 'The unit can’t change while this food is stored.' : null),
            items: [for (final x in units) DropdownMenuItem(value: x.code, child: Text(x.symbol))], onChanged: lockUnit ? null : (v) => setLocal(() => un = v ?? un)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: z, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Usually kept'),
            items: [for (final x in _zones) DropdownMenuItem(value: x.code, child: Text(x.name))], onChanged: (v) => setLocal(() => z = v ?? z)),
        const SizedBox(height: 16),
        const Text('Does it contain any of these? (optional)', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        ChipSelect(options: c.allergens, selected: al, warn: true, onChanged: (v) => setLocal(() => al = v)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (nameCtl.text.trim().isEmpty) { setLocal(() => err = 'Enter the food’s name.'); return; } Navigator.pop(ctx, true); }, child: Text(saveLabel)),
      ],
    )));
    final n = nameCtl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    nameCtl.dispose();
    if (ok != true || n.isEmpty) return null;
    return (name: n, category: g, unit: un, zone: z, allergens: al);
  }

  List<Widget> _foodsView() {
    final p = Palette.of(context);
    final foods = _inv.myFoods(_hh);
    Future<void> add() async {
      final v = await _foodForm(saveLabel: 'Save food');
      if (v == null) return;
      final e = _do(() => _inv.createFood(hh: _hh, name: v.name, category: v.category, unit: v.unit, zone: v.zone, allergens: v.allergens), '${v.name} saved as your food.');
      if (e != null) _toast(e);
      setState(() {});
    }
    Future<void> edit(DbRow f) async {
      final v = await _foodForm(title: 'Edit ${f['canonical_name']}', name: f['canonical_name'] as String, category: (f['food_category_code'] as String?) ?? 'OTHER',
          unit: f['default_unit_code'] as String, zone: f['storage_zone'] as String == 'ANY' ? 'AMBIENT' : f['storage_zone'] as String,
          allergens: ((f['allergens'] as String?) ?? '').split(',').where((x) => x.isNotEmpty).toList(), lockUnit: (f['lots'] as int) > 0, saveLabel: 'Save changes');
      if (v == null) return;
      final e = _do(() => _inv.updateFood(hh: _hh, id: f['id'] as String, name: v.name, category: v.category, unit: v.unit, zone: v.zone, allergens: v.allergens), 'Changes saved.');
      if (e != null) _toast(e);
      setState(() {});
    }
    return [
      Text('Foods you added that aren’t in the WAMWins list. Only your household sees them.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      GhostButton(onPressed: add, child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add), SizedBox(width: 6), Text('Add a new food')])),
      const SizedBox(height: 8),
      if (foods.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('You haven’t added any foods of your own yet.', textAlign: TextAlign.center, style: TextStyle(color: p.text2))),
      for (final f in foods) Container(
        padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f['canonical_name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text([_catalog.nameOf(_catalog.foodGroups, (f['food_category_code'] as String?) ?? 'OTHER'), _unitName(f['default_unit_code'] as String),
              const {'AMBIENT': 'room temperature', 'CHILLED': 'fridge', 'FROZEN': 'freezer'}[f['storage_zone']] ?? ''].where((x) => x.isNotEmpty).join(' · '),
                style: Theme.of(context).textTheme.bodySmall),
            if ((f['allergens'] as String?)?.isNotEmpty ?? false) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 4, runSpacing: 4,
                children: [for (final a in (f['allergens'] as String).split(',')) Tag(_catalog.nameOf(_catalog.allergens, a), danger: true)])),
          ])),
          TextButton(onPressed: () => edit(f), child: Text('Edit', semanticsLabel: 'Edit ${f['canonical_name']}')),
          TextButton(onPressed: (f['in_stock'] as int) > 0 ? null : () { final e = _do(() => _inv.removeFood(_hh, f['id'] as String), '${f['canonical_name']} removed from your foods.'); if (e != null) _toast(e); setState(() {}); },
              child: Text('Remove', semanticsLabel: 'Remove ${f['canonical_name']}')),
        ]),
      ),
    ];
  }
}

class _WarnTag extends StatelessWidget {
  const _WarnTag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: dark ? const Color(0xFF3A2E06) : Brand.yellow50, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: dark ? Brand.yellow : const Color(0xFF8A6400))));
  }
}

/// Inline form for one action (amount, reason, or destination).
class _ActionPanel extends StatefulWidget {
  const _ActionPanel({super.key, required this.kind, required this.item, required this.unit, required this.inv, required this.places, required this.wasteReasons,
      required this.onCancel, required this.onSubmit});
  final String kind, unit;
  final DbRow item;
  final InventoryService inv;
  final List<DbRow> places;
  final List<String> wasteReasons;
  final VoidCallback onCancel;
  final String? Function(String kind, double amount, String? reason, String? toStorage, String? toSection) onSubmit;
  @override
  State<_ActionPanel> createState() => _ActionPanelState();
}

class _ActionPanelState extends State<_ActionPanel> {
  late final TextEditingController _amt;
  String? _reason, _err, _to, _toSection;
  @override
  void initState() {
    super.initState();
    final q = fmtQty(widget.item['quantity'] as num);
    _amt = TextEditingController(text: const {'waste', 'correct', 'return', 'move'}.contains(widget.kind) ? q : '');
    _reason = switch (widget.kind) { 'use' => 'Used', 'add' => 'Bought', 'waste' => widget.wasteReasons.first, 'correct' => 'Counted again', _ => null };
    _to = widget.item['storage_instance_id'] as String;
  }
  @override
  void dispose() { _amt.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final k = widget.kind;
    final reasons = switch (k) { 'use' => ['Used', 'Eaten as a snack', 'Given away'], 'add' => ['Bought', 'Received', 'Found more'], 'waste' => widget.wasteReasons,
      'correct' => ['Counted again', 'Entered wrong before', 'Other'], _ => const <String>[] };
    final heading = const {'use': 'Use some', 'add': 'Add more', 'waste': 'Throw away', 'correct': 'Correct the amount', 'return': 'Returned to the store', 'move': 'Move to another place'}[k]!;
    final confirm = const {'use': 'Use', 'add': 'Add', 'waste': 'Throw away', 'correct': 'Save amount', 'return': 'Return', 'move': 'Move'}[k]!;
    return Container(margin: const EdgeInsets.only(top: 16), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: Brand.blue, width: 1.5), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(heading, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (k == 'move') ...[
          DropdownButtonFormField<String>(value: _to, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'To'),
              items: [for (final pl in widget.places) DropdownMenuItem(value: pl['id'] as String, child: Text(pl['label'] as String))],
              onChanged: (v) => setState(() { _to = v; _toSection = null; })),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(value: _toSection, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Shelf'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('No specific shelf')),
                for (final s in widget.inv.sections(_to!)) DropdownMenuItem<String?>(value: s['id'] as String, child: Text(s['name'] as String))],
              onChanged: (v) => setState(() => _toSection = v)),
          const SizedBox(height: 12),
        ],
        TextField(controller: _amt, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: wamField(context).copyWith(labelText: k == 'correct' ? 'Amount now (${widget.unit})' : 'Amount (${widget.unit})')),
        if (reasons.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _reason, isExpanded: true, decoration: wamField(context).copyWith(labelText: k == 'add' ? 'How' : 'Reason'),
              items: [for (final r in reasons) DropdownMenuItem(value: r, child: Text(r))], onChanged: (v) => setState(() => _reason = v)),
        ],
        const SizedBox(height: 8),
        ErrorBanner(_err),
        const SizedBox(height: 8),
        Row(children: [
          PrimaryButton(label: confirm, expand: false, onPressed: () {
            final v = double.tryParse(_amt.text.replaceAll(',', '.'));
            if (v == null || v < 0 || (k != 'correct' && v == 0)) return setState(() => _err = 'Enter an amount.');
            setState(() => _err = widget.onSubmit(k, v, _reason, _to, _toSection));
          }),
          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        ]),
      ]));
  }
}

/// "Edit details": shelf, use-by, added-on, running-low level, note.
class _Details extends StatefulWidget {
  const _Details({super.key, required this.item, required this.sections, required this.unit, required this.onSave});
  final DbRow item;
  final List<DbRow> sections;
  final String unit;
  final String? Function(String? section, String? useBy, String? bought, double? low, String? notes) onSave;
  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  late String? _section = widget.item['storage_section_id'] as String?, _useBy = widget.item['expires_on'] as String?, _bought = widget.item['purchased_on'] as String?;
  late final _low = TextEditingController(text: widget.item['low_stock_threshold'] == null ? '' : fmtQty(widget.item['low_stock_threshold'] as num));
  late final _notes = TextEditingController(text: widget.item['notes'] as String? ?? '');
  String? _err;
  @override
  void dispose() { _low.dispose(); _notes.dispose(); super.dispose(); }

  Future<String?> _pick(String? current) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: current == null ? now : DateTime.parse(current), firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
    return d?.toIso8601String().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero, shape: const Border(), collapsedShape: const Border(), childrenPadding: const EdgeInsets.only(bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: const Text('Edit details', style: TextStyle(fontWeight: FontWeight.w500)),
        children: [
          DropdownButtonFormField<String?>(value: _section, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Shelf'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('No specific shelf')),
                for (final s in widget.sections) DropdownMenuItem<String?>(value: s['id'] as String, child: Text(s['name'] as String))],
              onChanged: (v) => setState(() => _section = v)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(icon: const Icon(Icons.event_outlined, size: 18), label: Text(_useBy == null ? 'Use by: not set' : 'Use by $_useBy'),
                onPressed: () async { final d = await _pick(_useBy); if (d != null) setState(() => _useBy = d); }),
            if (_useBy != null) TextButton(onPressed: () => setState(() => _useBy = null), child: const Text('Clear')),
            OutlinedButton.icon(icon: const Icon(Icons.event_available_outlined, size: 18), label: Text(_bought == null ? 'Added on: not set' : 'Added on $_bought'),
                onPressed: () async { final d = await _pick(_bought); if (d != null) setState(() => _bought = d); }),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _low, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: wamField(context).copyWith(labelText: 'Alert when at or below (${widget.unit})')),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLength: 200, decoration: wamField(context).copyWith(labelText: 'Note (optional)')),
          ErrorBanner(_err),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: PrimaryButton(label: 'Save details', expand: false, onPressed: () {
            final lowText = _low.text.trim().replaceAll(',', '.');
            final low = lowText.isEmpty ? null : double.tryParse(lowText);
            if (lowText.isNotEmpty && (low == null || low < 0)) return setState(() => _err = 'The running-low amount must be zero or more.');
            setState(() => _err = widget.onSave(_section, _useBy, _bought, low, _notes.text.trim().isEmpty ? null : _notes.text.trim()));
          })),
        ],
      );
}

/// "Add food": place + shelf, food (list, your foods, or a new one), amount, unit, how, dates, running-low level.
class _AddFood extends StatefulWidget {
  const _AddFood({required this.inv, required this.catalog, required this.hh, required this.userId, required this.initialPlace, required this.onDone, required this.foodForm});
  final InventoryService inv;
  final Catalog catalog;
  final String hh, userId;
  final String? initialPlace;
  final void Function(String message) onDone;
  final Future<({String name, String category, String unit, String zone, List<String> allergens})?> Function(
      {String title, String name, String category, String unit, String zone, List<String> allergens, bool lockUnit, String saveLabel}) foodForm;
  @override
  State<_AddFood> createState() => _AddFoodState();
}

class _AddFoodState extends State<_AddFood> {
  late List<DbRow> _places;
  late String _place;
  String? _section, _useBy, _err;
  ItemInfo? _food;
  late Catalog _catalog = widget.catalog;
  final _search = TextEditingController(), _amt = TextEditingController(), _low = TextEditingController();
  String _unit = 'PIECE', _how = 'PURCHASE', _bought = todayIso();

  @override
  void initState() {
    super.initState();
    _places = widget.inv.places(widget.hh);
    _place = _places.any((p) => p['id'] == widget.initialPlace) ? widget.initialPlace! : (_places.isEmpty ? '' : _places.first['id'] as String);
  }
  @override
  void dispose() { _search.dispose(); _amt.dispose(); _low.dispose(); super.dispose(); }

  bool _mine(ItemInfo i) => widget.inv.myFoods(widget.hh).any((f) => f['id'] == i.id);

  void _choose(ItemInfo i) => setState(() {
        _food = i;
        _unit = i.unit;
        _amt.text = fmtQty(const {'G': 500, 'ML': 500, 'KG': 1, 'L': 1}[i.unit] ?? 1);
        _search.clear();
      });

  Future<void> _newFood(String name) async {
    final zone = _places.where((p) => p['id'] == _place).map((p) => p['temperature_zone'] as String?).firstOrNull;
    final v = await widget.foodForm(name: name, zone: zone == 'CHILLED' || zone == 'FROZEN' ? zone! : 'AMBIENT');
    if (v == null) return;
    final known = _catalog.items.where((i) => i.name.toLowerCase() == v.name.toLowerCase()).firstOrNull;
    if (known != null) return _choose(known);
    try {
      final id = widget.inv.createFood(hh: widget.hh, name: v.name, category: v.category, unit: v.unit, zone: v.zone, allergens: v.allergens);
      if (!mounted) return;
      _catalog = Catalog.load(AppScope.of(context).db, householdId: widget.hh);
      _choose(_catalog.items.firstWhere((i) => i.id == id));
    } on InventoryException catch (e) {
      setState(() => _err = e.message);
    }
  }

  Future<void> _pickDate(bool useBy) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
    if (d != null) setState(() => useBy ? _useBy = d.toIso8601String().substring(0, 10) : _bought = d.toIso8601String().substring(0, 10));
  }

  void _save() {
    final q = double.tryParse(_amt.text.replaceAll(',', '.'));
    if (q == null || q <= 0) return setState(() => _err = 'Enter an amount greater than zero.');
    final lowText = _low.text.trim().replaceAll(',', '.');
    final low = lowText.isEmpty ? null : double.tryParse(lowText);
    if (lowText.isNotEmpty && (low == null || low < 0)) return setState(() => _err = 'The running-low amount must be zero or more.');
    try {
      widget.inv.createLot(hh: widget.hh, userId: widget.userId, itemMasterId: _food!.id, storageId: _place, sectionId: _section, quantity: q, unit: _unit,
          purchasedOn: _bought, expiresOn: _useBy, lowStock: low, type: _how);
      final label = _places.firstWhere((p) => p['id'] == _place)['label'];
      widget.onDone('Added ${fmtQty(q)} ${widget.catalog.units.where((u) => u.code == _unit).map((u) => u.symbol).firstOrNull ?? ''} of ${_food!.name} to $label.');
    } on InventoryException catch (e) {
      setState(() => _err = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (_places.isEmpty) return Text('Add a storage place first: Home → Update my answers → Kitchens & equipment.', style: TextStyle(color: p.text2));
    final raw = _search.text.trim(), q = raw.toLowerCase();
    final hits = q.isEmpty ? <ItemInfo>[] : _catalog.items.where((i) => i.name.toLowerCase().contains(q)).take(8).toList();
    final exact = hits.any((i) => i.name.toLowerCase() == q);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(value: _place, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Where is it kept?'),
          items: [for (final pl in _places) DropdownMenuItem(value: pl['id'] as String, child: Text(pl['label'] as String))],
          onChanged: (v) => setState(() { _place = v ?? _place; _section = null; })),
      const SizedBox(height: 12),
      DropdownButtonFormField<String?>(value: _section, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Shelf (optional)'),
          items: [const DropdownMenuItem<String?>(value: null, child: Text('No specific shelf')),
            for (final s in widget.inv.sections(_place)) DropdownMenuItem<String?>(value: s['id'] as String, child: Text(s['name'] as String))],
          onChanged: (v) => setState(() => _section = v)),
      const SizedBox(height: 20),
      if (_food == null) ...[
        TextField(controller: _search, autofocus: true, onChanged: (_) => setState(() {}),
            decoration: wamField(context).copyWith(labelText: 'Food', hintText: 'Search foods, e.g. rice, eggs, chicken', prefixIcon: const Icon(Icons.search))),
        if (q.isNotEmpty) Container(margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (hits.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('“$raw” isn’t in the WAMWins list yet.', style: Theme.of(context).textTheme.bodySmall)),
            for (final i in hits) ListTile(title: Text(i.name), onTap: () => _choose(i), trailing: Text(_mine(i) ? 'your food' : (i.zone == 'ANY' ? '' : i.zone.toLowerCase()), style: Theme.of(context).textTheme.bodySmall)),
            if (!exact) ListTile(leading: Icon(Icons.add, color: p.link), title: Text('Add “$raw” as a new food', style: TextStyle(color: p.link, fontWeight: FontWeight.w500)), onTap: () => _newFood(raw)),
          ])),
      ] else ...[
        Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(border: Border.all(color: Brand.blue, width: 1.5), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [Expanded(child: Text(_food!.name, style: const TextStyle(fontWeight: FontWeight.w500))),
            if (_mine(_food!)) const Tag('your food'), TextButton(onPressed: () => setState(() => _food = null), child: const Text('Change'))])),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: TextField(controller: _amt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: wamField(context).copyWith(labelText: 'Amount'))),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<String>(value: _unit, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Unit'),
              items: [for (final u in widget.catalog.unitsLike(_food!.unit)) DropdownMenuItem(value: u.code, child: Text(u.symbol))], onChanged: (v) => setState(() => _unit = v ?? _unit))),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _how, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'How'),
            items: const [DropdownMenuItem(value: 'PURCHASE', child: Text('Bought it')), DropdownMenuItem(value: 'MANUAL_ADD', child: Text('Already had it'))],
            onChanged: (v) => setState(() => _how = v ?? _how)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(icon: const Icon(Icons.event_available_outlined, size: 18), label: Text('Added on $_bought'), onPressed: () => _pickDate(false)),
          OutlinedButton.icon(icon: const Icon(Icons.event_outlined, size: 18), label: Text(_useBy == null ? 'Use by (optional)' : 'Use by $_useBy'), onPressed: () => _pickDate(true)),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _low, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: wamField(context).copyWith(labelText: 'Alert when at or below (optional)')),
        const SizedBox(height: 8),
        ErrorBanner(_err),
        const SizedBox(height: 8),
        PrimaryButton(label: 'Add to inventory', onPressed: _save),
      ],
      if (_food == null && _err != null) ErrorBanner(_err),
    ]);
  }
}
