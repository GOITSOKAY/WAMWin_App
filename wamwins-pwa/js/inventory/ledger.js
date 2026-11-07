// The single write path for inventory quantities in the browser - the same rules the shared database
// triggers enforce on every other client (src/modules/inventory/domain/InventoryLedger.ts, migration 005):
// items start at 0; quantity changes ONLY through an inventory_transaction; signs follow the transaction
// type; WASTE / CORRECTION / OTHER need a reason; never below zero; lifecycle status follows each change.
export const EFFECT = { OPENING_BALANCE: 'INCREASE', MANUAL_ADD: 'INCREASE', PURCHASE: 'INCREASE', TRANSFER_IN: 'INCREASE',
  MEAL_USAGE: 'DECREASE', WASTE: 'DECREASE', EXPIRED: 'DECREASE', RETURN: 'DECREASE', TRANSFER_OUT: 'DECREASE', CORRECTION: 'SIGNED', OTHER: 'SIGNED' };
export const TYPE_NAMES = { OPENING_BALANCE: 'Opening balance', MANUAL_ADD: 'Added', PURCHASE: 'Bought', TRANSFER_IN: 'Moved in', MEAL_USAGE: 'Used in a meal',
  WASTE: 'Thrown away', EXPIRED: 'Expired', RETURN: 'Returned', TRANSFER_OUT: 'Moved out', CORRECTION: 'Corrected', OTHER: 'Used' };
const NEEDS_REASON = new Set(['WASTE', 'CORRECTION', 'OTHER']);
export const STORES = ['inventory_item', 'inventory_transaction', 'local_mutation_outbox'];
export const r4 = (v) => Math.round(v * 10000) / 10000;
export const today = () => { const d = new Date(); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10); };
export const addDays = (iso, n) => { const d = new Date(`${iso}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
export class InventoryError extends Error {}

/** Earliest of: use-by, best-before, purchase + shelf life for the storage zone, opened + opened shelf life. */
export function useSoonOn({ purchasedOn, zone, shelfLife = {}, expiresOn, bestBeforeOn, openedOn }) {
  const life = shelfLife[zone === 'FROZEN' ? 'FROZEN' : zone === 'CHILLED' ? 'CHILLED' : 'AMBIENT'];
  const c = [expiresOn, bestBeforeOn, purchasedOn && life != null ? addDays(purchasedOn, life) : null,
    openedOn && shelfLife.OPENED != null ? addDays(openedOn, shelfLife.OPENED) : null].filter(Boolean).sort();
  return c[0] ?? null;
}

/** Same CASE as trg_txn_apply. */
export function statusAfter(item, type, after) {
  if (after === 0) return type === 'EXPIRED' ? 'EXPIRED' : type === 'WASTE' ? 'DISCARDED' : 'DEPLETED';
  if (item.low_stock_threshold != null && after <= item.low_stock_threshold) return 'LOW';
  return item.opened_on ? 'OPENED' : 'ACTIVE';
}

/** Status when details (threshold, opened) change without a quantity change. */
export function statusFor(item) {
  if (!(item.quantity > 0)) return item.lifecycle_status;
  return statusAfter(item, null, item.quantity);
}

/** Append one transaction and apply it to the item (inside the caller's tx). */
export async function post(t, { hh, item, type, delta, reason = null, userId, groupId = null, relatedId = null, mealRecordId = null, unitLabel }) {
  if (!EFFECT[type]) throw new InventoryError(`Unknown change type ${type}`);
  delta = r4(Number(delta));
  if (!Number.isFinite(delta) || delta === 0) throw new InventoryError('Enter an amount greater than zero.');
  if ((EFFECT[type] === 'INCREASE' && delta < 0) || (EFFECT[type] === 'DECREASE' && delta > 0)) throw new InventoryError('That change goes the wrong way.');
  if (NEEDS_REASON.has(type) && !String(reason ?? '').trim()) throw new InventoryError('Please choose a reason.');
  const before = r4(item.quantity), after = r4(before + delta);
  if (after < 0) throw new InventoryError(`Only ${before} ${unitLabel ?? item.unit_code.toLowerCase()} left.`);
  const id = crypto.randomUUID(), now = new Date().toISOString();
  await t.insert('inventory_transaction', { id, household_id: hh, inventory_item_id: item.id, transaction_type_code: type, quantity_delta: delta, unit_code: item.unit_code,
    quantity_before: before, quantity_after: after, occurred_at: now, recorded_at: now, actor_user_id: userId ?? null, transfer_group_id: groupId,
    related_inventory_item_id: relatedId, meal_record_id: mealRecordId, reason: reason ? String(reason).trim() : null, created_source_code: 'MANUAL', idempotency_key: null });
  const updated = await t.update('inventory_item', { ...item, quantity: after, last_transaction_id: id, last_source_code: 'MANUAL', lifecycle_status: statusAfter(item, type, after) });
  return { transactionId: id, item: updated };
}

/** New lot at 0 + its opening transaction (MANUAL_ADD, PURCHASE or TRANSFER_IN). */
export async function createLot(t, { hh, userId, food, storage, sectionId = null, quantity, unit, purchasedOn = today(), openedOn = null, expiresOn = null,
  bestBeforeOn = null, lowStock = null, notes = null, type = 'MANUAL_ADD', groupId = null, relatedId = null }) {
  if (!(Number(quantity) > 0)) throw new InventoryError('Enter an amount greater than zero.');
  const row = { id: crypto.randomUUID(), household_id: hh, item_master_id: food.id, kitchen_id: storage.kitchen_id, storage_instance_id: storage.id,
    storage_section_id: sectionId || null, container_id: null, quantity: 0, unit_code: unit, low_stock_threshold: lowStock === '' || lowStock == null ? null : Number(lowStock),
    purchased_on: purchasedOn || null, opened_on: openedOn || null, best_before_on: bestBeforeOn || null, expires_on: expiresOn || null,
    use_soon_on: useSoonOn({ purchasedOn, zone: storage.temperature_zone, shelfLife: food.shelfLife, expiresOn, bestBeforeOn, openedOn }),
    lifecycle_status: 'ACTIVE', label: food.name, notes: notes || null, last_transaction_id: null, created_source_code: 'MANUAL', last_source_code: null };
  const created = await t.insert('inventory_item', row);
  return post(t, { hh, item: created, type, delta: Number(quantity), userId, groupId, relatedId });
}

/** Move part or all of a lot: TRANSFER_OUT here + a new lot with TRANSFER_IN there, linked by one group id. */
export async function transfer(t, { hh, userId, item, food, toStorage, toSectionId, quantity }) {
  const groupId = crypto.randomUUID();
  const out = await post(t, { hh, item, type: 'TRANSFER_OUT', delta: -Number(quantity), userId, groupId });
  const dest = await createLot(t, { hh, userId, food, storage: toStorage, sectionId: toSectionId, quantity, unit: item.unit_code, purchasedOn: item.purchased_on,
    openedOn: item.opened_on, expiresOn: item.expires_on, bestBeforeOn: item.best_before_on, lowStock: item.low_stock_threshold, notes: item.notes,
    type: 'TRANSFER_IN', groupId, relatedId: item.id });
  return { from: out.item, to: dest.item };
}

/** What needs attention (pure, used for the list badges and the summary). */
export function flags(item, now = today()) {
  const live = item.quantity > 0;
  const expired = live && ((item.expires_on && item.expires_on < now) || item.lifecycle_status === 'EXPIRED');
  return { expired, useSoon: live && !expired && !!item.use_soon_on && item.use_soon_on <= addDays(now, 3), low: live && item.lifecycle_status === 'LOW',
    opened: live && !!item.opened_on, usedUp: !live };
}
