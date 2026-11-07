import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../core/db.dart';
import '../core/ids.dart';
import '../inquiry/catalog.dart';
import '../matching/matching_engine.dart';
import '../matching/matching_service.dart';
import '../matching/meal_service.dart';
import '../ui/widgets.dart';

/// "What can we cook?" - safety-first meal matching for the people selected, using what the household has.
/// Data is loaded when "Find meals" is pressed and released when the screen closes.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.user});
  final DbRow user;
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  late String _hh;
  late List<DbRow> _members;
  late Set<String> _selected;
  String _slot = 'ANY';
  MatchRun? _run;
  bool _busy = false;
  String? _error;
  final Set<String> _cooked = {};
  bool _loaded = false;

  static const _slots = [Option('ANY', 'Any meal'), Option('BREAKFAST', 'Breakfast'), Option('LUNCH', 'Lunch'), Option('DINNER', 'Dinner'), Option('SNACK', 'Snack')];
  static const _reasons = {'ALLERGEN': 'Allergy', 'INTOLERANCE': 'Intolerance', 'DIETARY': 'Diet', 'HEALTH_RULE': 'Health goal',
    'EQUIPMENT': 'Equipment', 'TOO_MANY_MISSING': 'Too many ingredients missing'};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = AppScope.of(context);
    _hh = s.profile.householdIdFor(widget.user['id'] as String)!;
    _members = s.db.select('SELECT id, display_name FROM family_member WHERE household_id = ? AND deleted_at IS NULL AND is_active = 1 ORDER BY (linked_user_id IS NULL), created_at', [_hh]);
    _selected = {for (final m in _members) m['id'] as String};
  }

  void _find() {
    if (_selected.isEmpty) return setState(() => _error = 'Choose who you’re cooking for.');
    final s = AppScope.of(context);
    setState(() { _busy = true; _error = null; });
    try {
      final run = MatchingService(s.db).run(householdId: _hh, userId: widget.user['id'] as String, memberIds: _selected.toList(),
          mealSlot: _slot == 'ANY' ? null : _slot, maxResults: 5, today: todayIso());
      setState(() { _run = run; _busy = false; _cooked.clear(); });
    } catch (e) {
      setState(() { _error = 'Meals couldn’t be matched right now. Your other features still work. ($e)'; _busy = false; });
    }
  }

  Future<void> _cook(MatchResultView r) async {
    final s = AppScope.of(context);
    final base = (s.db.first('SELECT servings FROM recipe_master WHERE id = ?', [r.ranked.recipeId])!['servings'] as num).round();
    var servings = base;
    final ok = await showModalBottomSheet<bool>(context: context, showDragHandle: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Cook ${r.ranked.title}', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('The ingredients will be taken out of your inventory, oldest use-by date first.', style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 12),
        CounterRow(label: 'Servings', value: servings, min: 1, max: 20, onChanged: (v) => setLocal(() => servings = v)),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Cook this', onPressed: () => Navigator.pop(ctx, true)),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      ]),
    ))));
    if (ok != true || !mounted) return;
    try {
      final c = MealService(s.db).confirm(householdId: _hh, userId: widget.user['id'] as String, matchResultId: r.matchResultId,
          servings: servings.toDouble(), mealSlot: _slot == 'ANY' ? null : _slot, today: todayIso());
      setState(() => _cooked.add(r.matchResultId));
      s.toast(c.shortfalls.isEmpty ? 'Enjoy! The ingredients were taken out of your inventory.'
          : 'Enjoy! Not enough in stock for: ${c.shortfalls.join(', ')}.');
    } catch (e) {
      s.toast('The meal couldn’t be saved. Nothing was changed. ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final run = _run;
    String explain(Ranked r, String code) => r.factors.where((f) => f.code == code).map((f) => f.explanation).firstOrNull ?? '';

    Widget resultCard(MatchResultView v) {
      final r = v.ranked, cooked = _cooked.contains(v.matchResultId);
      final soft = explain(r, 'HEALTH_RULE'), pref = explain(r, 'PREFERENCE');
      Widget line(IconData icon, Color color, String text) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
          ]));
      return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.surface, border: Border.all(color: v.rank == 1 ? Brand.blue : p.line, width: 1.5), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(r.title, style: Theme.of(context).textTheme.titleMedium)),
            if (v.rank == 1) const Tag('Best match'),
            if (cooked) ...[const SizedBox(width: 6), const Tag('Cooked')],
          ]),
          line(Icons.verified_user_outlined, p.ok, explain(r, 'SAFETY')),
          line(Icons.kitchen_outlined, p.link, explain(r, 'INVENTORY')),
          if (r.useSoon.isNotEmpty) line(Icons.schedule, const Color(0xFF8A6400), explain(r, 'USE_SOON')),
          if (r.missing.isNotEmpty) line(Icons.shopping_basket_outlined, p.text2, explain(r, 'PURCHASE_MINIMIZATION')),
          if (soft.isNotEmpty) line(Icons.info_outline, p.text2, soft),
          if (!pref.startsWith('No stated')) line(Icons.favorite_border, p.text2, pref),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: cooked
              ? Text('Saved to your meals', style: TextStyle(color: p.ok, fontWeight: FontWeight.w500))
              : PrimaryButton(label: 'Cook this', expand: false, onPressed: () => _cook(v))),
        ]));
    }

    return Scaffold(
      appBar: wamAppBar(context, leading: IconButton(tooltip: 'Back to home', icon: const Icon(Icons.arrow_back), onPressed: () => s.router.go('home', replace: true)),
          title: const Text('What can we cook?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [ContentWidth(max: 760, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        QBlock(first: true, title: 'Cooking for', hint: 'Allergies and diets of everyone selected are checked first.', children: [
          ChipSelect(options: [for (final m in _members) Option(m['id'] as String, m['display_name'] as String)], selected: _selected.toList(),
              onChanged: (v) => setState(() => _selected = v.toSet())),
        ]),
        QBlock(title: 'Meal', children: [ChipSelect(options: _slots, selected: [_slot], single: true, onChanged: (v) => setState(() => _slot = v.first))]),
        PrimaryButton(label: _busy ? 'Finding meals…' : 'Find meals', busy: _busy, onPressed: _find),
        const SizedBox(height: 12),
        ErrorBanner(_error),
        if (run != null) ...[
          const SizedBox(height: 12),
          Semantics(header: true, child: Text(run.results.isEmpty ? 'No safe matches yet' : 'Suggested for you', style: Theme.of(context).textTheme.titleLarge)),
          const SizedBox(height: 4),
          Text(run.results.isEmpty
              ? 'Nothing fits everyone with what you have. Try fewer people, another meal, or add food to your inventory.'
              : 'Ranked by what you already have, what needs using soon, and your family’s preferences.',
              style: TextStyle(color: p.text2)),
          const SizedBox(height: 12),
          ...run.results.map(resultCard),
          if (run.excluded.isNotEmpty) ExpansionTile(
            tilePadding: EdgeInsets.zero, shape: const Border(), collapsedShape: const Border(),
            title: Text('Not suggested (${run.excluded.length})', style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Why some recipes were left out'),
            children: [for (final e in run.excluded) ListTile(contentPadding: EdgeInsets.zero,
                leading: Icon(e.reason == 'ALLERGEN' || e.reason == 'INTOLERANCE' ? Icons.block : Icons.remove_circle_outline,
                    color: e.reason == 'ALLERGEN' || e.reason == 'INTOLERANCE' ? p.danger : p.text2),
                title: Text(run.recipeTitles[e.recipeId] ?? 'Recipe'),
                subtitle: Text('${_reasons[e.reason] ?? e.reason}: ${e.detail}'))],
          ),
        ],
      ]))]),
    );
  }
}
