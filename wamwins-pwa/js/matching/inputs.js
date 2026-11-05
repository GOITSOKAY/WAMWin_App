// Builds the engine's inputs from ONE household's rows + the generated reference - the same selection the
// reference read port makes with SQL (src/modules/matching/data/MatchingReadPort.ts). Pure: no browser APIs,
// so it is verified in Node against the shared conformance scenario (scripts/check-matching.mjs).
const live = (r) => !r.deleted_at;
export const MAX_CANDIDATES = 200;

export function buildInputs({ snapshot, ref, memberIds, mealSlot = null, today, maxMissing = 3 }) {
  const members = snapshot.members.filter(live)
    .filter(m => memberIds?.length ? memberIds.includes(m.id) : (m.is_active !== false && m.include_in_matching_by_default !== false))
    .map(m => ({ id: m.id, display_name: m.display_name }));
  const ids = new Set(members.map(m => m.id));
  const mine = (rows) => rows.filter(live).filter(r => ids.has(r.member_id));
  const types = new Map(ref.requirementTypes.map(t => [t.code, t]));
  const constraints = {
    allergies: mine(snapshot.allergies).map(r => ({ member_id: r.member_id, allergen_code: r.allergen_code })),
    intolerances: mine(snapshot.intolerances ?? []).map(r => ({ member_id: r.member_id, allergen_code: r.allergen_code ?? null,
      item_master_id: r.item_master_id ?? null, food_category_code: r.food_category_code ?? null, handling: r.handling })),
    diets: mine(snapshot.diets).map(r => ({ member_id: r.member_id, dietary_pattern_code: r.dietary_pattern_code, strictness: r.strictness })),
    healthRules: mine(snapshot.healthRequirements).map(r => { const t = types.get(r.requirement_type_code) ?? {};
      return { member_id: r.member_id, code: r.requirement_type_code, strictness: r.strictness, threshold: r.threshold_value ?? t.default_threshold ?? null,
        nutrient_code: t.nutrient_code ?? null, direction: t.direction, avoid_food_category: t.avoid_food_category ?? null }; }),
    preferences: mine(snapshot.preferences).map(r => ({ member_id: r.member_id, preference_kind: r.preference_kind, subject_type: r.subject_type,
      item_master_id: r.item_master_id ?? null, cuisine_code: r.cuisine_code ?? null, recipe_id: r.recipe_id ?? null,
      food_category_code: r.food_category_code ?? null, strength: r.strength ?? 3 })),
  };
  const slotOk = new Set(ref.slots.filter(([, s]) => !mealSlot || s === mealSlot).map(([rid]) => rid));
  const recipes = ref.recipes.filter(r => slotOk.has(r.id)).slice(0, MAX_CANDIDATES);
  const rids = new Set(recipes.map(r => r.id));
  const ingredients = ref.ingredients.filter(i => rids.has(i.recipe_id));
  const itemIds = new Set(ingredients.map(i => i.item_master_id));
  const facts = {
    allergens: ref.allergens.filter(a => itemIds.has(a.item_master_id)),
    diet: ref.diet.filter(d => itemIds.has(d.item_master_id)),
    nutrients: ref.nutrients.filter(n => itemIds.has(n.item_master_id)),
  };
  const groups = new Map();                                 // aggregated availability per item + unit
  for (const i of snapshot.inventory) {
    if (!live(i) || !(i.quantity > 0) || ['EXPIRED', 'DISCARDED'].includes(i.lifecycle_status) || !itemIds.has(i.item_master_id)) continue;
    const k = `${i.item_master_id}|${i.unit_code}`;
    const g = groups.get(k) ?? { item_master_id: i.item_master_id, unit_code: i.unit_code, qty: 0, earliest_use_by: null };
    g.qty += i.quantity;
    const d = i.use_soon_on ?? i.expires_on ?? i.best_before_on ?? null;
    if (d && (!g.earliest_use_by || d < g.earliest_use_by)) g.earliest_use_by = d;
    groups.set(k, g);
  }
  const owned = new Set(snapshot.equipment.filter(live).filter(e => e.is_active !== false && (e.condition ?? 'WORKING') === 'WORKING').map(e => e.equipment_type_code));
  const methods = new Set(['NO_COOK', ...ref.methods.filter(([type]) => owned.has(type)).map(([, m]) => m)]);
  return { today, useSoonDays: 3, maxMissing, equipmentEvaluated: true, members, constraints, recipes, ingredients,
    equipment: ref.equipment.filter(e => rids.has(e.recipe_id)), facts, availability: [...groups.values()], methods };
}
