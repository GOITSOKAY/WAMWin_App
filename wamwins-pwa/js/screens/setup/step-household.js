import { h, field, stepper } from '../../core/dom.js';
import { KITCHEN_TYPES } from '../../inquiry/questions.js';
import { Q } from '../../inquiry/draft.js';
import { ensureHousehold } from '../../inquiry/provisioning.js';

export function create({ draft, user, session, refresh }) {
  const hh = draft.household;
  const first = (draft.about.displayName || user.display_name || '').trim().split(/\s+/)[0];
  hh.name ??= first ? `${first}’s household` : 'My household';
  hh.size ??= Math.max(2, draft.family.length);
  const name = h('input', { class: 'input', type: 'text', value: hh.name, maxlength: 80 });
  name.oninput = () => { hh.name = name.value; refresh(); };
  const fName = field({ label: 'Household name', hint: 'Shown to people you invite later.', input: name });
  const counter = (label, sub, value, max, onChange) => h('div', { class: `counter${value ? ' has-value' : ''}` },
    h('div', {}, h('div', { class: 'name', text: label }), sub ? h('div', { class: 'sub', text: sub }) : null),
    stepper({ value, min: 0, max, label, onChange: (v) => { onChange(v); } }));
  const kitchenRows = KITCHEN_TYPES.map(t => {
    const row = counter(t.name, null, draft.kitchens[t.code] || 0, 5, v => { draft.kitchens[t.code] = v; row.classList.toggle('has-value', v > 0); refresh(); });
    return row;
  });
  const el = h('div', {},
    h('section', { class: 'q-block' }, fName),
    h('section', { class: 'q-block' }, h('h2', { text: 'How many people live in your home?' }),
      h('div', { class: 'counter-list' }, counter('People', 'Including you', hh.size, 20, v => { hh.size = Math.max(1, v); }))),
    h('section', { class: 'q-block' }, h('h2', { text: 'Which kitchens do you have?' }),
      h('p', { class: 'hint', text: 'Count each separate cooking area, like an outdoor or dirty kitchen.' }),
      h('div', { class: 'counter-list' }, kitchenRows)));
  return {
    el,
    validate: () => {
      fName.setError(hh.name?.trim() ? '' : 'Enter a household name.');
      if (!hh.name?.trim()) return 'Enter a household name.';
      if (!Object.values(draft.kitchens).some(n => n > 0)) return 'Add at least one kitchen.';
      if (!hh.size || hh.size < 1) return 'At least one person lives in the household.';
      return null;
    },
    answers: () => [[Q.HOUSEHOLD, '', { ...hh, name: hh.name.trim() }], [Q.KITCHENS, '', draft.kitchens]],
    afterSave: () => ensureHousehold(user, session, { ...hh, name: hh.name.trim() }),
  };
}
