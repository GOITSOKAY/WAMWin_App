import { h, icon, clear, field } from '../../core/dom.js';
import { REF } from '../../inquiry/reference.js';
import { CONDITIONS } from '../../inquiry/questions.js';
import { allStorage, sectionOptions } from '../../inquiry/draft.js';
import { autocomplete, searchList } from '../../components/autocomplete.js';
import { newFoodForm } from '../../inventory/new-food-form.js';
import { infoButton } from '../../components/info.js';
import { tierLockedFeatures, FOOD_LOCKED } from '../../components/tier-locked.js';

// Module 6 - Food Inventories. Food becomes inventory_item + an opening MANUAL_ADD ledger transaction when entries are
// saved (quantities never change any other way). Optional fields stay optional and tucked under "More details".
const US_UNITS = { MASS: ['OZ', 'LB', 'G', 'KG'], VOLUME: ['FL_OZ', 'CUP', 'PINT', 'QUART', 'GALLON', 'TBSP', 'TSP', 'ML', 'L'] };
const dimOf = (code) => REF.units.find(u => u.code === code)?.dimension;
const unitLabel = (u) => u.code === 'PIECE' ? 'each' : u.symbol;
function unitsFor(code, imperial) {
  const dim = dimOf(code);
  if (dim === 'COUNT') return REF.units.filter(u => u.dimension === 'COUNT' && (u.code === code || ['PIECE', 'PACK', 'DOZEN'].includes(u.code)));
  const order = imperial ? US_UNITS[dim] ?? [] : [...(US_UNITS[dim] ?? [])].reverse();
  return order.map(c => REF.units.find(u => u.code === c)).filter(Boolean);
}
function startAmount(unit, imperial) {
  const dim = dimOf(unit);
  if (imperial && dim === 'MASS') return { unit: 'LB', quantity: 1 };
  if (imperial && dim === 'VOLUME') return { unit: 'FL_OZ', quantity: 16 };
  return { unit, quantity: { G: 500, ML: 500 }[unit] ?? 1 };
}

export async function create({ draft, session, refresh }) {
  const imperial = draft.about.measures !== 'METRIC';
  const places = allStorage(draft).map(s => ({ ...s, label: draft.kitchens.length > 1 ? `${s.name} (${s.kitchenName})` : s.name }));
  draft.food = draft.food.filter(f => places.some(p => p.key === f.storageKey));          // storage removed in Module 3
  const loc = { storage: places[0]?.key ?? null, section: null, container: null };
  const list = h('div', { class: 'stack' });
  const customBox = h('div');
  const disposers = [];
  const myFoods = () => [...new Map(draft.food.filter(f => f.custom).map(f => [f.itemId, { id: f.itemId, name: f.name, unit: f.custom.unit, zone: f.custom.zone, mine: true }])).values()];

  // ---- where it's kept
  const storageSel = h('select', { class: 'input', id: 'food-storage' }, places.map(p => h('option', { value: p.key, text: p.label })));
  const sectionSel = h('select', { class: 'input', id: 'food-section' });
  const containerSel = h('select', { class: 'input', id: 'food-container' });
  const fillPlaces = () => {
    const s = places.find(p => p.key === loc.storage); const o = s ? sectionOptions(s) : { sections: [], containers: [] };
    clear(sectionSel).append(h('option', { value: '', text: 'No specific section' }), ...o.sections.map(x => h('option', { value: x.key, text: x.name })));
    clear(containerSel).append(h('option', { value: '', text: 'No container' }), ...o.containers.map(x => h('option', { value: x.key, text: x.name })));
    sectionSel.disabled = !o.sections.length; containerSel.disabled = !o.containers.length; loc.section = null; loc.container = null;
  };
  storageSel.onchange = () => { loc.storage = storageSel.value; fillPlaces(); };
  sectionSel.onchange = () => { loc.section = sectionSel.value || null; };
  containerSel.onchange = () => { loc.container = containerSel.value || null; };
  fillPlaces();

  function add(item, custom) {
    const a = startAmount(item.unit, imperial);
    const mine = custom ?? draft.food.find(f => f.itemId === item.id && f.custom)?.custom;
    draft.food.push({ key: crypto.randomUUID(), itemId: item.id, name: item.name, storageKey: loc.storage, sectionKey: loc.section, containerKey: loc.container,
      quantity: a.quantity, unit: a.unit, purchasedOn: new Date().toISOString().slice(0, 10), ...(mine ? { custom: mine } : {}) });
    clear(customBox); draw(); refresh(); search.focus();
  }
  const search = autocomplete({ id: 'food-search', label: 'Add food', placeholder: 'Type 3 letters, e.g. ric, egg, chi',
    search: async (q) => (await searchList([...myFoods(), ...REF.items])(q)), describe: i => i.mine ? 'your food' : (i.zone === 'ANY' ? '' : i.zone.toLowerCase()),
    addLabel: q => `Add “${q}” as a new food`, onPick: i => add(i),
    onAddNew: (q) => {
      const zone = places.find(p => p.key === loc.storage)?.zone;
      clear(customBox).append(newFoodForm({ initial: { name: q, zone: ['CHILLED', 'FROZEN'].includes(zone) ? zone : 'AMBIENT', unit: imperial ? 'OZ' : 'G' },
        onSave: ({ name, category, unit, zone: z, allergens }) => {
          const known = [...myFoods(), ...REF.items].find(i => i.name.toLowerCase() === name.toLowerCase());
          if (known) return add(known);
          add({ id: crypto.randomUUID(), name, unit }, { category, unit, zone: z, allergens, source: 'USER_DEFINED' });
        },
        onCancel: () => { clear(customBox); search.focus(); } }));
    } });
  disposers.push(search.dispose);

  function row(f) {
    const place = places.find(p => p.key === f.storageKey);
    const o = place ? sectionOptions(place) : { sections: [], containers: [] };
    const inp = (key, label, type = 'text', extra = {}) => { const i = h('input', { class: 'input', type, value: f[key] ?? '', id: `fd-${key}-${f.key}`, ...extra });
      i.oninput = () => { f[key] = type === 'number' ? (i.value === '' ? null : Number(i.value)) : i.value; }; return field({ label, input: i }); };
    const qty = h('input', { class: 'input', type: 'number', min: '0', step: 'any', inputmode: 'decimal', value: f.quantity, id: `fd-qty-${f.key}` });
    qty.oninput = () => { f.quantity = Number(qty.value); };
    const unit = h('select', { class: 'input', id: `fd-unit-${f.key}` }, unitsFor(f.unit, imperial).map(u => h('option', { value: u.code, selected: u.code === f.unit, text: unitLabel(u) })));
    unit.onchange = () => { f.unit = unit.value; };
    const sel = (key, label, opts, none) => { const s = h('select', { class: 'input', id: `fd-${key}-${f.key}` }, [h('option', { value: '', text: none }), ...opts.map(x => h('option', { value: x.key ?? x.code, selected: (x.key ?? x.code) === f[key], text: x.name }))]);
      s.onchange = () => { f[key] = s.value || null; }; return field({ label, input: s }); };
    const pkgUnit = h('select', { class: 'input', id: `fd-pkgunit-${f.key}` }, [h('option', { value: '', text: '—' }), ...unitsFor(f.unit, imperial).map(u => h('option', { value: u.code, selected: u.code === f.packageUnit, text: unitLabel(u) }))]);
    pkgUnit.onchange = () => { f.packageUnit = pkgUnit.value || null; };
    const dateInfo = infoButton({ label: 'Dates', title: 'Food dates', body: ['Best-by: quality is best before this date; usually still safe after. Use-by: use it by this date for safety or quality.',
      'Expiration: the last date the maker says to use it. WAMWins reminds you about the earliest of these.'] });
    return h('article', { class: 'food-row', 'aria-label': f.name },
      h('div', { class: 'member-head' }, h('div', { class: 'who' }, h('b', { text: f.name }), h('span', { class: 'hint', text: [place?.label, o.sections.find(x => x.key === f.sectionKey)?.name].filter(Boolean).join(' › ') })),
        h('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${f.name}`, onclick: () => { draft.food = draft.food.filter(x => x !== f); draw(); refresh(); } }, icon('close', 20))),
      h('div', { class: 'food-fields' }, field({ label: 'Quantity', input: qty }), field({ label: 'Unit', input: unit }), inp('expiresOn', 'Expiration date', 'date')),
      h('details', { class: 'disclosure' }, h('summary', { text: 'More details (optional)' }), h('div', {},
        h('div', { class: 'food-fields' }, inp('brand', 'Brand', 'text', { maxlength: 60 }), sel('packaging', 'Packaging', REF.packaging, 'Not set'),
          inp('packageSize', 'Package size', 'number', { min: '0', step: 'any' }), field({ label: 'Package unit', input: pkgUnit })),
        h('div', { class: 'food-fields' }, sel('sectionKey', 'Shelf / section', o.sections, 'No specific section'), sel('containerKey', 'Container', o.containers, 'No container')),
        h('p', { class: 'label with-info' }, h('span', { text: 'Dates' }), dateInfo),
        h('div', { class: 'food-fields' }, inp('purchasedOn', 'Purchase date', 'date'), inp('openedOn', 'Opened date', 'date'), inp('bestByOn', 'Best-by date', 'date'), inp('useByOn', 'Use-by date', 'date')),
        h('div', { class: 'food-fields' }, sel('condition', 'Condition', CONDITIONS, 'Not set'), inp('notes', 'Notes', 'text', { maxlength: 200 })))));
  }
  function draw() {
    clear(list);
    if (!draft.food.length) list.append(h('p', { class: 'empty', text: 'No food added yet. Search above, or skip this module and add food later from your inventory.' }));
    else list.append(...draft.food.map(row));
  }
  draw();
  const el = h('div', {},
    places.length ? h('section', { class: 'q-block' }, h('h2', { text: 'Where is it kept?' }),
      h('div', { class: 'food-fields' }, field({ label: 'Storage', input: storageSel }), field({ label: 'Shelf / section', input: sectionSel }), field({ label: 'Container', input: containerSel })),
      search.el, customBox)
      : h('p', { class: 'empty', text: 'Add a storage area in Kitchens & Storages first, or skip and add food later.' }),
    h('section', { class: 'q-block' }, h('h2', { text: 'Food you’re adding' }), list));
  tierLockedFeatures(session.household_id, FOOD_LOCKED).then(x => { if (x) el.append(x); });
  return {
    el,
    nextLabel: () => (draft.food.length ? 'Continue' : 'Skip for now'),
    validate: () => draft.food.some(f => !(f.quantity > 0)) ? 'Each food needs a quantity greater than zero.' : null,
    dispose: () => disposers.forEach(d => d()),
  };
}
