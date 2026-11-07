import { h, field } from '../core/dom.js';
import { REF } from '../inquiry/reference.js';

// "Add a new food" / "Edit your food" - the few facts WAMWins needs to store, count and keep it safe.
// Used by the setup food step and the Inventory screen.
export const CUSTOM_UNITS = ['PIECE', 'G', 'KG', 'ML', 'L', 'PACK', 'CAN', 'BOTTLE', 'BUNCH', 'DOZEN', 'SLICE', 'CUP'];
export const ZONES = [['AMBIENT', 'Room temperature'], ['CHILLED', 'Fridge'], ['FROZEN', 'Freezer']];

export function newFoodForm({ title = 'Add a new food', hint = 'It’s saved as your household’s own food, so you can find it again next time.',
  initial = {}, lockUnit = false, saveLabel = 'Add food', onSave, onCancel }) {
  const nameIn = h('input', { class: 'input', id: 'custom-name', value: initial.name ?? '', maxlength: '80', autocomplete: 'off' });
  const cat = h('select', { class: 'input', id: 'custom-cat' }, REF.foodCategories.map(c => h('option', { value: c.code, selected: c.code === (initial.category ?? 'OTHER'), text: c.name })));
  const unit = h('select', { class: 'input', id: 'custom-unit', disabled: lockUnit }, CUSTOM_UNITS.map(code => REF.units.find(u => u.code === code)).filter(Boolean)
    .map(u => h('option', { value: u.code, selected: u.code === (initial.unit ?? 'PIECE'), text: `${u.name} (${u.symbol})` })));
  const zone = h('select', { class: 'input', id: 'custom-zone' }, ZONES.map(([code, label]) => h('option', { value: code, selected: code === (initial.zone ?? 'AMBIENT'), text: label })));
  const allergens = new Set(initial.allergens ?? []);
  const chipRow = h('div', { class: 'chips', role: 'group', 'aria-label': 'Allergens it contains' }, REF.allergens.map(a => {
    const b = h('button', { type: 'button', class: 'chip warn', 'aria-pressed': String(allergens.has(a.code)), text: a.name });
    b.onclick = () => { allergens.has(a.code) ? allergens.delete(a.code) : allergens.add(a.code); b.setAttribute('aria-pressed', String(allergens.has(a.code))); };
    return b;
  }));
  const err = h('p', { class: 'form-error', role: 'alert' });
  nameIn.oninput = () => { err.textContent = ''; };
  const save = h('button', { type: 'button', class: 'btn btn-primary', text: saveLabel });
  save.onclick = async () => {
    const name = nameIn.value.trim().replace(/\s+/g, ' ');
    if (!name) { err.textContent = 'Enter the food’s name.'; nameIn.focus(); return; }
    save.disabled = true;
    try { await onSave({ name, category: cat.value, unit: unit.value, zone: zone.value, allergens: [...allergens] }); }
    catch (e) { err.textContent = e.message || 'The food couldn’t be saved.'; }
    finally { save.disabled = false; }
  };
  const el = h('div', { class: 'custom-food' },
    h('h3', { text: title }), h('p', { class: 'hint', text: hint }),
    field({ label: 'Name', input: nameIn }),
    h('div', { class: 'food-fields' },
      h('label', { class: 'mini' }, h('span', { text: 'Food group' }), cat),
      h('label', { class: 'mini' }, h('span', { text: 'Measured in' }), unit),
      h('label', { class: 'mini' }, h('span', { text: 'Usually kept' }), zone)),
    lockUnit ? h('p', { class: 'hint', text: 'The unit can’t change while this food is in stock.' }) : null,
    h('div', { class: 'field' }, h('span', { class: 'label', text: 'Does it contain any of these? (optional)' }),
      h('p', { class: 'hint', text: 'Helps keep meal suggestions safe for people with allergies.' }), chipRow),
    err,
    h('div', { class: 'row' }, save, h('button', { type: 'button', class: 'btn-text', text: 'Cancel', onclick: onCancel })));
  setTimeout(() => nameIn.focus(), 0);
  return el;
}
