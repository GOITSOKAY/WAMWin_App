import { REF } from './reference.js';
import { LEGACY_KITCHEN_TYPES, DEFAULT_MEASURES } from './questions.js';

/**
 * Backward-compatible draft adapter: questionnaire v1 answers -> the v2 draft shape. v1 answer rows are never
 * rewritten; v2 answers are saved beside them. Draft keys are kept IDENTICAL to v1 (kitchen:MAIN-1,
 * storage:MAIN-1/REFRIGERATOR-1, equipment:MAIN-1:WOK, member:<key>, food:<key>) so saving again on an
 * existing household adds only what is new and never duplicates.
 */
const V1 = { ABOUT: 'ABOUT_YOU', HOUSEHOLD: 'HOUSEHOLD', KITCHENS: 'KITCHENS', STORAGE: 'STORAGE_UNITS', APPLIANCES: 'COOKING_APPLIANCES',
  COOKWARE: 'COOKWARE', UTENSILS: 'UTENSILS', FAMILY: 'FAMILY_MEMBERS', HEALTH_CONSENT: 'HEALTH_CONSENT', FOOD: 'FOOD_ON_HAND' };
const restricted = (m) => (m.allergies?.length || m.diets?.length || m.health?.length) > 0;

export function adaptV1(answer) {
  const about = { measures: DEFAULT_MEASURES, ...(answer(V1.ABOUT) ?? {}) };
  const hv1 = answer(V1.HOUSEHOLD) ?? {};
  const counts = answer(V1.KITCHENS) ?? { MAIN: 1 };
  const kitchens = [];
  for (const t of LEGACY_KITCHEN_TYPES) {
    const n = counts[t.code] || 0;
    for (let i = 1; i <= n; i++) {
      const key = `${t.code}-${i}`;
      const kind = REF.kitchenKinds.some(k => k.code === t.code) ? t.code : null;          // v1 "Other kitchen" keeps its name, no kind
      const storageCounts = answer(V1.STORAGE, key) ?? (t.code === 'MAIN' && i === 1 ? { REFRIGERATOR: 1, PANTRY: 1 } : {});
      const storage = [];
      for (const st of REF.storageTypes) {
        const c = storageCounts[st.code] || 0;
        for (let j = 1; j <= c; j++) storage.push({ key: `${key}/${st.code}-${j}`, type: st.code, name: c > 1 ? `${st.name} ${j}` : st.name, counts: {}, custom: [], legacy: true });
      }
      kitchens.push({ key, kind, legacyType: t.code, name: n > 1 ? `${t.name} ${i}` : t.name, storage });
    }
  }
  const appliances = [], kitchenware = [];
  for (const k of kitchens) {
    for (const code of answer(V1.APPLIANCES, k.key) ?? []) {
      const e = REF.equipment.find(x => x.code === code);
      appliances.push({ key: `${k.key}:${code}`, pkey: `equipment:${k.key}:${code}`, kitchenKey: k.key, code, name: e?.name ?? code });
    }
    for (const code of [...(answer(V1.COOKWARE, k.key) ?? []), ...(answer(V1.UTENSILS, k.key) ?? [])]) {
      const t = REF.kitchenwareTypes.find(x => x.code === code), e = REF.equipment.find(x => x.code === code);
      kitchenware.push({ key: `${k.key}:${code}`, pkey: `equipment:${k.key}:${code}`, kitchenKey: k.key, code: t ? code : null,
        category: t?.category ?? 'COOKWARE', name: t?.name ?? e?.name ?? code, quantity: 1 });
    }
  }
  const family = answer(V1.FAMILY) ?? [];
  const me = family.find(m => m.isMe);
  const people = family.filter(m => restricted(m) || (!m.isMe && family.length > 1)).map(m => ({
    key: m.key, name: m.name, relationship: m.isMe ? 'SELF' : m.relationship, ageBand: m.ageBand, isMe: !!m.isMe,
    allergies: m.allergies ?? [], intolerances: [], diets: m.diets ?? [], health: m.health ?? [], avoid: [], prioritize: [], meals: {} }));
  return {
    version: 2, migratedFrom: 1,
    about, selfKey: me?.key ?? 'me',
    household: { name: hv1.name ?? '', nickname: '', size: hv1.size ?? 2, eaters: hv1.size ?? 2 },
    health: { needed: family.some(restricted) ? 'YES' : (answer(V1.FAMILY) ? 'NO' : null), consent: answer(V1.HEALTH_CONSENT) ?? null, people },
    kitchens, appliances, kitchenware,
    food: (answer(V1.FOOD) ?? []).map(f => ({ ...f, sectionKey: null })),
  };
}
