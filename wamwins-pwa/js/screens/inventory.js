import { h, icon, clear, toast, field } from '../core/dom.js';
import { tx } from '../data/db.js';
import { REF } from '../inquiry/reference.js';
import { canUse } from '../tier/capabilities.js';
import { post, createLot, transfer, flags, statusFor, useSoonOn, today, r4, STORES, TYPE_NAMES, InventoryError } from '../inventory/ledger.js';
import { newFoodForm } from '../inventory/new-food-form.js';

// Inventory (manual encoding, WAMWins Basic): browse, add, use, throw away, correct, move, open, expire, return,
// edit details, history, and the household's own foods. Every quantity change goes through the ledger.
// Loaded only when opened; one household's rows, rendered 50 at a time; released when the screen closes.
const PAGE = 50;
const live = (rows) => rows.filter(r => !r.deleted_at);
const fmt = (v) => String(r4(Number(v)));
const sym = (code) => REF.units.find(u => u.code === code)?.symbol ?? code.toLowerCase();
const unitsFor = (code) => { const dim = REF.units.find(u => u.code === code)?.dimension;
  return REF.units.filter(u => u.dimension === dim && (dim !== 'COUNT' || u.code === code || ['PIECE', 'PACK'].includes(u.code))); };
const niceDate = (iso) => iso ? new Date(`${iso}T00:00:00`).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) : '';
const WASTE_REASONS = ['Spoiled', 'Past its date', 'Leftovers thrown out', 'Spilled or damaged', 'Other'];

async function load(hh) {
  return tx(['kitchen', 'storage_instance', 'storage_section', 'inventory_item', 'item_master', 'item_allergen'], 'readonly', async t => ({
    kitchens: live(await t.byIndex('kitchen', 'household_id', hh)).sort((a, b) => a.sort_order - b.sort_order),
    storage: live(await t.byIndex('storage_instance', 'household_id', hh)),
    sections: live(await t.byIndex('storage_section', 'household_id', hh)).sort((a, b) => a.ordinal - b.ordinal),
    items: live(await t.byIndex('inventory_item', 'household_id', hh)),
    myFoods: live(await t.byIndex('item_master', 'household_id', hh)),
    myAllergens: await t.byIndex('item_allergen', 'household_id', hh),
  }));
}

export async function mount(root, ctx) {
  const m = (await tx(['household_membership'], 'readonly', t => t.byIndex('household_membership', 'user_id', ctx.user.id))).find(x => x.status === 'ACTIVE');
  if (!m || !(await canUse(m.household_id, 'MANUAL_INVENTORY'))) { ctx.go('home', true); return { dispose() {} }; }
  const hh = m.household_id, userId = ctx.user.id;
  const caps = { history: await canUse(hh, 'INVENTORY_HISTORY'), soon: await canUse(hh, 'USE_SOON_ALERTS'), low: await canUse(hh, 'LOW_STOCK_ALERTS') };
  let data = await load(hh);
  let view = { name: 'list' };
  const filter = { q: '', place: 'ALL', show: 'IN_STOCK' };
  let limit = PAGE;

  const title = h('h1', { tabindex: '-1', style: { fontSize: 'var(--step-1)' }, text: 'Inventory' });
  const main = h('main', { class: 'content', id: 'main' });
  const back = h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Back', onclick: () => (view.name === 'list' ? ctx.go('home') : go({ name: 'list' })) }, icon('back'));
  root.append(h('div', { class: 'frame' }, h('header', { class: 'topbar' }, back, title), main));

  // ---- lookups
  const kitchenOf = (id) => data.kitchens.find(k => k.id === id);
  const places = () => data.storage.slice().sort((a, b) => (kitchenOf(a.kitchen_id)?.sort_order ?? 0) - (kitchenOf(b.kitchen_id)?.sort_order ?? 0) || a.sort_order - b.sort_order)
    .map(s => ({ ...s, label: data.kitchens.length > 1 ? `${s.name} (${kitchenOf(s.kitchen_id)?.name ?? ''})` : s.name }));
  const placeOf = (id) => places().find(p => p.id === id);
  const sectionsOf = (storageId) => data.sections.filter(s => s.storage_instance_id === storageId);
  const allergensOf = (itemId) => data.myAllergens.filter(a => a.item_master_id === itemId).map(a => a.allergen_code);
  function foodOf(id) {
    const g = REF.items.find(i => i.id === id);
    if (g) return { id, name: g.name, unit: g.unit, zone: g.zone, shelfLife: g.shelfLife, category: g.category };
    const f = data.myFoods.find(x => x.id === id);
    return f ? { id, name: f.canonical_name, unit: f.default_unit_code, zone: f.storage_zone, shelfLife: {}, category: f.food_category_code, mine: true }
      : { id, name: 'Food item', unit: 'PIECE', zone: 'ANY', shelfLife: {} };
  }
  const nameOf = (it) => foodOf(it.item_master_id).name ?? it.label;

  function go(v) {
    view = v;
    title.textContent = { list: 'Inventory', item: 'Food details', add: 'Add food', foods: 'Your foods' }[v.name];
    back.setAttribute('aria-label', v.name === 'list' ? 'Back to home' : 'Back to inventory');
    render();
    window.scrollTo?.(0, 0);
    title.focus();
  }
  async function reload() { data = await load(hh); }
  async function save(stores, fn, okMessage) {
    try { const r = await tx(stores, 'readwrite', fn); await reload(); if (okMessage) toast(okMessage); return r ?? true; }
    catch (e) { if (!(e instanceof InventoryError)) console.error(e); throw e; }
  }
  function render() {
    clear(main);
    const v = view.name === 'item' ? itemView(view.id) : view.name === 'add' ? addView() : view.name === 'foods' ? foodsView() : listView();
    main.append(h('div', { class: 'stack' }, v));
  }

  // ======================================================================= list
  function badges(it, now = today()) {
    const f = flags(it, now);
    return [f.expired ? h('span', { class: 'tag danger', text: 'Expired' }) : null,
      caps.soon && f.useSoon ? h('span', { class: 'tag warn', text: `Use by ${niceDate(it.use_soon_on)}` }) : null,
      caps.low && f.low ? h('span', { class: 'tag', text: 'Running low' }) : null,
      f.opened ? h('span', { class: 'tag blue', text: 'Opened' }) : null,
      f.usedUp ? h('span', { class: 'tag', text: { DISCARDED: 'Thrown away', EXPIRED: 'Expired', DEPLETED: 'Used up' }[it.lifecycle_status] ?? 'Used up' }) : null];
  }
  function listView() {
    const now = today(), stock = data.items.filter(i => i.quantity > 0);
    const n = { soon: stock.filter(i => flags(i, now).useSoon).length, expired: stock.filter(i => flags(i, now).expired).length, low: stock.filter(i => flags(i, now).low).length };
    const attention = [caps.soon && n.expired ? ['EXPIRED', `Expired (${n.expired})`, 'danger'] : null, caps.soon && n.soon ? ['USE_SOON', `Use soon (${n.soon})`, 'warn'] : null,
      caps.low && n.low ? ['LOW', `Running low (${n.low})`, ''] : null].filter(Boolean);
    const listEl = h('div', { class: 'inv-list', 'aria-live': 'polite' });
    const search = h('input', { class: 'input', type: 'search', id: 'inv-search', placeholder: 'Search your food', value: filter.q, autocomplete: 'off' });
    search.oninput = () => { filter.q = search.value; limit = PAGE; drawList(); };
    const place = h('select', { class: 'input', id: 'inv-place' }, [h('option', { value: 'ALL', text: 'All places' }), ...places().map(p => h('option', { value: p.id, selected: filter.place === p.id, text: p.label }))]);
    place.onchange = () => { filter.place = place.value; limit = PAGE; drawList(); };
    const show = h('select', { class: 'input', id: 'inv-show' }, [['IN_STOCK', 'In stock'], ['USE_SOON', 'Use soon'], ['EXPIRED', 'Expired'], ['LOW', 'Running low'], ['USED_UP', 'Used up or thrown away']]
      .map(([v, t]) => h('option', { value: v, selected: filter.show === v, text: t })));
    show.onchange = () => { filter.show = show.value; limit = PAGE; drawList(); };

    function drawList() {
      clear(listEl);
      const q = filter.q.trim().toLowerCase();
      const rows = data.items.filter(it => {
        const f = flags(it, now);
        if (filter.place !== 'ALL' && it.storage_instance_id !== filter.place) return false;
        if (q && !nameOf(it).toLowerCase().includes(q)) return false;
        return { IN_STOCK: !f.usedUp, USE_SOON: f.useSoon, EXPIRED: f.expired, LOW: f.low, USED_UP: f.usedUp }[filter.show];
      });
      const order = places().map(p => p.id);
      rows.sort((a, b) => order.indexOf(a.storage_instance_id) - order.indexOf(b.storage_instance_id) || nameOf(a).localeCompare(nameOf(b)));
      if (!rows.length) {
        listEl.append(h('p', { class: 'empty', text: data.items.length ? 'Nothing matches. Try another place, filter or search.' : 'No food yet. Tap “Add food” to start your inventory.' }));
        return;
      }
      let current = null;
      for (const it of rows.slice(0, limit)) {
        if (it.storage_instance_id !== current) {
          current = it.storage_instance_id;
          listEl.append(h('h2', { class: 'inv-group', text: placeOf(current)?.label ?? 'Storage' }));
        }
        const sec = data.sections.find(s => s.id === it.storage_section_id)?.name;
        listEl.append(h('button', { type: 'button', class: 'inv-item', 'aria-label': `${nameOf(it)}, ${fmt(it.quantity)} ${sym(it.unit_code)}`, onclick: () => go({ name: 'item', id: it.id }) },
          h('span', { class: 'nm', text: nameOf(it) }),
          h('span', { class: 'qty', text: `${fmt(it.quantity)} ${sym(it.unit_code)}` }),
          h('span', { class: 'meta' }, sec ? h('span', { text: sec }) : null, ...badges(it, now)),
          icon('chev', 18)));
      }
      if (rows.length > limit) listEl.append(h('button', { type: 'button', class: 'btn btn-ghost btn-block', text: `Show more (${rows.length - limit} more)`, onclick: () => { limit += PAGE; drawList(); } }));
    }
    drawList();
    return [
      h('div', { class: 'row' },
        h('button', { type: 'button', class: 'btn btn-primary', onclick: () => go({ name: 'add' }) }, icon('plus', 20), h('span', { text: 'Add food' })),
        h('button', { type: 'button', class: 'btn btn-ghost', text: 'Your foods', onclick: () => go({ name: 'foods' }) })),
      attention.length ? h('section', { class: 'attention', 'aria-label': 'Needs attention' },
        h('h2', { text: 'Needs attention' }),
        h('div', { class: 'chips' }, attention.map(([code, label, cls]) => h('button', { type: 'button', class: `chip ${cls}`, text: label,
          onclick: () => { filter.show = code; filter.place = 'ALL'; render(); } })))) : null,
      h('div', { class: 'inv-filters' }, field({ label: 'Search', input: search }), field({ label: 'Place', input: place }), field({ label: 'Show', input: show })),
      listEl,
    ];
  }

  // ======================================================================= item
  function itemView(id) {
    const it = data.items.find(i => i.id === id);
    if (!it) { setTimeout(() => go({ name: 'list' })); return h('p', { text: '' }); }
    const food = foodOf(it.item_master_id), place = placeOf(it.storage_instance_id), u = sym(it.unit_code);
    const sec = data.sections.find(s => s.id === it.storage_section_id)?.name;
    const panel = h('div', { class: 'action-panel', 'aria-live': 'polite' });
    const has = it.quantity > 0;

    async function change(type, delta, reason, message) {
      await save(STORES, async t => post(t, { hh, item: await t.get('inventory_item', it.id), type, delta, reason, userId, unitLabel: u }), message);
      go({ name: 'item', id: it.id });
    }
    function amountForm({ heading, confirm, defaultAmount = '', mode = 'delta', reasons, reasonLabel = 'Reason', sign, type, message }) {
      clear(panel);
      const amt = h('input', { class: 'input', type: 'number', id: 'act-amount', min: '0', step: 'any', inputmode: 'decimal', value: defaultAmount });
      const reason = reasons ? h('select', { class: 'input', id: 'act-reason' }, reasons.map(r => h('option', { value: r, text: r }))) : null;
      const err = h('p', { class: 'form-error', role: 'alert' });
      const ok = h('button', { type: 'button', class: 'btn btn-primary', text: confirm });
      ok.onclick = async () => {
        err.textContent = '';
        const v = Number(amt.value);
        if (!(v >= 0) || amt.value === '' || (mode === 'delta' && v === 0)) { err.textContent = 'Enter an amount.'; return; }
        const delta = mode === 'exact' ? r4(v - it.quantity) : sign * v;
        if (mode === 'exact' && delta === 0) { err.textContent = `It’s already ${fmt(it.quantity)} ${u}.`; return; }
        ok.disabled = true;
        try { await change(mode === 'exact' ? 'CORRECTION' : type, delta, reason?.value ?? (mode === 'exact' ? 'Counted again' : null), message(v)); }
        catch (e) { err.textContent = e.message; ok.disabled = false; }
      };
      panel.append(h('div', { class: 'custom-food' }, h('h3', { text: heading }),
        h('div', { class: 'food-fields' }, h('label', { class: 'mini' }, h('span', { text: mode === 'exact' ? `Amount now (${u})` : `Amount (${u})` }), amt),
          reason ? h('label', { class: 'mini' }, h('span', { text: reasonLabel }), reason) : null),
        err, h('div', { class: 'row' }, ok, h('button', { type: 'button', class: 'btn-text', text: 'Cancel', onclick: () => clear(panel) }))));
      amt.focus();
    }
    function moveForm() {
      clear(panel);
      const dest = h('select', { class: 'input', id: 'move-place' }, places().map(p => h('option', { value: p.id, selected: p.id === it.storage_instance_id, text: p.label })));
      const shelf = h('select', { class: 'input', id: 'move-section' });
      const fillShelves = () => { clear(shelf).append(h('option', { value: '', text: 'No specific shelf' }), ...sectionsOf(dest.value).map(s => h('option', { value: s.id, text: s.name }))); };
      dest.onchange = fillShelves; fillShelves();
      const amt = h('input', { class: 'input', type: 'number', id: 'move-amount', min: '0', step: 'any', inputmode: 'decimal', value: fmt(it.quantity) });
      const err = h('p', { class: 'form-error', role: 'alert' });
      const ok = h('button', { type: 'button', class: 'btn btn-primary', text: 'Move' });
      ok.onclick = async () => {
        const v = Number(amt.value);
        if (!(v > 0)) { err.textContent = 'Enter an amount.'; return; }
        if (dest.value === it.storage_instance_id && (shelf.value || null) === (it.storage_section_id || null)) { err.textContent = 'Choose a different place or shelf.'; return; }
        ok.disabled = true;
        try {
          const to = placeOf(dest.value);
          const r = await save(STORES, async t => transfer(t, { hh, userId, item: await t.get('inventory_item', it.id), food, toStorage: to, toSectionId: shelf.value || null, quantity: v }),
            `Moved ${fmt(v)} ${u} to ${to.label}.`);
          go({ name: 'item', id: r.to.id });
        } catch (e) { err.textContent = e.message; ok.disabled = false; }
      };
      panel.append(h('div', { class: 'custom-food' }, h('h3', { text: 'Move to another place' }),
        h('div', { class: 'food-fields' }, h('label', { class: 'mini' }, h('span', { text: 'To' }), dest), h('label', { class: 'mini' }, h('span', { text: 'Shelf' }), shelf),
          h('label', { class: 'mini' }, h('span', { text: `Amount (${u})` }), amt)),
        err, h('div', { class: 'row' }, ok, h('button', { type: 'button', class: 'btn-text', text: 'Cancel', onclick: () => clear(panel) }))));
    }
    async function setDetails(patch, message) {
      await save(STORES, async t => {
        const cur = { ...(await t.get('inventory_item', it.id)), ...patch };
        cur.use_soon_on = useSoonOn({ purchasedOn: cur.purchased_on, zone: place?.temperature_zone, shelfLife: food.shelfLife, expiresOn: cur.expires_on, bestBeforeOn: cur.best_before_on, openedOn: cur.opened_on });
        cur.lifecycle_status = statusFor(cur);
        return t.update('inventory_item', cur);
      }, message);
      go({ name: 'item', id: it.id });
    }
    const act = (label, ic, fn, cls = 'btn-ghost') => h('button', { type: 'button', class: `btn ${cls}`, onclick: fn }, icon(ic, 18), h('span', { text: label }));
    const actions = has ? [
      act('Use some', 'minus', () => amountForm({ heading: 'Use some', confirm: 'Use', type: 'OTHER', sign: -1, reasons: ['Used', 'Eaten as a snack', 'Given away'], message: v => `Used ${fmt(v)} ${u} of ${food.name}.` }), 'btn-primary'),
      act('Add more', 'plus', () => amountForm({ heading: 'Add more', confirm: 'Add', type: 'PURCHASE', sign: 1, reasons: ['Bought', 'Received', 'Found more'], reasonLabel: 'How', message: v => `Added ${fmt(v)} ${u}.` })),
      act('Throw away', 'trash', () => amountForm({ heading: 'Throw away', confirm: 'Throw away', type: 'WASTE', sign: -1, defaultAmount: fmt(it.quantity), reasons: WASTE_REASONS, message: v => `Threw away ${fmt(v)} ${u}.` })),
      act('Correct amount', 'edit', () => amountForm({ heading: 'Correct the amount', confirm: 'Save amount', mode: 'exact', defaultAmount: fmt(it.quantity), reasons: ['Counted again', 'Entered wrong before', 'Other'], message: v => `Amount set to ${fmt(v)} ${u}.` })),
      act('Move', 'box', moveForm),
      !it.opened_on ? act('Mark as opened', 'check', () => setDetails({ opened_on: today() }, 'Marked as opened.')) : null,
      act('Mark as expired', 'clock', async () => { await change('EXPIRED', -it.quantity, null, `${food.name} marked as expired.`); }),
      act('Returned to store', 'back', () => amountForm({ heading: 'Returned to the store', confirm: 'Return', type: 'RETURN', sign: -1, defaultAmount: fmt(it.quantity), message: v => `Returned ${fmt(v)} ${u}.` })),
    ] : [
      act('Add more', 'plus', () => amountForm({ heading: 'Add more', confirm: 'Add', type: 'PURCHASE', sign: 1, reasons: ['Bought', 'Received', 'Found more'], reasonLabel: 'How', message: v => `Added ${fmt(v)} ${u}.` }), 'btn-primary'),
      act('Remove from the list', 'trash', async () => { await save(STORES, async t => t.update('inventory_item', { ...(await t.get('inventory_item', it.id)), deleted_at: new Date().toISOString() }), `${food.name} removed from the list.`); go({ name: 'list' }); }),
    ];

    // details editor
    const shelf = h('select', { class: 'input', id: 'det-section' }, [h('option', { value: '', text: 'No specific shelf' }), ...sectionsOf(it.storage_instance_id).map(s => h('option', { value: s.id, selected: s.id === it.storage_section_id, text: s.name }))]);
    const useBy = h('input', { class: 'input', type: 'date', id: 'det-expires', value: it.expires_on ?? '' });
    const bought = h('input', { class: 'input', type: 'date', id: 'det-purchased', value: it.purchased_on ?? '' });
    const lowAt = h('input', { class: 'input', type: 'number', id: 'det-low', min: '0', step: 'any', inputmode: 'decimal', value: it.low_stock_threshold ?? '' });
    const notes = h('input', { class: 'input', id: 'det-notes', maxlength: '200', value: it.notes ?? '' });
    const detErr = h('p', { class: 'form-error', role: 'alert' });
    const saveDet = h('button', { type: 'button', class: 'btn btn-primary', text: 'Save details' });
    saveDet.onclick = async () => {
      if (lowAt.value !== '' && !(Number(lowAt.value) >= 0)) { detErr.textContent = 'The running-low amount must be zero or more.'; return; }
      saveDet.disabled = true;
      try { await setDetails({ storage_section_id: shelf.value || null, expires_on: useBy.value || null, purchased_on: bought.value || null,
        low_stock_threshold: lowAt.value === '' ? null : Number(lowAt.value), notes: notes.value.trim() || null }, 'Details saved.'); }
      catch (e) { detErr.textContent = e.message; saveDet.disabled = false; }
    };
    const historyEl = h('div', { class: 'history' });
    if (caps.history) tx(['inventory_transaction'], 'readonly', t => t.byIndex('inventory_transaction', 'household_id', hh)).then(rows => {
      const mine = rows.filter(r => r.inventory_item_id === it.id).sort((a, b) => b.occurred_at.localeCompare(a.occurred_at)).slice(0, 50);
      clear(historyEl).append(...mine.map(r => h('div', { class: 'hist-row' },
        h('span', { text: TYPE_NAMES[r.transaction_type_code] ?? r.transaction_type_code }),
        h('span', { class: r.quantity_delta < 0 ? 'neg' : 'pos', text: `${r.quantity_delta > 0 ? '+' : ''}${fmt(r.quantity_delta)} ${sym(r.unit_code)}` }),
        h('span', { class: 'meta', text: `${new Date(r.occurred_at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })} · ${fmt(r.quantity_before)} → ${fmt(r.quantity_after)}${r.reason ? ` · ${r.reason}` : ''}` }))));
    });

    return [
      h('section', { class: 'item-head' },
        h('h2', { text: food.name }),
        h('p', { class: 'hint', text: [place?.label, sec].filter(Boolean).join(' · ') }),
        h('p', { class: 'big-qty', text: `${fmt(it.quantity)} ${u}` }),
        h('div', { class: 'row' }, ...badges(it)),
        h('p', { class: 'hint', text: [it.purchased_on && `Added ${niceDate(it.purchased_on)}`, it.opened_on && `opened ${niceDate(it.opened_on)}`,
          it.expires_on && `use by ${niceDate(it.expires_on)}`, it.use_soon_on && `best used by ${niceDate(it.use_soon_on)}`].filter(Boolean).join(' · ') })),
      h('div', { class: 'actions-grid' }, actions),
      panel,
      h('details', { class: 'disclosure' }, h('summary', { text: 'Edit details' }), h('div', {},
        h('div', { class: 'food-fields' }, h('label', { class: 'mini' }, h('span', { text: 'Shelf' }), shelf), h('label', { class: 'mini' }, h('span', { text: 'Use by' }), useBy),
          h('label', { class: 'mini' }, h('span', { text: 'Added on' }), bought), h('label', { class: 'mini' }, h('span', { text: `Alert when at or below (${u})` }), lowAt)),
        field({ label: 'Note (optional)', input: notes }), detErr, h('div', { class: 'row' }, saveDet))),
      caps.history ? h('details', { class: 'disclosure', open: true }, h('summary', { text: 'History' }), historyEl) : null,
    ];
  }

  // ======================================================================= add
  function addView() {
    const all = places();
    if (!all.length) return h('p', { class: 'empty', text: 'Add a storage place first: Home → Update my answers → Kitchens & equipment.' });
    let food = null;
    const place = h('select', { class: 'input', id: 'add-place' }, all.map(p => h('option', { value: p.id, selected: p.id === filter.place, text: p.label })));
    const shelf = h('select', { class: 'input', id: 'add-section' });
    const fillShelves = () => clear(shelf).append(h('option', { value: '', text: 'No specific shelf' }), ...sectionsOf(place.value).map(s => h('option', { value: s.id, text: s.name })));
    place.onchange = fillShelves; fillShelves();
    const picker = h('div');
    const details = h('div');
    const mine = () => data.myFoods.map(f => foodOf(f.id));

    function pickFood() {
      clear(picker); clear(details); food = null;
      const search = h('input', { class: 'input', type: 'search', id: 'add-search', placeholder: 'Search foods, e.g. rice, eggs, chicken', autocomplete: 'off' });
      const results = h('div', { class: 'search-results', role: 'listbox', 'aria-label': 'Matching foods', hidden: true });
      const custom = h('div');
      search.oninput = () => {
        const raw = search.value.trim(), q = raw.toLowerCase();
        clear(results);
        if (!q) { results.hidden = true; return; }
        const hits = [...mine(), ...REF.items.map(i => foodOf(i.id))].filter(i => i.name.toLowerCase().includes(q)).slice(0, 8);
        results.hidden = false;
        for (const i of hits) results.append(h('button', { type: 'button', role: 'option', onclick: () => choose(i) },
          h('span', { text: i.name }), h('span', { class: 'hint', text: i.mine ? 'your food' : (i.zone === 'ANY' ? '' : i.zone.toLowerCase()) })));
        if (!hits.some(i => i.name.toLowerCase() === q)) {
          if (!hits.length) results.append(h('p', { class: 'hint', style: { padding: '12px 12px 0' }, text: `“${raw}” isn’t in the WAMWins list yet.` }));
          results.append(h('button', { type: 'button', role: 'option', class: 'add-new', onclick: () => openNew(raw) }, icon('plus', 18), h('span', { text: `Add “${raw}” as a new food` })));
        }
      };
      function openNew(name) {
        results.hidden = true;
        const zone = placeOf(place.value)?.temperature_zone;
        clear(custom).append(newFoodForm({ initial: { name, zone: ['CHILLED', 'FROZEN'].includes(zone) ? zone : 'AMBIENT' },
          onSave: async (v) => {
            const known = [...mine(), ...REF.items.map(i => foodOf(i.id))].find(i => i.name.toLowerCase() === v.name.toLowerCase());
            if (known) return choose(known);
            const id = await createFood(v);
            choose(foodOf(id));
          },
          onCancel: () => { clear(custom); search.focus(); } }));
      }
      picker.append(h('div', { class: 'field' }, h('label', { class: 'label', for: 'add-search', text: 'Food' }), search, results), custom);
      search.focus();
    }
    function choose(f) {
      food = f;
      clear(picker).append(h('div', { class: 'chosen' }, h('b', { text: f.name }), f.mine ? h('span', { class: 'tag blue', text: 'your food' }) : null,
        h('button', { type: 'button', class: 'btn-text', text: 'Change', onclick: pickFood })));
      const start = { G: 500, ML: 500, KG: 1, L: 1 }[f.unit] ?? 1;
      const amt = h('input', { class: 'input', type: 'number', id: 'add-amount', min: '0', step: 'any', inputmode: 'decimal', value: String(start) });
      const unit = h('select', { class: 'input', id: 'add-unit' }, unitsFor(f.unit).map(x => h('option', { value: x.code, selected: x.code === f.unit, text: x.symbol })));
      const how = h('select', { class: 'input', id: 'add-how' }, [['PURCHASE', 'Bought it'], ['MANUAL_ADD', 'Already had it']].map(([v, t]) => h('option', { value: v, text: t })));
      const bought = h('input', { class: 'input', type: 'date', id: 'add-date', value: today() });
      const useBy = h('input', { class: 'input', type: 'date', id: 'add-expires' });
      const lowAt = h('input', { class: 'input', type: 'number', id: 'add-low', min: '0', step: 'any', inputmode: 'decimal' });
      const err = h('p', { class: 'form-error', role: 'alert' });
      const ok = h('button', { type: 'button', class: 'btn btn-primary', text: 'Add to inventory' });
      ok.onclick = async () => {
        err.textContent = '';
        if (!(Number(amt.value) > 0)) { err.textContent = 'Enter an amount greater than zero.'; amt.focus(); return; }
        ok.disabled = true;
        try {
          const to = placeOf(place.value);
          await save(STORES, t => createLot(t, { hh, userId, food, storage: to, sectionId: shelf.value || null, quantity: Number(amt.value), unit: unit.value,
            purchasedOn: bought.value || today(), expiresOn: useBy.value || null, lowStock: lowAt.value === '' ? null : Number(lowAt.value), type: how.value }),
            `Added ${fmt(amt.value)} ${sym(unit.value)} of ${food.name} to ${to.label}.`);
          filter.place = 'ALL'; filter.show = 'IN_STOCK';
          go({ name: 'list' });
        } catch (e) { err.textContent = e.message; ok.disabled = false; }
      };
      clear(details).append(h('div', { class: 'food-fields' },
        h('label', { class: 'mini' }, h('span', { text: 'Amount' }), amt), h('label', { class: 'mini' }, h('span', { text: 'Unit' }), unit),
        h('label', { class: 'mini' }, h('span', { text: 'How' }), how), h('label', { class: 'mini' }, h('span', { text: 'Added on' }), bought),
        h('label', { class: 'mini' }, h('span', { text: 'Use by (optional)' }), useBy),
        h('label', { class: 'mini' }, h('span', { text: 'Alert when at or below (optional)' }), lowAt)), err, h('div', { class: 'row' }, ok));
      amt.focus();
    }
    pickFood();
    return [h('section', { class: 'q-block' }, field({ label: 'Where is it kept?', input: place }), field({ label: 'Shelf (optional)', input: shelf })),
      h('section', { class: 'q-block' }, picker, details)];
  }

  // ======================================================================= your foods
  async function createFood(v) {
    const id = crypto.randomUUID();
    await save(['item_master', 'item_allergen', 'local_mutation_outbox'], async t => {
      await t.insert('item_master', { id, household_id: hh, item_kind: 'FOOD', canonical_name: v.name, display_name: null, search_name: v.name.toLowerCase(),
        food_category_code: v.category, default_unit_code: v.unit, storage_zone: v.zone, is_perishable: v.zone !== 'AMBIENT', is_verified: false, created_source_code: 'MANUAL' });
      for (const code of v.allergens) await t.insert('item_allergen', { id: `${id}|${code}`, household_id: hh, item_master_id: id, allergen_code: code, presence: 'CONTAINS' });
    }, `${v.name} saved as your food.`);
    return id;
  }
  function foodsView() {
    const box = h('div');
    const listEl = h('div');
    const foods = data.myFoods.slice().sort((a, b) => a.canonical_name.localeCompare(b.canonical_name));
    const lots = (id) => data.items.filter(i => i.item_master_id === id);
    for (const f of foods) {
      const inStock = lots(f.id).some(i => i.quantity > 0);
      const al = allergensOf(f.id);
      listEl.append(h('div', { class: 'inv-row' },
        h('div', {}, h('b', { style: { fontWeight: 500 }, text: f.canonical_name }),
          h('div', { class: 'meta', text: [REF.foodCategories.find(c => c.code === f.food_category_code)?.name, REF.units.find(x => x.code === f.default_unit_code)?.name,
            { AMBIENT: 'room temperature', CHILLED: 'fridge', FROZEN: 'freezer' }[f.storage_zone]].filter(Boolean).join(' · ') }),
          al.length ? h('div', { class: 'row', style: { gap: '4px', marginTop: '4px' } }, al.map(c => h('span', { class: 'tag danger', text: REF.allergens.find(a => a.code === c)?.name ?? c }))) : null),
        h('div', { class: 'row' },
          h('button', { type: 'button', class: 'btn-text', text: 'Edit', 'aria-label': `Edit ${f.canonical_name}`, onclick: () => edit(f) }),
          h('button', { type: 'button', class: 'btn-text', text: 'Remove', 'aria-label': `Remove ${f.canonical_name}`, disabled: inStock, title: inStock ? 'Use up or throw away the stock first' : '',
            onclick: async () => {
              await save(['item_master', 'local_mutation_outbox'], async t => t.update('item_master', { ...(await t.get('item_master', f.id)), deleted_at: new Date().toISOString() }), `${f.canonical_name} removed from your foods.`);
              go({ name: 'foods' });
            } }))));
    }
    function edit(f) {
      clear(box).append(newFoodForm({ title: `Edit ${f.canonical_name}`, hint: 'Changes apply wherever this food is stored.', saveLabel: 'Save changes', lockUnit: lots(f.id).length > 0,
        initial: { name: f.canonical_name, category: f.food_category_code, unit: f.default_unit_code, zone: f.storage_zone, allergens: allergensOf(f.id) },
        onSave: async (v) => {
          const clash = [...data.myFoods.filter(x => x.id !== f.id).map(x => x.canonical_name), ...REF.items.map(i => i.name)].find(n => n.toLowerCase() === v.name.toLowerCase());
          if (clash) throw new Error(`“${clash}” already exists. Choose another name.`);
          await save(['item_master', 'item_allergen', 'inventory_item', 'local_mutation_outbox'], async t => {
            const cur = await t.get('item_master', f.id);
            await t.update('item_master', { ...cur, canonical_name: v.name, search_name: v.name.toLowerCase(), food_category_code: v.category,
              default_unit_code: lots(f.id).length ? cur.default_unit_code : v.unit, storage_zone: v.zone, is_perishable: v.zone !== 'AMBIENT' });
            for (const code of allergensOf(f.id)) if (!v.allergens.includes(code)) await t.del('item_allergen', `${f.id}|${code}`);
            for (const code of v.allergens) if (!allergensOf(f.id).includes(code)) await t.insert('item_allergen', { id: `${f.id}|${code}`, household_id: hh, item_master_id: f.id, allergen_code: code, presence: 'CONTAINS' });
            for (const lot of (await t.byIndex('inventory_item', 'household_id', hh)).filter(i => i.item_master_id === f.id && !i.deleted_at)) await t.update('inventory_item', { ...lot, label: v.name });
          }, 'Changes saved.');
          go({ name: 'foods' });
        },
        onCancel: () => clear(box) }));
      box.scrollIntoView?.({ block: 'nearest' });
    }
    const addNew = h('button', { type: 'button', class: 'btn btn-ghost', onclick: () => clear(box).append(newFoodForm({ title: 'Add a new food', saveLabel: 'Save food',
      onSave: async (v) => {
        if ([...data.myFoods.map(x => x.canonical_name), ...REF.items.map(i => i.name)].some(n => n.toLowerCase() === v.name.toLowerCase())) throw new Error(`“${v.name}” already exists.`);
        await createFood(v); go({ name: 'foods' });
      }, onCancel: () => clear(box) })) }, icon('plus', 18), h('span', { text: 'Add a new food' }));
    return [h('p', { class: 'hint', text: 'Foods you added that aren’t in the WAMWins list. Only your household sees them.' }), addNew, box,
      foods.length ? listEl : h('p', { class: 'empty', text: 'You haven’t added any foods of your own yet.' })];
  }

  go({ name: 'list' });
  return { dispose() { data = null; } };
}
