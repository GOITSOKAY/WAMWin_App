import { tx } from '../data/db.js';
import { REF } from './reference.js';
import { deriveTree, sectionOptions } from './draft.js';
import { startBasic, invalidate } from '../tier/capabilities.js';

const STORES = ['household', 'household_membership', 'subscription', 'subscription_entitlement', 'questionnaire_session', 'answer',
  'kitchen', 'storage_instance', 'storage_section', 'household_appliance', 'household_cookware', 'household_utensil', 'household_kitchenware', 'household_container', 'family_member',
  'member_allergy', 'member_dietary_requirement', 'member_health_food_requirement', 'member_preference', 'member_intolerance', 'member_food_rule', 'location_media', 'inventory_item', 'item_master', 'item_allergen',
  'inventory_transaction', 'household_module_instance', 'provisioning_record', 'local_mutation_outbox', 'consent_record', 'user_account'];

/** Module 1: the household record (+ owner membership + WAMWins Basic entitlements). Idempotent. */
export async function ensureHousehold(user, session, household) {
  return tx(STORES, 'readwrite', async t => {
    const s = await t.get('questionnaire_session', session.id);
    if (s.household_id) {
      const h = await t.get('household', s.household_id);
      if (h.name !== household.name || h.nickname !== (household.nickname || null) || h.member_count !== household.size || h.eater_count !== household.eaters)
        await t.update('household', { ...h, name: household.name, nickname: household.nickname || null, member_count: household.size, eater_count: household.eaters });
      return h.id;
    }
    const id = crypto.randomUUID();
    await t.insert('household', { id, household_id: id, name: household.name, owner_user_id: user.id, timezone: user.timezone, locale: user.locale,
      status: 'ACTIVE', onboarding_status: 'IN_PROGRESS', created_source_code: 'MANUAL', planned_size: household.size, nickname: household.nickname || null,
      member_count: household.size, eater_count: household.eaters });
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
 * Review -> "Save Entries": answers become records. Creates ONLY what the answers describe. Every created record is
 * traced in provisioning_record by a stable draft key (the same keys v1 used), so saving again - e.g. after
 * "Update my answers" - adds what is new and never duplicates. Quantities go through the ledger (item at 0 +
 * MANUAL_ADD transaction). Health rows are written only with consent.
 */
const MEAL_RULE = (kind, ctx) => (t) => ({ rule_kind: kind, meal_context: ctx, label: t.label, item_master_id: t.itemId ?? null, food_category_code: t.categoryCode ?? null });
const COOKING = { ME: 'PRIMARY', SHARED: 'SHARED', OTHER: 'OTHER' };

export async function provision(user, session, draft) {
  const hh = session.household_id;
  if (!hh) throw new Error('Household is missing; complete “About You” first.');
  const created = { kitchens: 0, storage: 0, sections: 0, equipment: 0, kitchenware: 0, members: 0, items: 0, photos: 0, existing: false };
  await tx(STORES, 'readwrite', async t => {
    const recs = new Map((await t.byIndex('provisioning_record', 'household_id', hh)).map(r => [r.draft_key, r]));
    created.existing = recs.size > 0;
    const once = async (draftKey, table, make) => {
      const r = recs.get(draftKey);
      if (r) return r.created_entity_id;
      const row = await make();
      const rec = { id: `${hh}|${draftKey}`, household_id: hh, session_id: session.id, draft_key: draftKey, created_entity_table: table, created_entity_id: row.id, created_at: new Date().toISOString() };
      await t.add('provisioning_record', rec); recs.set(draftKey, rec);
      return row.id;
    };
    const touch = async (table, id, patch) => { const cur = await t.get(table, id); if (cur && Object.entries(patch).some(([k, v]) => cur[k] !== v)) await t.update(table, { ...cur, ...patch }); };
    const moduleInstance = (code, resourceId, name) => once(`module:${code}:${resourceId ?? ''}`, 'household_module_instance', () =>
      t.insert('household_module_instance', { id: crypto.randomUUID(), household_id: hh, module_code: code, resource_type: resourceId ? 'storage_instance' : null,
        resource_id: resourceId ?? null, display_name: name, current_status: 'ACTIVE', activated_at: new Date().toISOString() }));
    const ids = new Map();                                                       // draft location key -> { kitchen, storage, section, container }

    // ---- Module 1: household + you
    await touch('household', hh, { name: draft.household.name, nickname: draft.household.nickname || null, member_count: draft.household.size, eater_count: draft.household.eaters });
    const selfId = await once(`member:${draft.selfKey}`, 'family_member', () => (created.members++, t.insert('family_member', { id: crypto.randomUUID(), household_id: hh,
      linked_user_id: user.id, display_name: draft.about.displayName, relationship: 'SELF', age_band: 'ADULT', is_active: true, include_in_matching_by_default: true, created_source_code: 'MANUAL' })));
    await touch('family_member', selfId, { display_name: draft.about.displayName, household_role_code: draft.about.householdRole ?? null, cooking_responsibility: COOKING[draft.about.cookingRole] ?? null });

    // ---- Module 3: kitchens -> storage -> sections (follow-ups + nested own sections) / containers
    for (const [ki, k] of draft.kitchens.entries()) {
      const legacyType = REF.kitchenKinds.find(x => x.code === k.kind)?.legacy_kitchen_type ?? k.legacyType ?? 'OTHER';
      const kitchenId = await once(`kitchen:${k.key}`, 'kitchen', () => (created.kitchens++, t.insert('kitchen',
        { id: crypto.randomUUID(), household_id: hh, name: k.name, kitchen_type: legacyType, kitchen_kind_code: k.kind ?? null, sort_order: ki, is_active: true, created_source_code: 'MANUAL' })));
      await touch('kitchen', kitchenId, { name: k.name, kitchen_kind_code: k.kind ?? null });
      ids.set(`kitchen:${k.key}`, { kitchen: kitchenId });
      for (const [si, s] of k.storage.entries()) {
        const zone = REF.storageTypes.find(x => x.code === s.type)?.temperature_zone ?? 'AMBIENT';
        const sid = await once(`storage:${s.key}`, 'storage_instance', async () => {
          created.storage++;
          const row = await t.insert('storage_instance', { id: crypto.randomUUID(), household_id: hh, kitchen_id: kitchenId, storage_type_code: s.type,
            name: s.name, temperature_zone: zone, sort_order: si, is_active: true, created_source_code: 'MANUAL' });
          if (s.legacy && !Object.values(s.counts ?? {}).some(Boolean)) {             // v1 storage never saved before: v1 template sections
            for (const [oi, tpl] of REF.sectionTemplates.filter(x => x.storage_type_code === s.type).sort((a, b) => a.ordinal - b.ordinal).entries()) {
              created.sections++;
              await t.insert('storage_section', { id: crypto.randomUUID(), household_id: hh, storage_instance_id: row.id, parent_section_id: null,
                section_kind: tpl.section_kind, name: tpl.default_name, ordinal: oi, depth: 0, path: '', created_source_code: 'SYSTEM_DEFAULT' });
            }
          }
          return row;
        });
        await touch('storage_instance', sid, { name: s.name });
        ids.set(`storage:${s.key}`, { kitchen: kitchenId, storage: sid });
        await moduleInstance('STORAGE', sid, s.name);
        const { sections, containers } = sectionOptions(s);
        for (const [oi, sec] of sections.entries()) {
          const parent = sec.parentKey ? ids.get(`section:${sec.parentKey}`) : null;
          const secId = await once(`section:${sec.key}`, 'storage_section', () => (created.sections++, t.insert('storage_section', { id: crypto.randomUUID(), household_id: hh,
            storage_instance_id: sid, parent_section_id: parent?.section ?? null, section_kind: sec.kind === 'CONTAINER' ? 'CUSTOM' : sec.kind, name: sec.name.split(' › ').pop(),
            ordinal: oi, depth: sec.name.split(' › ').length - 1, path: parent?.path ? `${parent.path}/${parent.section}` : (parent?.section ?? ''), created_source_code: 'MANUAL' })));
          ids.set(`section:${sec.key}`, { kitchen: kitchenId, storage: sid, section: secId, path: parent?.path ? `${parent.path}/${parent.section}` : (parent?.section ?? '') });
        }
        for (const c of containers) {
          const parent = c.parentKey ? ids.get(`section:${c.parentKey}`) : null;
          const cid = await once(`container:${c.key}`, 'household_container', () => t.insert('household_container', { id: crypto.randomUUID(), household_id: hh, kitchen_id: kitchenId,
            storage_instance_id: sid, storage_section_id: parent?.section ?? null, equipment_type_code: 'AIRTIGHT_CONTAINER', equipment_class: 'CONTAINER',
            name: c.name.split(' › ').pop(), is_active: true, created_source_code: 'MANUAL' }));
          ids.set(`container:${c.key}`, { kitchen: kitchenId, storage: sid, section: parent?.section ?? null, container: cid });
        }
      }
    }
    // reference photos taken during onboarding -> real ids (photos keep their draft key for traceability)
    for (const m of (await t.byIndex('location_media', 'household_id', hh)).filter(x => x.location_draft_key && !x.kitchen_id)) {
      const at = ids.get(m.location_draft_key);
      if (at) { created.photos++; await t.update('location_media', { ...m, kitchen_id: at.kitchen ?? null, storage_instance_id: at.storage ?? null, storage_section_id: at.section ?? null, container_id: at.container ?? null }); }
    }

    // ---- Module 4: appliances (details; refrigerator/freezer cross-reference their storage unit)
    for (const a of draft.appliances) {
      const kitchenId = ids.get(`kitchen:${a.kitchenKey}`)?.kitchen; if (!kitchenId) continue;
      const patch = { name: a.name, brand: a.brand || null, model: a.model || null, serial_number: a.serial || null, purchased_on: a.purchasedOn || null, warranty_end_on: a.warrantyEnd || null,
        location_note: a.location ? (ids.get(`storage:${a.location}`) ? null : a.location) : null, condition: a.condition ?? 'WORKING', notes: a.notes || null,
        storage_instance_id: (a.storageKey && ids.get(`storage:${a.storageKey}`)?.storage) || (a.location && ids.get(`storage:${a.location}`)?.storage) || null };
      const aid = await once(a.pkey ?? `appliance:${a.kitchenKey}:${a.key}`, 'household_appliance', () => (created.equipment++, t.insert('household_appliance', { id: crypto.randomUUID(),
        household_id: hh, kitchen_id: kitchenId, equipment_type_code: a.code ?? 'CUSTOM_APPLIANCE', equipment_class: 'APPLIANCE', is_active: true, created_source_code: 'MANUAL', ...patch })));
      await touch('household_appliance', aid, patch);
    }
    // ---- Module 5: kitchenware with quantities (v1 cookware/utensil records are found by their v1 keys: no duplicates)
    for (const w of draft.kitchenware) {
      const kitchenId = ids.get(`kitchen:${w.kitchenKey}`)?.kitchen; if (!kitchenId) continue;
      const wid = await once(w.pkey ?? `kitchenware:${w.kitchenKey}:${w.code ?? w.key}`, 'household_kitchenware', () => (created.kitchenware++, t.insert('household_kitchenware', {
        id: crypto.randomUUID(), household_id: hh, kitchen_id: kitchenId, kitchenware_type_code: w.code ?? null, category: w.category, name: w.name, quantity: w.quantity, is_active: true, created_source_code: 'MANUAL' })));
      if (!w.pkey) await touch('household_kitchenware', wid, { quantity: w.quantity, name: w.name });
    }

    // ---- Module 2: health profiles (people + structured needs), only with consent
    const replace = async (table, memberId, rows) => {
      for (const old of (await t.byIndex(table, 'household_id', hh)).filter(r => r.member_id === memberId)) await t.del(table, old.id);
      for (const r of rows) await t.insert(table, { id: crypto.randomUUID(), household_id: hh, member_id: memberId, created_source_code: 'MANUAL', ...r });
    };
    if (draft.health.needed === 'YES' && draft.health.consent === true) {
      for (const p of draft.health.people) {
        const memberId = p.isMe ? selfId : await once(`member:${p.key}`, 'family_member', async () => {
          if (p.existingId && await t.get('family_member', p.existingId)) return { id: p.existingId };
          created.members++;
          return t.insert('family_member', { id: crypto.randomUUID(), household_id: hh, linked_user_id: null, display_name: p.name, relationship: p.relationship, age_band: p.ageBand,
            is_active: true, include_in_matching_by_default: true, created_source_code: 'MANUAL' });
        });
        if (!p.isMe) await touch('family_member', memberId, { display_name: p.name, relationship: p.relationship, age_band: p.ageBand });
        await replace('member_allergy', memberId, p.allergies.map(code => ({ allergen_code: code, severity: 'UNKNOWN' })));
        await replace('member_intolerance', memberId, (p.intolerances ?? []).map(code => ({ allergen_code: code, severity: 'MODERATE', handling: 'EXCLUDE' })));
        await replace('member_dietary_requirement', memberId, p.diets.map(code => ({ dietary_pattern_code: code, strictness: 'HARD' })));
        await replace('member_health_food_requirement', memberId, p.health.map(code => ({ requirement_type_code: code, strictness: 'SOFT' })));
        await replace('member_food_rule', memberId, [...(p.avoid ?? []).map(MEAL_RULE('AVOID', 'ANY')), ...(p.prioritize ?? []).map(MEAL_RULE('PRIORITIZE', 'ANY')),
          ...Object.entries(p.meals ?? {}).flatMap(([ctx, m]) => [...(m.avoid ?? []).map(MEAL_RULE('AVOID', ctx)), ...(m.prioritize ?? []).map(MEAL_RULE('PRIORITIZE', ctx)),
            ...(m.note?.trim() ? [{ rule_kind: 'NOTE', meal_context: ctx, label: m.note.trim(), item_master_id: null, food_category_code: null }] : [])])]);
      }
    }

    // ---- Module 6: the household's own foods, then food -> inventory item (at 0) + MANUAL_ADD (ledger rule)
    for (const f of draft.food.filter(x => x.custom)) {
      await once(`item:${f.itemId}`, 'item_master', async () => {
        await t.insert('item_master', { id: f.itemId, household_id: hh, item_kind: 'FOOD', canonical_name: f.name, display_name: null, search_name: f.name.toLowerCase(),
          food_category_code: f.custom.category || 'OTHER', default_unit_code: f.custom.unit, storage_zone: f.custom.zone || 'ANY',
          is_perishable: f.custom.zone === 'CHILLED' || f.custom.zone === 'FROZEN', is_verified: false, created_source_code: f.custom.source ?? 'MANUAL', deleted_at: null });
        for (const code of f.custom.allergens || [])
          await t.insert('item_allergen', { id: `${f.itemId}|${code}`, household_id: hh, item_master_id: f.itemId, allergen_code: code, presence: 'CONTAINS' });
        return { id: f.itemId };
      });
    }
    for (const f of draft.food) {
      const at = ids.get(`storage:${f.storageKey}`); if (!at) continue;
      await once(`food:${f.key}`, 'inventory_item', async () => {
        created.items++;
        const item = REF.items.find(i => i.id === f.itemId);
        const storage = await t.get('storage_instance', at.storage);
        const purchased = f.purchasedOn || new Date().toISOString().slice(0, 10);
        const life = item?.shelfLife?.[storage.temperature_zone];
        const bySL = life != null ? new Date(Date.parse(`${purchased}T00:00:00Z`) + life * 86400000).toISOString().slice(0, 10) : null;
        const useSoon = [f.expiresOn, f.useByOn, f.bestByOn, bySL].filter(Boolean).sort()[0] ?? null;
        const row = await t.insert('inventory_item', { id: crypto.randomUUID(), household_id: hh, item_master_id: f.itemId, kitchen_id: at.kitchen, storage_instance_id: at.storage,
          storage_section_id: (f.sectionKey && ids.get(`section:${f.sectionKey}`)?.section) || null, container_id: (f.containerKey && ids.get(`container:${f.containerKey}`)?.container) || null,
          quantity: 0, unit_code: f.unit, purchased_on: purchased, opened_on: f.openedOn || null, best_before_on: f.bestByOn || null, use_by_on: f.useByOn || null,
          expires_on: f.expiresOn || null, use_soon_on: useSoon, brand: f.brand || null, packaging_code: f.packaging || null, package_size: f.packageSize || null,
          package_unit_code: f.packageUnit || null, item_condition: f.condition || null, notes: f.notes || null,
          lifecycle_status: f.openedOn ? 'OPENED' : 'ACTIVE', created_source_code: 'MANUAL', label: item?.name ?? f.name, last_transaction_id: null });
        const txnId = crypto.randomUUID();
        await t.insert('inventory_transaction', { id: txnId, household_id: hh, inventory_item_id: row.id, transaction_type_code: 'MANUAL_ADD',
          quantity_delta: f.quantity, unit_code: f.unit, quantity_before: 0, quantity_after: f.quantity, occurred_at: new Date().toISOString(),
          actor_user_id: user.id, created_source_code: 'MANUAL', idempotency_key: `onboarding:${f.key}` });
        await t.put('inventory_item', { ...row, quantity: f.quantity, last_transaction_id: txnId });
        return row;
      });
    }

    // ---- Modules this household needs (only those)
    for (const m of deriveTree(draft).modules.filter(x => x.on && x.code !== 'STORAGE')) await moduleInstance(m.code, null, m.name);

    const s = await t.get('questionnaire_session', session.id);
    await t.put('questionnaire_session', { ...s, status: 'COMPLETED', completed_at: new Date().toISOString(), current_step: 'review', questionnaire_version: 2 });
    const hrow = await t.get('household', hh);
    await t.update('household', { ...hrow, onboarding_status: 'COMPLETED' });
    const u = await t.get('user_account', user.id);
    await t.put('user_account', { ...u, display_name: draft.about.displayName, preferences: { cookingRole: draft.about.cookingRole, skill: draft.about.skill, measures: draft.about.measures,
      householdRole: draft.about.householdRole ?? null }, updated_at: new Date().toISOString() });
  });
  return created;
}

/** Reads the household structure for Home (scoped to one household). */
export async function loadHousehold(householdId) {
  return tx(['household', 'kitchen', 'storage_instance', 'storage_section', 'inventory_item', 'family_member', 'member_allergy',
    'member_dietary_requirement', 'household_module_instance', 'household_appliance', 'household_cookware', 'household_utensil', 'household_kitchenware'], 'readonly', async t => {
    const g = (s) => t.byIndex(s, 'household_id', householdId);
    const live = (rows) => rows.filter(r => !r.deleted_at);
    return { household: await t.get('household', householdId), kitchens: live(await g('kitchen')).sort((a, b) => a.sort_order - b.sort_order),
      storage: live(await g('storage_instance')), sections: live(await g('storage_section')), items: live(await g('inventory_item')).filter(i => i.quantity > 0),
      members: live(await g('family_member')), allergies: live(await g('member_allergy')), diets: live(await g('member_dietary_requirement')),
      modules: live(await g('household_module_instance')),
      equipment: [...live(await g('household_appliance')), ...live(await g('household_cookware')), ...live(await g('household_utensil'))],
      kitchenware: live(await g('household_kitchenware')) };
  });
}
