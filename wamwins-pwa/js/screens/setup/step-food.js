import { h, clear, icon, field } from '../../core/dom.js';
import { REF } from '../../inquiry/reference.js';
import { Q, kitchenList, storageList } from '../../inquiry/draft.js';

export function create({ draft, refresh }) {
  const places = kitchenList(draft.kitchens).flatMap(k => storageList(draft, k.key).map(s => ({ ...s, label: kitchenList(draft.kitchens).length > 1 ? `${s.name} (${k.name})` : s.name })));
  let place = places[0]?.key;
  const unitsFor = (code) => { const dim = REF.units.find(u => u.code === code)?.dimension; return REF.units.filter(u => u.dimension === dim && (dim !== 'COUNT' || u.code === code || ['PIECE', 'PACK'].includes(u.code))); };
  const select = h('select', { class: 'input', id: 'food-place' }, places.map(p => h('option', { value: p.key, text: p.label })));
  select.onchange = () => { place = select.value; };
  const search = h('input', { class: 'input', type: 'search', placeholder: 'Search foods, e.g. rice, eggs, chicken', autocomplete: 'off', enterkeyhint: 'search' });
  const results = h('div', { class: 'search-results', role: 'listbox', 'aria-label': 'Matching foods', hidden: true });
  const rows = h('div');
  const updateLabel = () => {};
  search.oninput = () => {
    const q = search.value.trim().toLowerCase();
    clear(results);
    if (!q) { results.hidden = true; return; }
    const hits = REF.items.filter(i => i.name.toLowerCase().includes(q)).slice(0, 8);
    results.hidden = false;
    if (!hits.length) results.append(h('p', { class: 'hint', style: { padding: '12px' }, text: `No match for “${search.value.trim()}”. You can add your own foods after setup.` }));
    for (const i of hits) results.append(h('button', { type: 'button', role: 'option', onclick: () => add(i) },
      h('span', { text: i.name }), h('span', { class: 'hint', text: i.zone === 'ANY' ? '' : i.zone.toLowerCase() })));
  };
  function add(item) {
    const start = { G: 500, ML: 500, KG: 1, L: 1 }[item.unit] ?? 1;                // a realistic starting amount for the unit
    draft.food.push({ key: crypto.randomUUID(), itemId: item.id, name: item.name, storageKey: place, quantity: start, unit: item.unit, expiresOn: '' });
    search.value = ''; results.hidden = true; clear(results); render(); refresh(); search.focus();
  }
  function render() {
    clear(rows);
    if (!draft.food.length) { rows.append(h('p', { class: 'empty', text: 'No food added yet. Search above, or skip this step and add food later.' })); return; }
    for (const f of draft.food) {
      const qty = h('input', { class: 'input', type: 'number', min: '0.1', step: 'any', inputmode: 'decimal', value: String(f.quantity), 'aria-label': `Amount of ${f.name}` });
      qty.oninput = () => { f.quantity = Number(qty.value); };
      const unit = h('select', { class: 'input', 'aria-label': `Unit for ${f.name}` }, unitsFor(f.unit).map(u => h('option', { value: u.code, selected: u.code === f.unit, text: u.symbol })));
      unit.onchange = () => { f.unit = unit.value; };
      const exp = h('input', { class: 'input', type: 'date', value: f.expiresOn || '', 'aria-label': `Use-by date for ${f.name}` });
      exp.onchange = () => { f.expiresOn = exp.value; };
      rows.append(h('div', { class: 'inv-row' },
        h('div', {}, h('b', { style: { fontWeight: 500 }, text: f.name }), h('div', { class: 'meta', text: places.find(p => p.key === f.storageKey)?.label || '' })),
        h('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${f.name}`, onclick: () => { draft.food.splice(draft.food.indexOf(f), 1); render(); refresh(); } }, icon('x', 20)),
        h('div', { class: 'food-fields' },
          h('label', { class: 'mini' }, h('span', { text: 'Amount' }), qty), h('label', { class: 'mini' }, h('span', { text: 'Unit' }), unit),
          h('label', { class: 'mini' }, h('span', { text: 'Use by (optional)' }), exp))));
    }
  }
  render();
  const api = {
    el: h('div', {},
      h('section', { class: 'q-block' },
        field({ label: 'Where is it kept?', input: select }),
        h('div', { class: 'field' }, h('label', { class: 'label', for: 'food-search', text: 'Add food' }), Object.assign(search, { id: 'food-search' }), results)),
      h('section', { class: 'q-block' }, h('h2', { text: 'Food you’re adding' }), rows)),
    nextLabel: () => (draft.food.length ? 'Continue' : 'Skip for now'),
    validate: () => draft.food.some(f => !(f.quantity > 0)) ? 'Each food needs an amount greater than zero.' : null,
    answers: () => [[Q.FOOD, '', draft.food.filter(f => places.some(p => p.key === f.storageKey))]],
  };
  const origRefresh = refresh;
  refresh = () => { origRefresh(); api.onNextLabel?.(api.nextLabel()); };
  return api;
}
