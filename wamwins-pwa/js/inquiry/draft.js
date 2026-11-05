import { tx } from '../data/db.js';
import { REF } from './reference.js';
import { KITCHEN_TYPES, STORAGE_TYPES, QUESTIONNAIRE } from './questions.js';

/**
 * Answers are stored as rows (questionnaire answer table) per question + repeat key, saved
 * after every step so profiling can be resumed on any device state. The "draft" is the
 * in-memory view of those answers for the current screen only.
 */
export const Q = { ABOUT: 'ABOUT_YOU', HOUSEHOLD: 'HOUSEHOLD', KITCHENS: 'KITCHENS', STORAGE: 'STORAGE_UNITS', APPLIANCES: 'COOKING_APPLIANCES',
  COOKWARE: 'COOKWARE', UTENSILS: 'UTENSILS', FAMILY: 'FAMILY_MEMBERS', HEALTH_CONSENT: 'HEALTH_CONSENT', FOOD: 'FOOD_ON_HAND' };

export async function ensureSession(user) {
  return tx(['questionnaire_session', 'household_membership'], 'readwrite', async t => {
    const sessions = await t.byIndex('questionnaire_session', 'user_id', user.id);
    const open = sessions.find(s => s.status !== 'ABANDONED');
    if (open) return open;
    const m = (await t.byIndex('household_membership', 'user_id', user.id)).find(x => x.status === 'ACTIVE');
    const s = { id: crypto.randomUUID(), user_id: user.id, household_id: m?.household_id ?? null, questionnaire_code: QUESTIONNAIRE.code,
      questionnaire_version: QUESTIONNAIRE.version, status: 'IN_PROGRESS', current_step: 'about', started_at: new Date().toISOString(), completed_at: null };
    await t.add('questionnaire_session', s);
    return s;
  });
}

export async function loadDraft(session) {
  const rows = await tx(['answer'], 'readonly', t => t.byIndex('answer', 'session_id', session.id));
  const a = (code, key = '') => rows.find(r => r.question_code === code && r.repeat_key === key)?.value;
  const kitchens = a(Q.KITCHENS) ?? { MAIN: 1 };
  const draft = { about: a(Q.ABOUT) ?? {}, household: a(Q.HOUSEHOLD) ?? {}, kitchens, storage: {}, appliances: {}, cookware: {}, utensils: {},
                  family: a(Q.FAMILY) ?? [], healthConsent: a(Q.HEALTH_CONSENT) ?? null, food: a(Q.FOOD) ?? [] };
  for (const k of kitchenList(kitchens)) {
    draft.storage[k.key] = a(Q.STORAGE, k.key) ?? (k.type === 'MAIN' && k.n === 1 ? { REFRIGERATOR: 1, PANTRY: 1 } : {});
    draft.appliances[k.key] = a(Q.APPLIANCES, k.key) ?? [];
    draft.cookware[k.key] = a(Q.COOKWARE, k.key) ?? [];
    draft.utensils[k.key] = a(Q.UTENSILS, k.key) ?? [];
  }
  return draft;
}

export async function saveAnswers(session, entries, extra = {}) {
  const now = new Date().toISOString();
  await tx(['answer', 'questionnaire_session'], 'readwrite', async t => {
    for (const [code, key, value] of entries)
      await t.put('answer', { id: `${session.id}|${code}|${key}`, session_id: session.id, household_id: session.household_id, question_code: code,
        repeat_key: key, value, answered_at: now, created_source_code: 'MANUAL' });
    const s = await t.get('questionnaire_session', session.id);
    Object.assign(session, s, extra);
    await t.put('questionnaire_session', session);
  });
}

/** Kitchens the household said it has, with stable keys used across steps. */
export function kitchenList(kitchens) {
  const out = [];
  for (const t of KITCHEN_TYPES) {
    const n = kitchens[t.code] || 0;
    for (let i = 1; i <= n; i++) out.push({ key: `${t.code}-${i}`, type: t.code, n: i, name: n > 1 ? `${t.name} ${i}` : t.name });
  }
  return out;
}
export function storageList(draft, kitchenKey) {
  const counts = draft.storage[kitchenKey] || {}, out = [];
  for (const st of STORAGE_TYPES) {
    const n = counts[st.code] || 0;
    for (let i = 1; i <= n; i++) out.push({ key: `${kitchenKey}/${st.code}-${i}`, type: st.code, zone: st.zone, name: n > 1 ? `${st.name} ${i}` : st.name,
      sections: REF.sectionTemplates.filter(s => s.storage_type_code === st.code).sort((a, b) => a.ordinal - b.ordinal).map(s => s.default_name) });
  }
  return out;
}

/** The household-specific module tree + the modules these answers require. */
export function deriveTree(draft) {
  const kitchens = kitchenList(draft.kitchens).map(k => ({ ...k, storage: storageList(draft, k.key).map(s => ({ ...s,
    items: draft.food.filter(f => f.storageKey === s.key).length })),
    equipment: (draft.appliances[k.key]?.length || 0) + (draft.cookware[k.key]?.length || 0) + (draft.utensils[k.key]?.length || 0) }));
  const storageCount = kitchens.reduce((n, k) => n + k.storage.length, 0);
  const equipmentCount = kitchens.reduce((n, k) => n + k.equipment, 0);
  const members = draft.family.length;
  const health = draft.family.some(m => (m.allergies?.length || m.diets?.length || m.health?.length));
  const canCook = kitchens.some(k => (draft.appliances[k.key] || []).length > 0);
  const modules = [
    { code: 'HOUSEHOLD', name: 'Household', on: true },
    { code: 'KITCHEN', name: 'Kitchens', on: kitchens.length > 0 },
    { code: 'STORAGE', name: `Storage (${storageCount})`, on: storageCount > 0 },
    { code: 'EQUIPMENT', name: 'Appliances & tools', on: equipmentCount > 0 },
    { code: 'FAMILY', name: 'Family', on: members > 0 },
    { code: 'HEALTH', name: 'Health & diet', on: health },
    { code: 'INVENTORY', name: 'Inventory', on: storageCount > 0 },
    { code: 'SHOPPING', name: 'Shopping list', on: storageCount > 0 },
    { code: 'MATCHING', name: 'Meal matching', on: members > 0 && storageCount > 0 && canCook },
    { code: 'MEALS', name: 'Meal history', on: members > 0 && storageCount > 0 && canCook },
  ];
  return { kitchens, storageCount, equipmentCount, members, modules, moduleCount: modules.filter(m => m.on).length };
}
