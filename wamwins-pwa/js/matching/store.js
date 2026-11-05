import { tx } from '../data/db.js';

// Browser persistence for matching and meals (same tables and columns as the shared database; IndexedDB v2).
const HH_STORES = ['family_member', 'member_allergy', 'member_dietary_requirement', 'member_health_food_requirement', 'member_preference',
  'inventory_item', 'household_appliance', 'household_cookware', 'household_utensil'];
const RUN_STORES = ['match_run', 'match_run_member', 'match_result', 'match_result_factor', 'match_result_item', 'match_exclusion', 'local_mutation_outbox'];
const MEAL_STORES = ['meal_record', 'meal_participant', 'consumption_record', 'inventory_item', 'inventory_transaction', 'match_result', 'match_run_member', 'local_mutation_outbox'];
const round4 = (v) => Math.round(v * 10000) / 10000;

/** One household's rows needed by matching, read once and released with the screen. */
export async function loadSnapshot(hh) {
  const rows = await tx(HH_STORES, 'readonly', async t => {
    const out = {};
    for (const s of HH_STORES) out[s] = await t.byIndex(s, 'household_id', hh);
    return out;
  });
  return { members: rows.family_member, allergies: rows.member_allergy, diets: rows.member_dietary_requirement,
    healthRequirements: rows.member_health_food_requirement, preferences: rows.member_preference, inventory: rows.inventory_item,
    equipment: [...rows.household_appliance, ...rows.household_cookware, ...rows.household_utensil], intolerances: [] };
}

/** Persist an explainable run (unsafe recipes are never stored as recommendations). */
export async function saveRun({ hh, userId, mealSlot, maxResults, maxMissing, engineVersion, members, ranked, excluded, candidateCount, durationMs }) {
  const runId = crypto.randomUUID();
  const now = new Date().toISOString();
  const results = [];
  await tx(RUN_STORES, 'readwrite', async t => {
    await t.insert('match_run', { id: runId, household_id: hh, requested_by_user_id: userId, kitchen_id: null, meal_slot: mealSlot, status: 'COMPLETED',
      engine_version: engineVersion, max_results: maxResults, max_missing_items: maxMissing, prioritize_use_soon: true, candidate_count: candidateCount,
      excluded_count: excluded.length, duration_ms: durationMs, requested_at: now, completed_at: now, created_source_code: 'MANUAL' });
    for (const m of members) await t.insert('match_run_member', { id: `${runId}|${m.id}`, run_id: runId, household_id: hh, member_id: m.id });
    for (const [k, r] of ranked.slice(0, maxResults).entries()) {
      const resultId = crypto.randomUUID();
      await t.insert('match_result', { id: resultId, run_id: runId, household_id: hh, recipe_id: r.recipeId, rank: k + 1, total_score: r.score, safety_passed: true,
        available_ingredient_ratio: r.availableRatio, missing_item_count: r.missing.length, use_soon_item_count: r.useSoon.length, equipment_ok: true, status: 'PROPOSED' });
      for (const f of r.factors) await t.insert('match_result_factor', { id: `${resultId}|${f.code}`, result_id: resultId, household_id: hh, factor_code: f.code, score: f.score, weight: f.weight, explanation: f.explanation });
      for (const [role, list] of [['AVAILABLE', r.available], ['MISSING', r.missing], ['USE_SOON', r.useSoon]])
        for (const it of list) await t.insert('match_result_item', { id: `${resultId}|${it.itemMasterId}|${role}`, result_id: resultId, household_id: hh, item_master_id: it.itemMasterId, role, required_quantity: it.quantity, unit_code: it.unit });
      results.push({ matchResultId: resultId, rank: k + 1, ...r });
    }
    for (const e of excluded.slice(0, 50)) await t.insert('match_exclusion', { id: `${runId}|${e.recipeId}|${e.reason}`, run_id: runId, household_id: hh, recipe_id: e.recipeId, reason_code: e.reason, member_id: e.memberId ?? null, detail: e.detail });
  });
  return { runId, results };
}

/**
 * Cook this: record the meal and deduct each non-optional ingredient through MEAL_USAGE transactions,
 * oldest use-by first, applying the same ledger rules the shared database triggers enforce
 * (quantity_before/after, never negative, lifecycle status). Confirming twice deducts once.
 */
export async function confirmMeal({ hh, userId, matchResultId, servings, mealSlot, today, ref, units }) {
  return tx(MEAL_STORES, 'readwrite', async t => {
    const meals = await t.byIndex('meal_record', 'household_id', hh);
    const done = meals.find(m => m.match_result_id === matchResultId && m.status !== 'CANCELLED');
    if (done) return { mealRecordId: done.id, alreadyConfirmed: true, shortfalls: [] };
    const mr = await t.get('match_result', matchResultId);
    if (!mr || mr.household_id !== hh) throw new Error('Unknown match result');
    const recipe = ref.recipes.find(r => r.id === mr.recipe_id);
    const serve = servings ?? recipe.servings, factor = serve / recipe.servings;
    const mealId = crypto.randomUUID(), now = new Date().toISOString();
    await t.insert('meal_record', { id: mealId, household_id: hh, kitchen_id: null, recipe_id: recipe.id, match_result_id: matchResultId, title: recipe.title,
      meal_slot: mealSlot ?? null, meal_date: today, servings: serve, status: 'CONFIRMED', confirmed_by_user_id: userId, confirmed_at: now, inventory_deducted_at: now, created_source_code: 'MANUAL' });
    for (const m of (await t.byIndex('match_run_member', 'household_id', hh)).filter(m => m.run_id === mr.run_id))
      await t.insert('meal_participant', { id: `${mealId}|${m.member_id}`, meal_record_id: mealId, household_id: hh, member_id: m.member_id, portion_factor: 1 });
    const shortfalls = [];
    const ings = ref.ingredients.filter(i => i.recipe_id === recipe.id && !i.is_optional).sort((a, b) => a.ordinal - b.ordinal);
    for (const ing of ings) {
      let remaining = round4(ing.quantity * factor);
      const lots = (await t.byIndex('inventory_item', 'household_id', hh))
        .filter(l => !l.deleted_at && l.item_master_id === ing.item_master_id && l.quantity > 0)
        .sort((a, b) => (a.use_soon_on ?? a.expires_on ?? a.best_before_on ?? '9999-12-31').localeCompare(b.use_soon_on ?? b.expires_on ?? b.best_before_on ?? '9999-12-31')
          || a.created_at.localeCompare(b.created_at)).slice(0, 20);
      for (const lot of lots) {
        if (remaining <= 1e-9) break;
        const need = units.convert(remaining, ing.unit_code, lot.unit_code, ing.item_master_id);
        if (need === undefined) continue;
        const take = round4(Math.min(need, lot.quantity));
        if (take <= 0) continue;
        const after = round4(lot.quantity - take), txnId = crypto.randomUUID();
        await t.insert('inventory_transaction', { id: txnId, household_id: hh, inventory_item_id: lot.id, transaction_type_code: 'MEAL_USAGE', quantity_delta: -take,
          unit_code: lot.unit_code, quantity_before: lot.quantity, quantity_after: after, occurred_at: now, actor_user_id: userId, meal_record_id: mealId,
          created_source_code: 'MANUAL', idempotency_key: `meal:${mealId}:${ing.id}:${lot.id}` });
        const status = after === 0 ? 'DEPLETED' : (lot.low_stock_threshold != null && after <= lot.low_stock_threshold) ? 'LOW' : lot.opened_on ? 'OPENED' : 'ACTIVE';
        await t.update('inventory_item', { ...lot, quantity: after, last_transaction_id: txnId, last_source_code: 'MANUAL', lifecycle_status: status });
        await t.insert('consumption_record', { id: crypto.randomUUID(), household_id: hh, meal_record_id: mealId, item_master_id: ing.item_master_id,
          quantity: take, unit_code: lot.unit_code, consumed_at: now, inventory_transaction_id: txnId, created_source_code: 'MANUAL' });
        remaining -= units.convert(take, lot.unit_code, ing.unit_code, ing.item_master_id) ?? 0;
      }
      if (remaining > 1e-4) shortfalls.push(`${ing.name} (${round4(remaining)} ${ing.unit_code.toLowerCase()})`);
    }
    await t.update('match_result', { ...mr, status: 'ACCEPTED' });
    return { mealRecordId: mealId, servings: serve, shortfalls };
  });
}
