import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../core/db.dart';
import '../../inquiry/catalog.dart';
import '../../inquiry/draft.dart';
import '../../inquiry/profile_store.dart';
import '../../inquiry/provisioning.dart';
import '../../ui/brand.dart';
import '../../ui/widgets.dart';
import 'household_tree.dart';
import 'steps.dart';

/// Inquiry & Profiling Engine screen: progress, one step at a time, Back/Continue in thumb reach, and the
/// household tree (side panel on tablets, pull-up sheet on phones). Draft + catalogue are scoped to this
/// screen and released when it closes.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.user, required this.step});
  final DbRow user;
  final String step;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late ProfileDraft _draft;
  late Catalog _catalog;
  late String _step;
  late bool _consentAtStart;
  bool _busy = false, _loaded = false;
  String? _error;
  final _scroll = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = AppScope.of(context);
    _step = profileSteps.contains(widget.step) ? widget.step : 'about';
    final userId = widget.user['id'] as String;
    if (profileSteps.indexOf(_step) > 1 && s.profile.householdIdFor(userId) == null) _step = 'household';
    _draft = s.profile.loadDraft(widget.user);
    _catalog = Catalog.load(s.db, householdId: s.profile.householdIdFor(userId));
    _consentAtStart = s.profile.healthConsentGranted(userId);
    _draft.addListener(_onDraft);
  }

  void _onDraft() => setState(() {});

  @override
  void dispose() {
    _draft.removeListener(_onDraft);
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int get _index => profileSteps.indexOf(_step);

  Future<void> _next() async {
    final s = AppScope.of(context);
    final err = validateStep(_step, _draft);
    if (err != null) return setState(() => _error = err);
    setState(() { _busy = true; _error = null; });
    final userId = widget.user['id'] as String;
    try {
      if (_step == 'review') {
        final hh = s.profile.householdIdFor(userId)!;
        final r = Provisioner(s.db, _catalog).provision(user: widget.user, householdId: hh, sessionId: s.profile.sessionFor(userId, hh), d: _draft);
        s.profile.save(widget.user, _draft, 'review');
        s.toast(r.createdStructure ? 'Your household is ready.' : 'Your answers are updated.');
        s.router.reset('home');
        return;
      }
      if (_step == 'household') s.profile.ensureHousehold(widget.user, _draft);
      if (_step == 'family' && (_draft.healthConsent ?? false) != _consentAtStart) s.profile.recordHealthConsent(userId, _draft.healthConsent ?? false);
      final next = profileSteps[_index + 1];
      s.profile.save(widget.user, _draft, next);
      s.router.go('setup/$next');
    } catch (e) {
      setState(() { _error = 'Your answers could not be saved: $e'; _busy = false; });
    }
  }

  Widget _stepBody() => switch (_step) {
        'about' => AboutStep(draft: _draft),
        'household' => HouseholdStep(draft: _draft),
        'kitchens' => KitchensStep(draft: _draft, catalog: _catalog),
        'family' => FamilyStep(draft: _draft, catalog: _catalog, userName: widget.user['display_name'] as String, consentAtStart: _consentAtStart),
        'food' => FoodStep(draft: _draft, catalog: _catalog),
        _ => _Review(draft: _draft, catalog: _catalog, onChange: (step) => AppScope.of(context).router.go('setup/$step')),
      };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final split = size.width >= 900 || (size.width >= 700 && size.height < 520);
    final tree = deriveTree(_draft, _catalog);
    final spec = _index < 5 ? stepSpecs[_index] : const StepSpec('review', 'Review your household', 'Check your answers. WAMWins will create only what you see here.');
    final nextLabel = _step == 'review' ? 'Create my household' : (_step == 'food' && _draft.food.isEmpty ? 'Skip for now' : 'Continue');

    final content = ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(20, 20, 20, 28), children: [ContentWidth(max: 720, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_index < 5) ...[
        Row(children: [for (var i = 0; i < 5; i++) Expanded(child: Container(height: 6, margin: EdgeInsets.only(right: i < 4 ? 6.0 : 0.0),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: i < _index ? Brand.blue : i == _index ? Brand.yellow : p.surface2)))]),
        const SizedBox(height: 8),
        Text('Step ${_index + 1} of 5', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
      ],
      Semantics(header: true, child: Text(spec.title, style: Theme.of(context).textTheme.headlineMedium)),
      const SizedBox(height: 6),
      Text(spec.lead, style: TextStyle(color: p.text2)),
      const SizedBox(height: 20),
      _stepBody(),
      ErrorBanner(_error),
    ]))]);

    final actions = SafeArea(top: false, child: Container(
      decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(children: [
        if (_index > 0) ...[GhostButton(expand: false, onPressed: _busy ? null : () => s.router.go('setup/${profileSteps[_index - 1]}'), child: const Icon(Icons.arrow_back, semanticLabel: 'Back')), const SizedBox(width: 12)],
        Expanded(child: PrimaryButton(label: nextLabel, busy: _busy, onPressed: _next)),
      ]),
    ));

    final treePanel = Container(color: Brand.blue, padding: const EdgeInsets.all(20), child: SafeArea(left: false, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Expanded(child: Text('Your household so far', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500))),
        Text('${tree.moduleCount} modules', style: const TextStyle(color: Brand.yellow, fontWeight: FontWeight.w500))]),
      const SizedBox(height: 12),
      HouseholdTreeView(draft: _draft, catalog: _catalog),
    ]))));

    final appBar = wamAppBar(context, 
      titleSpacing: 20,
      title: Row(children: [const BrandLogo(kind: LogoKind.bar), if (!isLargeScreen(context)) ...[const SizedBox(width: 10), const Wordmark(size: 20)]]),
      actions: [TextButton(onPressed: () async { await s.auth.logout(); s.toast('Your answers are saved. Log in to continue.'); s.router.reset('welcome'); }, child: const Text('Save & sign out'))],
    );

    if (split) {
      return Scaffold(body: Row(children: [
        Expanded(child: Scaffold(appBar: appBar, body: content, bottomNavigationBar: actions)),
        SizedBox(width: size.width >= 1100 ? 380.0 : 300.0, child: treePanel),
      ]));
    }
    return Scaffold(
      appBar: appBar,
      body: content,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        Material(color: Brand.blue, child: InkWell(
          onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Brand.blue, showDragHandle: true,
              builder: (_) => DraggableScrollableSheet(expand: false, initialChildSize: 0.6, maxChildSize: 0.9, builder: (_, ctl) => ListView(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [HouseholdTreeView(draft: _draft, catalog: _catalog)]))),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), child: Row(children: [
            const Icon(Icons.keyboard_arrow_up, color: Colors.white70),
            const SizedBox(width: 8),
            const Expanded(child: Text('Your household so far', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
            Text('${tree.moduleCount} modules', style: const TextStyle(color: Brand.yellow, fontWeight: FontWeight.w500)),
          ])),
        )),
        actions,
      ]),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.draft, required this.catalog, required this.onChange});
  final ProfileDraft draft;
  final Catalog catalog;
  final ValueChanged<String> onChange;
  static const _role = {'ME': 'You do most of the cooking.', 'SHARED': 'Cooking is shared.', 'OTHER': 'Someone else does most of the cooking.'};
  static const _skill = {'BEGINNER': 'Just starting out in the kitchen.', 'COMFORTABLE': 'Comfortable with everyday cooking.', 'CONFIDENT': 'Confident cook.'};

  @override
  Widget build(BuildContext context) {
    final t = deriveTree(draft, catalog);
    Widget block(String title, String step, List<Widget> body, {bool first = false}) => QBlock(first: first, children: [
          Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed: () => onChange(step), child: Text('Change', semanticsLabel: 'Change ${title.toLowerCase()}'))]),
          ...body,
        ]);
    final kn = t.kitchens.length, sc = t.storageCount, mc = t.members;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      block('You', 'about', [Text('${draft.about['displayName']}. ${_role[draft.about['cookingRole']] ?? ''} ${_skill[draft.about['skill']] ?? ''}'.trim())], first: true),
      block('Household', 'household', [Text('${draft.householdName}, ${draft.householdSize} ${draft.householdSize == 1 ? 'person' : 'people'}, $kn kitchen${kn == 1 ? '' : 's'}.')]),
      block('Kitchens & equipment', 'kitchens', [for (final k in t.kitchens) Text.rich(TextSpan(children: [
        TextSpan(text: '${k.name}: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        TextSpan(text: (t.storage[k.key] ?? []).isEmpty ? 'no storage' : t.storage[k.key]!.map((s) => s.name).join(', ')),
        if ((t.equipment[k.key] ?? 0) > 0) TextSpan(text: '; ${t.equipment[k.key]} ${t.equipment[k.key] == 1 ? 'appliance or tool' : 'appliances and tools'}'),
      ]))]),
      block('Family & health', 'family', [for (final m in draft.family) Padding(padding: const EdgeInsets.only(bottom: 6), child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(m.name),
        for (final a in m.allergies) Tag('No ${catalog.nameOf(catalog.allergens, a).toLowerCase()}', danger: true),
        for (final x in m.diets) Tag(catalog.nameOf(catalog.diets, x)),
      ]))]),
      block('Food on hand', 'food', [Text(draft.food.isEmpty ? 'None yet. You can add food after setup.' : '${draft.food.length} food item${draft.food.length == 1 ? '' : 's'} ready to add.')]),
      QBlock(children: [Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Brand.blue, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WAMWins will set up ${t.moduleCount} parts for your household', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('$kn kitchen${kn == 1 ? '' : 's'}, $sc storage unit${sc == 1 ? '' : 's'} with their shelves, $mc family member${mc == 1 ? '' : 's'}. Nothing you didn’t mention is created.',
              style: const TextStyle(color: Brand.onBrandSoft)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final m in t.modules.where((m) => m.on))
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Brand.yellow, borderRadius: BorderRadius.circular(999)),
                child: Text(m.name, style: const TextStyle(color: Brand.navy, fontSize: 13, fontWeight: FontWeight.w500)))]),
        ]))]),
    ]);
  }
}
