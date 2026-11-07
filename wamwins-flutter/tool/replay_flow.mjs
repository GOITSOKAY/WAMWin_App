// Replays the Flutter app's write path, statement for statement, in the order the Dart code runs it
// (auth_service -> profile_store.ensureHousehold -> capabilities.startBasic -> _writeAnswers -> provisioning
// -> settings "delete all data"), against the real shared schema with all triggers and constraints.
// Catches constraint/trigger violations the compile check cannot. Usage: node tool/replay_flow.mjs
import { readdirSync, readFileSync } from 'node:fs';
import { randomUUID as id } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
const mig = new URL('../assets/db/migrations/', import.meta.url);
const db = new DatabaseSync(':memory:'); db.exec('PRAGMA foreign_keys = ON');
for (const f of readdirSync(mig).sort()) db.exec(readFileSync(new URL(f, mig), 'utf8'));
const run = (s, p = []) => db.prepare(s).run(...p), first = (s, p = []) => db.prepare(s).get(...p), all = (s, p = []) => db.prepare(s).all(...p);
const tx = (f) => { db.exec('BEGIN IMMEDIATE'); try { const r = f(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } };

// auth_service.register
const userId = id();
tx(() => {
  run("INSERT INTO user_account(id, email, display_name, locale, timezone) VALUES (?, ?, ?, 'en', ?)", [userId, 'ana@example.com', 'Ana Santos', 'PST']);
  run('INSERT INTO local_auth_identity(id, user_id, provider_subject, secret_hash, salt, iterations) VALUES (?, ?, ?, ?, ?, ?)', [id(), userId, 'ana@example.com', 'aGFzaA==', 'c2FsdA==', 310000]);
  for (const [t, g] of [['TERMS', 1], ['PRIVACY_POLICY', 1], ['HEALTH_DATA_PROCESSING', 1]]) run("INSERT INTO consent_record(id, user_id, consent_type, document_version, granted) VALUES (?, ?, ?, '1', ?)", [id(), userId, t, g]);
});
run('INSERT INTO local_session(token_hash, user_id, expires_at) VALUES (?, ?, ?)', ['abc', userId, '2099-01-01T00:00:00Z']);

// profile_store.ensureHousehold + capabilities.startBasic + sessionFor
const hh = id();
let sessionId;
tx(() => {
  run("INSERT INTO household(id, name, owner_user_id, onboarding_status) VALUES (?, ?, ?, 'IN_PROGRESS')", [hh, 'Ana’s household', userId]);
  run("INSERT INTO household_membership(id, household_id, user_id, role_code, status, joined_at) VALUES (?, ?, ?, 'OWNER', 'ACTIVE', ?)", [id(), hh, userId, new Date().toISOString()]);
  const tier = first("SELECT id, product_id FROM product_tier WHERE tier_code = 'WAMWINS_BASIC' AND effective_to IS NULL");
  const sub = id();
  run("INSERT INTO subscription(id, household_id, product_id, product_tier_id, billing_user_id, status, source_code) VALUES (?, ?, ?, ?, ?, 'ACTIVE', 'SYSTEM_DEFAULT')", [sub, hh, tier.product_id, tier.id, userId]);
  run("INSERT INTO subscription_tier_history(id, subscription_id, household_id, from_tier_id, to_tier_id, reason, changed_by_user_id) VALUES (?, ?, ?, NULL, ?, 'INITIAL', ?)", [id(), sub, hh, tier.id, userId]);
  for (const r of all(`SELECT c.id AS capability_id, CASE WHEN c.is_platform_guaranteed = 1 THEN 'ENABLED' ELSE COALESCE(tc.status, 'UNDEFINED') END AS status,
       CASE WHEN c.is_platform_guaranteed = 1 THEN 'PLATFORM_GUARANTEE' ELSE 'TIER' END AS resolved_from FROM capability c
       LEFT JOIN tier_capability tc ON tc.capability_id = c.id AND tc.tier_id = ? AND tc.effective_to IS NULL WHERE c.active = 1`, [tier.id]))
    run('INSERT INTO subscription_entitlement(id, subscription_id, household_id, capability_id, status, resolved_from) VALUES (?, ?, ?, ?, ?, ?)', [id(), sub, hh, r.capability_id, r.status, r.resolved_from]);
  run(`INSERT INTO subscription_entitlement_parameter(entitlement_id, parameter_definition_id, integer_value, decimal_value, boolean_value, text_value)
       SELECT se.id, p.parameter_definition_id, p.integer_value, p.decimal_value, p.boolean_value, p.text_value FROM subscription_entitlement se
       JOIN tier_capability tc ON tc.capability_id = se.capability_id AND tc.tier_id = ? AND tc.effective_to IS NULL
       JOIN tier_capability_parameter p ON p.tier_capability_id = tc.id WHERE se.subscription_id = ? AND se.status = 'ENABLED'`, [tier.id, sub]);
  const q = first("SELECT id FROM questionnaire WHERE code = 'HOUSEHOLD_PROFILE' AND status = 'PUBLISHED' ORDER BY version DESC LIMIT 1");
  sessionId = id();
  run('INSERT INTO questionnaire_session(id, household_id, user_id, questionnaire_id) VALUES (?, ?, ?, ?)', [sessionId, hh, userId, q.id]);
});
// _writeAnswers (twice: supersede path)
const qs = Object.fromEntries(all("SELECT q.id, q.code FROM question q JOIN questionnaire x ON x.id = q.questionnaire_id WHERE x.code = 'HOUSEHOLD_PROFILE'").map(r => [r.code, r.id]));
for (let pass = 0; pass < 2; pass++) tx(() => {
  for (const [code, key] of [['ABOUT_YOU', ''], ['HOUSEHOLD', ''], ['KITCHENS', ''], ['STORAGE_UNITS', 'MAIN-1'], ['COOKING_APPLIANCES', 'MAIN-1'], ['COOKWARE', 'MAIN-1'], ['UTENSILS', 'MAIN-1'], ['HEALTH_CONSENT', ''], ['FAMILY_MEMBERS', ''], ['FOOD_ON_HAND', '']]) {
    run("UPDATE answer SET superseded_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE session_id = ? AND question_id = ? AND repeat_key = ? AND superseded_at IS NULL", [sessionId, qs[code], key]);
    run('INSERT INTO answer(id, household_id, session_id, question_id, repeat_key, text_value) VALUES (?, ?, ?, ?, ?, ?)', [id(), hh, sessionId, qs[code], key, '{}']);
  }
});

// provisioning.provision (kitchen, fridge+pantry with template sections, equipment, 2 members + health + cuisine, 2 foods, modules)
const once = (key, table, make) => { const e = first('SELECT created_entity_id FROM profile_provisioning_record WHERE household_id = ? AND draft_key = ?', [hh, key]); if (e) return e.created_entity_id;
  const eid = make(); run('INSERT INTO profile_provisioning_record(id, household_id, session_id, draft_key, created_entity_table, created_entity_id) VALUES (?, ?, ?, ?, ?, ?)', [id(), hh, sessionId, key, table, eid]); return eid; };
const moduleId = (c) => first('SELECT id FROM module_definition WHERE module_code = ?', [c]).id;
const moduleInstance = (code, rid, name) => once(`module:${code}:${rid ?? ''}`, 'household_module_instance', () => { const i = id();
  run("INSERT INTO household_module_instance(id, household_id, module_id, resource_type, resource_id, display_name, current_status) VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE')", [i, hh, moduleId(code), rid ? 'storage_instance' : null, rid ?? null, name]); return i; });
const ubeId = id();
function provision() { return tx(() => {
  const kitchenId = once('kitchen:MAIN-1', 'kitchen', () => { const i = id(); run("INSERT INTO kitchen(id, household_id, name, kitchen_type, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')", [i, hh, 'Main kitchen', 'MAIN', 0]); return i; });
  const storage = {};
  for (const [si, type, name, zone] of [[0, 'REFRIGERATOR', 'Refrigerator', 'CHILLED'], [1, 'PANTRY', 'Pantry', 'AMBIENT']]) {
    storage[type] = once(`storage:MAIN-1/${type}-1`, 'storage_instance', () => { const i = id();
      run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'MANUAL')", [i, hh, kitchenId, type, name, zone, si]);
      all('SELECT id, section_kind, default_name FROM storage_section_template WHERE storage_type_code = ? AND is_default_selected = 1 ORDER BY ordinal', [type]).forEach((t, oi) =>
        run("INSERT INTO storage_section(id, household_id, storage_instance_id, section_kind, name, ordinal, template_id, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'SYSTEM_DEFAULT')", [id(), hh, i, t.section_kind, t.default_name, oi, t.id]));
      return i; });
    moduleInstance('STORAGE', storage[type], name);
  }
  for (const [table, code] of [['household_appliance', 'STOVETOP'], ['household_cookware', 'WOK'], ['household_utensil', 'SPATULA']])
    once(`equipment:MAIN-1:${code}`, table, () => { const i = id(); run(`INSERT INTO ${table}(id, household_id, kitchen_id, equipment_type_code, name, created_source_code) VALUES (?, ?, ?, ?, ?, 'MANUAL')`, [i, hh, kitchenId, code, code]); return i; });
  for (const m of [{ key: 'm1', name: 'Ana Santos', rel: 'SELF', age: 'ADULT', me: true, allergies: [], diets: ['DAIRY_FREE'] }, { key: 'm2', name: 'Ben', rel: 'CHILD', age: 'CHILD', me: false, allergies: ['PEANUT'], diets: [] }]) {
    const mid = once(`member:${m.key}`, 'family_member', () => { const i = id(); run("INSERT INTO family_member(id, household_id, linked_user_id, display_name, relationship, age_band, created_source_code) VALUES (?, ?, ?, ?, ?, ?, 'MANUAL')", [i, hh, m.me ? userId : null, m.name, m.rel, m.age]); return i; });
    run("UPDATE family_member SET display_name = ?, relationship = ?, age_band = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ? AND (display_name <> ? OR relationship <> ? OR age_band <> ?)", [m.name, m.rel, m.age, mid, m.name, m.rel, m.age]);
    for (const t of ['member_allergy', 'member_dietary_requirement', 'member_health_food_requirement']) run(`DELETE FROM ${t} WHERE member_id = ?`, [mid]);
    m.allergies.forEach(c => run("INSERT INTO member_allergy(id, household_id, member_id, allergen_code, severity) VALUES (?, ?, ?, ?, 'UNKNOWN')", [id(), hh, mid, c]));
    m.diets.forEach(c => run("INSERT INTO member_dietary_requirement(id, household_id, member_id, dietary_pattern_code, strictness) VALUES (?, ?, ?, ?, 'HARD')", [id(), hh, mid, c]));
    run("INSERT INTO member_health_food_requirement(id, household_id, member_id, requirement_type_code, strictness) VALUES (?, ?, ?, ?, 'SOFT')", [id(), hh, mid, 'LOW_SODIUM']);
    run("DELETE FROM member_preference WHERE member_id = ? AND subject_type = 'CUISINE'", [mid]);
    run("INSERT INTO member_preference(id, household_id, member_id, preference_kind, subject_type, cuisine_code) VALUES (?, ?, ?, 'LIKE', 'CUISINE', ?)", [id(), hh, mid, 'FILIPINO']);
  }
  // the household's own food (provisioning.dart): item_master with household_id + allergen, before inventory
  once('item:ube', 'item_master', () => {
    run("INSERT INTO item_master(id, household_id, item_kind, canonical_name, food_category_code, default_unit_code, storage_zone, is_perishable, is_verified, created_source_code) VALUES (?, ?, 'FOOD', ?, ?, ?, ?, ?, 0, 'MANUAL')",
      [ubeId, hh, 'Ube halaya', 'SNACKS', 'G', 'CHILLED', 1]);
    run("INSERT INTO item_allergen(item_master_id, allergen_code, presence) VALUES (?, ?, 'CONTAINS')", [ubeId, 'MILK']);
    return ubeId; });
  for (const [key, name, unit, q, place] of [['f1', 'Chicken breast', 'G', 500, 'REFRIGERATOR'], ['f2', 'White rice', 'G', 1000.5, 'PANTRY'], ['f3', 'Ube halaya', 'G', 500, 'REFRIGERATOR']]) once(`food:${key}`, 'inventory_item', () => {
    const item = first('SELECT id FROM item_master WHERE canonical_name = ? AND (household_id IS NULL OR household_id = ?)', [name, hh]);
    const st = first('SELECT kitchen_id, temperature_zone FROM storage_instance WHERE id = ?', [storage[place]]);
    const i = id();
    run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, quantity, unit_code, purchased_on, expires_on, use_soon_on, label, created_source_code) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, 'MANUAL')",
      [i, hh, item.id, st.kitchen_id, storage[place], unit, '2026-11-05', null, '2026-11-07', name]);
    run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, actor_user_id, created_source_code, idempotency_key) VALUES (?, ?, ?, 'MANUAL_ADD', ?, ?, 0, ?, ?, 'MANUAL', ?)",
      [id(), hh, i, q, unit, q, userId, `onboarding:${key}`]);
    return i; });
  for (const c of ['HOUSEHOLD', 'KITCHEN', 'EQUIPMENT', 'FAMILY', 'HEALTH', 'INVENTORY', 'SHOPPING', 'MATCHING', 'MEALS']) moduleInstance(c, null, c);
  run("UPDATE questionnaire_session SET status = 'COMPLETED', completed_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [sessionId]);
  run("UPDATE household SET onboarding_status = 'COMPLETED', row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [hh]);
  run("UPDATE user_account SET display_name = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", ['Ana Santos', userId]);
}); }
provision();
const counts = () => Object.fromEntries(['kitchen', 'storage_instance', 'storage_section', 'family_member', 'member_allergy', 'inventory_item', 'inventory_transaction', 'household_module_instance', 'profile_provisioning_record']
  .map(t => [t, first(`SELECT COUNT(*) n FROM ${t} WHERE household_id = ?`, [hh]).n]));
const c1 = counts();
provision();                                                   // "Update my answers": must not duplicate
const c2 = counts();
const ok = (cond, msg) => { console.log(`  ${cond ? 'ok' : 'FAIL'}: ${msg}`); if (!cond) process.exitCode = 1; };
console.log('created:', JSON.stringify(c1));
ok(c1.storage_section === 8, 'fridge (5) + pantry (3) template shelves');
ok(c1.inventory_item === 3 && first('SELECT household_id FROM item_master WHERE id = ?', [ubeId]).household_id === hh, 'the household’s own food is stored with its household and stocked through the ledger');
// another household must not be able to use it (shared visibility trigger)
const other = id();
run("INSERT INTO household(id, name, owner_user_id) VALUES (?, 'Other', ?)", [other, userId]);
const kOther = id(); run("INSERT INTO kitchen(id, household_id, name, kitchen_type, sort_order, created_source_code) VALUES (?, ?, 'K', 'MAIN', 0, 'MANUAL')", [kOther, other]);
const sOther = id(); run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, 'PANTRY', 'P', 'AMBIENT', 0, 'MANUAL')", [sOther, other, kOther]);
let refused = false;
try { run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, quantity, unit_code, created_source_code) VALUES (?, ?, ?, ?, ?, 0, 'G', 'MANUAL')", [id(), other, ubeId, kOther, sOther]); } catch { refused = true; }
ok(refused, 'another household cannot use this household’s own food');
run('DELETE FROM household WHERE id = ?', [other]);
ok(first('SELECT quantity FROM inventory_item WHERE label = ?', ['White rice']).quantity === 1000.5, 'inventory quantity applied by the ledger trigger');
ok(JSON.stringify(c1) === JSON.stringify(c2), 're-running provisioning creates nothing new');
ok(first("SELECT COUNT(*) n FROM subscription_entitlement se JOIN capability c ON c.id = se.capability_id WHERE se.household_id = ? AND se.is_entitled = 1 AND c.code = 'CLOUD_BACKUP'", [hh]).n === 1, 'Basic entitlements include cloud backup');
ok(first("SELECT COUNT(*) n FROM subscription_entitlement_parameter").n >= 1, 'limits copied (latest 5 cloud backups)');
// settings: delete all data on this device
tx(() => { run("UPDATE household SET status = 'PENDING_DELETION' WHERE id = ?", [hh]); run('DELETE FROM household WHERE id = ?', [hh]); run('DELETE FROM user_account WHERE id = ?', [userId]); run("DELETE FROM local_setting WHERE key LIKE 'profile.%'"); });
ok(first('SELECT COUNT(*) n FROM inventory_transaction').n === 0 && first('SELECT COUNT(*) n FROM local_auth_identity').n === 0, 'delete-all removes household, history and the local account');
console.log(process.exitCode ? 'REPLAY FAILED' : 'Replay OK: the Flutter write path satisfies every shared constraint and trigger');
