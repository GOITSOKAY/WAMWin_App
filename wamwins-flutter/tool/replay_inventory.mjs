// Replays the Flutter inventory service (lib/inventory/inventory_service.dart) statement for statement against the shared
// schema with all triggers: every action, the statuses the triggers set, the filters, and a full ledger audit.
// Usage (from mobile/): node tool/replay_inventory.mjs
import { readdirSync, readFileSync } from 'node:fs';
import { randomUUID as id } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
const mig = new URL('../assets/db/migrations/', import.meta.url);
const db = new DatabaseSync(':memory:'); db.exec('PRAGMA foreign_keys = ON');
for (const f of readdirSync(mig).sort()) db.exec(readFileSync(new URL(f, mig), 'utf8'));
const run = (s, p = []) => db.prepare(s).run(...p), first = (s, p = []) => db.prepare(s).get(...p), all = (s, p = []) => db.prepare(s).all(...p);
const count = (s, p = []) => Object.values(first(s, p))[0];
const tx = (f) => { db.exec('SAVEPOINT x'); try { const r = f(); db.exec('RELEASE x'); return r; } catch (e) { db.exec('ROLLBACK TO x'); db.exec('RELEASE x'); throw e; } };
const r4 = (v) => Math.round(v * 10000) / 10000;
const today = new Date().toISOString().slice(0, 10), addDays = (d, n) => { const x = new Date(`${d}T00:00:00Z`); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
let fails = 0; const ok = (c, m) => { console.log(`  ${c ? 'ok' : 'FAIL'}: ${m}`); if (!c) fails++; };

// household with a fridge (2 shelves) and a pantry
const user = id(), hh = id(), k = id(), fridge = id(), pantry = id(), shelf = id();
run("INSERT INTO user_account(id, email, display_name) VALUES (?, 'a@b.c', 'A')", [user]);
run("INSERT INTO household(id, name, owner_user_id) VALUES (?, 'H', ?)", [hh, user]);
run("INSERT INTO kitchen(id, household_id, name, kitchen_type, sort_order, created_source_code) VALUES (?, ?, 'Main kitchen', 'MAIN', 0, 'MANUAL')", [k, hh]);
run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, 'REFRIGERATOR', 'Refrigerator', 'CHILLED', 0, 'MANUAL')", [fridge, hh, k]);
run("INSERT INTO storage_instance(id, household_id, kitchen_id, storage_type_code, name, temperature_zone, sort_order, created_source_code) VALUES (?, ?, ?, 'PANTRY', 'Pantry', 'AMBIENT', 1, 'MANUAL')", [pantry, hh, k]);
run("INSERT INTO storage_section(id, household_id, storage_instance_id, section_kind, name, ordinal, created_source_code) VALUES (?, ?, ?, 'SHELF', 'Top shelf', 0, 'MANUAL')", [shelf, hh, fridge]);

// ---- service methods (same SQL as the Dart)
const EFFECT = { MANUAL_ADD: 1, PURCHASE: 1, TRANSFER_IN: 1, WASTE: -1, EXPIRED: -1, RETURN: -1, TRANSFER_OUT: -1, CORRECTION: 0, OTHER: 0 };
function post({ itemId, type, delta, reason = null, groupId = null, relatedId = null }) {
  const d = r4(delta); const eff = EFFECT[type];
  if (d === 0 || (eff > 0 && d < 0) || (eff < 0 && d > 0)) throw new Error('wrong sign');
  if (['WASTE', 'CORRECTION', 'OTHER'].includes(type) && !reason) throw new Error('reason');
  const cur = first('SELECT quantity, unit_code FROM inventory_item WHERE id = ? AND household_id = ? AND deleted_at IS NULL', [itemId, hh]);
  const before = r4(cur.quantity), after = r4(before + d);
  if (after < 0) throw new Error(`Only ${before} left.`);
  const tid = id();
  run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after, actor_user_id, transfer_group_id, related_inventory_item_id, reason, created_source_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
    [tid, hh, itemId, type, d, cur.unit_code, before, after, user, groupId, relatedId, reason]);
  return tid;
}
function food(itemMasterId) { return first('SELECT id, canonical_name, default_unit_code, shelf_life_ambient_days, shelf_life_chilled_days, shelf_life_frozen_days, shelf_life_opened_days FROM item_master WHERE id = ? AND (household_id IS NULL OR household_id = ?) AND deleted_at IS NULL', [itemMasterId, hh]); }
function useSoon({ purchasedOn, zone, f, expiresOn, openedOn }) {
  const life = f[zone === 'FROZEN' ? 'shelf_life_frozen_days' : zone === 'CHILLED' ? 'shelf_life_chilled_days' : 'shelf_life_ambient_days'];
  return [expiresOn, purchasedOn && life != null ? addDays(purchasedOn, life) : null, openedOn && f.shelf_life_opened_days != null ? addDays(openedOn, f.shelf_life_opened_days) : null].filter(Boolean).sort()[0] ?? null;
}
function createLot({ itemMasterId, storageId, sectionId = null, quantity, unit, purchasedOn = today, openedOn = null, expiresOn = null, lowStock = null, type = 'MANUAL_ADD', groupId = null, relatedId = null }) {
  return tx(() => {
    const f = food(itemMasterId), s = first('SELECT kitchen_id, temperature_zone FROM storage_instance WHERE id = ? AND household_id = ?', [storageId, hh]);
    const iid = id();
    run("INSERT INTO inventory_item(id, household_id, item_master_id, kitchen_id, storage_instance_id, storage_section_id, quantity, unit_code, low_stock_threshold, purchased_on, opened_on, best_before_on, expires_on, use_soon_on, label, notes, created_source_code) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'MANUAL')",
      [iid, hh, itemMasterId, s.kitchen_id, storageId, sectionId, unit, lowStock, purchasedOn, openedOn, null, expiresOn, useSoon({ purchasedOn, zone: s.temperature_zone, f, expiresOn, openedOn }), f.canonical_name, null]);
    post({ itemId: iid, type, delta: quantity, groupId, relatedId });
    return iid;
  });
}
function transfer({ itemId, toStorageId, toSectionId = null, quantity }) {
  return tx(() => { const src = first('SELECT * FROM inventory_item WHERE id = ? AND household_id = ?', [itemId, hh]); const g = id();
    post({ itemId, type: 'TRANSFER_OUT', delta: -quantity, groupId: g });
    return createLot({ itemMasterId: src.item_master_id, storageId: toStorageId, sectionId: toSectionId, quantity, unit: src.unit_code, purchasedOn: src.purchased_on, openedOn: src.opened_on, expiresOn: src.expires_on, lowStock: src.low_stock_threshold, type: 'TRANSFER_IN', groupId: g, relatedId: itemId }); });
}
function setDetails({ itemId, sectionId, expiresOn, purchasedOn, lowStock, notes, openedOn }) {
  const it = first('SELECT i.*, s.temperature_zone, m.shelf_life_ambient_days, m.shelf_life_chilled_days, m.shelf_life_frozen_days, m.shelf_life_opened_days FROM inventory_item i JOIN item_master m ON m.id = i.item_master_id JOIN storage_instance s ON s.id = i.storage_instance_id WHERE i.id = ? AND i.household_id = ?', [itemId, hh]);
  const status = it.quantity <= 0 ? it.lifecycle_status : (lowStock != null && it.quantity <= lowStock) ? 'LOW' : openedOn != null ? 'OPENED' : 'ACTIVE';
  run("UPDATE inventory_item SET storage_section_id = ?, expires_on = ?, purchased_on = ?, low_stock_threshold = ?, notes = ?, opened_on = ?, use_soon_on = ?, lifecycle_status = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ? AND household_id = ?",
    [sectionId, expiresOn, purchasedOn, lowStock, notes, openedOn, useSoon({ purchasedOn, zone: it.temperature_zone, f: it, expiresOn, openedOn }), status, itemId, hh]);
}
const item = (iid) => first('SELECT * FROM inventory_item WHERE id = ?', [iid]);
const chicken = first("SELECT id FROM item_master WHERE canonical_name = 'Chicken breast' AND household_id IS NULL").id;

// ---- actions
const c1 = createLot({ itemMasterId: chicken, storageId: fridge, sectionId: shelf, quantity: 500, unit: 'G', type: 'PURCHASE' });
ok(item(c1).quantity === 500 && item(c1).use_soon_on === addDays(today, 2), 'add: stocked through the ledger, use-soon from the fridge shelf life');
post({ itemId: c1, type: 'OTHER', delta: -200, reason: 'Used' }); ok(item(c1).quantity === 300, 'use some');
post({ itemId: c1, type: 'PURCHASE', delta: 50, reason: 'Bought' }); ok(item(c1).quantity === 350, 'add more');
post({ itemId: c1, type: 'WASTE', delta: -100, reason: 'Spoiled' }); ok(item(c1).quantity === 250, 'throw away (with reason)');
post({ itemId: c1, type: 'CORRECTION', delta: r4(240 - 250), reason: 'Counted again' }); ok(item(c1).quantity === 240, 'correct the amount (down)');
post({ itemId: c1, type: 'RETURN', delta: -10 }); ok(item(c1).quantity === 230, 'returned to store');
let over = false; try { post({ itemId: c1, type: 'OTHER', delta: -999, reason: 'Used' }); } catch { over = true; }
ok(over && item(c1).quantity === 230, 'can’t use more than is in stock');
let dbGuard = false; try { run("INSERT INTO inventory_transaction(id, household_id, inventory_item_id, transaction_type_code, quantity_delta, unit_code, quantity_before, quantity_after) VALUES (?, ?, ?, 'WASTE', 5, 'G', 230, 235)", [id(), hh, c1]); } catch { dbGuard = true; }
ok(dbGuard, 'the database itself refuses a wrong-way change');
const moved = transfer({ itemId: c1, toStorageId: pantry, quantity: 30 });
ok(item(c1).quantity === 200 && item(moved).quantity === 30 && item(moved).storage_instance_id === pantry, 'move part of the stock (new lot in the other place)');
ok(count("SELECT COUNT(DISTINCT transfer_group_id) FROM inventory_transaction WHERE transfer_group_id IS NOT NULL") === 1, 'move-out and move-in are linked');
setDetails({ itemId: c1, sectionId: shelf, expiresOn: addDays(today, 1), purchasedOn: today, lowStock: 250, notes: 'For adobo', openedOn: today });
ok(item(c1).lifecycle_status === 'LOW' && item(c1).use_soon_on === addDays(today, 1) && item(c1).notes === 'For adobo', 'details: use-by, note and running-low status');
post({ itemId: c1, type: 'PURCHASE', delta: 100, reason: 'Bought' }); ok(item(c1).lifecycle_status === 'OPENED', 'trigger: above the alert level again -> opened');
post({ itemId: moved, type: 'EXPIRED', delta: -30 }); ok(item(moved).lifecycle_status === 'EXPIRED' && item(moved).quantity === 0, 'mark expired');
run("UPDATE inventory_item SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'), row_version = row_version + 1 WHERE id = ? AND household_id = ?", [moved, hh]);
ok(!!item(moved).deleted_at, 'remove a used-up item from the list');
const r2 = createLot({ itemMasterId: chicken, storageId: pantry, quantity: 5, unit: 'G' });
post({ itemId: r2, type: 'WASTE', delta: -5, reason: 'Spilled or damaged' }); ok(item(r2).lifecycle_status === 'DISCARDED', 'throw away everything -> discarded');

// ---- your foods (create, edit, allergens, rename labels, remove rules)
const ube = id();
run("INSERT INTO item_master(id, household_id, item_kind, canonical_name, food_category_code, default_unit_code, storage_zone, is_perishable, is_verified, created_source_code) VALUES (?, ?, 'FOOD', ?, ?, ?, ?, ?, 0, 'MANUAL')", [ube, hh, 'Ube halaya', 'SNACKS', 'G', 'CHILLED', 1]);
run("INSERT INTO item_allergen(item_master_id, allergen_code, presence) VALUES (?, ?, 'CONTAINS')", [ube, 'MILK']);
const u1 = createLot({ itemMasterId: ube, storageId: fridge, quantity: 300, unit: 'G' });
tx(() => { run("UPDATE item_master SET canonical_name = ?, food_category_code = ?, default_unit_code = CASE WHEN ? THEN default_unit_code ELSE ? END, storage_zone = ?, is_perishable = ?, row_version = row_version + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ? AND household_id = ?",
  ['Ube jam', 'SNACKS', 1, 'KG', 'CHILLED', 1, ube, hh]);
  run('DELETE FROM item_allergen WHERE item_master_id = ?', [ube]);
  for (const a of ['MILK', 'EGG']) run("INSERT INTO item_allergen(item_master_id, allergen_code, presence) VALUES (?, ?, 'CONTAINS')", [ube, a]);
  run('UPDATE inventory_item SET label = ? WHERE item_master_id = ? AND household_id = ?', ['Ube jam', ube, hh]); });
const ubeRow = first('SELECT * FROM item_master WHERE id = ?', [ube]);
ok(ubeRow.canonical_name === 'Ube jam' && ubeRow.default_unit_code === 'G' && count('SELECT COUNT(*) FROM item_allergen WHERE item_master_id = ?', [ube]) === 2 && item(u1).label === 'Ube jam',
  'edit your food: renamed, allergens replaced, unit kept while stored');
const mine = all("SELECT m.*, (SELECT group_concat(allergen_code) FROM item_allergen a WHERE a.item_master_id = m.id) AS allergens, (SELECT COUNT(*) FROM inventory_item i WHERE i.item_master_id = m.id AND i.deleted_at IS NULL) AS lots, (SELECT COUNT(*) FROM inventory_item i WHERE i.item_master_id = m.id AND i.deleted_at IS NULL AND i.quantity > 0) AS in_stock FROM item_master m WHERE m.household_id = ? AND m.deleted_at IS NULL ORDER BY m.search_name", [hh]);
ok(mine.length === 1 && mine[0].in_stock === 1, 'your-foods list knows what is in stock');

// ---- list queries (same SQL), attention counts, history
const list = (show, extra = '', args = []) => all(`SELECT i.*, COALESCE(m.canonical_name, i.label) AS food_name, u.symbol FROM inventory_item i JOIN item_master m ON m.id = i.item_master_id JOIN unit_of_measure u ON u.code = i.unit_code JOIN storage_instance s ON s.id = i.storage_instance_id JOIN kitchen k ON k.id = i.kitchen_id LEFT JOIN storage_section sec ON sec.id = i.storage_section_id WHERE i.household_id = ? AND i.deleted_at IS NULL ${show} ${extra} ORDER BY k.sort_order, s.sort_order, lower(COALESCE(m.canonical_name, i.label)) LIMIT ?`, [hh, ...args, 51]);
ok(list('AND i.quantity > 0').length === 2, 'list: in stock');
ok(list('AND i.quantity = 0').length === 1, 'list: used up (removed items hidden)');
ok(list("AND i.quantity > 0 AND lower(COALESCE(m.canonical_name, i.label)) LIKE ?", '', ['%ube%']).length === 1, 'list: search finds your renamed food');
ok(list('AND i.quantity > 0 AND i.use_soon_on IS NOT NULL AND i.use_soon_on <= ? AND NOT (i.expires_on IS NOT NULL AND i.expires_on < ?)', '', [addDays(today, 3), today]).length >= 1, 'list: use soon');
ok(all('SELECT transaction_type_code FROM inventory_transaction WHERE household_id = ? AND inventory_item_id = ? ORDER BY occurred_at DESC, recorded_at DESC LIMIT 50', [hh, c1]).length === 8, 'history: all 8 accepted changes of the item (refused attempts leave no record)');

// ---- ledger audit
const items = all('SELECT * FROM inventory_item WHERE household_id = ?', [hh]);
const audit = items.every(i => { const t = all('SELECT * FROM inventory_transaction WHERE inventory_item_id = ? ORDER BY rowid', [i.id]);
  const sum = r4(t.reduce((s, x) => s + x.quantity_delta, 0));
  return t.length && t.at(-1).id === i.last_transaction_id && Math.abs(sum - i.quantity) < 1e-6 && t.every((x, n) => n === 0 ? x.quantity_before === 0 : Math.abs(x.quantity_before - t[n - 1].quantity_after) < 1e-9); });
ok(audit, `ledger audit: all ${items.length} items equal the sum of their history`);
console.log(fails ? `${fails} inventory check(s) failed` : 'Inventory replay OK: every Flutter inventory action satisfies the shared rules');
process.exit(fails ? 1 : 0);
