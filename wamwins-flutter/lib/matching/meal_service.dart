import '../core/db.dart';
import '../core/ids.dart';
import 'units.dart';

class MealConfirmation {
  MealConfirmation(this.mealRecordId, this.servings, this.shortfalls, {this.alreadyConfirmed = false});
  final String mealRecordId;
  final double servings;
  final List<String> shortfalls;
  final bool alreadyConfirmed;
}

/// Port of src/modules/meals/application/MealsModule.ts + InventoryLedger.consume/post:
/// confirming a meal records it and deducts every non-optional ingredient through MEAL_USAGE
/// transactions (oldest use-by first). The shared database triggers apply the quantities.
/// Idempotent: confirming the same match result twice deducts once.
class MealService {
  MealService(this.db);
  final AppDb db;

  MealConfirmation confirm({required String householdId, required String userId, required String matchResultId, double? servings, String? mealSlot, required String today}) {
    final existing = db.first("SELECT id, servings FROM meal_record WHERE match_result_id = ? AND household_id = ? AND status <> 'CANCELLED'", [matchResultId, householdId]);
    if (existing != null) return MealConfirmation(existing['id'] as String, (existing['servings'] as num).toDouble(), const [], alreadyConfirmed: true);
    final mr = db.first('SELECT recipe_id, run_id FROM match_result WHERE id = ? AND household_id = ?', [matchResultId, householdId]);
    if (mr == null) throw ArgumentError('Unknown match result');
    final recipe = db.first('SELECT title, servings FROM recipe_master WHERE id = ?', [mr['recipe_id']])!;
    final base = (recipe['servings'] as num).toDouble(), serve = servings ?? base, factor = serve / base;
    final units = UnitConverter(db);
    final mealId = newId();
    final shortfalls = <String>[];
    db.transaction(() {
      db.run("INSERT INTO meal_record(id, household_id, recipe_id, match_result_id, title, meal_slot, meal_date, servings, status, confirmed_by_user_id, confirmed_at) "
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'CONFIRMED', ?, strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
          [mealId, householdId, mr['recipe_id'], matchResultId, recipe['title'], mealSlot, today, serve, userId]);
      for (final m in db.select('SELECT member_id FROM match_run_member WHERE run_id = ?', [mr['run_id']])) {
        db.run('INSERT INTO meal_participant(meal_record_id, household_id, member_id) VALUES (?, ?, ?)', [mealId, householdId, m['member_id']]);
      }
      final ings = db.select('SELECT ri.id, ri.item_master_id, ri.quantity, ri.unit_code, i.canonical_name AS name FROM recipe_ingredient ri '
          'JOIN item_master i ON i.id = ri.item_master_id WHERE ri.recipe_id = ? AND ri.is_optional = 0 ORDER BY ri.ordinal', [mr['recipe_id']]);
      for (final ing in ings) {
        final itemId = ing['item_master_id'] as String, unit = ing['unit_code'] as String;
        var remaining = _round4((ing['quantity'] as num).toDouble() * factor);
        final lots = db.select("SELECT id, quantity, unit_code FROM inventory_item WHERE household_id = ? AND item_master_id = ? AND deleted_at IS NULL AND quantity > 0 "
            "ORDER BY COALESCE(use_soon_on, expires_on, best_before_on, '9999-12-31'), created_at LIMIT 20", [householdId, itemId]);
        for (final lot in lots) {
          if (remaining <= 1e-9) break;
          final lotQty = (lot['quantity'] as num).toDouble(), lotUnit = lot['unit_code'] as String;
          final need = units.convert(remaining, unit, lotUnit, itemId);
          if (need == null) continue;
          final take = _round4(need < lotQty ? need : lotQty);
          if (take <= 0) continue;
          final txnId = newId();
          db.run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, "
              "actor_user_id, meal_record_id, created_source_code, idempotency_key) VALUES (?, ?, ?, 'MEAL_USAGE', ?, ?, ?, ?, ?, ?, 'MANUAL', ?)",
              [txnId, householdId, lot['id'], -take, lotUnit, lotQty, _round4(lotQty - take), userId, mealId, 'meal:$mealId:${ing['id']}:${lot['id']}']);
          db.run('INSERT INTO consumption_record(id, household_id, meal_record_id, item_master_id, quantity, unit_code, inventory_transaction_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
              [newId(), householdId, mealId, itemId, take, lotUnit, txnId]);
          remaining -= units.convert(take, lotUnit, unit, itemId) ?? 0;
        }
        if (remaining > 1e-4) shortfalls.add('${ing['name']} (${_round4(remaining)} ${unit.toLowerCase()})');
      }
      db.run("UPDATE meal_record SET inventory_deducted_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [mealId]);
      db.run("UPDATE match_result SET status = 'ACCEPTED' WHERE id = ?", [matchResultId]);
    });
    return MealConfirmation(mealId, serve, shortfalls);
  }

  static double _round4(double v) => (v * 10000).roundToDouble() / 10000;
}
