import { h, stepper, chips, clear } from '../../core/dom.js';
import { STORAGE_TYPES, APPLIANCES, COOKWARE, UTENSILS, STORAGE_HINT } from '../../inquiry/questions.js';
import { Q, kitchenList } from '../../inquiry/draft.js';

export function create({ draft, refresh }) {
  const kitchens = kitchenList(draft.kitchens);
  for (const k of kitchens) { draft.storage[k.key] ??= {}; draft.appliances[k.key] ??= []; draft.cookware[k.key] ??= []; draft.utensils[k.key] ??= []; }
  let active = kitchens[0]?.key;
  const panel = h('div');
  const tabs = kitchens.length > 1 ? h('div', { class: 'kitchen-tabs', role: 'tablist', 'aria-label': 'Kitchens' }) : null;
  function renderTabs() {
    if (!tabs) return;
    clear(tabs).append(...kitchens.map(k => h('button', { type: 'button', role: 'tab', class: 'chip', 'aria-selected': String(k.key === active),
      'aria-pressed': String(k.key === active), text: k.name, onclick: () => { active = k.key; renderTabs(); renderPanel(); } })));
  }
  function renderPanel() {
    const k = kitchens.find(x => x.key === active);
    const counts = draft.storage[k.key];
    clear(panel).append(
      h('section', { class: 'q-block' }, h('h2', { text: kitchens.length > 1 ? `Where do you keep food in the ${k.name.toLowerCase()}?` : 'Where do you keep food?' }),
        h('p', { class: 'hint', text: 'Shelves and drawers are added for you for each type. You can rename them later.' }),
        h('div', { class: 'counter-list' }, STORAGE_TYPES.map(t => {
          const row = h('div', { class: `counter${counts[t.code] ? ' has-value' : ''}` },
            h('div', {}, h('div', { class: 'name', text: t.name }), STORAGE_HINT[t.code] ? h('div', { class: 'sub', text: STORAGE_HINT[t.code] }) : null),
            stepper({ value: counts[t.code] || 0, max: 10, label: t.name, onChange: v => { counts[t.code] = v; row.classList.toggle('has-value', v > 0); refresh(); } }));
          return row;
        }))),
      h('section', { class: 'q-block' }, h('h2', { text: 'Which cooking appliances do you have?' }),
        chips(APPLIANCES, draft.appliances[k.key], v => { draft.appliances[k.key] = v; refresh(); })),
      h('section', { class: 'q-block' }, h('h2', { text: 'Pots and pans' }),
        chips(COOKWARE, draft.cookware[k.key], v => { draft.cookware[k.key] = v; refresh(); })),
      h('section', { class: 'q-block' }, h('h2', { text: 'Utensils' }),
        chips(UTENSILS, draft.utensils[k.key], v => { draft.utensils[k.key] = v; refresh(); })));
  }
  renderTabs(); renderPanel();
  return {
    el: h('div', {}, tabs, panel),
    validate: () => {
      const empty = kitchens.filter(k => !Object.values(draft.storage[k.key]).some(n => n > 0));
      if (empty.length === kitchens.length) return 'Add at least one place where you keep food, like a refrigerator or pantry.';
      return null;
    },
    answers: () => kitchens.flatMap(k => [[Q.STORAGE, k.key, draft.storage[k.key]], [Q.APPLIANCES, k.key, draft.appliances[k.key]],
      [Q.COOKWARE, k.key, draft.cookware[k.key]], [Q.UTENSILS, k.key, draft.utensils[k.key]]]),
  };
}
