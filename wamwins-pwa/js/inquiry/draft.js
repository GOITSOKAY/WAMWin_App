import { tx } from '../data/db.js';
import { REF } from './reference.js';
import { QUESTIONNAIRE, DEFAULT_MEASURES, V1_STEP_MAP } from './questions.js';
import { adaptV1 } from './adapter.js';

/**
 * Questionnaire HOUSEHOLD_PROFILE v2. Answers are rows (one per question + repeat key), saved after every module so
 * onboarding can resume. v2 rows have their own ids (".|v2|.") and questionnaire_version = 2, so v1 rows are never
 * overwritten; a v1 session is read through the adapter and continues as v2. The "draft" is the in-memory view of the
 * answers for the current screen only.
 */
export const Q = { ABOUT: 'ABOUT_YOU', HOUSEHOLD: 'HOUSEHOLD', HEALTH_NEEDED: 'HEALTH_NEEDED', HEALTH_CONSENT: 'HEALTH_CONSENT', HEALTH: 'HEALTH_PROFILES',
  KITCHENS: 'KITCHENS', APPLIANCES: 'APPLIANCES', KITCHENWARE: 'KITCHENWARE', FOOD: 'FOOD_ON_HAND' };

export async function ensureSession(user) {
  return tx(['questionnaire_session', 'household_membership'], 'readwrite', async t => {
    const sessions = await t.byIndex('questionnaire_session', 'user_id', user.id);
    const open = sessions.find(s => s.status !== 'ABANDONED');
    if (open) {
      if ((open.questionnaire_version ?? 1) < 2) open.current_step = V1_STEP_MAP[open.current_step] ?? 'about';   // resume v1 sessions in v2
      return open;
    }
    const m = (await t.byIndex('household_membership', 'user_id', user.id)).find(x => x.status === 'ACTIVE');
    const s = { id: crypto.randomUUID(), user_id: user.id, household_id: m?.household_id ?? null, questionnaire_code: QUESTIONNAIRE.code,
      questionnaire_version: QUESTIONNAIRE.version, status: 'IN_PROGRESS', current_step: 'about', started_at: new Date().toISOString(), completed_at: null };
    await t.add('questionnaire_session', s);
    return s;
  });
}

export function newKitchen(kind, kitchens) {
  const k = REF.kitchenKinds.find(x => x.code === kind);
  const n = Math.max(0, ...kitchens.filter(x => x.key.startsWith(`${kind}-`)).map(x => Number(x.key.split('-').pop()) || 0)) + 1;
  const same = kitchens.filter(x => x.kind === kind).length;
  return { key: `${kind}-${n}`, kind, name: same ? `${k.name} ${same + 1}` : k.name, storage: [] };
}
export function newStorage(kitchen, type) {
  const st = REF.storageTypes.find(s => s.code === type);
  const n = Math.max(0, ...kitchen.storage.filter(s => s.type === type).map(s => Number(s.key.split('-').pop()) || 0)) + 1;
  const same = kitchen.storage.filter(s => s.type === type).length;
  const counts = Object.fromEntries(REF.sectionQuestions.filter(q => q.storage_type_code === type).map(q => [q.code, q.default_value]));
  return { key: `${kitchen.key}/${type}-${n}`, type, name: same ? `${st.name} ${same + 1}` : st.name, counts, custom: [] };
}
function freshDraft() {
  const main = newKitchen('MAIN', []);
  main.storage.push(newStorage(main, 'REFRIGERATOR'), newStorage(main, 'PANTRY'));
  return { version: 2, about: { measures: DEFAULT_MEASURES }, selfKey: 'me', household: { size: 2, eaters: 2 },
    health: { needed: null, consent: null, people: [] }, kitchens: [main], appliances: [], kitchenware: [], food: [] };
}

export async function loadDraft(session) {
  const rows = await tx(['answer'], 'readonly', t => t.byIndex('answer', 'session_id', session.id));
  const v2 = rows.filter(r => r.questionnaire_version === 2), v1 = rows.filter(r => !r.questionnaire_version);
  const pick = (set) => (code, key = '') => set.find(r => r.question_code === code && r.repeat_key === key)?.value;
  if (!v2.length) return v1.length ? adaptV1(pick(v1)) : freshDraft();
  const a = pick(v2), d = freshDraft();
  const about = a(Q.ABOUT) ?? {};
  return { version: 2, about: { ...d.about, ...about.about }, selfKey: about.selfKey ?? 'me', household: { ...d.household, ...(a(Q.HOUSEHOLD) ?? {}) },
    health: { needed: a(Q.HEALTH_NEEDED) ?? null, consent: a(Q.HEALTH_CONSENT) ?? null, people: a(Q.HEALTH) ?? [] },
    kitchens: a(Q.KITCHENS) ?? d.kitchens, appliances: a(Q.APPLIANCES) ?? [], kitchenware: a(Q.KITCHENWARE) ?? [], food: a(Q.FOOD) ?? [] };
}

/** All v2 answers for the draft (each module saves everything it changed; cheap, keeps resume exact). */
export function answersOf(draft) {
  return [[Q.ABOUT, '', { about: draft.about, selfKey: draft.selfKey }], [Q.HOUSEHOLD, '', draft.household],
    [Q.HEALTH_NEEDED, '', draft.health.needed], [Q.HEALTH_CONSENT, '', draft.health.consent], [Q.HEALTH, '', draft.health.people],
    [Q.KITCHENS, '', draft.kitchens], [Q.APPLIANCES, '', draft.appliances], [Q.KITCHENWARE, '', draft.kitchenware], [Q.FOOD, '', draft.food]];
}

export async function saveAnswers(session, entries, extra = {}) {
  const now = new Date().toISOString();
  await tx(['answer', 'questionnaire_session'], 'readwrite', async t => {
    for (const [code, key, value] of entries)
      await t.put('answer', { id: `${session.id}|v2|${code}|${key}`, session_id: session.id, household_id: session.household_id, questionnaire_version: 2,
        question_code: code, repeat_key: key, value, answered_at: now, created_source_code: 'MANUAL' });
    const s = await t.get('questionnaire_session', session.id);
    const migrated = (s.questionnaire_version ?? 1) < 2 ? { questionnaire_version: 2, migrated_from_version: s.questionnaire_version ?? 1 } : {};
    Object.assign(session, s, migrated, extra);
    await t.put('questionnaire_session', session);
  });
}

/** Section names a storage unit will get: follow-up answers + the household's own (nested) sections. */
export function sectionNames(storage) {
  if (storage.legacy && !Object.keys(storage.counts ?? {}).length && !storage.custom?.length)
    return REF.sectionTemplates.filter(s => s.storage_type_code === storage.type).sort((a, b) => a.ordinal - b.ordinal).map(s => s.default_name);
  const out = [];
  for (const q of REF.sectionQuestions.filter(q => q.storage_type_code === storage.type)) {
    const v = storage.counts?.[q.code] ?? 0;
    if (q.input_kind === 'TOGGLE') { if (v) out.push(q.name_pattern); }
    else for (let n = 1; n <= v; n++) out.push(q.name_pattern.replace('{n}', n));
  }
  const walk = (nodes, prefix = '') => { for (const c of nodes ?? []) { out.push(prefix + c.name); walk(c.children, `${prefix}${c.name} › `); } };
  walk(storage.custom);
  return out;
}
export const allStorage = (draft) => draft.kitchens.flatMap(k => k.storage.map(s => ({ ...s, kitchenKey: k.key, kitchenName: k.name,
  zone: REF.storageTypes.find(t => t.code === s.type)?.temperature_zone ?? 'AMBIENT' })));

/** The household-specific tree + the modules these answers require. Health shows COUNTS only, never details. */
export function deriveTree(draft) {
  const kitchens = draft.kitchens.map(k => ({ ...k, storage: k.storage.map(s => ({ ...s, sections: sectionNames(s), items: draft.food.filter(f => f.storageKey === s.key).length })),
    appliances: draft.appliances.filter(a => a.kitchenKey === k.key).length, kitchenware: draft.kitchenware.filter(w => w.kitchenKey === k.key).reduce((n, w) => n + 1, 0) }));
  const storageCount = kitchens.reduce((n, k) => n + k.storage.length, 0);
  const applianceCount = draft.appliances.length, kitchenwareCount = draft.kitchenware.length;
  const healthProfiles = draft.health.needed === 'YES' ? draft.health.people.length : 0;
  const members = 1 + draft.health.people.filter(p => !p.isMe).length;
  const health = draft.health.consent === true && draft.health.people.some(p => p.allergies?.length || p.intolerances?.length || p.diets?.length || p.health?.length || p.avoid?.length || p.prioritize?.length);
  const canCook = draft.appliances.length > 0;
  const modules = [
    { code: 'HOUSEHOLD', name: 'Household', on: true },
    { code: 'FAMILY', name: 'Family', on: true },
    { code: 'HEALTH', name: 'Health & diet', on: health },
    { code: 'KITCHEN', name: 'Kitchens', on: kitchens.length > 0 },
    { code: 'STORAGE', name: `Storage (${storageCount})`, on: storageCount > 0 },
    { code: 'EQUIPMENT', name: 'Appliances & kitchenware', on: applianceCount + kitchenwareCount > 0 },
    { code: 'INVENTORY', name: 'Inventory', on: storageCount > 0 },
    { code: 'SHOPPING', name: 'Shopping list', on: storageCount > 0 },
    { code: 'MATCHING', name: 'Meal matching', on: storageCount > 0 && canCook },
    { code: 'MEALS', name: 'Meal history', on: storageCount > 0 && canCook },
  ];
  return { kitchens, storageCount, applianceCount, kitchenwareCount, healthProfiles, members, foodCount: draft.food.length, modules, moduleCount: modules.filter(m => m.on).length };
}

/** Places inside a storage unit with stable keys (the food step and provisioning use the same keys). */
export function sectionOptions(storage) {
  const sections = [], containers = [];
  for (const q of REF.sectionQuestions.filter(q => q.storage_type_code === storage.type)) {
    const v = storage.counts?.[q.code] ?? 0;
    if (q.input_kind === 'TOGGLE') { if (v) sections.push({ key: `${storage.key}#${q.code}`, name: q.name_pattern, kind: q.section_kind }); }
    else for (let n = 1; n <= v; n++) sections.push({ key: `${storage.key}#${q.code}-${n}`, name: q.name_pattern.replace('{n}', n), kind: q.section_kind });
  }
  const walk = (nodes, prefix, parentKey) => { for (const c of nodes ?? []) {
    const key = `${storage.key}#c:${c.key}`;
    (c.kind === 'CONTAINER' ? containers : sections).push({ key, name: prefix + c.name, kind: c.kind, parentKey });
    walk(c.children, `${prefix}${c.name} › `, key);
  } };
  walk(storage.custom, '', null);
  return { sections, containers };
}
