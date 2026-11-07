/**
 * Proves the Flutter matching fixture + SQL are equivalent to the reference:
 *   1. builds test/fixtures/matching_household.json with the SAME SQL as the Dart test/app,
 *   2. runs the REFERENCE engine (src/modules/matching) on it -> must equal conformance/vectors/matching-scenario.json,
 *   3. replays the Dart app's persistence (matching_service.dart) and cooking (meal_service.dart) SQL against all
 *      shared constraints and the inventory-ledger triggers.
 * Run from the repository root: npx tsx mobile/tool/check_matching_fixture.ts
 */
import { readdirSync, readFileSync } from 'node:fs';
import { randomUUID as id } from 'node:crypto';
import { NodeSqliteDatabase } from '../../src/data/SqlDatabase';
import { MatchingReadPort } from '../../src/modules/matching/data/MatchingReadPort';
import { rankRecipes } from '../../src/modules/matching/domain/MatchingEngine';
import { UnitConverter } from '../../src/modules/catalog/domain/UnitConverter';

const fx = JSON.parse(readFileSync('mobile/test/fixtures/matching_household.json', 'utf8'));
const scenario = JSON.parse(readFileSync('conformance/vectors/matching-scenario.json', 'utf8'));
const addDays = (d: string, n: number) => { const x = new Date(`${d}T00:00:00Z`); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
let failures = 0;
const ok = (c: boolean, m: string) => { console.log(`  ${c ? 'ok' : 'FAIL'}: ${m}`); if (!c) failures++; };

(async () => {
  const db = await NodeSqliteDatabase.open(':memory:');
  for (const f of readdirSync('mobile/assets/db/migrations').sort()) await db.exec(readFileSync(`mobile/assets/db/migrations/${f}`, 'utf8'));
  const user = id(), hh = id(), today = fx.today, members: string[] = [];
  // ---- buildFixture (same statements as test/matching_conformance_test.dart)
  await db.run("INSERT INTO user_account(id, email, display_name) VALUES (?, 'fixture@example.com', 'Fixture')", [user]);
  await db.run("INSERT INTO household(id, name, owner_user_id, onboarding_status) VALUES (?, 'Fixture household', ?, 'COMPLETED')", [hh, user]);
  await db.run("INSERT INTO household_membership(id, household_id, user_id, role_code, status) VALUES (?, ?, ?, 'OWNER', 'ACTIVE')", [id(), hh, user]);
  const kitchen = id();
  await db.run("INSERT INTO kitchen(id, household_id, name, kitchen_type, sort_order, created_source_code) VALUES (?, ?, ?, ?, 0, 'MANUAL')", [kitchen, hh, fx.kitchen.name, fx.kitchen.type]);
  const storage: Record<string, [string, string]> = {};
  for (const s of fx.storage) { const sid = id();
    await db.run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, ?, 0, 'MANUAL')", [sid, hh, kitchen, s.type, s.name, s.zone]);
    storage[s.key] = [sid, s.zone]; }
  for (const [table, code] of fx.equipment) await db.run(`INSERT INTO ${table}(id, household_id, kitchen_id, equipment_type_code, name, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')`, [id(), hh, kitchen, code, code]);
  for (const i of fx.inventory) {
    const item = (await db.get<any>('SELECT id, default_unit_code, shelf_life_ambient_days, shelf_life_chilled_days, shelf_life_frozen_days FROM item_master WHERE canonical_name = ? AND household_id IS NULL', [i.item]))!;
    const [sid, zone] = storage[i.storage];
    const life = item[zone === 'CHILLED' ? 'shelf_life_chilled_days' : zone === 'FROZEN' ? 'shelf_life_frozen_days' : 'shelf_life_ambient_days'];
    const dates = [...(i.expiresOn ? [i.expiresOn] : []), ...(life != null ? [addDays(today, life)] : [])].sort();
    const iid = id();
    await db.run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, quantity, unit_code, purchased_on, expires_on, use_soon_on, created_source_code) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, 'MANUAL')",
      [iid, hh, item.id, kitchen, sid, item.default_unit_code, today, i.expiresOn ?? null, dates[0] ?? null]);
    await db.run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, created_source_code) VALUES (?, ?, ?, 'MANUAL_ADD', ?, ?, 0, ?, 'MANUAL')",
      [id(), hh, iid, i.qty, item.default_unit_code, i.qty]);
  }
  for (const m of fx.members) { const mid = id(); members.push(mid);
    await db.run("INSERT INTO family_member(id, household_id, display_name, relationship, age_band, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')", [mid, hh, m.name, m.relationship, m.ageBand]);
    for (const a of m.allergies) await db.run("INSERT INTO member_allergy(id, household_id, member_id, allergen_code, severity) VALUES (?, ?, ?, ?, 'SEVERE')", [id(), hh, mid, a]);
    for (const d of m.diets) await db.run("INSERT INTO member_dietary_requirement(id, household_id, member_id, dietary_pattern_code, strictness) VALUES (?, ?, ?, ?, 'HARD')", [id(), hh, mid, d]);
    for (const h of m.health) await db.run("INSERT INTO member_health_food_requirement(id, household_id, member_id, requirement_type_code, strictness) VALUES (?, ?, ?, ?, 'SOFT')", [id(), hh, mid, h]); }

  // ---- reference engine on the fixture
  const port = new MatchingReadPort(db);
  const mem = await port.members(hh, members);
  const recipes = await port.candidates(hh);
  const ids = recipes.map(r => r.id);
  const ingredients = await port.ingredients(ids);
  const itemIds = [...new Set(ingredients.map(i => i.item_master_id))];
  const { ranked, excluded } = await rankRecipes({ today, useSoonDays: 3, maxMissing: 3, equipmentEvaluated: true, members: mem,
    constraints: await port.constraints(hh, members), recipes, ingredients, equipment: await port.equipmentRequirements(ids),
    facts: await port.itemFacts(itemIds), availability: await port.availability(hh, itemIds), methods: await port.cookingMethods(hh) }, new UnitConverter(db));
  const title = (rid: string) => recipes.find(r => r.id === rid)!.title;
  const sorted = (o: Record<string, string>) => JSON.stringify(Object.entries(o).sort());
  ok(sorted(Object.fromEntries(excluded.map(e => [title(e.recipeId), e.reason]))) === sorted(scenario.must_exclude), 'fixture reproduces the reference exclusions (with reasons)');
  ok(JSON.stringify(ranked.slice(0, 10).map(r => r.title).sort()) === JSON.stringify(scenario.must_recommend), 'fixture reproduces the reference recommendations');

  // ---- matching_service.dart persistence SQL
  const runId = id();
  await db.run("INSERT INTO match_run(id, household_id, requested_by_user_id, kitchen_id, meal_slot, status, engine_version, max_results, max_missing_items) VALUES (?, ?, ?, ?, ?, 'RUNNING', ?, ?, ?)", [runId, hh, user, null, null, 'wamwins-basic-matching/1.0.0', 5, 3]);
  for (const m of members) await db.run('INSERT INTO match_run_member(run_id, household_id, member_id) VALUES (?, ?, ?)', [runId, hh, m]);
  const resultIds: string[] = [];
  for (const [k, r] of ranked.slice(0, 5).entries()) { const rid = id(); resultIds.push(rid);
    await db.run('INSERT INTO match_result(id, run_id, household_id, recipe_id, rank, total_score, safety_passed, available_ingredient_ratio, missing_item_count, use_soon_item_count, equipment_ok) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, 1)',
      [rid, runId, hh, r.recipeId, k + 1, r.score, r.availableRatio, r.missing.length, r.useSoon.length]);
    for (const f of r.factors) await db.run('INSERT INTO match_result_factor(result_id, factor_code, score, weight, explanation) VALUES (?, ?, ?, ?, ?)', [rid, f.code, f.score, f.weight, f.explanation]);
    for (const [role, list] of [['AVAILABLE', r.available], ['MISSING', r.missing], ['USE_SOON', r.useSoon]] as const)
      for (const it of list) await db.run('INSERT INTO match_result_item(result_id, item_master_id, role, required_quantity, unit_code) VALUES (?, ?, ?, ?, ?)', [rid, it.itemMasterId, role, it.quantity, it.unit]); }
  for (const e of excluded) await db.run('INSERT OR IGNORE INTO match_exclusion(run_id, recipe_id, reason_code, member_id, detail) VALUES (?, ?, ?, ?, ?)', [runId, e.recipeId, e.reason, e.memberId ?? null, e.detail]);
  await db.run("UPDATE match_run SET status = 'COMPLETED', candidate_count = ?, excluded_count = ?, duration_ms = ?, completed_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [recipes.length, excluded.length, 1, runId]);
  ok(true, 'match run, results, factors, items and exclusions saved within all constraints');

  // ---- meal_service.dart cooking SQL (MEAL_USAGE through the ledger triggers)
  const mr = (await db.get<any>('SELECT recipe_id, run_id FROM match_result WHERE id = ?', [resultIds[0]]))!;
  const recipe = (await db.get<any>('SELECT title, servings FROM recipe_master WHERE id = ?', [mr.recipe_id]))!;
  const units = new UnitConverter(db), mealId = id(), r4 = (v: number) => Math.round(v * 10000) / 10000;
  await db.run("INSERT INTO meal_record(id, household_id, recipe_id, match_result_id, title, meal_slot, meal_date, servings, status, confirmed_by_user_id, confirmed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'CONFIRMED', ?, strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
    [mealId, hh, mr.recipe_id, resultIds[0], recipe.title, null, today, recipe.servings, user]);
  for (const m of await db.all<any>('SELECT member_id FROM match_run_member WHERE run_id = ?', [mr.run_id])) await db.run('INSERT INTO meal_participant(meal_record_id, household_id, member_id) VALUES (?, ?, ?)', [mealId, hh, m.member_id]);
  let usages = 0;
  for (const ing of await db.all<any>('SELECT ri.id, ri.item_master_id, ri.quantity, ri.unit_code, i.canonical_name AS name FROM recipe_ingredient ri JOIN item_master i ON i.id = ri.item_master_id WHERE ri.recipe_id = ? AND ri.is_optional = 0 ORDER BY ri.ordinal', [mr.recipe_id])) {
    let remaining = r4(ing.quantity);
    for (const lot of await db.all<any>("SELECT id, quantity, unit_code FROM inventory_item WHERE household_id = ? AND item_master_id = ? AND deleted_at IS NULL AND quantity > 0 ORDER BY COALESCE(use_soon_on, expires_on, best_before_on, '9999-12-31'), created_at LIMIT 20", [hh, ing.item_master_id])) {
      if (remaining <= 1e-9) break;
      const need = await units.convert(remaining, ing.unit_code, lot.unit_code, ing.item_master_id);
      if (need === undefined) continue;
      const take = r4(Math.min(need, lot.quantity)), txn = id();
      await db.run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, actor_user_id, meal_record_id, created_source_code, idempotency_key) VALUES (?, ?, ?, 'MEAL_USAGE', ?, ?, ?, ?, ?, ?, 'MANUAL', ?)",
        [txn, hh, lot.id, -take, lot.unit_code, lot.quantity, r4(lot.quantity - take), user, mealId, `meal:${mealId}:${ing.id}:${lot.id}`]);
      await db.run('INSERT INTO consumption_record(id, household_id, meal_record_id, item_master_id, quantity, unit_code, inventory_transaction_id) VALUES (?, ?, ?, ?, ?, ?, ?)', [id(), hh, mealId, ing.item_master_id, take, lot.unit_code, txn]);
      remaining -= (await units.convert(take, lot.unit_code, ing.unit_code, ing.item_master_id)) ?? 0; usages++;
    }
  }
  await db.run("UPDATE meal_record SET inventory_deducted_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [mealId]);
  await db.run("UPDATE match_result SET status = 'ACCEPTED' WHERE id = ?", [resultIds[0]]);
  ok(usages > 0, `cooking "${recipe.title}" posted ${usages} MEAL_USAGE transactions accepted by the ledger triggers`);
  const left = await db.get<any>("SELECT i.quantity FROM inventory_item i JOIN item_master m ON m.id = i.item_master_id WHERE m.canonical_name = 'Garlic' AND i.household_id = ?", [hh]);
  ok(left!.quantity < 12, `garlic deducted (now ${left!.quantity})`);
  console.log(failures ? `${failures} check(s) failed` : 'Matching fixture + Flutter SQL verified against the reference');
  process.exit(failures ? 1 : 0);
})();
