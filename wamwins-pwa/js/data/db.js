// Local-first IndexedDB store. Object stores use the SAME names and columns as the WAMWins
// database tables (database/sqlite + database/postgres), so the sync service maps rows 1:1.
// Schema changes are versioned migrations: additive only, never a rebuild.
const DB_NAME = 'wamwins';
const HOUSEHOLD_SCOPED = ['household_membership', 'subscription', 'subscription_entitlement', 'kitchen', 'storage_instance', 'storage_section',
  'household_appliance', 'household_cookware', 'household_utensil', 'family_member', 'member_allergy', 'member_dietary_requirement',
  'member_health_food_requirement', 'member_preference', 'inventory_item', 'inventory_transaction', 'household_module_instance', 'provisioning_record'];
const MIGRATIONS = [
  /* v1 */ (db) => {
    const s = (name, keyPath = 'id') => db.createObjectStore(name, { keyPath });
    s('user_account').createIndex('email', 'email', { unique: true });
    s('auth_identity').createIndex('provider_subject', 'provider_subject', { unique: true });
    s('consent_record').createIndex('user_id', 'user_id');
    s('session', 'token_hash');
    s('household').createIndex('owner_user_id', 'owner_user_id');
    s('questionnaire_session').createIndex('user_id', 'user_id');
    s('answer').createIndex('session_id', 'session_id');
    for (const name of HOUSEHOLD_SCOPED) {
      const st = s(name);
      st.createIndex('household_id', 'household_id');
      if (name === 'household_membership') st.createIndex('user_id', 'user_id');
      if (name === 'storage_section' || name === 'inventory_item') st.createIndex('storage_instance_id', 'storage_instance_id');
      if (name.startsWith('member_')) st.createIndex('member_id', 'member_id');
    }
    s('local_mutation_outbox', 'client_mutation_id').createIndex('household_id', 'household_id');
    s('app_meta', 'key');
  },
  /* v2: meal matching + meals (additive - existing stores and data are untouched) */
  (db) => {
    for (const name of ['match_run', 'match_run_member', 'match_result', 'match_result_factor', 'match_result_item', 'match_exclusion',
                        'meal_record', 'meal_participant', 'consumption_record']) {
      db.createObjectStore(name, { keyPath: 'id' }).createIndex('household_id', 'household_id');
    }
  },
  /* v3: the household's own foods (item_master rows with household_id set) and their allergens (additive) */
  (db) => {
    for (const name of ['item_master', 'item_allergen']) db.createObjectStore(name, { keyPath: 'id' }).createIndex('household_id', 'household_id');
  },
];
export const DB_VERSION = MIGRATIONS.length;

let dbPromise;
export function openDb() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    if (!('indexedDB' in window)) return reject(new Error('This browser cannot store data offline (IndexedDB is unavailable).'));
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (e) => { for (let v = e.oldVersion; v < DB_VERSION; v++) MIGRATIONS[v](req.result); };
    req.onsuccess = () => { const db = req.result; db.onversionchange = () => { db.close(); location.reload(); }; resolve(db); };
    req.onerror = () => reject(req.error);
    req.onblocked = () => reject(new Error('Please close other WAMWins tabs to finish updating.'));
  });
  return dbPromise;
}
export const req = (r) => new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });

/** Runs fn inside ONE transaction (all-or-nothing). Only IndexedDB requests may be awaited inside. */
export async function tx(stores, mode, fn) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const t = db.transaction(stores, mode);
    let result, failed = false;
    const api = {
      get: (s, k) => req(t.objectStore(s).get(k)),
      put: (s, v) => req(t.objectStore(s).put(v)),
      add: (s, v) => req(t.objectStore(s).add(v)),
      del: (s, k) => req(t.objectStore(s).delete(k)),
      byIndex: (s, i, k) => req(t.objectStore(s).index(i).getAll(k)),
      oneByIndex: (s, i, k) => req(t.objectStore(s).index(i).get(k)),
      count: (s, i, k) => req(i ? t.objectStore(s).index(i).count(k) : t.objectStore(s).count()),
      /** Insert a syncable row + queue it for sync (client_mutation_id = idempotent push). */
      insert: async (s, row) => {
        const now = new Date().toISOString();
        const full = { created_at: now, updated_at: now, deleted_at: null, row_version: 1, ...row };
        await req(t.objectStore(s).add(full));
        if (full.household_id && stores.includes('local_mutation_outbox'))
          await req(t.objectStore('local_mutation_outbox').add({ client_mutation_id: crypto.randomUUID(), household_id: full.household_id, entity_table: s,
            entity_id: full.id, operation: 'INSERT', created_at: now, pushed_at: null }));
        return full;
      },
      update: async (s, row) => {
        const now = new Date().toISOString();
        const full = { ...row, updated_at: now, row_version: (row.row_version || 1) + 1 };
        await req(t.objectStore(s).put(full));
        if (full.household_id && stores.includes('local_mutation_outbox'))
          await req(t.objectStore('local_mutation_outbox').add({ client_mutation_id: crypto.randomUUID(), household_id: full.household_id, entity_table: s,
            entity_id: full.id, operation: 'UPDATE', base_row_version: row.row_version || 1, created_at: now, pushed_at: null }));
        return full;
      },
    };
    t.oncomplete = () => resolve(result);
    t.onabort = () => reject(t.error || new Error('Saving failed. Nothing was changed.'));
    Promise.resolve().then(() => fn(api)).then(v => { result = v; }, e => { failed = true; try { t.abort(); } catch {} reject(e); });
  });
}
export const get = (s, k) => tx([s], 'readonly', t => t.get(s, k));
export const byIndex = (s, i, k) => tx([s], 'readonly', t => t.byIndex(s, i, k));
export const ALL_STORES = () => openDb().then(db => [...db.objectStoreNames]);
export async function deleteEverything() {
  const db = await openDb(); db.close(); dbPromise = undefined;
  await new Promise((res, rej) => { const r = indexedDB.deleteDatabase(DB_NAME); r.onsuccess = res; r.onerror = () => rej(r.error); r.onblocked = res; });
}
