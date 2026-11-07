import '../core/db.dart';
import '../core/ids.dart';
import 'matching_data.dart';
import 'matching_engine.dart';
import 'units.dart';

class MatchResultView {
  MatchResultView(this.matchResultId, this.rank, this.ranked);
  final String matchResultId;
  final int rank;
  final Ranked ranked;
}

class MatchRun {
  MatchRun(this.runId, this.results, this.excluded, this.candidateCount, this.recipeTitles);
  final String runId;
  final List<MatchResultView> results;
  final List<Exclusion> excluded;
  final int candidateCount;
  final Map<String, String> recipeTitles;
}

/// Port of src/modules/matching/application/MatchingModule.ts: load only what this run needs,
/// rank, persist the explainable results (unsafe recipes are never stored as recommendations),
/// then release everything.
class MatchingService {
  MatchingService(this.db);
  final AppDb db;

  MatchRun run({required String householdId, required String userId, List<String>? memberIds, String? mealSlot, String? kitchenId,
      int maxResults = 5, int maxMissingItems = 3, required String today, bool equipmentEvaluated = true}) {
    final watch = Stopwatch()..start();
    final data = MatchingData(db);
    final members = data.members(householdId, memberIds);
    if (memberIds != null && memberIds.isNotEmpty && members.length != memberIds.length) throw ArgumentError('Unknown family member selected');
    final recipes = data.candidates(householdId, mealSlot);
    final ids = [for (final r in recipes) r['id'] as String];
    final ingredients = data.ingredients(ids);
    final itemIds = {for (final i in ingredients) i['item_master_id'] as String}.toList();
    final result = rankRecipes(MatchInputs(
      today: today, maxMissing: maxMissingItems, equipmentEvaluated: equipmentEvaluated, members: members,
      constraints: data.constraints(householdId, [for (final m in members) m['id'] as String]),
      recipes: recipes, ingredients: ingredients, equipment: data.equipmentRequirements(ids), facts: data.itemFacts(itemIds),
      availability: data.availability(householdId, itemIds, kitchenId), methods: equipmentEvaluated ? data.cookingMethods(householdId, kitchenId) : <String>{},
    ), UnitConverter(db));

    final runId = newId();
    final top = result.ranked.take(maxResults).toList();
    final views = <MatchResultView>[];
    db.transaction(() {
      db.run("INSERT INTO match_run(id, household_id, requested_by_user_id, kitchen_id, meal_slot, status, engine_version, max_results, max_missing_items) "
          "VALUES (?, ?, ?, ?, ?, 'RUNNING', ?, ?, ?)", [runId, householdId, userId, kitchenId, mealSlot, engineVersion, maxResults, maxMissingItems]);
      for (final m in members) {
        db.run('INSERT INTO match_run_member(run_id, household_id, member_id) VALUES (?, ?, ?)', [runId, householdId, m['id']]);
      }
      for (var k = 0; k < top.length; k++) {
        final r = top[k], resultId = newId();
        db.run('INSERT INTO match_result(id, run_id, household_id, recipe_id, rank, total_score, safety_passed, available_ingredient_ratio, missing_item_count, use_soon_item_count, equipment_ok) '
            'VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, 1)', [resultId, runId, householdId, r.recipeId, k + 1, r.score, r.availableRatio, r.missing.length, r.useSoon.length]);
        for (final f in r.factors) {
          db.run('INSERT INTO match_result_factor(result_id, factor_code, score, weight, explanation) VALUES (?, ?, ?, ?, ?)', [resultId, f.code, f.score, f.weight, f.explanation]);
        }
        for (final (role, list) in [('AVAILABLE', r.available), ('MISSING', r.missing), ('USE_SOON', r.useSoon)]) {
          for (final it in list) {
            db.run('INSERT INTO match_result_item(result_id, item_master_id, role, required_quantity, unit_code) VALUES (?, ?, ?, ?, ?)', [resultId, it.itemMasterId, role, it.quantity, it.unit]);
          }
        }
        views.add(MatchResultView(resultId, k + 1, r));
      }
      for (final e in result.excluded.take(50)) {
        db.run('INSERT OR IGNORE INTO match_exclusion(run_id, recipe_id, reason_code, member_id, detail) VALUES (?, ?, ?, ?, ?)', [runId, e.recipeId, e.reason, e.memberId, e.detail]);
      }
      db.run("UPDATE match_run SET status = 'COMPLETED', candidate_count = ?, excluded_count = ?, duration_ms = ?, completed_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?",
          [recipes.length, result.excluded.length, watch.elapsedMilliseconds, runId]);
    });
    return MatchRun(runId, views, result.excluded, recipes.length, {for (final r in recipes) r['id'] as String: r['title'] as String});
  }
}
