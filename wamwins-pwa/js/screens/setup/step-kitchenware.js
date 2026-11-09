import { h, icon, clear, stepper, field } from '../../core/dom.js';
import { REF } from '../../inquiry/reference.js';
import { KITCHENWARE_CATEGORIES } from '../../inquiry/questions.js';

// Module 5 - Utensils & Kitchenware. One record per item type with a quantity (never one record per fork).
export function create({ draft, refresh }) {
  let active = draft.kitchens[0]?.key;
  const body = h('div');
  const find = (code) => draft.kitchenware.find(w => w.kitchenKey === active && w.code === code);

  function row(t) {
    const w = find(t.code);
    const box = h('input', { type: 'checkbox', checked: !!w, id: `kw-${active}-${t.code}` });
    box.onchange = () => {
      if (box.checked) draft.kitchenware.push({ key: `${active}:${t.code}`, kitchenKey: active, code: t.code, category: t.category, name: t.name, quantity: 1 });
      else draft.kitchenware = draft.kitchenware.filter(x => !(x.kitchenKey === active && x.code === t.code));
      draw(); refresh();
    };
    return h('div', { class: `pick-row inline${w ? ' on' : ''}` }, h('label', { class: 'check' }, box, h('span', { text: t.name })),
      w ? stepper({ value: w.quantity, min: 1, max: 99, label: `${t.name} quantity`, onChange: v => { w.quantity = v; } }) : null);
  }
  function customRow(w) {
    return h('div', { class: 'pick-row inline on' }, h('span', { text: w.name }),
      stepper({ value: w.quantity, min: 1, max: 99, label: `${w.name} quantity`, onChange: v => { w.quantity = v; } }),
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${w.name}`, onclick: () => { draft.kitchenware = draft.kitchenware.filter(x => x !== w); draw(); refresh(); } }, icon('trash', 18)));
  }
  function draw() {
    clear(body);
    const name = h('input', { class: 'input', maxlength: 80, id: 'kw-new', placeholder: 'e.g. Pizza stone' });
    const cat = h('select', { class: 'input', id: 'kw-new-cat' }, KITCHENWARE_CATEGORIES.map(c => h('option', { value: c.code, selected: c.code === 'OTHER', text: c.name })));
    const add = h('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
      const n = name.value.trim(); if (!n) { name.focus(); return; }
      draft.kitchenware.push({ key: crypto.randomUUID(), kitchenKey: active, code: null, category: cat.value, name: n, quantity: 1 }); draw(); refresh(); } }, icon('plus', 18), h('span', { text: 'Add Item' }));
    body.append(
      draft.kitchens.length > 1 ? h('div', { class: 'tabs', role: 'tablist', 'aria-label': 'Kitchens' }, draft.kitchens.map(k => h('button', { type: 'button', role: 'tab', 'aria-selected': String(k.key === active), text: k.name,
        onclick: () => { active = k.key; draw(); } }))) : null,
      ...KITCHENWARE_CATEGORIES.map(c => h('section', { class: 'q-block' }, h('h2', { text: c.name }),
        h('div', { class: 'pick-list' }, REF.kitchenwareTypes.filter(t => t.category === c.code).map(row),
          draft.kitchenware.filter(w => w.kitchenKey === active && !w.code && w.category === c.code).map(customRow)))),
      h('section', { class: 'q-block' }, h('h2', { text: 'Add something else' }), h('div', { class: 'food-fields' }, field({ label: 'Item', input: name }), field({ label: 'Category', input: cat })), add));
  }
  draw();
  return {
    el: body,
    nextLabel: () => (draft.kitchenware.length ? 'Continue' : 'Skip for now'),
    validate: () => draft.kitchenware.some(w => !(w.quantity >= 1)) ? 'Quantities must be 1 or more.' : null,
  };
}
