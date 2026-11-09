import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../core/db.dart';
import '../../inquiry/catalog.dart';
import '../../inquiry/draft_v2.dart';
import '../../inquiry/entry_ref.dart';
import '../../inquiry/profile_store.dart';
import '../../inquiry/provisioning_v2.dart';
import '../../ui/brand.dart';
import '../../ui/new_food_dialog.dart';
import '../../ui/widgets.dart';
import 'modules_v2.dart';

/// Entry Module v2 frame: seven modules (About You, Health Profiles, Kitchens & Storages, Kitchen Appliances, Utensils &
/// Kitchenware, Food Inventories, Review My Household Entries). Answers are saved after every module; "Save Entries" turns them
/// into records. The draft and reference lists are scoped to this screen and released when it closes.
const _titles = {
  'about': ('About You', 'A few questions about you and your household, so WAMWins fits the way your home runs.'),
  'health': ('Health Profiles', 'Dietary needs help keep meal suggestions safe for everyone at your table.'),
  'kitchens': ('Kitchens & Storages', 'Add each kitchen and where you keep food. WAMWins sets up only what you choose.'),
  'appliances': ('Kitchen Appliances', 'Tick the appliances you have. Details are optional and can be added any time.'),
  'kitchenware': ('Utensils & Kitchenware', 'Tick what you have and how many. You can skip this and add it later.'),
  'food': ('Food Inventories', 'Add food you have now, or skip and add food later from your inventory.'),
  'review': ('Review My Household Entries', 'Check your entries. WAMWins saves only what you see here.'),
};

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.user, required this.step});
  final DbRow user;
  final String step;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late DraftV2 _d;
  late EntryRef _ref;
  late Catalog _catalog;
  late String _step, _userId;
  String? _hh;
  late bool _consentAtStart;
  List<DbRow> _known = const [];
  bool _busy = false, _loaded = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = AppScope.of(context);
    _userId = widget.user['id'] as String;
    _step = steps.contains(widget.step) ? widget.step : (v1StepMap[widget.step] ?? 'about');
    _hh = s.profile.householdIdFor(_userId);
    if (steps.indexOf(_step) > 0 && _hh == null) _step = 'about';
    _ref = EntryRef.load(s.db);
    _catalog = Catalog.load(s.db, householdId: _hh);
    _d = s.profile.loadDraftV2(widget.user, _ref);
    _consentAtStart = s.profile.healthConsentGranted(_userId);
    _d.health['consent'] ??= _consentAtStart;
    if (_hh != null) _known = s.db.select('SELECT id, display_name, relationship, age_band, linked_user_id FROM family_member WHERE household_id = ? AND deleted_at IS NULL', [_hh]);
    _d.addListener(_onDraft);
  }

  void _onDraft() => setState(() => _error = null);                 // the button label follows the module; stale errors clear

  @override
  void dispose() {
    _d.removeListener(_onDraft);
    _d.dispose();
    super.dispose();
  }

  int get _index => steps.indexOf(_step);

  String? _validate() => switch (_step) {
        'about' => validateAbout(_d), 'health' => validateHealth(_d), 'kitchens' => validateKitchens(_d), 'appliances' => validateAppliances(_d),
        'kitchenware' => validateKitchenware(_d), 'food' => validateFood(_d), _ => null };

  String get _nextLabel => switch (_step) {
        'review' => 'Save Entries',
        'appliances' => _d.appliances.isEmpty ? 'Skip for now' : 'Continue',
        'kitchenware' => _d.kitchenware.isEmpty ? 'Skip for now' : 'Continue',
        'food' => _d.food.isEmpty ? 'Skip for now' : 'Continue',
        _ => 'Continue' };

  Future<void> _next() async {
    final s = AppScope.of(context);
    final err = _validate();
    if (err != null) return setState(() => _error = err);
    setState(() { _busy = true; _error = null; });
    try {
      if (_step == 'review') {
        final hh = s.profile.householdIdFor(_userId)!;
        ProvisionerV2(s.db, _ref, _catalog).save(user: widget.user, householdId: hh, sessionId: s.profile.sessionV2(_userId, hh), d: _d);
        s.profile.saveV2(widget.user, _d, 'review');
        s.toast('Your entries are saved.');
        s.router.reset('home');
        return;
      }
      if (_step == 'about') _hh = s.profile.ensureHouseholdV2(widget.user, _d);
      if (_step == 'health' && (_d.health['consent'] == true) != _consentAtStart) s.profile.recordHealthConsent(_userId, _d.health['consent'] == true);
      final next = steps[_index + 1];
      s.profile.saveV2(widget.user, _d, next);                       // saved after every module (resume, offline)
      s.router.go('setup/$next');
    } catch (e) {
      setState(() { _error = 'Your answers could not be saved: $e'; _busy = false; });
    }
  }

  Widget _module() {
    final c = Ctx(d: _d, ref: _ref, catalog: _catalog, householdId: _hh, userId: _userId);
    return switch (_step) {
      'about' => AboutModule(c: c),
      'health' => HealthModule(c: c, knownMembers: _known),
      'kitchens' => KitchensModule(c: c),
      'appliances' => AppliancesModule(c: c),
      'kitchenware' => KitchenwareModule(c: c),
      'food' => FoodModule(c: c, onNewFood: (name, zone) => showNewFoodDialog(context, _catalog, name: name, zone: zone, unit: _d.about['measures'] == 'METRIC' ? 'G' : 'OZ')),
      _ => _ReviewV2(d: _d, ref: _ref, catalog: _catalog, onChange: (st) => AppScope.of(context).router.go('setup/$st')),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final split = size.width >= 900 || (size.width >= 700 && size.height < 520);
    final t = deriveTreeV2(_d);
    final (title, lead) = _titles[_step]!;
    final content = ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 28), children: [ContentWidth(max: 760, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [for (var i = 0; i < steps.length; i++) Expanded(child: Container(height: 6, margin: EdgeInsets.only(right: i < steps.length - 1 ? 6.0 : 0.0),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: i < _index ? Brand.blue : i == _index ? Brand.yellow : p.surface2)))]),
      const SizedBox(height: 8),
      Semantics(liveRegion: true, child: Text('Step ${_index + 1} of ${steps.length}: $title', style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height: 16),
      Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.headlineMedium)),
      const SizedBox(height: 6),
      Text(lead, style: TextStyle(color: p.text2)),
      const SizedBox(height: 20),
      _module(),
      const SizedBox(height: 8),
      ErrorBanner(_error),
    ]))]);
    final actions = SafeArea(top: false, child: Container(
      decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.line))), padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(children: [
        if (_index > 0) ...[GhostButton(expand: false, onPressed: _busy ? null : () => s.router.go('setup/${steps[_index - 1]}'), child: const Icon(Icons.arrow_back, semanticLabel: 'Back')), const SizedBox(width: 12)],
        Expanded(child: PrimaryButton(label: _nextLabel, busy: _busy, onPressed: _next)),
      ]),
    ));
    final tree = _HouseholdTreeV2(d: _d, ref: _ref, t: t);
    final appBar = wamAppBar(context, titleSpacing: 20,
        title: Row(children: [const BrandLogo(kind: LogoKind.bar), if (!isLargeScreen(context)) ...[const SizedBox(width: 10), const Wordmark(size: 20)]]),
        actions: [TextButton(onPressed: () async { s.profile.saveV2(widget.user, _d, _step); await s.auth.logout(); s.toast('Your answers are saved. Log in to continue.'); s.router.reset('welcome'); },
            child: const Text('Save & sign out'))]);
    if (split) {
      return Scaffold(body: Row(children: [
        Expanded(child: Scaffold(appBar: appBar, body: content, bottomNavigationBar: actions)),
        SizedBox(width: size.width >= 1100 ? 380.0 : 300.0, child: Container(color: Brand.blue, padding: const EdgeInsets.all(20), child: SafeArea(left: false, child: SingleChildScrollView(child: tree)))),
      ]));
    }
    return Scaffold(appBar: appBar, body: content, bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
      Material(color: Brand.blue, child: InkWell(
        onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Brand.blue, showDragHandle: true,
            builder: (_) => DraggableScrollableSheet(expand: false, initialChildSize: 0.6, maxChildSize: 0.9, builder: (_, ctl) => ListView(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [tree]))),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), child: Row(children: [
          const Icon(Icons.keyboard_arrow_up, color: Colors.white70), const SizedBox(width: 8),
          const Expanded(child: Text('Your household so far', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
          Text('${t.moduleCount} modules', style: const TextStyle(color: Brand.yellow, fontWeight: FontWeight.w500)),
        ])),
      )),
      actions,
    ]));
  }
}

/// Live household tree: kitchens, storage (section counts), appliances, kitchenware, food - and health as a COUNT only.
class _HouseholdTreeV2 extends StatelessWidget {
  const _HouseholdTreeV2({required this.d, required this.ref, required this.t});
  final DraftV2 d;
  final EntryRef ref;
  final TreeV2 t;
  @override
  Widget build(BuildContext context) {
    const soft = TextStyle(color: Brand.onBrandSoft, fontSize: 13);
    Widget node(int depth, String label, {TextStyle? style, bool square = false}) => Padding(padding: EdgeInsets.only(left: depth * 18.0, top: 3, bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 6), child: Container(width: 9, height: 9, decoration: BoxDecoration(color: square ? Brand.yellow : Colors.white, borderRadius: BorderRadius.circular(square ? 2 : 5)))),
          const SizedBox(width: 8), Expanded(child: Text(label, style: style ?? const TextStyle(color: Colors.white))),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Expanded(child: Text('Your household so far', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500))),
        Text('${t.moduleCount} modules', style: const TextStyle(color: Brand.yellow, fontWeight: FontWeight.w500))]),
      const SizedBox(height: 8),
      const Text('Built from your answers. Only these parts are set up for your household.', style: soft),
      const SizedBox(height: 10),
      node(0, (d.household['name'] as String?)?.isNotEmpty == true ? d.household['name'] as String : 'Your household'),
      if (t.healthProfiles > 0) node(1, '${t.healthProfiles} health profile${t.healthProfiles > 1 ? 's' : ''} configured', style: soft),
      for (final k in d.kitchens) ...[
        node(1, k['name'] as String? ?? 'Kitchen'),
        for (final s in (k['storage'] as List).cast<J>()) ...[
          node(2, s['name'] as String? ?? '', square: true),
          node(3, () { final n = sectionNames(ref, s).length; return n == 0 ? 'Main area' : '$n section${n > 1 ? 's' : ''}'; }(), style: soft),
          if (d.food.any((f) => f['storageKey'] == s['key'])) node(3, '${d.food.where((f) => f['storageKey'] == s['key']).length} food item(s)', style: const TextStyle(color: Color(0xFFFFE38A), fontSize: 13)),
        ],
        if (d.appliances.any((a) => a['kitchenKey'] == k['key'])) node(2, '${d.appliances.where((a) => a['kitchenKey'] == k['key']).length} appliance(s)', style: soft),
        if (d.kitchenware.any((w) => w['kitchenKey'] == k['key'])) node(2, '${d.kitchenware.where((w) => w['kitchenKey'] == k['key']).length} kitchenware type(s)', style: soft),
      ],
      const SizedBox(height: 14),
      const Text('Modules you’ll get', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final m in t.modules.where((m) => m.$3)) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Brand.yellow, borderRadius: BorderRadius.circular(999)), child: Text(m.$2, style: const TextStyle(color: Brand.navy, fontSize: 13, fontWeight: FontWeight.w500)))]),
    ]);
  }
}

/// Module 7 - Review My Household Entries: six sections, each with Change.
class _ReviewV2 extends StatelessWidget {
  const _ReviewV2({required this.d, required this.ref, required this.catalog, required this.onChange});
  final DraftV2 d;
  final EntryRef ref;
  final Catalog catalog;
  final ValueChanged<String> onChange;
  @override
  Widget build(BuildContext context) {
    final t = deriveTreeV2(d);
    String nameOf(List<Option> l, Object? c) => l.where((o) => o.code == c).map((o) => o.name).firstOrNull ?? '';
    Widget block(int n, String title, String step, List<Widget> body) => QBlock(first: n == 1, children: [
          Row(children: [Expanded(child: Text('$n. $title', style: Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed: () => onChange(step), child: Text('Change', semanticsLabel: 'Change $title'))]),
          ...body,
        ]);
    final a = d.about, h = d.household;
    final people = d.health['needed'] == 'YES' && d.health['consent'] == true ? d.people : const <J>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      block(1, 'About You', 'about', [
        Text('${a['displayName']}. ${nameOf(cookingRoles, a['cookingRole'])}${a['householdRole'] != null ? ' (${ref.nameOf(ref.roles, a['householdRole'])})' : ''}. '
            '${nameOf(skillsV2, a['skill'])}. ${nameOf(measuresV2, a['measures'])} units.'),
        Text('${h['name']}${(h['nickname'] as String?)?.isNotEmpty == true ? ' (“${h['nickname']}”)' : ''}: ${h['size']} people, ${h['eaters']} eating from this kitchen.'),
      ]),
      block(2, 'Health Profiles', 'health', [
        if (d.health['needed'] != 'YES') const Text('No special dietary management.')
        else if (d.health['consent'] != true) const Text('Health details are not stored (permission not given).')
        else for (final p in people) Padding(padding: const EdgeInsets.only(bottom: 6), child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
          for (final c in ((p['allergies'] as List?) ?? const []).cast<String>()) Tag('No ${catalog.nameOf(catalog.allergens, c).toLowerCase()}', danger: true),
          for (final c in ((p['diets'] as List?) ?? const []).cast<String>()) Tag(catalog.nameOf(catalog.diets, c)),
        ])),
      ]),
      block(3, 'Kitchens & Storages', 'kitchens', [for (final k in d.kitchens) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text.rich(TextSpan(children: [
        TextSpan(text: '${k['name']}: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        TextSpan(text: (k['storage'] as List).isEmpty ? 'no storage' : (k['storage'] as List).cast<J>().map((s) { final n = sectionNames(ref, s).length; return n > 0 ? '${s['name']} ($n sections)' : s['name']; }).join(', ')),
      ])))]),
      block(4, 'Kitchen Appliances', 'appliances', [Text(d.appliances.isEmpty ? 'None added. You can add appliances later.' : d.appliances.map((x) => x['name']).join(', '))]),
      block(5, 'Utensils & Kitchenware', 'kitchenware', [Text(d.kitchenware.isEmpty ? 'None added. You can add kitchenware later.' : d.kitchenware.map((w) => '${w['name']} ×${w['quantity']}').join(', '))]),
      block(6, 'Food Inventories', 'food', [Text(d.food.isEmpty ? 'None yet. You can add food later.' : '${d.food.length} food item${d.food.length == 1 ? '' : 's'}: ${d.food.take(6).map((f) => f['name']).join(', ')}${d.food.length > 6 ? '…' : ''}')]),
      QBlock(children: [Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Brand.blue, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WAMWins will set up ${t.moduleCount} parts for your household', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('${d.kitchens.length} kitchen(s), ${t.storageCount} storage area(s), ${t.appliances} appliance(s), ${t.healthProfiles} health profile(s). Nothing you didn’t enter is created.',
              style: const TextStyle(color: Brand.onBrandSoft)),
        ]))]),
    ]);
  }
}
