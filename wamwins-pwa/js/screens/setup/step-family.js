import { h, chips, choices, clear, icon, field } from '../../core/dom.js';
import { RELATIONSHIPS, AGE_BANDS, ALLERGENS, DIETS, HEALTH_GOALS, CUISINES } from '../../inquiry/questions.js';
import { Q } from '../../inquiry/draft.js';
import { tx } from '../../data/db.js';

export async function create({ draft, user, refresh }) {
  const consents = await tx(['consent_record'], 'readonly', t => t.byIndex('consent_record', 'user_id', user.id));
  const latest = consents.filter(c => c.consent_type === 'HEALTH_DATA_PROCESSING').sort((a, b) => a.recorded_at.localeCompare(b.recorded_at)).pop();
  const consentAtStart = latest?.granted ?? false;
  if (draft.healthConsent === null || draft.healthConsent === undefined) draft.healthConsent = consentAtStart;
  if (!draft.family.length) draft.family.push({ key: crypto.randomUUID(), name: draft.about.displayName || user.display_name, relationship: 'SELF', ageBand: 'ADULT', isMe: true, allergies: [], diets: [], health: [], cuisines: [] });

  const list = h('div', { class: 'stack' });
  const sizeNote = h('p', { class: 'hint' });
  const label = (arr, code) => arr.find(x => x.code === code)?.name ?? '';

  function memberCard(m) {
    const initials = (m.name || '?').trim().split(/\s+/).map(p => p[0]).slice(0, 2).join('').toUpperCase();
    const summary = [...(m.allergies || []).map(c => h('span', { class: 'tag danger', text: `No ${label(ALLERGENS, c).toLowerCase()}` })),
      ...(m.diets || []).map(c => h('span', { class: 'tag blue', text: label(DIETS, c) }))];
    const name = h('input', { class: 'input', type: 'text', value: m.name, maxlength: 60 });
    name.oninput = () => { m.name = name.value; };
    name.onchange = () => render();
    const healthOff = !draft.healthConsent;
    const lock = healthOff ? h('p', { class: 'hint', text: 'Turn on “Use health details” above to add these.' }) : null;
    const sec = (title, body, open) => h('details', { class: 'disclosure', open }, h('summary', { text: title }), h('div', {}, body));
    return h('article', { class: 'member', 'aria-label': m.name || 'Family member' },
      h('div', { class: 'member-head' }, h('span', { class: 'avatar', 'aria-hidden': 'true', text: initials || '?' }),
        h('div', { class: 'who' }, h('b', { text: m.isMe ? `${m.name} (you)` : m.name }), h('span', { text: [...new Set([label(RELATIONSHIPS, m.relationship), label(AGE_BANDS, m.ageBand)].filter(Boolean))].join(', ') })),
        m.isMe ? null : h('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${m.name}`, onclick: () => {
          draft.family.splice(draft.family.indexOf(m), 1); render(); refresh(); } }, icon('trash', 20))),
      summary.length ? h('div', { class: 'chips' }, summary) : null,
      sec('Name and age', h('div', { class: 'stack-s' }, field({ label: 'Name', input: name }),
        h('p', { class: 'label', text: 'Age group' }), chipsSingle(AGE_BANDS, m.ageBand, v => { m.ageBand = v; render(); }),
        m.isMe ? null : h('div', { class: 'stack-s' }, h('p', { class: 'label', text: 'Relationship to you' }),
          chipsSingle(RELATIONSHIPS.filter(r => r.code !== 'SELF'), m.relationship, v => { m.relationship = v; render(); }))), false),
      sec('Food allergies', [lock, chips(ALLERGENS, m.allergies, v => { m.allergies = v; refresh(); }, { warn: true, disabled: healthOff })], !healthOff && !!m.allergies?.length),
      sec('Dietary needs', [lock, chips(DIETS, m.diets, v => { m.diets = v; refresh(); }, { disabled: healthOff })], false),
      sec('Health goals', [lock, h('p', { class: 'hint', text: 'Used to rank meals, not to give medical advice.' }), chips(HEALTH_GOALS, m.health, v => { m.health = v; }, { disabled: healthOff })], false),
      sec('Favourite cuisines', chips(CUISINES, m.cuisines, v => { m.cuisines = v; }), false));
  }
  function chipsSingle(options, value, onChange) {
    return h('div', { class: 'chips', role: 'radiogroup' }, options.map(o => h('button', { type: 'button', role: 'radio', class: 'chip', 'aria-pressed': String(o.code === value),
      'aria-checked': String(o.code === value), text: o.name, onclick: () => onChange(o.code) })));
  }
  const addForm = h('div');
  function openAdd() {
    const n = { key: crypto.randomUUID(), name: '', relationship: 'CHILD', ageBand: 'CHILD', isMe: false, allergies: [], diets: [], health: [], cuisines: [] };
    const name = h('input', { class: 'input', type: 'text', maxlength: 60, placeholder: 'First name' });
    const fName = field({ label: 'Name', input: name });
    const rel = chipsSingle(RELATIONSHIPS.filter(r => r.code !== 'SELF'), n.relationship, v => { n.relationship = v; rel.querySelectorAll('.chip').forEach(c => c.setAttribute('aria-pressed', String(c.textContent === label(RELATIONSHIPS, v)))); });
    const age = chipsSingle(AGE_BANDS, n.ageBand, v => { n.ageBand = v; age.querySelectorAll('.chip').forEach(c => c.setAttribute('aria-pressed', String(c.textContent === label(AGE_BANDS, v)))); });
    clear(addForm).append(h('div', { class: 'member' }, h('h2', { text: 'Add a family member' }), fName,
      h('p', { class: 'label', text: 'Relationship to you' }), rel, h('p', { class: 'label', text: 'Age group' }), age,
      h('div', { class: 'row' },
        h('button', { type: 'button', class: 'btn btn-blue', text: 'Add to household', onclick: () => {
          if (!name.value.trim()) { fName.setError('Enter a name.'); return name.focus(); }
          n.name = name.value.trim(); draft.family.push(n); clear(addForm); render(); refresh(); } }),
        h('button', { type: 'button', class: 'btn-text', text: 'Cancel', onclick: () => clear(addForm) }))));
    name.focus();
  }
  function render() {
    clear(list).append(...draft.family.map(memberCard));
    sizeNote.textContent = `You said ${draft.household.size || draft.family.length} ${draft.household.size === 1 ? 'person lives' : 'people live'} here. ${draft.family.length} added so far.`;
  }
  const consentBox = h('input', { type: 'checkbox', id: 'health-consent', checked: !!draft.healthConsent });
  consentBox.onchange = () => { draft.healthConsent = consentBox.checked; render(); };
  render();
  const el = h('div', {},
    h('section', { class: 'q-block' },
      h('label', { class: 'check', for: 'health-consent' }, consentBox,
        h('span', {}, h('b', { style: { fontWeight: 500 }, text: 'Use health details to keep meal suggestions safe' }),
          h('span', { class: 'hint', style: { display: 'block' }, text: 'Allergies, diets and health goals are only visible to household members you allow. You can turn this off anytime.' })))),
    h('section', { class: 'q-block' }, h('h2', { text: 'Who are you planning meals for?' }), sizeNote, list, addForm,
      h('button', { type: 'button', class: 'btn btn-ghost', onclick: openAdd }, icon('plus', 20), 'Add family member')));
  return {
    el,
    validate: () => {
      if (!draft.family.length) return 'Add at least one person.';
      if (draft.family.some(m => !m.name?.trim())) return 'Every family member needs a name.';
      return null;
    },
    answers: () => [[Q.FAMILY, '', draft.family.map(m => ({ ...m, name: m.name.trim(),
      ...(draft.healthConsent ? {} : { allergies: [], diets: [], health: [] }) }))], [Q.HEALTH_CONSENT, '', !!draft.healthConsent]],
    afterSave: async () => {
      if (!!draft.healthConsent === consentAtStart) return;
      await tx(['consent_record'], 'readwrite', t => t.add('consent_record', { id: crypto.randomUUID(), user_id: user.id, consent_type: 'HEALTH_DATA_PROCESSING',
        document_version: '1', granted: !!draft.healthConsent, recorded_at: new Date().toISOString() }));
    },
  };
}
