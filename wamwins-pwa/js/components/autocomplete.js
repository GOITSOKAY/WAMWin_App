import { h, icon, clear } from '../core/dom.js';

/**
 * AutocompleteField / MasterDataSearch: suggestions appear only from 3 characters, after a 300 ms pause.
 * `search(query)` returns a SCOPED result (max ~8 items) - callers query the reference data or the database for
 * that text only; nothing large is put into screen state. Keyboard: arrows move, Enter picks, Esc closes.
 * Works for foods, appliance brands/models, storage types, dietary terms and future master-data fields.
 */
export const MIN_CHARS = 3, DEBOUNCE_MS = 300;

export function autocomplete({ id, label, placeholder = '', search, onPick, onAddNew, addLabel = (q) => `Add “${q}” as new`, describe = () => '', minChars = MIN_CHARS, debounceMs = DEBOUNCE_MS }) {
  const input = h('input', { class: 'input', id, type: 'search', placeholder, autocomplete: 'off', role: 'combobox', 'aria-autocomplete': 'list',
    'aria-expanded': 'false', 'aria-controls': `${id}-list` });
  const list = h('div', { class: 'search-results', id: `${id}-list`, role: 'listbox', 'aria-label': `${label} suggestions`, hidden: true });
  const hint = h('p', { class: 'hint ac-hint', 'aria-live': 'polite', text: '' });
  let timer = null, active = -1, options = [], seq = 0;
  const close = () => { list.hidden = true; input.setAttribute('aria-expanded', 'false'); active = -1; };
  const setActive = (i) => { options.forEach((o, n) => o.setAttribute('aria-selected', String(n === i))); active = i; options[i]?.scrollIntoView?.({ block: 'nearest' });
    if (options[i]) input.setAttribute('aria-activedescendant', options[i].id); };
  async function run(raw) {
    const q = raw.trim(), mine = ++seq;
    if (q.length < minChars) { close(); clear(list); hint.textContent = q.length ? `Type ${minChars - q.length} more character${minChars - q.length === 1 ? '' : 's'} to see suggestions.` : ''; return; }
    hint.textContent = '';
    const hits = await search(q);
    if (mine !== seq) return;                                   // a newer query is in flight
    clear(list); options = [];
    hits.forEach((item, i) => { const o = h('button', { type: 'button', role: 'option', id: `${id}-o${i}`, 'aria-selected': 'false', onclick: () => pick(item) },
      h('span', { text: item.name }), h('span', { class: 'hint', text: describe(item) })); options.push(o); list.append(o); });
    if (!hits.length) list.append(h('p', { class: 'hint', style: { padding: '12px 12px 0' }, text: `“${q}” isn’t in the WAMWins list yet.` }));
    if (onAddNew && !hits.some(i => i.name.toLowerCase() === q.toLowerCase())) {
      const o = h('button', { type: 'button', role: 'option', class: 'add-new', id: `${id}-new`, 'aria-selected': 'false', onclick: () => { close(); onAddNew(q); } },
        icon('plus', 18), h('span', { text: addLabel(q) }));
      options.push(o); list.append(o);
    }
    list.hidden = false; input.setAttribute('aria-expanded', 'true'); active = -1;
  }
  function pick(item) { input.value = ''; clear(list); close(); onPick(item); }
  input.oninput = () => { clearTimeout(timer); const v = input.value; timer = setTimeout(() => run(v), debounceMs); };
  input.onkeydown = (e) => {
    if (list.hidden) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); setActive(Math.min(active + 1, options.length - 1)); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(Math.max(active - 1, 0)); }
    else if (e.key === 'Enter' && active >= 0) { e.preventDefault(); options[active].click(); }
    else if (e.key === 'Escape') { e.preventDefault(); close(); }
  };
  const el = h('div', { class: 'field ac' }, h('label', { class: 'label', for: id, text: label }), input, hint, list);
  return { el, input, focus: () => input.focus(), dispose: () => clearTimeout(timer) };
}

/** Scoped search over an in-memory reference list (small lists) - returns at most `limit` matches. */
export const searchList = (list, key = 'name', limit = 8) => async (q) => {
  const s = q.toLowerCase();
  return list.filter(x => String(x[key]).toLowerCase().includes(s)).sort((a, b) => String(a[key]).toLowerCase().indexOf(s) - String(b[key]).toLowerCase().indexOf(s)).slice(0, limit);
};
