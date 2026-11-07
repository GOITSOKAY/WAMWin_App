import '../core/db.dart';
import '../core/ids.dart';
import 'matching_data.dart';
import 'units.dart';

/// Port of src/modules/matching/domain/MatchingEngine.ts (reference). Same order, same rules, same texts:
/// hard safety (allergens CONTAINS + MAY_CONTAIN, EXCLUDE intolerances, HARD diets, HARD health rules)
/// -> equipment -> inventory -> use-soon -> preferences -> purchase minimisation -> rank.
/// Unknown data never counts as safe: an unverified item under a HARD diet excludes the recipe.
/// Conformance rule C3: must reproduce conformance/vectors/matching-scenario.json.
const engineVersion = 'wamwins-basic-matching/1.0.0';
const _wInventory = 40.0, _wUseSoon = 8.0, _wPreference = 4.0, _wPurchase = 6.0, _wSoftPenalty = 10.0;

class ItemRole {
  ItemRole(this.itemMasterId, this.name, this.quantity, this.unit);
  final String itemMasterId, name, unit;
  final double quantity;
}

class Factor {
  Factor(this.code, this.score, this.weight, this.explanation);
  final String code, explanation;
  final double score, weight;
}

class Ranked {
  Ranked(this.recipeId, this.title, this.score, this.availableRatio, this.missing, this.available, this.useSoon, this.factors, this.omittedOptional);
  final String recipeId, title;
  final double score, availableRatio;
  final List<ItemRole> missing, available, useSoon;
  final List<Factor> factors;
  final List<String> omittedOptional;
}

class Exclusion {
  Exclusion(this.recipeId, this.reason, this.detail, [this.memberId]);
  final String recipeId, reason, detail;
  final String? memberId;
}

class MatchInputs {
  MatchInputs({required this.today, this.useSoonDays = 3, required this.maxMissing, required this.equipmentEvaluated, required this.members,
      required this.constraints, required this.recipes, required this.ingredients, required this.equipment, required this.facts,
      required this.availability, required this.methods});
  final String today;
  final int useSoonDays, maxMissing;
  final bool equipmentEvaluated;
  final List<DbRow> members, recipes, ingredients, equipment, availability;
  final Constraints constraints;
  final ItemFacts facts;
  final Set<String> methods;
}

double _r(double v, int digits) {
  final f = digits == 1 ? 10.0 : digits == 2 ? 100.0 : digits == 3 ? 1000.0 : 10000.0;
  return (v * f).roundToDouble() / f;
}
double _d(Object? v) => (v as num).toDouble();

({List<Ranked> ranked, List<Exclusion> excluded}) rankRecipes(MatchInputs inp, UnitConverter units) {
  Map<String, List<DbRow>> by(List<DbRow> rows, String k) {
    final m = <String, List<DbRow>>{};
    for (final r in rows) { m.putIfAbsent(r[k] as String, () => []).add(r); }
    return m;
  }
  final ingByRecipe = by(inp.ingredients, 'recipe_id'), eqByRecipe = by(inp.equipment, 'recipe_id');
  final allergenByItem = by(inp.facts.allergens, 'item_master_id'), dietByItem = by(inp.facts.diet, 'item_master_id');
  final nutrByItem = by(inp.facts.nutrients, 'item_master_id'), availByItem = by(inp.availability, 'item_master_id');
  String name(Object? id) => inp.members.where((m) => m['id'] == id).map((m) => m['display_name'] as String).firstOrNull ?? 'member';
  final soonLimit = addDaysIso(inp.today, inp.useSoonDays);
  final ranked = <Ranked>[], excluded = <Exclusion>[];
  final c = inp.constraints;

  for (final r in inp.recipes) {
    final rid = r['id'] as String;
    final ings = ingByRecipe[rid] ?? const <DbRow>[];
    Exclusion? exclusion;
    final omittedOptional = <String>[];
    var softPenalty = 0.0;
    final softNotes = <String>[];
    bool optional(DbRow i) => (i['is_optional'] as int) == 1;

    // 1. hard safety: allergens + EXCLUDE intolerances (optional conflicting ingredients are omitted, never served)
    (String reason, String? memberId, String detail)? conflictOf(DbRow ing) {
      final al = allergenByItem[ing['item_master_id']] ?? const <DbRow>[];
      for (final a in c.allergies) {
        if (al.any((x) => x['allergen_code'] == a['allergen_code'])) {
          return ('ALLERGEN', a['member_id'] as String, '${ing['name']} contains/may contain ${a['allergen_code']} (allergy: ${name(a['member_id'])})');
        }
      }
      for (final t in c.intolerances.where((t) => t['handling'] == 'EXCLUDE')) {
        if ((t['allergen_code'] != null && al.any((x) => x['allergen_code'] == t['allergen_code'])) || t['item_master_id'] == ing['item_master_id'] ||
            (t['food_category_code'] != null && t['food_category_code'] == ing['food_category_code'])) {
          return ('INTOLERANCE', t['member_id'] as String, '${ing['name']} conflicts with an intolerance (${name(t['member_id'])})');
        }
      }
      return null;
    }
    final usable = <DbRow>[];
    for (final ing in ings) {
      final cf = conflictOf(ing);
      if (cf != null && !optional(ing)) { exclusion = Exclusion(rid, cf.$1, cf.$3, cf.$2); break; }
      if (cf != null) { omittedOptional.add(ing['name'] as String); } else { usable.add(ing); }
    }
    if (exclusion == null) {
      for (final t in c.intolerances.where((t) => t['handling'] == 'PENALIZE')) {
        for (final ing in usable) {
          if (t['item_master_id'] == ing['item_master_id'] || (t['food_category_code'] != null && t['food_category_code'] == ing['food_category_code']) ||
              (t['allergen_code'] != null && (allergenByItem[ing['item_master_id']] ?? const <DbRow>[]).any((a) => a['allergen_code'] == t['allergen_code']))) {
            softPenalty += _wSoftPenalty;
            softNotes.add('${ing['name']} is not well tolerated by ${name(t['member_id'])}');
          }
        }
      }
    }
    // 2. dietary patterns
    if (exclusion == null) {
      for (final d in c.diets) {
        DbRow? bad;
        for (final i in usable.where((i) => !optional(i))) {
          final f = (dietByItem[i['item_master_id']] ?? const <DbRow>[]).where((x) => x['dietary_pattern_code'] == d['dietary_pattern_code']).firstOrNull;
          if (f == null || (f['is_compatible'] as int) != 1) { bad = i; break; }
        }
        if (bad == null) continue;
        final known = (dietByItem[bad['item_master_id']] ?? const <DbRow>[]).any((x) => x['dietary_pattern_code'] == d['dietary_pattern_code']);
        final detail = '${bad['name']} is ${known ? 'not' : 'not verified as'} ${(d['dietary_pattern_code'] as String).toLowerCase().replaceFirst('_', '-')} (${name(d['member_id'])})';
        if (d['strictness'] == 'HARD') { exclusion = Exclusion(rid, 'DIETARY', detail, d['member_id'] as String); break; }
        softPenalty += _wSoftPenalty;
        softNotes.add(detail);
      }
    }
    // 3. health-food rules (per serving)
    if (exclusion == null && c.healthRules.isNotEmpty) {
      final perServing = <String, double>{};
      for (final i in usable.where((i) => !optional(i))) {
        final mv = units.toMassOrVolume(_d(i['quantity']), i['unit_code'] as String, i['item_master_id'] as String);
        if (mv == null) continue;
        for (final n in nutrByItem[i['item_master_id']] ?? const <DbRow>[]) {
          perServing[n['nutrient_code'] as String] = (perServing[n['nutrient_code']] ?? 0) + _d(n['amount']) * mv.amount / 100 / _d(r['servings']);
        }
      }
      for (final h in c.healthRules) {
        var violated = false;
        var detail = '';
        if (h['direction'] == 'AVOID' && h['avoid_food_category'] != null) {
          final hit = usable.where((i) => !optional(i) && i['food_category_code'] == h['avoid_food_category']).firstOrNull;
          if (hit != null) { violated = true; detail = '${hit['name']} conflicts with ${h['code']} (${name(h['member_id'])})'; }
        } else if (h['nutrient_code'] != null && h['threshold'] != null) {
          final v = _r(perServing[h['nutrient_code']] ?? 0, 1);
          final threshold = _d(h['threshold']);
          final nut = (h['nutrient_code'] as String).toLowerCase();
          if (h['direction'] == 'LIMIT' && v > threshold) { violated = true; detail = '$nut ~${_num(v)} per serving exceeds ${_num(threshold)} (${h['code']}, ${name(h['member_id'])})'; }
          if (h['direction'] == 'INCREASE' && v < threshold) { softPenalty += _wSoftPenalty / 2; softNotes.add('$nut ~${_num(v)} per serving is below the ${h['code']} goal'); }
        }
        if (!violated) continue;
        if (h['strictness'] == 'HARD') { exclusion = Exclusion(rid, 'HEALTH_RULE', detail, h['member_id'] as String); break; }
        softPenalty += _wSoftPenalty;
        softNotes.add(detail);
      }
    }
    // 4. equipment
    if (exclusion == null && inp.equipmentEvaluated) {
      final need = (eqByRecipe[rid] ?? const <DbRow>[]).where((e) => (e['is_optional'] as int) != 1 && e['cooking_method_code'] != null && !inp.methods.contains(e['cooking_method_code'])).toList();
      if (need.isNotEmpty) exclusion = Exclusion(rid, 'EQUIPMENT', 'Needs equipment for ${need.map((n) => (n['cooking_method_code'] as String).toLowerCase()).join(', ')}');
    }
    // 5. inventory + use-soon
    final available = <ItemRole>[], missing = <ItemRole>[], useSoon = <ItemRole>[];
    if (exclusion == null) {
      for (final i in usable.where((i) => !optional(i))) {
        var have = 0.0;
        String? soonest;
        for (final a in availByItem[i['item_master_id']] ?? const <DbRow>[]) {
          final cv = units.convert(_d(a['qty']), a['unit_code'] as String, i['unit_code'] as String, i['item_master_id'] as String);
          if (cv != null) have += cv;
          final e = a['earliest_use_by'] as String?;
          if (e != null && (soonest == null || e.compareTo(soonest) < 0)) soonest = e;
        }
        final qty = _d(i['quantity']);
        final role = ItemRole(i['item_master_id'] as String, i['name'] as String, qty, i['unit_code'] as String);
        if (have + 1e-9 >= qty) {
          available.add(role);
          if (soonest != null && soonest.compareTo(soonLimit) <= 0) useSoon.add(role);
        } else {
          missing.add(ItemRole(role.itemMasterId, role.name, _r(qty - have, 2), role.unit));
        }
      }
      if (missing.length > inp.maxMissing) exclusion = Exclusion(rid, 'TOO_MANY_MISSING', '${missing.length} ingredients missing');
    }
    if (exclusion != null) { excluded.add(exclusion); continue; }
    // 6. preferences
    var pref = 0.0;
    final prefNotes = <String>[];
    for (final p in c.preferences) {
      final kind = p['preference_kind'] as String;
      final sign = kind == 'FAVORITE' ? 1.5 : kind == 'LIKE' ? 1.0 : kind == 'DISLIKE' ? -1.0 : -2.0;
      final hit = p['recipe_id'] == rid || (p['cuisine_code'] != null && p['cuisine_code'] == r['cuisine_code']) ||
          (p['item_master_id'] != null && usable.any((i) => i['item_master_id'] == p['item_master_id'])) ||
          (p['food_category_code'] != null && usable.any((i) => i['food_category_code'] == p['food_category_code']));
      if (hit) { pref += sign * _d(p['strength']) * _wPreference / 3; prefNotes.add('${name(p['member_id'])} ${kind.toLowerCase()}s this'); }
    }
    final required = available.length + missing.length;
    final ratio = required == 0 ? 1.0 : available.length / required;
    String fmtMissing(ItemRole m) => '${m.name} (${_num(m.quantity)} ${m.unit.toLowerCase()})';
    final factors = <Factor>[
      Factor('SAFETY', 0, 1, 'Safe for ${inp.members.isEmpty ? 'household' : inp.members.map((m) => m['display_name']).join(', ')}: no allergen, intolerance'
          '${c.diets.isNotEmpty ? ', diet' : ''} or hard health-rule conflicts${omittedOptional.isNotEmpty ? '; omit optional ${omittedOptional.join(', ')}' : ''}'),
      Factor('INVENTORY', ratio * _wInventory, _wInventory, '${available.length} of $required ingredients already in your kitchen'),
      Factor('USE_SOON', (useSoon.length < 3 ? useSoon.length : 3) * _wUseSoon, _wUseSoon,
          useSoon.isNotEmpty ? 'Uses soon-to-expire: ${useSoon.map((u) => u.name).join(', ')}' : 'No use-soon items involved'),
      Factor('EQUIPMENT', 0, 0, inp.equipmentEvaluated ? 'You have the equipment needed' : 'Equipment not checked (equipment module unavailable)'),
      Factor('PREFERENCE', pref, _wPreference, prefNotes.isNotEmpty ? prefNotes.join('; ') : 'No stated preferences affect this'),
      Factor('PURCHASE_MINIMIZATION', -missing.length * _wPurchase, _wPurchase, missing.isNotEmpty ? 'Buy: ${missing.map(fmtMissing).join(', ')}' : 'Nothing to buy'),
      if (softPenalty != 0) Factor('HEALTH_RULE', -softPenalty, _wSoftPenalty, softNotes.join('; ')),
    ];
    final score = _r(factors.fold<double>(0, (s, f) => s + f.score), 3);
    ranked.add(Ranked(rid, r['title'] as String, score, _r(ratio, 4), missing, available, useSoon, factors, omittedOptional));
  }
  ranked.sort((a, b) { final s = b.score.compareTo(a.score); return s != 0 ? s : a.title.compareTo(b.title); });
  return (ranked: ranked, excluded: excluded);
}

/// Formats like JavaScript's number-to-string (1200 not 1200.0; 7.5 stays 7.5).
String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
