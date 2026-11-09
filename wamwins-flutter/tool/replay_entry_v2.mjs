// Replays the Flutter Entry Module v2 save (lib/inquiry/provisioning_v2.dart), statement for statement, against the shared
// schema with every trigger and constraint; then saves again and proves nothing is duplicated. Usage: node tool/replay_entry_v2.mjs
import { readdirSync, readFileSync } from 'node:fs';
import { randomUUID as id } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
const mig = new URL('../assets/db/migrations/', import.meta.url);
const db = new DatabaseSync(':memory:'); db.exec('PRAGMA foreign_keys = ON');
for (const f of readdirSync(mig).sort()) db.exec(readFileSync(new URL(f, mig), 'utf8'));
const run = (s, p = []) => db.prepare(s).run(...p), first = (s, p = []) => db.prepare(s).get(...p), all = (s, p = []) => db.prepare(s).all(...p);
const count = (s, p = []) => Object.values(first(s, p))[0];
let fails = 0; const ok = (c, m) => { console.log(`  ${c ? 'ok' : 'FAIL'}: ${m}`); if (!c) fails++; };

const user = id(), hh = id();
run("INSERT INTO user_account(id, email, display_name) VALUES (?, 'ana@example.com', 'Ana')", [user]);
run("INSERT INTO household(id, name, owner_user_id, onboarding_status) VALUES (?, 'Ana’s household', ?, 'IN_PROGRESS')", [hh, user]);
run("UPDATE household SET name = ?, nickname = ?, member_count = ?, eater_count = ? WHERE id = ?", ['Ana’s household', 'The Santos', 3, 2, hh]);
const q2 = first("SELECT id FROM questionnaire WHERE code = 'HOUSEHOLD_PROFILE' AND version = 2").id, session = id();
run('INSERT INTO questionnaire_session(id, household_id, user_id, questionnaire_id) VALUES (?, ?, ?, ?)', [session, hh, user, q2]);
for (const code of ['ABOUT_YOU', 'KITCHENS', 'FOOD_ON_HAND']) run("INSERT INTO answer(id, household_id, session_id, question_id, repeat_key, text_value) SELECT ?, ?, ?, q.id, '', '{}' FROM question q WHERE q.questionnaire_id = ? AND q.code = ?", [id(), hh, session, q2, code]);
const photo = id();
run("INSERT INTO media_blob(id, household_id, mime_type, bytes) VALUES (?, ?, 'image/jpeg', x'FFD8FF')", [id(), hh]);
run("INSERT INTO location_media(id, household_id, location_draft_key, blob_ref, mime_type, title, uploaded_by_user_id, source_type) VALUES (?, ?, 'storage:MAIN-1/REFRIGERATOR-1', 'db:media_blob/x', 'image/jpeg', 'Fridge door', ?, 'MANUAL')", [photo, hh, user]);
const rice = first("SELECT id FROM item_master WHERE canonical_name = 'White rice' AND household_id IS NULL").id;
const ube = id();

function save() {
  db.exec('BEGIN');
  const once = (key, table, make) => { const e = first('SELECT created_entity_id FROM profile_provisioning_record WHERE household_id = ? AND draft_key = ?', [hh, key]); if (e) return e.created_entity_id;
    const x = make(); run('INSERT INTO profile_provisioning_record(id, household_id, session_id, draft_key, created_entity_table, created_entity_id) VALUES (?, ?, ?, ?, ?, ?)', [id(), hh, session, key, table, x]); return x; };
  const self = once('member:me', 'family_member', () => { const x = id(); run("INSERT INTO family_member(id, household_id, linked_user_id, display_name, relationship, age_band, created_source_code) VALUES (?, ?, ?, ?, 'SELF', 'ADULT', 'MANUAL')", [x, hh, user, 'Ana']); return x; });
  run("UPDATE family_member SET display_name = ?, household_role_code = ?, cooking_responsibility = ? WHERE id = ?", ['Ana', 'MOTHER', 'PRIMARY', self]);
  const ids = {};
  for (const [ki, [key, kind, legacy, name, storage]] of [['MAIN-1', 'MAIN', 'MAIN', 'Main Kitchen', [['MAIN-1/REFRIGERATOR-1', 'REFRIGERATOR', 'CHILLED']]], ['BARN-1', 'BARN', 'OTHER', 'Barn Kitchen', [['BARN-1/PANTRY-1', 'PANTRY', 'AMBIENT']]]].entries()) {
    const k = once(`kitchen:${key}`, 'kitchen', () => { const x = id(); run("INSERT INTO kitchen(id, household_id, name, kitchen_type, kitchen_kind_code, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, ?, 'MANUAL')", [x, hh, name, legacy, kind, ki]); return x; });
    ids[`kitchen:${key}`] = { kitchen: k };
    for (const [si, [skey, type, zone]] of storage.entries()) {
      const sid = once(`storage:${skey}`, 'storage_instance', () => { const x = id(); run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'MANUAL')", [x, hh, k, type, type, zone, si]); return x; });
      ids[`storage:${skey}`] = { kitchen: k, storage: sid };
      // follow-up sections + nested own sections + a container (same keys as sectionOptions)
      const secs = type === 'REFRIGERATOR' ? [[`${skey}#SHELVES-1`, 'SHELF', 'Shelf 1', null], [`${skey}#FREEZER_SECTION`, 'ZONE', 'Freezer section', null]]
        : [[`${skey}#SHELVES-1`, 'SHELF', 'Shelf 1', null], [`${skey}#c:bin`, 'BIN', 'Snack bin', null], [`${skey}#c:inner`, 'COMPARTMENT', 'Snack bin › Left side', `${skey}#c:bin`]];
      secs.forEach(([sk, kind2, nm, parentKey], oi) => {
        const parent = parentKey ? ids[`section:${parentKey}`].section : null;
        const x = once(`section:${sk}`, 'storage_section', () => { const y = id(); run("INSERT INTO storage_section(id, household_id, storage_instance_id, parent_section_id, section_kind, name, ordinal, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'MANUAL')", [y, hh, sid, parent, kind2, nm.split(' › ').pop(), oi]); return y; });
        ids[`section:${sk}`] = { kitchen: k, storage: sid, section: x };
      });
      if (type === 'PANTRY') { const parent = ids[`section:${skey}#c:bin`].section;
        const c = once(`container:${skey}#c:jar`, 'household_container', () => { const y = id(); run("INSERT INTO household_container(id, household_id, kitchen_id, storage_instance_id, storage_section_id, equipment_type_code, name, created_source_code) VALUES (?, ?, ?, ?, ?, 'AIRTIGHT_CONTAINER', ?, 'MANUAL')", [y, hh, k, sid, parent, 'Container A']); return y; });
        ids[`container:${skey}#c:jar`] = { kitchen: k, storage: sid, section: parent, container: c }; }
    }
  }
  for (const m of all('SELECT id, location_draft_key FROM location_media WHERE household_id = ? AND location_draft_key IS NOT NULL AND kitchen_id IS NULL', [hh])) { const at = ids[m.location_draft_key];
    if (at) run("UPDATE location_media SET kitchen_id = ?, storage_instance_id = ?, storage_section_id = ?, container_id = ? WHERE id = ?", [at.kitchen, at.storage, at.section ?? null, at.container ?? null, m.id]); }
  for (const [key, code, name, link] of [['MAIN-1:REFRIGERATOR', 'REFRIGERATOR', 'Refrigerator', 'MAIN-1/REFRIGERATOR-1'], ['MAIN-1:RICE_COOKER', 'RICE_COOKER', 'Rice cooker', null], ['MAIN-1:waffle', null, 'Waffle maker', null]]) {
    const vals = [name, code === 'RICE_COOKER' ? 'Zojirushi' : null, null, null, '2024-05-01', null, null, 'OUT_OF_SERVICE', null, link ? ids[`storage:${link}`].storage : null];
    const a = once(`appliance:MAIN-1:${key}`, 'household_appliance', () => { const x = id(); run("INSERT INTO household_appliance(id, household_id, kitchen_id, equipment_type_code, name, brand, model, serial_number, purchased_on, warranty_end_on, location_note, condition, notes, storage_instance_id, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'MANUAL')", [x, hh, ids['kitchen:MAIN-1'].kitchen, code ?? 'CUSTOM_APPLIANCE', ...vals]); return x; });
    run("UPDATE household_appliance SET name = ?, brand = ?, model = ?, serial_number = ?, purchased_on = ?, warranty_end_on = ?, location_note = ?, condition = ?, notes = ?, storage_instance_id = ? WHERE id = ?", [...vals, a]);
  }
  for (const [code, cat, name, q] of [['WOK', 'COOKWARE', 'Wok', 1], ['FORK', 'FLATWARE', 'Forks', 8], [null, 'OTHER', 'Pizza stone', 1]])
    once(`kitchenware:MAIN-1:${code ?? 'pizza'}`, 'household_kitchenware', () => { const x = id(); run("INSERT INTO household_kitchenware(id, household_id, kitchen_id, kitchenware_type_code, category, name, quantity, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 'MANUAL')", [x, hh, ids['kitchen:MAIN-1'].kitchen, code, cat, name, q]); return x; });
  const ben = once('member:ben', 'family_member', () => { const x = id(); run("INSERT INTO family_member(id, household_id, display_name, relationship, age_band, created_source_code) VALUES (?, ?, 'Ben', 'CHILD', 'CHILD', 'MANUAL')", [x, hh]); return x; });
  for (const t of ['member_allergy', 'member_intolerance', 'member_dietary_requirement', 'member_health_food_requirement', 'member_food_rule']) run(`DELETE FROM ${t} WHERE member_id = ?`, [ben]);
  run("INSERT INTO member_allergy(id, household_id, member_id, allergen_code, severity) VALUES (?, ?, ?, 'PEANUT', 'UNKNOWN')", [id(), hh, ben]);
  run("INSERT INTO member_intolerance(id, household_id, member_id, allergen_code, severity, handling) VALUES (?, ?, ?, 'MILK', 'MODERATE', 'EXCLUDE')", [id(), hh, ben]);
  run("INSERT INTO member_food_rule(id, household_id, member_id, rule_kind, meal_context, label, item_master_id, food_category_code) VALUES (?, ?, ?, 'PRIORITIZE', 'ANY', 'White rice', ?, NULL)", [id(), hh, ben, rice]);
  run("INSERT INTO member_food_rule(id, household_id, member_id, rule_kind, meal_context, label, item_master_id, food_category_code) VALUES (?, ?, ?, 'NOTE', 'BREAKFAST', 'No caffeine', NULL, NULL)", [id(), hh, ben]);
  once(`item:${ube}`, 'item_master', () => { run("INSERT INTO item_master(id, household_id, item_kind, canonical_name, food_category_code, default_unit_code, storage_zone, is_perishable, is_verified, created_source_code) VALUES (?, ?, 'FOOD', 'Ube halaya', 'SNACKS', 'OZ', 'CHILLED', 1, 0, 'MANUAL')", [ube, hh]);
    run("INSERT INTO item_allergen(item_master_id, allergen_code, presence) VALUES (?, 'MILK', 'CONTAINS')", [ube]); return ube; });
  for (const [key, item, sk, unit, q, place, container] of [['f1', rice, 'BARN-1/PANTRY-1', 'LB', 2, 'BARN-1/PANTRY-1#c:inner', 'BARN-1/PANTRY-1#c:jar'], ['f2', ube, 'MAIN-1/REFRIGERATOR-1', 'OZ', 12, 'MAIN-1/REFRIGERATOR-1#SHELVES-1', null]])
    once(`food:${key}`, 'inventory_item', () => { const at = ids[`storage:${sk}`], x = id();
      run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, storage_section_id, container_id, quantity, unit_code, purchased_on, opened_on, best_before_on, use_by_on, expires_on, use_soon_on, brand, packaging_code, package_size, package_unit_code, item_condition, notes, label, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
        [x, hh, item, at.kitchen, at.storage, ids[`section:${place}`]?.section ?? null, container ? ids[`container:${container}`].container : null, unit, '2026-11-09', key === 'f2' ? '2026-11-09' : null, '2027-01-01', null, '2027-02-01', '2027-01-01', 'Mahatma', 'BAG', 5, 'LB', 'GOOD', 'Top shelf', key]);
      run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, actor_user_id, created_source_code, idempotency_key) VALUES (?, ?, ?, 'MANUAL_ADD', ?, ?, 0, ?, ?, 'MANUAL', ?)", [id(), hh, x, q, unit, q, user, `onboarding:${key}`]);
      return x; });
  run("UPDATE questionnaire_session SET status = 'COMPLETED', completed_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?", [session]);
  run("UPDATE household SET onboarding_status = 'COMPLETED' WHERE id = ?", [hh]);
  db.exec('COMMIT');
}
save();
const tables = ['kitchen', 'storage_instance', 'storage_section', 'household_container', 'household_appliance', 'household_kitchenware', 'family_member', 'member_allergy', 'member_intolerance', 'member_food_rule', 'inventory_item', 'inventory_transaction', 'item_master'];
const snap = () => Object.fromEntries(tables.map(t => [t, count(`SELECT COUNT(*) FROM ${t} WHERE household_id = ?`, [hh])]));
const a = snap(); save(); const b = snap();
console.log('created:', JSON.stringify(a));
ok(first("SELECT kitchen_kind_code k, kitchen_type t FROM kitchen WHERE name = 'Barn Kitchen'").k === 'BARN', 'Barn Kitchen: new kind, legacy type OTHER passes the old constraint');
const inner = first("SELECT depth, path, parent_section_id FROM storage_section WHERE name = 'Left side'");
ok(inner.depth === 1 && inner.parent_section_id && inner.path.includes(first("SELECT id FROM storage_section WHERE name = 'Snack bin'").id), 'nested section: depth and materialized path set by the shared triggers');
ok(!!first("SELECT 1 x FROM location_media WHERE id = ? AND storage_instance_id IS NOT NULL AND kitchen_id IS NOT NULL", [photo]), 'reference photo linked to its storage unit');
ok(!!first("SELECT 1 x FROM household_appliance WHERE equipment_type_code = 'REFRIGERATOR' AND storage_instance_id IS NOT NULL") && !!first("SELECT 1 x FROM household_appliance WHERE equipment_type_code = 'CUSTOM_APPLIANCE'"), 'appliances: refrigerator cross-reference and a custom appliance');
ok(count("SELECT COUNT(*) FROM v_household_cooking_capability WHERE household_id = ? AND cooking_method_code = 'RICE_COOK'", [hh]) === 0,
  'cooking capability follows appliance condition: the rice cooker saved as “not working” provides nothing');
run("UPDATE household_appliance SET condition = 'WORKING' WHERE equipment_type_code = 'RICE_COOKER' AND household_id = ?", [hh]);
ok(count("SELECT COUNT(*) FROM v_household_cooking_capability WHERE household_id = ? AND cooking_method_code IN ('RICE_COOK','STEAM')", [hh]) === 2,
  'widened cooking-capability view (appliances + cookware + utensils + kitchenware) reports the working rice cooker');
const ri = first("SELECT * FROM inventory_item WHERE label = 'f1'");
ok(ri.quantity === 2 && ri.container_id && ri.storage_section_id && ri.brand === 'Mahatma' && ri.item_condition === 'GOOD', 'food: quantity via the ledger trigger, placed in a container inside a section, details kept');
ok(first("SELECT lifecycle_status s FROM inventory_item WHERE label = 'f2'").s === 'OPENED', 'opened food gets the OPENED status from the ledger trigger');
ok(JSON.stringify(a) === JSON.stringify(b), 'saving again creates nothing new');
console.log(fails ? `${fails} Entry v2 check(s) failed` : 'Entry v2 replay OK: the Flutter save satisfies every shared constraint and trigger');
process.exit(fails ? 1 : 0);
