import { h, icon, clear, choices, chips, field } from '../../core/dom.js';
import { tx } from '../../data/db.js';
import { REF } from '../../inquiry/reference.js';
import { RELATIONSHIPS, AGE_BANDS, ALLERGENS, DIETS, HEALTH_GOALS, MEAL_CONTEXTS } from '../../inquiry/questions.js';
import { infoButton, labelWithInfo } from '../../components/info.js';
import { autocomplete, searchList } from '../../components/autocomplete.js';

// Module 2 - Health Profiles. Structured data only (allergies, intolerances, diets, health goals, foods to avoid /
// prioritize, per-meal rules), stored in separate tables, and only with consent. Not a medical diagnosis.
const YES_NO = [{ code: 'YES', name: 'Yes' }, { code: 'NO', name: 'No' }];
const foodsAndGroups = [...REF.items.map(i => ({ name: i.name, itemId: i.id })), ...REF.foodCategories.map(c => ({ name: c.name, categoryCode: c.code, group: true }))];
const blankPerson = (o) => ({ key: crypto.randomUUID(), name: '', relationship: 'CHILD', ageBand: 'CHILD', isMe: false, allergies: [], intolerances: [], diets: [], health: [],
  avoid: [], prioritize: [], meals: {}, ...o });
const hasData = (p) => p.allergies.length + p.intolerances.length + p.diets.length + p.health.length + p.avoid.length + p.prioritize.length
  + Object.values(p.meals ?? {}).reduce((n, m) => n + (m.avoid?.length || 0) + (m.prioritize?.length || 0) + (m.note ? 1 : 0), 0) > 0;

export async function create({ draft, user, session, refresh }) {
  const hs = draft.health;
  hs.consent ??= (await tx(['consent_record'], 'readonly', t => t.byIndex('consent_record', 'user_id', user.id)))
    .filter(c => c.consent_type === 'HEALTH_DATA_PROCESSING').sort((a, b) => a.recorded_at.localeCompare(b.recorded_at)).at(-1)?.granted ?? false;
  const consentAtStart = hs.consent;
  const known = session.household_id ? (await tx(['family_member'], 'readonly', t => t.byIndex('family_member', 'household_id', session.household_id))).filter(m => !m.deleted_at) : [];
  const editor = h('div');
  const disposers = [];

  function tagInput(id, label, list, hint) {
    const box = h('div', { class: 'chips' });
    const draw = () => clear(box).append(...list.map((t, i) => h('span', { class: 'tag-pill' }, h('span', { text: t.label }),
      h('button', { type: 'button', class: 'pill-x', 'aria-label': `Remove ${t.label}`, onclick: () => { list.splice(i, 1); draw(); refresh(); } }, icon('close', 14)))));
    const ac = autocomplete({ id, label, placeholder: 'Type 3 letters, e.g. sug', search: searchList(foodsAndGroups),
      describe: x => x.group ? 'food group' : '', addLabel: q => `Add “${q}”`,
      onPick: x => { if (!list.some(t => t.label === x.name)) list.push({ label: x.name, itemId: x.itemId ?? null, categoryCode: x.categoryCode ?? null }); draw(); refresh(); },
      onAddNew: q => { list.push({ label: q, itemId: null, categoryCode: null }); draw(); refresh(); } });
    disposers.push(ac.dispose);
    draw();
    return h('div', { class: 'stack-s' }, ac.el, hint ? h('p', { class: 'hint', text: hint }) : null, box);
  }

  function personCard(p, idx) {
    p.meals ??= {};
    const nameIn = h('input', { class: 'input', value: p.name, maxlength: 80, id: `hp-name-${p.key}` });
    nameIn.oninput = () => { p.name = nameIn.value; head.textContent = p.name || 'New person'; };
    const head = h('span', { text: p.name || 'New person' });
    const sec = (title, ...body) => h('details', { class: 'disclosure' }, h('summary', { text: title }), h('div', {}, ...body));
    const meals = MEAL_CONTEXTS.map(mc => {
      const m = (p.meals[mc.code] ??= { avoid: [], prioritize: [], note: '' });
      const note = h('input', { class: 'input', value: m.note ?? '', maxlength: 200, id: `hp-note-${p.key}-${mc.code}`, placeholder: 'e.g. low sugar, no caffeine after 3 pm' });
      note.oninput = () => { m.note = note.value; };
      return sec(mc.name, tagInput(`hp-${p.key}-${mc.code}-avoid`, `Avoid at ${mc.name.toLowerCase()}`, m.avoid), tagInput(`hp-${p.key}-${mc.code}-pri`, `Prioritize at ${mc.name.toLowerCase()}`, m.prioritize),
        field({ label: 'Note (optional)', input: note }));
    });
    return h('article', { class: 'member-card', 'aria-label': `Health profile ${idx + 1}` },
      h('div', { class: 'member-head' }, h('span', { class: 'avatar', 'aria-hidden': 'true', text: (p.name || '?').trim().slice(0, 1).toUpperCase() }),
        h('div', { class: 'who' }, h('b', {}, head), h('span', { class: 'hint', text: p.isMe ? 'You' : (RELATIONSHIPS.find(r => r.code === p.relationship)?.name ?? '') })),
        h('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${p.name || 'this person'}`, onclick: () => { hs.people.splice(idx, 1); draw(); refresh(); } }, icon('trash', 20))),
      p.isMe ? null : field({ label: 'Name', input: nameIn }),
      p.isMe ? null : h('div', { class: 'field' }, h('span', { class: 'label', text: 'Relationship' }), chips(RELATIONSHIPS.filter(r => r.code !== 'SELF'), [p.relationship], v => { p.relationship = v.at(-1) ?? p.relationship; draw(); })),
      h('div', { class: 'field' }, h('span', { class: 'label', text: 'Age group' }), chips(AGE_BANDS, [p.ageBand], v => { p.ageBand = v.at(-1) ?? p.ageBand; draw(); })),
      sec('Allergies', h('p', { class: 'hint', text: 'Recipes with these are never suggested.' }), chips(ALLERGENS, p.allergies, v => { p.allergies = v; refresh(); }, { warn: true })),
      sec('Intolerances', h('p', { class: 'hint', text: 'Foods that cause discomfort (for example lactose).' }), chips(ALLERGENS, p.intolerances, v => { p.intolerances = v; refresh(); }, { warn: true })),
      sec('Dietary requirements', chips(DIETS, p.diets, v => { p.diets = v; refresh(); })),
      sec('Health-related food requirements', h('p', { class: 'hint', text: 'Used to rank meals, not to give medical advice.' }), chips(HEALTH_GOALS, p.health, v => { p.health = v; refresh(); })),
      sec('Foods to avoid', tagInput(`hp-${p.key}-avoid`, 'Add a food or food group to avoid', p.avoid)),
      sec('Foods to prioritize', tagInput(`hp-${p.key}-pri`, 'Add a food or food group to prioritize', p.prioritize)),
      h('div', { class: 'meal-contexts' }, h('h3', { class: 'with-info' }, h('span', { text: 'By meal' }),
        infoButton({ label: 'Meal-specific needs', title: 'Meal-specific needs', body: 'Some needs depend on the time of day, like no caffeine at dinner or a protein-rich breakfast. Add them per meal, between-meal snacks and drinks.' })), ...meals));
  }

  function addPersonPicker() {
    const used = new Set(hs.people.map(p => p.key));
    const meIn = hs.people.some(p => p.isMe);
    const existing = known.filter(m => !used.has(m.id) && m.linked_user_id !== user.id);
    const panel = h('div', { class: 'custom-food' }, h('h3', { text: 'Who needs special dietary management?' }),
      h('div', { class: 'row' },
        meIn ? null : h('button', { type: 'button', class: 'btn btn-ghost', text: `Me (${draft.about.displayName})`, onclick: () => { hs.people.push(blankPerson({ key: draft.selfKey, name: draft.about.displayName, relationship: 'SELF', ageBand: 'ADULT', isMe: true })); draw(); refresh(); } }),
        ...existing.map(m => h('button', { type: 'button', class: 'btn btn-ghost', text: m.display_name, onclick: () => { hs.people.push(blankPerson({ key: m.id, existingId: m.id, name: m.display_name, relationship: m.relationship ?? 'OTHER', ageBand: m.age_band ?? 'ADULT' })); draw(); refresh(); } })),
        h('button', { type: 'button', class: 'btn btn-primary', onclick: () => { hs.people.push(blankPerson()); draw(); refresh(); setTimeout(() => editor.querySelector('article:last-of-type input')?.focus(), 0); } }, icon('plus', 18), h('span', { text: 'New family member' }))));
    return panel;
  }

  function draw() {
    disposers.splice(0).forEach(d => d());
    clear(editor);
    if (hs.needed !== 'YES') return;
    const consent = h('input', { type: 'checkbox', id: 'hp-consent', checked: hs.consent === true });
    consent.onchange = () => { hs.consent = consent.checked; draw(); };
    editor.append(h('section', { class: 'q-block' },
      h('label', { class: 'check' }, consent, h('span', {}, h('b', { style: { fontWeight: 500 }, text: 'Use these health details to keep meal suggestions safe' }),
        h('span', { class: 'hint', style: { display: 'block' }, text: 'Stored only on your household’s records, visible only to members you allow. Turn this off or change the details any time. This is not a medical diagnosis.' }))),
      hs.consent ? null : h('p', { class: 'hint', text: 'Without this, WAMWins won’t store health details. You can continue and add them later.' })));
    if (!hs.consent) return;
    editor.append(h('section', { class: 'q-block' }, h('h2', { text: 'People who need special dietary management' }),
      ...hs.people.map(personCard), addPersonPicker()));
  }

  const el = h('div', {},
    h('section', { class: 'q-block' },
      labelWithInfo('Does anyone in your household require special dietary management?', { title: 'Why we ask', body: ['Allergies, intolerances and diets decide which meals are safe to suggest. Allergies are always a hard stop.',
        'Health details are optional, stored separately from your kitchen, and only with your permission. WAMWins does not diagnose or give medical advice.'] }),
      choices(YES_NO, hs.needed, v => { hs.needed = v; if (v === 'YES' && hs.consent === false && !consentAtStart) hs.consent = false; draw(); refresh(); })),
    editor);
  draw();
  return {
    el,
    validate: () => {
      if (!hs.needed) return 'Choose Yes or No to continue.';
      if (hs.needed === 'NO') return null;
      if (!hs.consent) return null;                                      // continue without storing health data
      if (!hs.people.length) return 'Add at least one person, or choose No.';
      if (hs.people.some(p => !p.name?.trim())) return 'Every person needs a name.';
      if (!hs.people.some(hasData)) return 'Add at least one need (an allergy, diet, intolerance or food to avoid/prioritize).';
      hs.people.forEach(p => { p.name = p.name.trim(); });
      return null;
    },
    afterSave: async () => {
      if ((hs.consent === true) !== (consentAtStart === true))
        await tx(['consent_record'], 'readwrite', t => t.add('consent_record', { id: crypto.randomUUID(), user_id: user.id, consent_type: 'HEALTH_DATA_PROCESSING',
          document_version: '1', granted: hs.consent === true, recorded_at: new Date().toISOString() }));
    },
    dispose: () => disposers.forEach(d => d()),
  };
}
