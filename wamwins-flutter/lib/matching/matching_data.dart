import '../core/db.dart';

/// Port of src/modules/matching/data/MatchingReadPort.ts - the SAME scoped, bounded queries:
/// selected members' rules, <= 200 recipe candidates, involved items only, aggregated availability.
class MatchingData {
  MatchingData(this.db);
  final AppDb db;
  static const maxCandidates = 200;
  static String _ph(int n) => List.filled(n, '?').join(',');

  List<DbRow> members(String hh, [List<String>? ids]) => ids != null && ids.isNotEmpty
      ? db.select('SELECT id, display_name FROM family_member WHERE household_id = ? AND deleted_at IS NULL AND id IN (${_ph(ids.length)})', [hh, ...ids])
      : db.select('SELECT id, display_name FROM family_member WHERE household_id = ? AND deleted_at IS NULL AND is_active = 1 AND include_in_matching_by_default = 1 LIMIT 20', [hh]);

  Constraints constraints(String hh, List<String> memberIds) {
    if (memberIds.isEmpty) return Constraints.empty();
    final m = _ph(memberIds.length), args = [hh, ...memberIds];
    return Constraints(
      allergies: db.select('SELECT member_id, allergen_code FROM member_allergy WHERE household_id = ? AND deleted_at IS NULL AND member_id IN ($m)', args),
      intolerances: db.select('SELECT member_id, allergen_code, item_master_id, food_category_code, handling FROM member_intolerance WHERE household_id = ? AND deleted_at IS NULL AND member_id IN ($m)', args),
      diets: db.select('SELECT member_id, dietary_pattern_code, strictness FROM member_dietary_requirement WHERE household_id = ? AND deleted_at IS NULL AND member_id IN ($m)', args),
      healthRules: db.select('SELECT r.member_id, r.requirement_type_code AS code, r.strictness, COALESCE(r.threshold_value, t.default_threshold) AS threshold, '
          't.nutrient_code, t.direction, t.avoid_food_category FROM member_health_food_requirement r JOIN food_requirement_type t ON t.code = r.requirement_type_code '
          'WHERE r.household_id = ? AND r.deleted_at IS NULL AND r.member_id IN ($m)', args),
      preferences: db.select('SELECT member_id, preference_kind, subject_type, item_master_id, cuisine_code, recipe_id, food_category_code, strength FROM member_preference '
          'WHERE household_id = ? AND deleted_at IS NULL AND member_id IN ($m)', args),
    );
  }

  List<DbRow> candidates(String hh, String? mealSlot) => db.select(
      'SELECT r.id, r.title, r.servings, r.cuisine_code FROM recipe_master r WHERE (r.household_id IS NULL OR r.household_id = ?) AND r.is_active = 1 AND r.deleted_at IS NULL '
      'AND (? IS NULL OR EXISTS (SELECT 1 FROM recipe_meal_slot s WHERE s.recipe_id = r.id AND s.meal_slot = ?)) LIMIT $maxCandidates', [hh, mealSlot, mealSlot]);

  List<DbRow> ingredients(List<String> recipeIds) => recipeIds.isEmpty ? [] : db.select(
      'SELECT ri.id, ri.recipe_id, ri.item_master_id, ri.quantity, ri.unit_code, ri.is_optional, i.canonical_name AS name, i.food_category_code '
      'FROM recipe_ingredient ri JOIN item_master i ON i.id = ri.item_master_id WHERE ri.recipe_id IN (${_ph(recipeIds.length)})', recipeIds);

  List<DbRow> equipmentRequirements(List<String> recipeIds) => recipeIds.isEmpty ? [] : db.select(
      'SELECT recipe_id, cooking_method_code, is_optional FROM recipe_equipment_requirement WHERE recipe_id IN (${_ph(recipeIds.length)})', recipeIds);

  ItemFacts itemFacts(List<String> itemIds) {
    if (itemIds.isEmpty) return ItemFacts(const [], const [], const []);
    final p = _ph(itemIds.length);
    return ItemFacts(
      db.select('SELECT item_master_id, allergen_code, presence FROM item_allergen WHERE item_master_id IN ($p)', itemIds),
      db.select('SELECT item_master_id, dietary_pattern_code, is_compatible FROM item_dietary_compatibility WHERE item_master_id IN ($p)', itemIds),
      db.select('SELECT item_master_id, nutrient_code, amount, basis FROM item_nutrient WHERE item_master_id IN ($p)', itemIds),
    );
  }

  /// Aggregated per item (no item rows are loaded).
  List<DbRow> availability(String hh, List<String> itemIds, [String? kitchenId]) => itemIds.isEmpty ? [] : db.select(
      'SELECT item_master_id, unit_code, SUM(quantity) AS qty, MIN(COALESCE(use_soon_on, expires_on, best_before_on)) AS earliest_use_by '
      "FROM inventory_item WHERE household_id = ? AND deleted_at IS NULL AND quantity > 0 AND lifecycle_status NOT IN ('EXPIRED','DISCARDED') "
      'AND (? IS NULL OR kitchen_id = ?) AND item_master_id IN (${_ph(itemIds.length)}) GROUP BY item_master_id, unit_code', [hh, kitchenId, kitchenId, ...itemIds]);

  Set<String> cookingMethods(String hh, [String? kitchenId]) => {
        'NO_COOK',
        for (final r in db.select('SELECT DISTINCT cooking_method_code FROM v_household_cooking_capability WHERE household_id = ? AND (? IS NULL OR kitchen_id = ?)', [hh, kitchenId, kitchenId]))
          r['cooking_method_code'] as String
      };
}

class Constraints {
  Constraints({required this.allergies, required this.intolerances, required this.diets, required this.healthRules, required this.preferences});
  factory Constraints.empty() => Constraints(allergies: [], intolerances: [], diets: [], healthRules: [], preferences: []);
  final List<DbRow> allergies, intolerances, diets, healthRules, preferences;
}

class ItemFacts {
  ItemFacts(this.allergens, this.diet, this.nutrients);
  final List<DbRow> allergens, diet, nutrients;
}
