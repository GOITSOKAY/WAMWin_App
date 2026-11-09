import { h, icon, clear, field } from '../../core/dom.js';
import { APPLIANCE_TYPES, APPLIANCE_CONDITIONS } from '../../inquiry/questions.js';
import { allStorage } from '../../inquiry/draft.js';
import { infoButton } from '../../components/info.js';

// Module 4 - Kitchen Appliances. Electric (largest/built-in first) then manual/non-electrical. Only type/name and kitchen
// are needed; details are optional. A refrigerator/freezer appliance cross-references its storage unit (no duplicate objects).
const PROVIDES = { REFRIGERATOR: ['REFRIGERATOR', 'REFRIGERATOR_FREEZER'], UPRIGHT_FREEZER: ['FREEZER'], CHEST_FREEZER: ['CHEST_FREEZER'] };

export function create({ draft, refresh }) {
  let active = draft.kitchens[0]?.key;
  const body = h('div');
  const ofKitchen = () => draft.appliances.filter(a => a.kitchenKey === active);
  const storageIn = (types) => allStorage(draft).filter(s => s.kitchenKey === active && (!types || types.includes(s.type)));

  function details(a) {
    const inp = (key, label, type = 'text') => { const i = h('input', { class: 'input', type, value: a[key] ?? '', maxlength: 80, id: `ap-${key}-${a.key}` }); i.oninput = () => { a[key] = i.value; }; return field({ label, input: i }); };
    const nameIn = h('input', { class: 'input', value: a.name, maxlength: 80, id: `ap-name-${a.key}` }); nameIn.oninput = () => { a.name = nameIn.value; refresh(); };
    const loc = h('select', { class: 'input', id: `ap-loc-${a.key}` }, [h('option', { value: '', text: 'Not set' }), ...storageIn().map(s => h('option', { value: s.key, selected: s.key === a.location, text: s.name }))]);
    loc.onchange = () => { a.location = loc.value || null; };
    const cond = h('select', { class: 'input', id: `ap-cond-${a.key}` }, APPLIANCE_CONDITIONS.map(c => h('option', { value: c.code, selected: c.code === (a.condition ?? 'WORKING'), text: c.name })));
    cond.onchange = () => { a.condition = cond.value; };
    const notes = h('input', { class: 'input', value: a.notes ?? '', maxlength: 200, id: `ap-notes-${a.key}` }); notes.oninput = () => { a.notes = notes.value; };
    const links = PROVIDES[a.code] ? storageIn(PROVIDES[a.code]) : [];
    const link = links.length ? h('select', { class: 'input', id: `ap-link-${a.key}` }, [h('option', { value: '', text: 'Not linked' }), ...links.map(s => h('option', { value: s.key, selected: s.key === a.storageKey, text: s.name }))]) : null;
    if (link) link.onchange = () => { a.storageKey = link.value || null; };
    return h('details', { class: 'disclosure' }, h('summary', { text: 'Details (optional)' }), h('div', {},
      field({ label: 'Name', input: nameIn }),
      link ? field({ label: 'This is the appliance for storage area', hint: 'Links it to the storage you added, so it isn’t counted twice.', input: link }) : null,
      h('div', { class: 'food-fields' }, inp('brand', 'Brand'), inp('model', 'Model'), inp('serial', 'Serial number')),
      field({ label: 'Location', input: loc }),
      h('div', { class: 'food-fields' }, inp('purchasedOn', 'Date purchased', 'date'), inp('warrantyEnd', 'Warranty end date', 'date'), field({ label: 'Condition', input: cond })),
      field({ label: 'Notes', input: notes })));
  }
  function row(t) {
    const a = ofKitchen().find(x => x.code === t.code);
    const box = h('input', { type: 'checkbox', checked: !!a, id: `ap-${active}-${t.code}` });
    box.onchange = () => {
      if (box.checked) {
        const links = PROVIDES[t.code] ? storageIn(PROVIDES[t.code]) : [];
        draft.appliances.push({ key: `${active}:${t.code}`, kitchenKey: active, code: t.code, name: t.name, storageKey: links[0]?.key ?? null, condition: 'WORKING' });
      } else draft.appliances = draft.appliances.filter(x => !(x.kitchenKey === active && x.code === t.code));
      draw(); refresh();
    };
    return h('div', { class: `pick-row${a ? ' on' : ''}` }, h('label', { class: 'check' }, box, h('span', { text: t.name })), a ? details(a) : null);
  }
  function draw() {
    clear(body);
    const custom = ofKitchen().filter(a => !a.code);
    const newName = h('input', { class: 'input', maxlength: 80, id: 'ap-new', placeholder: 'e.g. Waffle maker' });
    const add = h('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
      const n = newName.value.trim(); if (!n) { newName.focus(); return; }
      draft.appliances.push({ key: crypto.randomUUID(), kitchenKey: active, code: null, name: n, condition: 'WORKING' }); draw(); refresh(); } }, icon('plus', 18), h('span', { text: 'Add Appliance' }));
    body.append(
      draft.kitchens.length > 1 ? h('div', { class: 'tabs', role: 'tablist', 'aria-label': 'Kitchens' }, draft.kitchens.map(k => h('button', { type: 'button', role: 'tab', 'aria-selected': String(k.key === active), text: k.name,
        onclick: () => { active = k.key; draw(); } }))) : null,
      h('section', { class: 'q-block' }, h('h2', { class: 'with-info' }, h('span', { text: 'Electrically operated' }),
        infoButton({ label: 'Appliance details', title: 'Appliance details', body: 'Only the appliance and its kitchen are needed. Brand, model, serial number and warranty dates are optional and help you later with repairs and warranties.' })),
        h('div', { class: 'pick-list' }, APPLIANCE_TYPES.filter(t => t.power_source === 'ELECTRIC').map(row))),
      h('section', { class: 'q-block' }, h('h2', { text: 'Manual / non-electrical equipment' }),
        h('div', { class: 'pick-list' }, APPLIANCE_TYPES.filter(t => t.power_source !== 'ELECTRIC').map(row))),
      h('section', { class: 'q-block' }, h('h2', { text: 'Something else?' }),
        custom.map(a => h('div', { class: 'pick-row on' }, h('div', { class: 'row', style: { justifyContent: 'space-between' } }, h('b', { style: { fontWeight: 500 }, text: a.name }),
          h('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${a.name}`, onclick: () => { draft.appliances = draft.appliances.filter(x => x !== a); draw(); refresh(); } }, icon('trash', 18))), details(a))),
        h('div', { class: 'row' }, field({ label: 'Appliance name', input: newName }), add)));
  }
  draw();
  return {
    el: body,
    nextLabel: () => (draft.appliances.length ? 'Continue' : 'Skip for now'),
    validate: () => draft.appliances.some(a => !a.name?.trim()) ? 'Every appliance needs a name.' : null,
  };
}
