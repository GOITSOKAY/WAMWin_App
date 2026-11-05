import { tx } from '../data/db.js';
import { REF } from './reference.js';
import { kitchenList, storageList, deriveTree } from './draft.js';
import { APPLIANCES, COOKWARE, UTENSILS } from './questions.js';
import { startBasic, invalidate } from '../tier/capabilities.js';

const STORES = ['household', 'household_membership', 'subscription', 'subscription_entitlement', 'questionnaire_session', 'answer',
  'kitchen', 'storage_instance', 'storage_section', 'household_appliance', 'household_cookware', 'household_utensil', 'family_member',
  'member_allergy', 'member_dietary_requirement', 'member_health_food_requirement', 'member_preference', 'inventory_item',
  'inventory_transaction', 'household_module_instance', 'provisioning_record', 'local_mutation_outbox', 'consent_record', 'user_account'];

/** Step 2: the household record (+ owner membership + WAMWins Basic entitlements). Idempotent. */
export async function ensureHousehold(user, session, household) {
  return tx(STORES, 'readwrite', async t => {
    const s = await t.get('questionnaire_session', session.id);
    if (s.household_id) {
      const h = await t.get('household', s.household_id);
      if (h.name !== household.name) await t.update('household', { ...h, name: household.name });
      return h.id;
    }
    const id = crypto.randomUUID();
    await t.insert('household', { id, household_id: id, name: household.name, owner_user_id: user.id, timezone: user.timezone, locale: user.locale,
      status: 'ACTIVE', onboarding_status: 'IN_PROGRESS', created_source_code: 'MANUAL', planned_size: household.size });
    await t.insert('household_membership', { id: crypto.randomUUID(), household_id: id, user_id: user.id, role_code: 'OWNER', status: 'ACTIVE', joined_at: new Date().toISOString() });
    await startBasic(t, id, user.id);
    s.household_id = id; await t.put('questionnaire_session', s);
    for (const a of await t.byIndex('answer', 'session_id', s.id)) await t.put('answer', { ...a, household_id: id });
    session.household_id = id;
    invalidate(id);
    return id;
  });
}

/**
 * Review -> "Create my household": answers become records. Creates ONLY what the answers
 * describe. Every created record is traced in provisioning_record by a stable draft key, so
 * running it again (e.g. after "Update my answers") adds what is new and never duplicates.
 */
export async function provision(user, session, draft) {
  const hh = session.household_id;
  if (!hh) throw new Error('Household is missing; complete "Your household" first.');
  const created = { kitchens: 0, storage: 0, sections: 0, equipment: 0, members: 0, items: 0 };
  await tx(STORES, 'readwrite', async t => {
    const recs = new Map((await t.byIndex('provisioning_record', 'household_id', hh)).map(r => [r.draft_key, r]));
    const once = async (draftKey, table, make) => {
      const r = recs.get(draftKey);
      if (r) return r.created_entity_id;
      const row = await make();
      const rec = { id: `${hh}|${draftKey}`, household_id: hh, session_id: session.id, draft_key: draftKey, created_entity_table: table, created_entity_id: row.id, created_at: new Date().toISOString() };
      await t.add('provisioning_record', rec); recs.set(draftKey, rec);
      return row.id;
    };
    const moduleInstance = (code, resourceId, name) => once(`module:${code}:${resourceId ?? ''}`, 'household_module_instance', () =>
      t.insert('household_module_instance', { id: crypto.randomUUID(), household_id: hh, module_code: code, resource_type: resourceId ? 'storage_instance' : null,
        resource_id: resourceId ?? null, display_name: name, current_status: 'ACTIVE', activated_at: new Date().toISOString() }));

    // Kitchens -> storage units -> sections (from templates); equipment per kitchen
    const storageIds = new Map();
    for (const [ki, k] of kitchenList(draft.kitchens).entries()) {
      const kitchenId = await once(`kitchen:${k.key}`, 'kitchen', () => (created.kitchens++, t.insert('kitchen',
        { id: crypto.randomUUID(), household_id: hh, name: k.name, kitchen_type: k.type, sort_order: ki, is_active: true, created_source_code: 'MANUAL' })));
      for (const [si, s] of storageList(draft, k.key).entries()) {
        const sid = await once(`storage:${s.key}`, 'storage_instance', async () => {
          created.storage++;
          const row = await t.insert('storage_instance', { id: crypto.randomUUID(), household_id: hh, kitchen_id: kitchenId, storage_type_code: s.type,
            name: s.name, temperature_zone: s.zone, sort_order: si, is_active: true, created_source_code: 'MANUAL' });
          for (const [oi, name] of s.sections.entries()) {
            created.sections++;
            await t.insert('storage_section', { id: crypto.randomUUID(), household_id: hh, storage_instance_id: row.id, parent_section_id: null,
              section_kind: 'SHELF', name, ordinal: oi, depth: 0, path: '', created_source_code: 'SYSTEM_DEFAULT' });
          }
          return row;
        });
        storageIds.set(s.key, sid);
        await moduleInstance('STORAGE', sid, s.name);
      }
      const equip = [['household_appliance', 'APPLIANCE', draft.appliances[k.key], APPLIANCES], ['household_cookware', 'COOKWARE', draft.cookware[k.key], COOKWARE],
                     ['household_utensil', 'UTENSIL', draft.utensils[k.key], UTENSILS]];
      for (const [table, cls, codes, list] of equip)
        for (const code of codes || [])
          await once(`equipment:${k.key}:${code}`, table, () => (created.equipment++, t.insert(table, { id: crypto.randomUUID(), household_id: hh, kitchen_id: kitchenId,
            equipment_type_code: code, equipment_class: cls, name: list.find(x => x.code === code)?.name ?? code, condition: 'WORKING', is_active: true, created_source_code: 'MANUAL' })));
    }

    // Family + health (health rows reflect the latest answers; only stored with consent)
    for (const m of draft.family) {
      const memberId = await once(`member:${m.key}`, 'family_member', () => (created.members++, t.insert('family_member', { id: crypto.randomUUID(), household_id: hh,
        linked_user_id: m.isMe ? user.id : null, display_name: m.name, relationship: m.relationship, age_band: m.ageBand, is_active: true,
        include_in_matching_by_default: true, created_source_code: 'MANUAL' })));
      const member = await t.get('family_member', memberId);
      if (member && (member.display_name !== m.name || member.relationship !== m.relationship || member.age_band !== m.ageBand))
        await t.update('family_member', { ...member, display_name: m.name, relationship: m.relationship, age_band: m.ageBand });
      const replace = async (table, rows) => {
        for (const old of await t.byIndex(table, 'member_id', memberId)) await t.del(table, old.id);
        for (const r of rows) await t.insert(table, { id: crypto.randomUUID(), household_id: hh, member_id: memberId, created_source_code: 'MANUAL', ...r });
      };
      if (draft.healthConsent) {
        await replace('member_allergy', (m.allergies || []).map(code => ({ allergen_code: code, severity: 'UNKNOWN' })));
        await replace('member_dietary_requirement', (m.diets || []).map(code => ({ dietary_pattern_code: code, strictness: 'HARD' })));
        await replace('member_health_food_requirement', (m.health || []).map(code => ({ requirement_type_code: code, strictness: 'SOFT' })));
      }
      await replace('member_preference', (m.cuisines || []).map(code => ({ preference_kind: 'LIKE', subject_type: 'CUISINE', cuisine_code: code, strength: 3 })));
    }

    // Food on hand -> inventory item (created at 0) + opening MANUAL_ADD transaction (ledger rule)
    for (const f of draft.food) {
      const storageId = storageIds.get(f.storageKey);
      if (!storageId) continue;
      await once(`food:${f.key}`, 'inventory_item', async () => {
        created.items++;
        const item = REF.items.find(i => i.id === f.itemId);
        const storage = await t.get('storage_instance', storageId);
        const today = new Date().toISOString().slice(0, 10);
        const life = item?.shelfLife?.[storage.temperature_zone];
        const bySL = life != null ? new Date(Date.now() + life * 86400000).toISOString().slice(0, 10) : null;
        const useSoon = [f.expiresOn, bySL].filter(Boolean).sort()[0] ?? null;
        const row = await t.insert('inventory_item', { id: crypto.randomUUID(), household_id: hh, item_master_id: f.itemId, kitchen_id: storage.kitchen_id,
          storage_instance_id: storageId, storage_section_id: null, quantity: 0, unit_code: f.unit, purchased_on: today, expires_on: f.expiresOn || null,
          use_soon_on: useSoon, lifecycle_status: 'ACTIVE', created_source_code: 'MANUAL', label: item?.name ?? f.name, last_transaction_id: null });
        const txnId = crypto.randomUUID();
        await t.insert('inventory_transaction', { id: txnId, household_id: hh, inventory_item_id: row.id, transaction_type_code: 'MANUAL_ADD',
          quantity_delta: f.quantity, unit_code: f.unit, quantity_before: 0, quantity_after: f.quantity, occurred_at: new Date().toISOString(),
          actor_user_id: user.id, created_source_code: 'MANUAL', idempotency_key: `onboarding:${f.key}` });
        await t.put('inventory_item', { ...row, quantity: f.quantity, last_transaction_id: txnId });
        return row;
      });
    }

    // Modules this household needs (only those)
    for (const m of deriveTree(draft).modules.filter(x => x.on && x.code !== 'STORAGE')) await moduleInstance(m.code, null, m.name);

    const s = await t.get('questionnaire_session', session.id);
    await t.put('questionnaire_session', { ...s, status: 'COMPLETED', completed_at: new Date().toISOString(), current_step: 'review' });
    const h = await t.get('household', hh);
    await t.update('household', { ...h, onboarding_status: 'COMPLETED' });
    if (draft.about?.displayName) {
      const u = await t.get('user_account', user.id);
      await t.put('user_account', { ...u, display_name: draft.about.displayName, preferences: { cookingRole: draft.about.cookingRole, skill: draft.about.skill, measures: draft.about.measures }, updated_at: new Date().toISOString() });
    }
  });
  return created;
}

/** Reads the household structure for Home (scoped to one household). */
export async function loadHousehold(householdId) {
  return tx(['household', 'kitchen', 'storage_instance', 'storage_section', 'inventory_item', 'family_member', 'member_allergy',
    'member_dietary_requirement', 'household_module_instance', 'household_appliance', 'household_cookware', 'household_utensil'], 'readonly', async t => {
    const g = (s) => t.byIndex(s, 'household_id', householdId);
    const live = (rows) => rows.filter(r => !r.deleted_at);
    return { household: await t.get('household', householdId), kitchens: live(await g('kitchen')).sort((a, b) => a.sort_order - b.sort_order),
      storage: live(await g('storage_instance')), sections: live(await g('storage_section')), items: live(await g('inventory_item')).filter(i => i.quantity > 0),
      members: live(await g('family_member')), allergies: live(await g('member_allergy')), diets: live(await g('member_dietary_requirement')),
      modules: live(await g('household_module_instance')),
      equipment: [...live(await g('household_appliance')), ...live(await g('household_cookware')), ...live(await g('household_utensil'))] };
  });
}
