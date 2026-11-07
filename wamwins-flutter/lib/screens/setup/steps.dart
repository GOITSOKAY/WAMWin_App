import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../inquiry/catalog.dart';
import '../../inquiry/draft.dart';
import '../../ui/widgets.dart';

/// The five inquiry steps of the entry module (infographic #1) - same questions, codes and rules as the web client.
class StepSpec {
  const StepSpec(this.id, this.title, this.lead);
  final String id, title, lead;
}
const stepSpecs = [
  StepSpec('about', 'About you', 'A few quick questions so WAMWins fits the way you cook.'),
  StepSpec('household', 'Your household', 'Tell us who you’re planning for and which kitchens you have.'),
  StepSpec('kitchens', 'Kitchens & equipment', 'Count what you actually have. WAMWins only sets up what you choose here.'),
  StepSpec('family', 'Family & health', 'Allergies and diets keep meal suggestions safe for everyone at your table.'),
  StepSpec('food', 'Food on hand', 'Add a few things you have now, or skip and add food later.'),
];

String? validateStep(String step, ProfileDraft d) {
  switch (step) {
    case 'about':
      return (d.about['displayName'] ?? '').trim().isEmpty ? 'Enter your name to continue.' : null;
    case 'household':
      if (d.householdName.trim().isEmpty) return 'Enter a household name.';
      if (!d.kitchens.values.any((n) => n > 0)) return 'Add at least one kitchen.';
      if (d.householdSize < 1) return 'At least one person lives in the household.';
      return null;
    case 'kitchens':
      final ks = kitchenList(d);
      return ks.every((k) => !(d.storage[k.key] ?? {}).values.any((n) => n > 0))
          ? 'Add at least one place where you keep food, like a refrigerator or pantry.' : null;
    case 'family':
      if (d.family.isEmpty) return 'Add at least one person.';
      if (d.family.any((m) => m.name.trim().isEmpty)) return 'Every family member needs a name.';
      return null;
    case 'food':
      return d.food.any((f) => !(f.quantity > 0)) ? 'Each food needs an amount greater than zero.' : null;
  }
  return null;
}

// ------------------------------------------------------------------------------------------ About you
class AboutStep extends StatefulWidget {
  const AboutStep({super.key, required this.draft});
  final ProfileDraft draft;
  @override
  State<AboutStep> createState() => _AboutStepState();
}

class _AboutStepState extends State<AboutStep> {
  late final _name = TextEditingController(text: widget.draft.about['displayName']);
  @override
  void initState() {
    super.initState();
    final a = widget.draft.about;
    a.putIfAbsent('cookingRole', () => 'ME');
    a.putIfAbsent('skill', () => 'COMFORTABLE');
    a.putIfAbsent('measures', () => 'METRIC');
  }
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final a = widget.draft.about;
    void choose(String k, String v) => setState(() { a[k] = v; widget.draft.changed(); });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QBlock(first: true, children: [TextField(controller: _name, textCapitalization: TextCapitalization.words,
          decoration: wamField(context).copyWith(labelText: 'What should we call you?'), onChanged: (v) { a['displayName'] = v; widget.draft.changed(); })]),
      QBlock(title: 'Who does most of the cooking?', children: [ChoiceList(options: cookingRoles, value: a['cookingRole'], onChanged: (v) => choose('cookingRole', v))]),
      QBlock(title: 'How confident are you in the kitchen?', children: [ChoiceList(options: skills, value: a['skill'], onChanged: (v) => choose('skill', v))]),
      QBlock(title: 'Which measurements do you use?', children: [ChoiceList(options: measures, value: a['measures'], onChanged: (v) => choose('measures', v))]),
    ]);
  }
}

// ------------------------------------------------------------------------------------------ Household
class HouseholdStep extends StatefulWidget {
  const HouseholdStep({super.key, required this.draft});
  final ProfileDraft draft;
  @override
  State<HouseholdStep> createState() => _HouseholdStepState();
}

class _HouseholdStepState extends State<HouseholdStep> {
  late final TextEditingController _name;
  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d.householdName.isEmpty) {
      final first = (d.about['displayName'] ?? '').trim().split(RegExp(r'\s+')).first;
      d.householdName = first.isEmpty ? 'My household' : '$first’s household';
    }
    _name = TextEditingController(text: d.householdName);
  }
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QBlock(first: true, children: [TextField(controller: _name, decoration: wamField(context).copyWith(labelText: 'Household name', helperText: 'Shown to people you invite later.'),
          onChanged: (v) { d.householdName = v; d.changed(); })]),
      QBlock(title: 'How many people live in your home?', children: [
        CounterRow(label: 'People', hint: 'Including you', value: d.householdSize, min: 1, max: 20, onChanged: (v) => setState(() { d.householdSize = v; d.changed(); })),
      ]),
      QBlock(title: 'Which kitchens do you have?', hint: 'Count each separate cooking area, like an outdoor or dirty kitchen.', children: [
        for (final t in kitchenTypes)
          CounterRow(label: t.name, value: d.kitchens[t.code] ?? 0, max: 5, onChanged: (v) => setState(() { d.kitchens[t.code] = v; d.changed(); })),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------------------------------ Kitchens & equipment
class KitchensStep extends StatefulWidget {
  const KitchensStep({super.key, required this.draft, required this.catalog});
  final ProfileDraft draft;
  final Catalog catalog;
  @override
  State<KitchensStep> createState() => _KitchensStepState();
}

class _KitchensStepState extends State<KitchensStep> {
  late String _active;
  @override
  void initState() {
    super.initState();
    final ks = kitchenList(widget.draft);
    for (final k in ks) {
      widget.draft.storage.putIfAbsent(k.key, () => {});
      widget.draft.appliances.putIfAbsent(k.key, () => []);
      widget.draft.cookware.putIfAbsent(k.key, () => []);
      widget.draft.utensils.putIfAbsent(k.key, () => []);
    }
    _active = ks.first.key;
  }
  @override
  Widget build(BuildContext context) {
    final d = widget.draft, c = widget.catalog;
    final ks = kitchenList(d);
    final k = ks.firstWhere((x) => x.key == _active);
    final counts = d.storage[k.key]!;
    void update(VoidCallback f) => setState(() { f(); d.changed(); });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ks.length > 1) Padding(padding: const EdgeInsets.only(bottom: 12), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final x in ks) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(x.name), selected: x.key == _active,
            onSelected: (_) => setState(() => _active = x.key), selectedColor: Brand.blue,
            labelStyle: TextStyle(color: x.key == _active ? Colors.white : Palette.of(context).text, fontWeight: FontWeight.w500), showCheckmark: false)),
      ]))),
      QBlock(first: true, title: ks.length > 1 ? 'Where do you keep food in the ${k.name.toLowerCase()}?' : 'Where do you keep food?',
          hint: 'Shelves and drawers are added for you for each type. You can rename them later.', children: [
        for (final t in c.storageTypes)
          CounterRow(label: t.name, hint: storageHints[t.code], value: counts[t.code] ?? 0, max: 10, onChanged: (v) => update(() => counts[t.code] = v)),
      ]),
      QBlock(title: 'Which cooking appliances do you have?', children: [ChipSelect(options: c.appliances, selected: d.appliances[k.key]!, onChanged: (v) => update(() => d.appliances[k.key] = v))]),
      QBlock(title: 'Pots and pans', children: [ChipSelect(options: c.cookware, selected: d.cookware[k.key]!, onChanged: (v) => update(() => d.cookware[k.key] = v))]),
      QBlock(title: 'Utensils', children: [ChipSelect(options: c.utensils, selected: d.utensils[k.key]!, onChanged: (v) => update(() => d.utensils[k.key] = v))]),
    ]);
  }
}

// ------------------------------------------------------------------------------------------ Family & health
class FamilyStep extends StatefulWidget {
  const FamilyStep({super.key, required this.draft, required this.catalog, required this.userName, required this.consentAtStart});
  final ProfileDraft draft;
  final Catalog catalog;
  final String userName;
  final bool consentAtStart;
  @override
  State<FamilyStep> createState() => _FamilyStepState();
}

class _FamilyStepState extends State<FamilyStep> {
  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    d.healthConsent ??= widget.consentAtStart;
    if (d.family.isEmpty) {
      d.family.add(Member(key: newId(), name: d.about['displayName'] ?? widget.userName, relationship: 'SELF', ageBand: 'ADULT', isMe: true));
    }
  }

  String _label(List<Option> list, String code) => widget.catalog.nameOf(list, code);
  String _fixed(List<Option> list, String code) => list.firstWhere((o) => o.code == code, orElse: () => Option(code, '')).name;

  Future<void> _addMember() async {
    final d = widget.draft;
    final name = TextEditingController();
    var rel = 'CHILD', age = 'CHILD';
    String? err;
    final added = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: const Text('Add a family member'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: wamField(context).copyWith(labelText: 'Name', errorText: err)),
        const SizedBox(height: 16), const Text('Relationship to you', style: TextStyle(fontWeight: FontWeight.w500)), const SizedBox(height: 8),
        ChipSelect(options: relationships, selected: [rel], single: true, onChanged: (v) => setLocal(() => rel = v.first)),
        const SizedBox(height: 16), const Text('Age group', style: TextStyle(fontWeight: FontWeight.w500)), const SizedBox(height: 8),
        ChipSelect(options: ageBands, selected: [age], single: true, onChanged: (v) => setLocal(() => age = v.first)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (name.text.trim().isEmpty) { setLocal(() => err = 'Enter a name.'); return; } Navigator.pop(ctx, true); }, child: const Text('Add to household')),
      ],
    )));
    if (added == true) setState(() { d.family.add(Member(key: newId(), name: name.text.trim(), relationship: rel, ageBand: age)); d.changed(); });
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft, c = widget.catalog, p = Palette.of(context);
    final consent = d.healthConsent ?? false;
    void update(VoidCallback f) => setState(() { f(); d.changed(); });
    Widget memberCard(Member m) {
      final initials = m.name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).map((x) => x[0]).take(2).join().toUpperCase();
      final sub = {_fixed(relationships, m.relationship), _fixed(ageBands, m.ageBand)}.where((x) => x.isNotEmpty).join(', ');
      final lock = consent ? null : Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Turn on “Use health details” above to add these.', style: Theme.of(context).textTheme.bodySmall));
      Widget section(String title, List<Widget> body, {bool open = false}) => ExpansionTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          initiallyExpanded: open, tilePadding: EdgeInsets.zero, childrenPadding: const EdgeInsets.only(bottom: 12), expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          shape: const Border(), collapsedShape: const Border(), children: body);
      return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 22, backgroundColor: Brand.yellow, child: Text(initials.isEmpty ? '?' : initials, style: const TextStyle(color: Brand.navy, fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.isMe ? '${m.name} (you)' : m.name, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(sub, style: Theme.of(context).textTheme.bodySmall),
            ])),
            if (!m.isMe) IconButton(tooltip: 'Remove ${m.name}', icon: const Icon(Icons.delete_outline), onPressed: () => update(() => d.family.remove(m))),
          ]),
          if (m.allergies.isNotEmpty || m.diets.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in m.allergies) Tag('No ${_label(c.allergens, a).toLowerCase()}', danger: true),
            for (final x in m.diets) Tag(_label(c.diets, x)),
          ])),
          section('Name and age', [
            TextFormField(initialValue: m.name, decoration: wamField(context).copyWith(labelText: 'Name'), onChanged: (v) { m.name = v; d.changed(); }),
            const SizedBox(height: 12), const Text('Age group', style: TextStyle(fontWeight: FontWeight.w500)), const SizedBox(height: 8),
            ChipSelect(options: ageBands, selected: [m.ageBand], single: true, onChanged: (v) => update(() => m.ageBand = v.first)),
            if (!m.isMe) ...[
              const SizedBox(height: 12), const Text('Relationship to you', style: TextStyle(fontWeight: FontWeight.w500)), const SizedBox(height: 8),
              ChipSelect(options: relationships, selected: [m.relationship], single: true, onChanged: (v) => update(() => m.relationship = v.first)),
            ],
          ]),
          section('Food allergies', [if (lock != null) lock, ChipSelect(options: c.allergens, selected: m.allergies, warn: true, enabled: consent, onChanged: (v) => update(() => m.allergies = v))],
              open: consent && m.allergies.isNotEmpty),
          section('Dietary needs', [if (lock != null) lock, ChipSelect(options: c.diets, selected: m.diets, enabled: consent, onChanged: (v) => update(() => m.diets = v))]),
          section('Health goals', [if (lock != null) lock, Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Used to rank meals, not to give medical advice.', style: Theme.of(context).textTheme.bodySmall)),
            ChipSelect(options: c.healthGoals, selected: m.health, enabled: consent, onChanged: (v) => update(() => m.health = v))]),
          section('Favourite cuisines', [ChipSelect(options: c.cuisines, selected: m.cuisines, onChanged: (v) => update(() => m.cuisines = v))]),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QBlock(first: true, children: [CheckboxListTile(value: consent, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => update(() => d.healthConsent = v ?? false),
          title: const Text('Use health details to keep meal suggestions safe', style: TextStyle(fontWeight: FontWeight.w500)),
          subtitle: const Text('Allergies, diets and health goals are only visible to household members you allow. You can turn this off anytime.'))]),
      QBlock(title: 'Who are you planning meals for?',
          hint: 'You said ${d.householdSize} ${d.householdSize == 1 ? 'person lives' : 'people live'} here. ${d.family.length} added so far.',
          children: [
        ...d.family.map(memberCard),
        GhostButton(onPressed: _addMember, child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add), SizedBox(width: 6), Text('Add family member')])),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------------------------------ Food on hand
class FoodStep extends StatefulWidget {
  const FoodStep({super.key, required this.draft, required this.catalog});
  final ProfileDraft draft;
  final Catalog catalog;
  @override
  State<FoodStep> createState() => _FoodStepState();
}

class _FoodStepState extends State<FoodStep> {
  final _search = TextEditingController();
  String? _place;
  @override
  void initState() {
    super.initState();
    final keys = _places().map((p) => p.$1).toSet();
    widget.draft.food.removeWhere((f) => !keys.contains(f.storageKey));   // storage removed in an earlier step
  }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  List<(String key, String label)> _places() {
    final d = widget.draft, ks = kitchenList(d);
    return [for (final k in ks) for (final s in storageList(d, widget.catalog, k.key)) (s.key, ks.length > 1 ? '${s.name} (${k.name})' : s.name)];
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft, c = widget.catalog, p = Palette.of(context);
    final places = _places();
    _place ??= places.isEmpty ? null : places.first.$1;
    final raw = _search.text.trim(), q = raw.toLowerCase();
    final mine = _myFoods();
    final hits = q.isEmpty ? <ItemInfo>[] : [...mine, ...c.items.where((i) => !mine.any((m) => m.id == i.id))].where((i) => i.name.toLowerCase().contains(q)).take(8).toList();
    final exact = hits.any((i) => i.name.toLowerCase() == q);
    void update(VoidCallback f) => setState(() { f(); d.changed(); });
    void add(ItemInfo i, [Map<String, dynamic>? custom]) => update(() {
          final start = const {'G': 500.0, 'ML': 500.0, 'KG': 1.0, 'L': 1.0}[i.unit] ?? 1.0;
          final known = custom ?? d.food.where((f) => f.itemId == i.id && f.custom != null).map((f) => f.custom).firstOrNull;
          d.food.add(FoodEntry(key: newId(), itemId: i.id, name: i.name, storageKey: _place!, quantity: start, unit: i.unit, custom: known));
          _search.clear();
        });
    Future<void> addNew(String name) async {
      final r = await _newFoodDialog(name);
      if (r == null) return;
      final known = [..._myFoods(), ...c.items].where((i) => i.name.toLowerCase() == r.name.toLowerCase()).firstOrNull;
      if (known != null) return add(known);                         // already listed: no duplicate
      add(ItemInfo(newId(), r.name, r.custom['unit'] as String, r.custom['zone'] as String, const {}), r.custom);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QBlock(first: true, children: [
        DropdownButtonFormField<String>(value: _place, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Where is it kept?'),
            items: [for (final pl in places) DropdownMenuItem(value: pl.$1, child: Text(pl.$2))], onChanged: (v) => setState(() => _place = v)),
        const SizedBox(height: 14),
        TextField(controller: _search, textInputAction: TextInputAction.search, onChanged: (_) => setState(() {}),
            decoration: wamField(context).copyWith(labelText: 'Add food', hintText: 'Search foods, e.g. rice, eggs, chicken', prefixIcon: Icon(Icons.search))),
        if (q.isNotEmpty) Container(margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (hits.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('“$raw” isn’t in the WAMWins list yet.', style: Theme.of(context).textTheme.bodySmall)),
            for (final i in hits) ListTile(title: Text(i.name), onTap: () => add(i),
                trailing: Text(mine.any((m) => m.id == i.id) ? 'your food' : (i.zone == 'ANY' ? '' : i.zone.toLowerCase()), style: Theme.of(context).textTheme.bodySmall)),
            if (!exact) ListTile(leading: Icon(Icons.add, color: p.link), title: Text('Add “$raw” as a new food', style: TextStyle(color: p.link, fontWeight: FontWeight.w500)),
                onTap: () => addNew(raw)),
          ])),
      ]),
      QBlock(title: 'Food you’re adding', children: [
        if (d.food.isEmpty)
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(16)),
              child: Text('No food added yet. Search above, or skip this step and add food later.', textAlign: TextAlign.center, style: TextStyle(color: p.text2))),
        for (final f in d.food) Container(
          padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(places.firstWhere((pl) => pl.$1 == f.storageKey).$2, style: Theme.of(context).textTheme.bodySmall),
              ])),
              IconButton(tooltip: 'Remove ${f.name}', icon: const Icon(Icons.close), onPressed: () => update(() => d.food.remove(f))),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
              SizedBox(width: 110, child: TextFormField(initialValue: _fmt(f.quantity), keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: wamField(context).copyWith(labelText: 'Amount'), onChanged: (v) { f.quantity = double.tryParse(v.replaceAll(',', '.')) ?? 0; d.changed(); })),
              SizedBox(width: 120, child: DropdownButtonFormField<String>(value: f.unit, decoration: wamField(context).copyWith(labelText: 'Unit'),
                  items: [for (final u in c.unitsLike(f.unit)) DropdownMenuItem(value: u.code, child: Text(u.symbol))], onChanged: (v) => update(() => f.unit = v ?? f.unit))),
              OutlinedButton.icon(icon: const Icon(Icons.event_outlined, size: 18), label: Text(f.expiresOn == null ? 'Use by (optional)' : 'Use by ${f.expiresOn}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(context: context, initialDate: now, firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 3650)));
                    if (picked != null) update(() => f.expiresOn = picked.toIso8601String().substring(0, 10));
                  }),
            ]),
          ]),
        ),
      ]),
    ]);
  }
  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Foods this household defined itself (from this draft and from earlier setups).
  List<ItemInfo> _myFoods() {
    final m = <String, ItemInfo>{};
    for (final f in widget.draft.food.where((f) => f.custom != null)) {
      m[f.itemId] = ItemInfo(f.itemId, f.name, (f.custom!['unit'] as String?) ?? f.unit, (f.custom!['zone'] as String?) ?? 'ANY', const {});
    }
    return m.values.toList();
  }

  static const _units = ['PIECE', 'G', 'KG', 'ML', 'L', 'PACK', 'CAN', 'BOTTLE', 'BUNCH', 'DOZEN', 'SLICE', 'CUP'];
  static const _zones = [Option('AMBIENT', 'Room temperature'), Option('CHILLED', 'Fridge'), Option('FROZEN', 'Freezer')];

  /// "Add a new food": the few facts WAMWins needs to store, count and keep it safe.
  Future<({String name, Map<String, dynamic> custom})?> _newFoodDialog(String initial) async {
    final c = widget.catalog;
    final name = TextEditingController(text: initial);
    final placeZone = storageZoneOf(_place);
    var group = 'OTHER', unit = 'PIECE', zone = (placeZone == 'CHILLED' || placeZone == 'FROZEN') ? placeZone! : 'AMBIENT';
    var allergens = <String>[];
    String? err;
    final units = [for (final code in _units) ...c.units.where((u) => u.code == code)];
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: const Text('Add a new food'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('It’s saved as your household’s own food, so you can find it again next time.', style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(controller: name, autofocus: true, maxLength: 80, textCapitalization: TextCapitalization.sentences,
            decoration: wamField(context).copyWith(labelText: 'Name', errorText: err), onChanged: (_) { if (err != null) setLocal(() => err = null); }),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(value: group, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Food group'),
            items: [for (final g in c.foodGroups) DropdownMenuItem(value: g.code, child: Text(g.name))], onChanged: (v) => setLocal(() => group = v ?? group)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: unit, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Measured in'),
            items: [for (final u in units) DropdownMenuItem(value: u.code, child: Text(u.symbol))], onChanged: (v) => setLocal(() => unit = v ?? unit)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: zone, isExpanded: true, decoration: wamField(context).copyWith(labelText: 'Usually kept'),
            items: [for (final z in _zones) DropdownMenuItem(value: z.code, child: Text(z.name))], onChanged: (v) => setLocal(() => zone = v ?? zone)),
        const SizedBox(height: 16),
        const Text('Does it contain any of these? (optional)', style: TextStyle(fontWeight: FontWeight.w500)),
        Text('Helps keep meal suggestions safe for people with allergies.', style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 8),
        ChipSelect(options: c.allergens, selected: allergens, warn: true, onChanged: (v) => setLocal(() => allergens = v)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (name.text.trim().isEmpty) { setLocal(() => err = 'Enter the food’s name.'); return; } Navigator.pop(ctx, true); },
            child: const Text('Add food')),
      ],
    )));
    final n = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    name.dispose();
    if (ok != true || n.isEmpty) return null;
    return (name: n, custom: <String, dynamic>{'category': group, 'unit': unit, 'zone': zone, 'allergens': allergens});
  }

  String? storageZoneOf(String? key) {
    if (key == null) return null;
    for (final k in kitchenList(widget.draft)) {
      for (final s in storageList(widget.draft, widget.catalog, k.key)) {
        if (s.key == key) return s.zone;
      }
    }
    return null;
  }
}
