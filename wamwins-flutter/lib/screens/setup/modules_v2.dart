import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../inquiry/catalog.dart';
import '../../inquiry/draft_v2.dart';
import '../../inquiry/entry_ref.dart';
import '../../ui/autocomplete_field.dart';
import '../../ui/info.dart';
import '../../ui/reference_photos.dart';
import '../../ui/tier_locked.dart';
import '../../ui/widgets.dart';

/// Entry Module v2 - the six input modules (the seventh, Review, is in setup_screen.dart). Same questions, codes, draft keys
/// and validation as the website (frontend/www/js/screens/setup/step-*.js).
class Ctx {
  const Ctx({required this.d, required this.ref, required this.catalog, required this.householdId, required this.userId});
  final DraftV2 d;
  final EntryRef ref;
  final Catalog catalog;
  final String? householdId;
  final String userId;
}

const cookingRoles = [Option('ME', 'Mostly me'), Option('SHARED', 'We share it'), Option('OTHER', 'Someone else does')];
const skillsV2 = [Option('BEGINNER', 'Just starting out', 'Simple recipes with clear steps'), Option('COMFORTABLE', 'Comfortable', 'Everyday cooking is fine'),
  Option('CONFIDENT', 'Confident cook', 'Happy to try anything')];
const measuresV2 = [Option('IMPERIAL', 'U.S. customary', 'oz, lb, cups, tbsp, tsp'), Option('METRIC', 'Metric', 'grams, kilograms, milliliters, liters')];
const relationshipsV2 = [Option('PARTNER', 'Spouse / Partner'), Option('CHILD', 'Child'), Option('PARENT', 'Parent'), Option('SIBLING', 'Sibling'),
  Option('GRANDPARENT', 'Grandparent'), Option('RELATIVE', 'Relative'), Option('CAREGIVER', 'Caregiver'), Option('GUEST', 'Frequent guest'), Option('OTHER', 'Other')];
const mealContexts = [Option('BREAKFAST', 'Breakfast'), Option('LUNCH', 'Lunch'), Option('DINNER', 'Dinner'), Option('SNACK', 'Between meals / snacks'), Option('BEVERAGE', 'Drinks / beverages')];
const kitchenwareCategories = [Option('DINNERWARE', 'Dinnerware'), Option('FLATWARE', 'Silverware / Flatware'), Option('COOKWARE', 'Cookware and Cooking Tools'),
  Option('GLASSWARE', 'Glassware'), Option('OTHER', 'Others')];
const conditionsV2 = [Option('NEW', 'New'), Option('GOOD', 'Good'), Option('FAIR', 'Fair'), Option('POOR', 'Poor')];
const applianceConditions = [Option('WORKING', 'Working'), Option('NEEDS_REPAIR', 'Needs repair'), Option('OUT_OF_SERVICE', 'Not working')];
List<Option> opts(List<DbRowAlias> rows) => [for (final r in rows) Option(r['code'] as String, r['name'] as String)];
typedef DbRowAlias = Map<String, Object?>;

Widget _text(BuildContext c, String label, Object? value, ValueChanged<String> onChanged, {String? hint, int max = 80, TextInputType? type, String? key}) =>
    TextFormField(key: key == null ? null : ValueKey(key), initialValue: value?.toString() ?? '', maxLength: max, keyboardType: type, onChanged: onChanged,
        decoration: wamField(c).copyWith(labelText: label, helperText: hint, counterText: ''));
Widget _drop(BuildContext c, String label, String? value, List<Option> options, ValueChanged<String?> onChanged, {String none = 'Not set'}) =>
    DropdownButtonFormField<String?>(value: options.any((o) => o.code == value) ? value : null, isExpanded: true, decoration: wamField(c).copyWith(labelText: label),
        items: [DropdownMenuItem<String?>(value: null, child: Text(none)), for (final o in options) DropdownMenuItem<String?>(value: o.code, child: Text(o.name))], onChanged: onChanged);

// ============================================================================================== Module 1 - About You
String? validateAbout(DraftV2 d) {
  if ((d.about['displayName'] as String? ?? '').trim().isEmpty) return 'Enter your name to continue.';
  if ((d.household['name'] as String? ?? '').trim().isEmpty) return 'Enter a household name to continue.';
  if (((d.household['size'] as num?) ?? 0) < 1) return 'At least one person belongs to the household.';
  if (d.about['cookingRole'] != 'ME') d.about.remove('householdRole');
  return null;
}

class AboutModule extends StatefulWidget {
  const AboutModule({super.key, required this.c});
  final Ctx c;
  @override
  State<AboutModule> createState() => _AboutModuleState();
}

class _AboutModuleState extends State<AboutModule> {
  @override
  void initState() {
    super.initState();
    final d = widget.c.d;
    d.about.putIfAbsent('cookingRole', () => 'ME'); d.about.putIfAbsent('measures', () => 'IMPERIAL');
    d.household.putIfAbsent('size', () => 2); d.household.putIfAbsent('eaters', () => d.household['size']);
    if ((d.household['name'] as String? ?? '').isEmpty) {
      final first = (d.about['displayName'] as String? ?? '').trim().split(RegExp(r'\s+')).first;
      d.household['name'] = first.isEmpty ? 'My household' : '$first’s household';
    }
  }
  @override
  Widget build(BuildContext context) {
    final d = widget.c.d, a = d.about, h = d.household;
    void set(VoidCallback f) => setState(() { f(); d.changed(); });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QBlock(first: true, children: [_text(context, 'What should we call you?', a['displayName'], (v) { a['displayName'] = v; d.changed(); }, hint: 'Your first name or the name you prefer.')]),
      QBlock(title: 'Who does most of the cooking?', hint: 'If you share the cooking, you can name the other cooks later in your family profiles.',
          children: [ChoiceList(options: cookingRoles, value: a['cookingRole'] as String?, onChanged: (v) => set(() => a['cookingRole'] = v))]),
      if (a['cookingRole'] == 'ME') QBlock(title: 'What is your role in the household?', hint: 'Optional. It helps WAMWins understand who plans and cooks.',
          children: [ChoiceList(options: opts(widget.c.ref.roles), value: a['householdRole'] as String?, onChanged: (v) => set(() => a['householdRole'] = v))]),
      QBlock(children: [
        const LabelWithInfo('Which measurements do you use?', title: 'Measurements', body: ['U.S. customary units (ounces, pounds, cups, tablespoons, teaspoons) are the default. Choose metric if you prefer grams and milliliters; you can change this later.']),
        const SizedBox(height: 8),
        ChoiceList(options: measuresV2, value: a['measures'] as String?, onChanged: (v) => set(() => a['measures'] = v)),
      ]),
      QBlock(title: 'Your household', children: [
        _text(context, 'Household name', h['name'], (v) { h['name'] = v; d.changed(); }, hint: 'Shown to people you invite later.'),
        const SizedBox(height: 12),
        _text(context, 'Household nickname (optional)', h['nickname'], (v) { h['nickname'] = v; d.changed(); }, max: 40),
        CounterRow(label: 'How many people belong to the household?', hint: 'Including you', value: (h['size'] as num).toInt(), min: 1, max: 30, onChanged: (v) => set(() => h['size'] = v)),
        CounterRow(label: 'How many people regularly eat from this kitchen?', hint: 'Including guests who eat with you often', value: (h['eaters'] as num).toInt(), max: 30,
            onChanged: (v) => set(() => h['eaters'] = v)),
      ]),
    ]);
  }
}

// ============================================================================================== Module 2 - Health Profiles
bool _hasNeeds(J p) => [for (final k in ['allergies', 'intolerances', 'diets', 'health', 'avoid', 'prioritize']) ((p[k] as List?) ?? const []).length].any((n) => n > 0) ||
    ((p['meals'] as Map?) ?? const {}).values.any((m) => ((m['avoid'] as List?)?.isNotEmpty ?? false) || ((m['prioritize'] as List?)?.isNotEmpty ?? false) || ((m['note'] as String?)?.trim().isNotEmpty ?? false));

String? validateHealth(DraftV2 d) {
  final h = d.health;
  if (h['needed'] == null) return 'Choose Yes or No to continue.';
  if (h['needed'] == 'NO' || h['consent'] != true) return null;              // continue without storing health data
  if (d.people.isEmpty) return 'Add at least one person, or choose No.';
  if (d.people.any((p) => (p['name'] as String? ?? '').trim().isEmpty)) return 'Every person needs a name.';
  if (!d.people.any(_hasNeeds)) return 'Add at least one need (an allergy, diet, intolerance or food to avoid/prioritize).';
  return null;
}

class HealthModule extends StatefulWidget {
  const HealthModule({super.key, required this.c, required this.knownMembers});
  final Ctx c;
  final List<DbRowAlias> knownMembers;
  @override
  State<HealthModule> createState() => _HealthModuleState();
}

class _HealthModuleState extends State<HealthModule> {
  late final List<Suggestion> _foods = [
    for (final i in widget.c.catalog.items) Suggestion(i.name, value: {'label': i.name, 'itemId': i.id, 'categoryCode': null}),
    for (final g in widget.c.catalog.foodGroups) Suggestion(g.name, note: 'food group', value: {'label': g.name, 'itemId': null, 'categoryCode': g.code}),
  ];
  J _person(Map<String, dynamic> o) => {'key': newId(), 'name': '', 'relationship': 'CHILD', 'ageBand': 'CHILD', 'isMe': false, 'allergies': <String>[], 'intolerances': <String>[],
    'diets': <String>[], 'health': <String>[], 'avoid': <J>[], 'prioritize': <J>[], 'meals': <String, dynamic>{}, ...o};

  Widget _tags(String label, List list) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AutocompleteField(label: label, hint: 'Type 3 letters, e.g. sug', search: searchSuggestions(_foods), addLabel: (q) => 'Add “$q”',
          onPick: (s) => setState(() { if (!list.any((t) => t['label'] == s.name)) list.add(Map<String, dynamic>.from(s.value as Map)); widget.c.d.changed(); }),
          onAddNew: (q) => setState(() { list.add({'label': q, 'itemId': null, 'categoryCode': null}); widget.c.d.changed(); })),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final t in List.of(list)) InputChip(label: Text(t['label'] as String), labelStyle: TextStyle(color: p.link),
          onDeleted: () => setState(() { list.remove(t); widget.c.d.changed(); }), deleteButtonTooltipMessage: 'Remove ${t['label']}')]),
    ]);
  }

  Widget _card(J pr) {
    final d = widget.c.d, ref = widget.c.catalog;
    void set(VoidCallback f) => setState(() { f(); d.changed(); });
    List<String> codes(String k) => ((pr[k] as List?) ?? const []).cast<String>();
    Widget sec(String title, List<Widget> body) => ExpansionTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)), tilePadding: EdgeInsets.zero,
        shape: const Border(), collapsedShape: const Border(), childrenPadding: const EdgeInsets.only(bottom: 12), expandedCrossAxisAlignment: CrossAxisAlignment.stretch, children: body);
    final meals = (pr['meals'] as Map<String, dynamic>);
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(color: Palette.of(context).surface, border: Border.all(color: Palette.of(context).line, width: 1.5), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(radius: 20, backgroundColor: Brand.yellow, child: Text(((pr['name'] as String?) ?? '?').trim().isEmpty ? '?' : (pr['name'] as String).trim()[0].toUpperCase(), style: const TextStyle(color: Brand.navy, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(child: Text(pr['isMe'] == true ? '${pr['name']} (you)' : ((pr['name'] as String?)?.isNotEmpty ?? false) ? pr['name'] as String : 'New person', style: const TextStyle(fontWeight: FontWeight.w500))),
          IconButton(tooltip: 'Remove ${pr['name']}', icon: const Icon(Icons.delete_outline), onPressed: () => set(() => d.people.remove(pr))),
        ]),
        if (pr['isMe'] != true) ...[
          const SizedBox(height: 8),
          _text(context, 'Name', pr['name'], (v) => set(() => pr['name'] = v), key: 'hp-name-${pr['key']}'),
          const SizedBox(height: 8), const Text('Relationship', style: TextStyle(fontWeight: FontWeight.w500)), const SizedBox(height: 6),
          ChipSelect(options: relationshipsV2, selected: [pr['relationship'] as String], single: true, onChanged: (v) => set(() => pr['relationship'] = v.first)),
        ],
        const SizedBox(height: 8), const Text('Age group', style: TextStyle(fontWeight: FontWeight.w500)), const SizedBox(height: 6),
        ChipSelect(options: ageBands, selected: [pr['ageBand'] as String], single: true, onChanged: (v) => set(() => pr['ageBand'] = v.first)),
        sec('Allergies', [Text('Recipes with these are never suggested.', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 6),
          ChipSelect(options: ref.allergens, selected: codes('allergies'), warn: true, onChanged: (v) => set(() => pr['allergies'] = v))]),
        sec('Intolerances', [Text('Foods that cause discomfort (for example lactose).', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 6),
          ChipSelect(options: ref.allergens, selected: codes('intolerances'), warn: true, onChanged: (v) => set(() => pr['intolerances'] = v))]),
        sec('Dietary requirements', [ChipSelect(options: ref.diets, selected: codes('diets'), onChanged: (v) => set(() => pr['diets'] = v))]),
        sec('Health-related food requirements', [Text('Used to rank meals, not to give medical advice.', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 6),
          ChipSelect(options: ref.healthGoals, selected: codes('health'), onChanged: (v) => set(() => pr['health'] = v))]),
        sec('Foods to avoid', [_tags('Add a food or food group to avoid', pr['avoid'] as List)]),
        sec('Foods to prioritize', [_tags('Add a food or food group to prioritize', pr['prioritize'] as List)]),
        const LabelWithInfo('By meal', title: 'Meal-specific needs', body: ['Some needs depend on the time of day, like no caffeine at dinner or a protein-rich breakfast. Add them per meal, between-meal snacks and drinks.']),
        for (final mc in mealContexts) Builder(builder: (_) {
          final m = (meals[mc.code] ??= <String, dynamic>{'avoid': <J>[], 'prioritize': <J>[], 'note': ''}) as Map<String, dynamic>;
          return sec(mc.name, [_tags('Avoid at ${mc.name.toLowerCase()}', m['avoid'] as List), const SizedBox(height: 8), _tags('Prioritize at ${mc.name.toLowerCase()}', m['prioritize'] as List),
            const SizedBox(height: 8), _text(context, 'Note (optional)', m['note'], (v) { m['note'] = v; d.changed(); }, max: 200, key: 'hp-note-${pr['key']}-${mc.code}')]);
        }),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.c.d, h = d.health;
    void set(VoidCallback f) => setState(() { f(); d.changed(); });
    final used = {for (final p in d.people) p['key']};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QBlock(first: true, children: [
        const LabelWithInfo('Does anyone in your household require special dietary management?', title: 'Why we ask', body: [
          'Allergies, intolerances and diets decide which meals are safe to suggest. Allergies are always a hard stop.',
          'Health details are optional, stored separately from your kitchen, and only with your permission. WAMWins does not diagnose or give medical advice.']),
        const SizedBox(height: 8),
        ChoiceList(options: const [Option('YES', 'Yes'), Option('NO', 'No')], value: h['needed'] as String?, onChanged: (v) => set(() => h['needed'] = v)),
      ]),
      if (h['needed'] == 'YES') QBlock(children: [
        CheckboxListTile(value: h['consent'] == true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, onChanged: (v) => set(() => h['consent'] = v ?? false),
            title: const Text('Use these health details to keep meal suggestions safe', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Stored only on your household’s records, visible only to members you allow. Turn this off or change the details any time. This is not a medical diagnosis.')),
        if (h['consent'] != true) Text('Without this, WAMWins won’t store health details. You can continue and add them later.', style: Theme.of(context).textTheme.bodySmall),
      ]),
      if (h['needed'] == 'YES' && h['consent'] == true) QBlock(title: 'People who need special dietary management', children: [
        for (final pr in List.of(d.people)) _card(pr),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!d.people.any((p) => p['isMe'] == true)) GhostButton(expand: false, child: Text('Me (${d.about['displayName']})'),
              onPressed: () => set(() => d.people.add(_person({'key': d.selfKey, 'name': d.about['displayName'], 'relationship': 'SELF', 'ageBand': 'ADULT', 'isMe': true})))),
          for (final m in widget.knownMembers.where((m) => !used.contains(m['id']) && m['linked_user_id'] == null))
            GhostButton(expand: false, child: Text(m['display_name'] as String), onPressed: () => set(() => d.people.add(_person({'key': m['id'], 'existingId': m['id'],
                'name': m['display_name'], 'relationship': m['relationship'] ?? 'OTHER', 'ageBand': m['age_band'] ?? 'ADULT'})))),
          PrimaryButton(label: 'New family member', expand: false, onPressed: () => set(() => d.people.add(_person({})))),
        ]),
      ]),
    ]);
  }
}

// ============================================================================================== Module 3 - Kitchens & Storages
String? validateKitchens(DraftV2 d) {
  if (d.kitchens.isEmpty) return 'Add at least one kitchen.';
  if (d.kitchens.any((k) => (k['name'] as String? ?? '').trim().isEmpty)) return 'Every kitchen needs a name.';
  if (allStorage(d).any((s) => (s['name'] as String? ?? '').trim().isEmpty)) return 'Every storage area needs a name.';
  return null;
}

const _nodeKinds = [Option('ZONE', 'Section'), Option('SHELF', 'Shelf'), Option('DRAWER', 'Drawer'), Option('BIN', 'Bin'), Option('COMPARTMENT', 'Division'), Option('CONTAINER', 'Container')];

class KitchensModule extends StatefulWidget {
  const KitchensModule({super.key, required this.c});
  final Ctx c;
  @override
  State<KitchensModule> createState() => _KitchensModuleState();
}

class _KitchensModuleState extends State<KitchensModule> {
  String? _active;
  void _set(VoidCallback f) => setState(() { f(); widget.c.d.changed(); });

  Future<void> _addNode(List nodes) async {
    var kind = 'ZONE';
    final name = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: const Text('Add a section, shelf, bin or container'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: kind, decoration: wamField(ctx).copyWith(labelText: 'Kind'), items: [for (final k in _nodeKinds) DropdownMenuItem(value: k.code, child: Text(k.name))],
            onChanged: (v) => setLocal(() => kind = v ?? kind)),
        const SizedBox(height: 12),
        TextField(controller: name, autofocus: true, maxLength: 60, decoration: wamField(ctx).copyWith(labelText: 'Name', hintText: 'e.g. Upper shelf, Bin A')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add'))],
    )));
    if (ok == true) {
      final label = name.text.trim().isEmpty ? '${_nodeKinds.firstWhere((k) => k.code == kind).name} ${nodes.length + 1}' : name.text.trim();
      _set(() => nodes.add(<String, dynamic>{'key': newId(), 'kind': kind, 'name': label, 'children': <J>[]}));
    }
    name.dispose();
  }

  Widget _tree(List nodes, int depth) => Padding(padding: EdgeInsets.only(left: depth * 16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final n in List.of(nodes).cast<J>()) ...[
          Row(children: [
            Tag(_nodeKinds.firstWhere((k) => k.code == n['kind'], orElse: () => _nodeKinds.first).name),
            const SizedBox(width: 8),
            Expanded(child: _text(context, 'Name', n['name'], (v) { n['name'] = v; widget.c.d.changed(); }, max: 60, key: 'node-${n['key']}')),
            if (n['kind'] != 'CONTAINER') IconButton(tooltip: 'Add inside ${n['name']}', icon: const Icon(Icons.subdirectory_arrow_right), onPressed: () => _addNode((n['children'] ??= <J>[]) as List)),
            IconButton(tooltip: 'Remove ${n['name']}', icon: const Icon(Icons.delete_outline), onPressed: () => _set(() => nodes.remove(n))),
          ]),
          if (((n['children'] as List?) ?? const []).isNotEmpty) _tree(n['children'] as List, depth + 1),
        ],
      ]));

  Widget _storageCard(J k, J s) {
    final c = widget.c, ref = c.ref, p = Palette.of(context);
    final counts = (s['counts'] ??= <String, dynamic>{}) as Map;
    final qs = ref.questionsFor(s['type'] as String);
    final names = sectionNames(ref, s);
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.kitchen_outlined, color: p.link), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ref.nameOf(ref.storageTypes, s['type']), style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(names.isEmpty ? 'No sections yet' : '${names.length} section${names.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodySmall),
          ])),
          IconButton(tooltip: 'Remove ${s['name']}', icon: const Icon(Icons.delete_outline), onPressed: () => _set(() {
            (k['storage'] as List).remove(s); c.d.food.removeWhere((f) => f['storageKey'] == s['key']);
          })),
        ]),
        const SizedBox(height: 8),
        _text(context, 'Name', s['name'], (v) { s['name'] = v; c.d.changed(); }, max: 60, key: 'st-${s['key']}'),
        if (s['legacy'] == true && !counts.values.any((v) => (v as num? ?? 0) > 0)) Text('Sections already set up: ${names.join(', ')}.', style: Theme.of(context).textTheme.bodySmall),
        if (qs.isNotEmpty) const LabelWithInfo('What’s inside?', title: 'Storage sections', body: [
          'Sections are the places inside a storage unit, like shelves, crisper drawers or bins. They help you find food quickly: “Refrigerator → Upper shelf → Bin”.',
          'Only the sections you choose are created. Add your own below, and put sections or containers inside other sections as deep as you need.']),
        for (final q in qs) q['input_kind'] == 'TOGGLE'
            ? CheckboxListTile(value: ((counts[q['code']] as num?) ?? 0) > 0, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                title: Text(q['label'] as String), onChanged: (v) => _set(() => counts[q['code']] = v == true ? 1 : 0))
            : CounterRow(label: q['label'] as String, value: ((counts[q['code']] as num?) ?? 0).toInt(), max: (q['max_value'] as num).toInt(), onChanged: (v) => _set(() => counts[q['code']] = v)),
        _tree((s['custom'] ??= <J>[]) as List, 0),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add a section, shelf, bin or container'), onPressed: () => _addNode(s['custom'] as List))),
        if (c.householdId != null) ReferencePhotos(householdId: c.householdId!, userId: c.userId, locationKey: 'storage:${s['key']}', locationName: s['name'] as String),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, d = c.d, ref = c.ref;
    final k = d.kitchens.where((x) => x['key'] == _active).firstOrNull ?? d.kitchens.firstOrNull;
    _active = k?['key'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QBlock(first: true, children: [
        const LabelWithInfo('Which kitchens do you have?', title: 'Kitchens', body: ['Add each separate cooking area. Rename any kitchen to match what you call it at home.']),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final x in d.kitchens) ChoiceChip(label: Text(x['name'] as String? ?? 'Kitchen'), selected: x['key'] == _active,
            onSelected: (_) => setState(() => _active = x['key'] as String))]),
        const SizedBox(height: 12), const Text('Add a kitchen', style: TextStyle(fontWeight: FontWeight.w500)), const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final kk in ref.kitchenKinds) ActionChip(avatar: const Icon(Icons.add, size: 16), label: Text(kk['name'] as String),
            onPressed: () => _set(() { final nk = newKitchen(ref, kk['code'] as String, d.kitchens); d.kitchens.add(nk); _active = nk['key'] as String; }))]),
      ]),
      if (k != null) QBlock(children: [
        Row(children: [Expanded(child: Text(k['name'] as String? ?? 'Kitchen', style: Theme.of(context).textTheme.titleLarge)),
          if (d.kitchens.length > 1) TextButton(onPressed: () => _set(() {
            final gone = {for (final s in (k['storage'] as List).cast<J>()) s['key']};
            d.kitchens.remove(k); d.food.removeWhere((f) => gone.contains(f['storageKey'])); d.appliances.removeWhere((a) => a['kitchenKey'] == k['key']); d.kitchenware.removeWhere((w) => w['kitchenKey'] == k['key']);
            _active = null;
          }), child: const Text('Remove this kitchen'))]),
        _text(context, 'Kitchen name', k['name'], (v) => _set(() => k['name'] = v), hint: '${ref.nameOf(ref.kitchenKinds, k['kind'])}. Rename it if you like.', max: 60, key: 'k-${k['key']}'),
        const SizedBox(height: 8),
        if (c.householdId != null) ReferencePhotos(householdId: c.householdId!, userId: c.userId, locationKey: 'kitchen:${k['key']}', locationName: k['name'] as String),
      ]),
      if (k != null) QBlock(title: 'What storage areas do you have?', hint: 'Tap to add each one. Add two if you have two.', children: [
        Wrap(spacing: 8, runSpacing: 8, children: [for (final t in ref.storageTypes) ActionChip(avatar: const Icon(Icons.add, size: 16), label: Text(t['name'] as String),
            onPressed: () => _set(() => (k['storage'] as List).add(newStorage(ref, k, t['code'] as String))))]),
        const SizedBox(height: 12),
        for (final s in List.of((k['storage'] as List).cast<J>())) _storageCard(k, s),
      ]),
      TierLockedFeatures(householdId: c.householdId, features: storageLocked),
    ]);
  }
}

// ============================================================================================== Module 4 - Appliances
const _provides = {'REFRIGERATOR': ['REFRIGERATOR', 'REFRIGERATOR_FREEZER'], 'UPRIGHT_FREEZER': ['FREEZER'], 'CHEST_FREEZER': ['CHEST_FREEZER']};
String? validateAppliances(DraftV2 d) => d.appliances.any((a) => (a['name'] as String? ?? '').trim().isEmpty) ? 'Every appliance needs a name.' : null;

class AppliancesModule extends StatefulWidget {
  const AppliancesModule({super.key, required this.c});
  final Ctx c;
  @override
  State<AppliancesModule> createState() => _AppliancesModuleState();
}

class _AppliancesModuleState extends State<AppliancesModule> {
  String? _active;
  final _newName = TextEditingController();
  @override
  void dispose() { _newName.dispose(); super.dispose(); }
  void _set(VoidCallback f) => setState(() { f(); widget.c.d.changed(); });

  Widget _details(J a, List<J> storageHere) {
    final d = widget.c.d;
    final links = storageHere.where((s) => (_provides[a['code']] ?? const []).contains(s['type'])).toList();
    Widget t(String label, String key, {TextInputType? type, String? hint}) => Padding(padding: const EdgeInsets.only(bottom: 10),
        child: _text(context, label, a[key], (v) { a[key] = v; d.changed(); }, type: type, hint: hint, key: 'ap-$key-${a['key']}'));
    return ExpansionTile(title: const Text('Details (optional)'), tilePadding: EdgeInsets.zero, shape: const Border(), collapsedShape: const Border(),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch, childrenPadding: const EdgeInsets.only(bottom: 12), children: [
      t('Name', 'name'),
      if (links.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: _drop(context, 'This is the appliance for storage area', a['storageKey'] as String?,
          [for (final s in links) Option(s['key'] as String, s['name'] as String)], (v) => _set(() => a['storageKey'] = v), none: 'Not linked')),
      t('Brand', 'brand'), t('Model', 'model'), t('Serial number', 'serial'),
      Padding(padding: const EdgeInsets.only(bottom: 10), child: _drop(context, 'Location', a['location'] as String?, [for (final s in storageHere) Option(s['key'] as String, s['name'] as String)],
          (v) => _set(() => a['location'] = v))),
      t('Date purchased', 'purchasedOn', type: TextInputType.datetime, hint: 'YYYY-MM-DD'), t('Warranty end date', 'warrantyEnd', type: TextInputType.datetime, hint: 'YYYY-MM-DD'),
      Padding(padding: const EdgeInsets.only(bottom: 10), child: _drop(context, 'Condition', (a['condition'] as String?) ?? 'WORKING', applianceConditions, (v) => _set(() => a['condition'] = v ?? 'WORKING'))),
      t('Notes', 'notes'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, d = c.d, ref = c.ref;
    _active ??= d.kitchens.firstOrNull?['key'] as String?;
    final storageHere = allStorage(d).where((s) => s['kitchenKey'] == _active).toList();
    Widget row(DbRowAlias t) {
      final a = d.appliances.where((x) => x['kitchenKey'] == _active && x['code'] == t['code']).firstOrNull;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CheckboxListTile(value: a != null, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: Text(t['name'] as String), onChanged: (on) => _set(() {
          if (on == true) {
            final link = storageHere.where((s) => (_provides[t['code']] ?? const []).contains(s['type'])).firstOrNull;
            d.appliances.add({'key': '$_active:${t['code']}', 'kitchenKey': _active, 'code': t['code'], 'name': t['name'], 'storageKey': link?['key'], 'condition': 'WORKING'});
          } else {
            d.appliances.removeWhere((x) => x['kitchenKey'] == _active && x['code'] == t['code']);
          }
        })),
        if (a != null) Padding(padding: const EdgeInsets.only(left: 12), child: _details(a, storageHere)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (d.kitchens.length > 1) Wrap(spacing: 8, children: [for (final k in d.kitchens) ChoiceChip(label: Text(k['name'] as String), selected: k['key'] == _active, onSelected: (_) => setState(() => _active = k['key'] as String))]),
      QBlock(first: true, children: [
        const LabelWithInfo('Electrically operated', title: 'Appliance details', body: ['Only the appliance and its kitchen are needed. Brand, model, serial number and warranty dates are optional and help you later with repairs and warranties.']),
        for (final t in ref.appliances.where((t) => t['power_source'] == 'ELECTRIC')) row(t),
      ]),
      QBlock(title: 'Manual / non-electrical equipment', children: [for (final t in ref.appliances.where((t) => t['power_source'] != 'ELECTRIC')) row(t)]),
      QBlock(title: 'Something else?', children: [
        for (final a in d.appliances.where((x) => x['kitchenKey'] == _active && x['code'] == null).toList()) Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(a['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500))),
            IconButton(tooltip: 'Remove ${a['name']}', icon: const Icon(Icons.delete_outline), onPressed: () => _set(() => d.appliances.remove(a)))]),
          _details(a, storageHere),
        ]),
        TextField(controller: _newName, maxLength: 80, decoration: wamField(context).copyWith(labelText: 'Appliance name', hintText: 'e.g. Waffle maker', counterText: '')),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: GhostButton(expand: false, onPressed: () {
          final n = _newName.text.trim();
          if (n.isEmpty) return;
          _set(() { d.appliances.add({'key': newId(), 'kitchenKey': _active, 'code': null, 'name': n, 'condition': 'WORKING'}); _newName.clear(); });
        }, child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add), SizedBox(width: 6), Text('Add Appliance')]))),
      ]),
    ]);
  }
}

// ============================================================================================== Module 5 - Kitchenware
String? validateKitchenware(DraftV2 d) => d.kitchenware.any((w) => ((w['quantity'] as num?) ?? 0) < 1) ? 'Quantities must be 1 or more.' : null;

class KitchenwareModule extends StatefulWidget {
  const KitchenwareModule({super.key, required this.c});
  final Ctx c;
  @override
  State<KitchenwareModule> createState() => _KitchenwareModuleState();
}

class _KitchenwareModuleState extends State<KitchenwareModule> {
  String? _active;
  String _cat = 'OTHER';
  final _name = TextEditingController();
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  void _set(VoidCallback f) => setState(() { f(); widget.c.d.changed(); });

  @override
  Widget build(BuildContext context) {
    final d = widget.c.d, ref = widget.c.ref;
    _active ??= d.kitchens.firstOrNull?['key'] as String?;
    Widget qtyRow(J w) => CounterRow(label: w['name'] as String, value: (w['quantity'] as num).toInt(), min: 1, max: 99, onChanged: (v) => _set(() => w['quantity'] = v));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (d.kitchens.length > 1) Wrap(spacing: 8, children: [for (final k in d.kitchens) ChoiceChip(label: Text(k['name'] as String), selected: k['key'] == _active, onSelected: (_) => setState(() => _active = k['key'] as String))]),
      for (final (i, cat) in kitchenwareCategories.indexed) QBlock(first: i == 0, title: cat.name, children: [
        for (final t in ref.kitchenware.where((t) => t['category'] == cat.code)) Builder(builder: (_) {
          final w = d.kitchenware.where((x) => x['kitchenKey'] == _active && x['code'] == t['code']).firstOrNull;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CheckboxListTile(value: w != null, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: Text(t['name'] as String), onChanged: (on) => _set(() {
              if (on == true) { d.kitchenware.add({'key': '$_active:${t['code']}', 'kitchenKey': _active, 'code': t['code'], 'category': t['category'], 'name': t['name'], 'quantity': 1}); }
              else { d.kitchenware.removeWhere((x) => x['kitchenKey'] == _active && x['code'] == t['code']); }
            })),
            if (w != null) Padding(padding: const EdgeInsets.only(left: 12), child: qtyRow(w)),
          ]);
        }),
        for (final w in d.kitchenware.where((x) => x['kitchenKey'] == _active && x['code'] == null && x['category'] == cat.code).toList())
          Row(children: [Expanded(child: qtyRow(w)), IconButton(tooltip: 'Remove ${w['name']}', icon: const Icon(Icons.delete_outline), onPressed: () => _set(() => d.kitchenware.remove(w)))]),
      ]),
      QBlock(title: 'Add something else', children: [
        TextField(controller: _name, maxLength: 80, decoration: wamField(context).copyWith(labelText: 'Item', hintText: 'e.g. Pizza stone', counterText: '')),
        const SizedBox(height: 8),
        _drop(context, 'Category', _cat, kitchenwareCategories, (v) => setState(() => _cat = v ?? 'OTHER')),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: GhostButton(expand: false, onPressed: () {
          final n = _name.text.trim();
          if (n.isEmpty) return;
          _set(() { d.kitchenware.add({'key': newId(), 'kitchenKey': _active, 'code': null, 'category': _cat, 'name': n, 'quantity': 1}); _name.clear(); });
        }, child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add), SizedBox(width: 6), Text('Add Item')]))),
      ]),
    ]);
  }
}

// ============================================================================================== Module 6 - Food Inventories
String? validateFood(DraftV2 d) => d.food.any((f) => !(((f['quantity'] as num?) ?? 0) > 0)) ? 'Each food needs a quantity greater than zero.' : null;
const _usMass = ['OZ', 'LB', 'G', 'KG'], _usVolume = ['FL_OZ', 'CUP', 'PINT', 'QUART', 'GALLON', 'TBSP', 'TSP', 'ML', 'L'];

class FoodModule extends StatefulWidget {
  const FoodModule({super.key, required this.c, required this.onNewFood});
  final Ctx c;
  final Future<({String name, String category, String unit, String zone, List<String> allergens})?> Function(String name, String zone) onNewFood;
  @override
  State<FoodModule> createState() => _FoodModuleState();
}

class _FoodModuleState extends State<FoodModule> {
  String? _storage, _section, _container;
  bool get _imperial => widget.c.d.about['measures'] != 'METRIC';
  void _set(VoidCallback f) => setState(() { f(); widget.c.d.changed(); });

  @override
  void initState() {
    super.initState();
    final keys = {for (final s in allStorage(widget.c.d)) s['key']};
    widget.c.d.food.removeWhere((f) => !keys.contains(f['storageKey']));     // storage removed in Module 3
  }

  String _dim(String unit) => widget.c.catalog.units.where((u) => u.code == unit).map((u) => u.dimension).firstOrNull ?? 'COUNT';
  List<UnitInfo> _units(String unit) {
    final dim = _dim(unit), all = widget.c.catalog.units;
    if (dim == 'COUNT') return all.where((u) => u.dimension == 'COUNT' && (u.code == unit || ['PIECE', 'PACK', 'DOZEN'].contains(u.code))).toList();
    final order = dim == 'MASS' ? _usMass : _usVolume;
    return [for (final c in _imperial ? order : order.reversed) ...all.where((u) => u.code == c)];
  }
  String _label(UnitInfo u) => u.code == 'PIECE' ? 'each' : u.symbol;

  void _add(String itemId, String name, String unit, [Map<String, dynamic>? custom]) {
    final dim = _dim(unit);
    final (u, q) = _imperial && dim == 'MASS' ? ('LB', 1) : _imperial && dim == 'VOLUME' ? ('FL_OZ', 16) : (unit, const {'G': 500, 'ML': 500}[unit] ?? 1);
    final mine = custom ?? widget.c.d.food.where((f) => f['itemId'] == itemId && f['custom'] != null).map((f) => f['custom']).firstOrNull;
    _set(() => widget.c.d.food.add({'key': newId(), 'itemId': itemId, 'name': name, 'storageKey': _storage, 'sectionKey': _section, 'containerKey': _container,
      'quantity': q, 'unit': u, 'purchasedOn': todayIso(), if (mine != null) 'custom': mine}));
  }

  Widget _row(J f, List<J> places) {
    final ref = widget.c.ref, p = Palette.of(context), d = widget.c.d;
    final place = places.where((s) => s['key'] == f['storageKey']).firstOrNull;
    final o = place == null ? (sections: <Place>[], containers: <Place>[]) : sectionOptions(ref, place);
    Widget t(String label, String key, {TextInputType? type, String? hint, int max = 60}) => _text(context, label, f[key], (v) {
          f[key] = type == TextInputType.number ? double.tryParse(v.replaceAll(',', '.')) : v; d.changed(); }, type: type, hint: hint, max: max, key: 'fd-$key-${f['key']}');
    final units = _units(f['unit'] as String);
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text([place?['name'], o.sections.where((x) => x.key == f['sectionKey']).map((x) => x.name).firstOrNull].whereType<String>().join(' › '), style: Theme.of(context).textTheme.bodySmall),
          ])),
          IconButton(tooltip: 'Remove ${f['name']}', icon: const Icon(Icons.close), onPressed: () => _set(() => d.food.remove(f))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _text(context, 'Quantity', f['quantity'], (v) { f['quantity'] = double.tryParse(v.replaceAll(',', '.')) ?? 0; d.changed(); },
              type: const TextInputType.numberWithOptions(decimal: true), key: 'fd-qty-${f['key']}')),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<String>(value: units.any((u) => u.code == f['unit']) ? f['unit'] as String : units.first.code, isExpanded: true,
              decoration: wamField(context).copyWith(labelText: 'Unit'), items: [for (final u in units) DropdownMenuItem(value: u.code, child: Text(_label(u)))],
              onChanged: (v) => _set(() => f['unit'] = v ?? f['unit']))),
        ]),
        const SizedBox(height: 8),
        t('Expiration date', 'expiresOn', type: TextInputType.datetime, hint: 'YYYY-MM-DD'),
        ExpansionTile(title: const Text('More details (optional)'), tilePadding: EdgeInsets.zero, shape: const Border(), collapsedShape: const Border(),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch, children: [
          t('Brand', 'brand'), const SizedBox(height: 10),
          _drop(context, 'Packaging', f['packaging'] as String?, opts(ref.packaging), (v) => _set(() => f['packaging'] = v)), const SizedBox(height: 10),
          t('Package size', 'packageSize', type: TextInputType.number), const SizedBox(height: 10),
          _drop(context, 'Package unit', f['packageUnit'] as String?, [for (final u in units) Option(u.code, _label(u))], (v) => _set(() => f['packageUnit'] = v), none: '—'), const SizedBox(height: 10),
          _drop(context, 'Shelf / section', f['sectionKey'] as String?, [for (final x in o.sections) Option(x.key, x.name)], (v) => _set(() => f['sectionKey'] = v), none: 'No specific section'),
          const SizedBox(height: 10),
          _drop(context, 'Container', f['containerKey'] as String?, [for (final x in o.containers) Option(x.key, x.name)], (v) => _set(() => f['containerKey'] = v), none: 'No container'),
          const LabelWithInfo('Dates', title: 'Food dates', body: ['Best-by: quality is best before this date; usually still safe after. Use-by: use it by this date for safety or quality.',
            'Expiration: the last date the maker says to use it. WAMWins reminds you about the earliest of these.']),
          for (final (k, l) in [('purchasedOn', 'Purchase date'), ('openedOn', 'Opened date'), ('bestByOn', 'Best-by date'), ('useByOn', 'Use-by date')])
            Padding(padding: const EdgeInsets.only(bottom: 10), child: t(l, k, type: TextInputType.datetime, hint: 'YYYY-MM-DD')),
          _drop(context, 'Condition', f['condition'] as String?, conditionsV2, (v) => _set(() => f['condition'] = v)), const SizedBox(height: 10),
          t('Notes', 'notes', max: 200), const SizedBox(height: 10),
        ]),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, d = c.d, ref = c.ref;
    final places = allStorage(d);
    if (places.isEmpty) return Text('Add a storage area in Kitchens & Storages first, or skip and add food later.', style: TextStyle(color: Palette.of(context).text2));
    _storage ??= places.first['key'] as String;
    final here = places.firstWhere((s) => s['key'] == _storage);
    final o = sectionOptions(ref, here);
    final mine = {for (final f in d.food.where((f) => f['custom'] != null)) f['itemId']: f};
    final suggestions = [
      for (final f in mine.values) Suggestion(f['name'] as String, note: 'your food', value: (f['itemId'], f['name'], (f['custom'] as Map)['unit'] ?? f['unit'])),
      for (final i in c.catalog.items) Suggestion(i.name, note: i.zone == 'ANY' ? '' : i.zone.toLowerCase(), value: (i.id, i.name, i.unit)),
    ];
    String label(J s) => d.kitchens.length > 1 ? '${s['name']} (${s['kitchenName']})' : s['name'] as String;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QBlock(first: true, title: 'Where is it kept?', children: [
        _drop(context, 'Storage', _storage, [for (final s in places) Option(s['key'] as String, label(s))], (v) => setState(() { _storage = v ?? _storage; _section = null; _container = null; }), none: 'Choose'),
        const SizedBox(height: 10),
        _drop(context, 'Shelf / section', _section, [for (final x in o.sections) Option(x.key, x.name)], (v) => setState(() => _section = v), none: 'No specific section'),
        const SizedBox(height: 10),
        _drop(context, 'Container', _container, [for (final x in o.containers) Option(x.key, x.name)], (v) => setState(() => _container = v), none: 'No container'),
        const SizedBox(height: 14),
        AutocompleteField(label: 'Add food', hint: 'Type 3 letters, e.g. ric, egg, chi', search: searchSuggestions(suggestions), addLabel: (q) => 'Add “$q” as a new food',
            onPick: (s) { final (id, name, unit) = s.value as (String, String, String); _add(id, name, unit); },
            onAddNew: (q) async {
              final z = here['type'] == null ? 'AMBIENT' : ref.zoneOf(here['type'] as String);
              final v = await widget.onNewFood(q, z == 'CHILLED' || z == 'FROZEN' ? z : 'AMBIENT');
              if (v == null) return;
              final known = suggestions.where((s) => s.name.toLowerCase() == v.name.toLowerCase()).firstOrNull;
              if (known != null) { final (id, name, unit) = known.value as (String, String, String); _add(id, name, unit); return; }
              _add(newId(), v.name, v.unit, {'category': v.category, 'unit': v.unit, 'zone': v.zone, 'allergens': v.allergens, 'source': 'USER_DEFINED'});
            }),
      ]),
      QBlock(title: 'Food you’re adding', children: [
        if (d.food.isEmpty) Text('No food added yet. Search above, or skip this module and add food later from your inventory.', style: TextStyle(color: Palette.of(context).text2)),
        for (final f in List.of(d.food)) _row(f, places),
      ]),
      TierLockedFeatures(householdId: c.householdId, features: foodLocked),
    ]);
  }
}
