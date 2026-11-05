import { h, icon, clear, toast, stepper, append } from '../core/dom.js';
import { tx } from '../data/db.js';
import { canUse } from '../tier/capabilities.js';
import { MATCH_REF } from '../matching/reference.js';
import { rankRecipes, ENGINE_VERSION } from '../matching/engine.js';
import { UnitConverter } from '../matching/units.js';
import { buildInputs } from '../matching/inputs.js';
import { loadSnapshot, saveRun, confirmMeal } from '../matching/store.js';

// "What can we cook?" - same screen and behaviour as the Flutter app. This module, the engine and the recipe
// data load only when the screen opens, and are released when it closes.
const SLOTS = [['ANY', 'Any meal'], ['BREAKFAST', 'Breakfast'], ['LUNCH', 'Lunch'], ['DINNER', 'Dinner'], ['SNACK', 'Snack']];
const REASONS = { ALLERGEN: 'Allergy', INTOLERANCE: 'Intolerance', DIETARY: 'Diet', HEALTH_RULE: 'Health goal', EQUIPMENT: 'Equipment', TOO_MANY_MISSING: 'Too many ingredients missing' };
const today = () => { const d = new Date(); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10); };

export async function mount(root, ctx) {
  const m = (await tx(['household_membership'], 'readonly', t => t.byIndex('household_membership', 'user_id', ctx.user.id))).find(x => x.status === 'ACTIVE');
  if (!m || !(await canUse(m.household_id, 'MEAL_MATCHING'))) { ctx.go('home', true); return { dispose() {} }; }   // capability gate, never "which tier?"
  const hh = m.household_id;
  const units = new UnitConverter(MATCH_REF);
  let snapshot = await loadSnapshot(hh);
  const members = snapshot.members.filter(x => !x.deleted_at && x.is_active !== false)
    .sort((a, b) => (b.linked_user_id === ctx.user.id) - (a.linked_user_id === ctx.user.id) || a.created_at.localeCompare(b.created_at));
  let selected = new Set(members.map(x => x.id)), slot = 'ANY';
  const results = h('section', { 'aria-live': 'polite' });
  const error = h('p', { class: 'form-error', role: 'alert' });

  const memberChips = h('div', { class: 'chips' }, members.map(mem => {
    const b = h('button', { type: 'button', class: 'chip', 'aria-pressed': 'true', text: mem.display_name });
    b.onclick = () => { selected.has(mem.id) ? selected.delete(mem.id) : selected.add(mem.id); b.setAttribute('aria-pressed', String(selected.has(mem.id))); };
    return b;
  }));
  const slotChips = h('div', { class: 'chips', role: 'radiogroup', 'aria-label': 'Meal' }, SLOTS.map(([code, name]) => {
    const b = h('button', { type: 'button', class: 'chip', role: 'radio', 'aria-pressed': String(code === slot), 'aria-checked': String(code === slot), text: name });
    b.onclick = () => { slot = code; slotChips.querySelectorAll('.chip').forEach(c => { const on = c === b; c.setAttribute('aria-pressed', String(on)); c.setAttribute('aria-checked', String(on)); }); };
    return b;
  }));
  const find = h('button', { type: 'button', class: 'btn btn-primary btn-block', text: 'Find meals' });

  find.onclick = async () => {
    error.textContent = '';
    if (!selected.size) { error.textContent = 'Choose who you’re cooking for.'; return; }
    find.disabled = true; find.textContent = 'Finding meals…';
    try {
      const started = performance.now();
      snapshot = await loadSnapshot(hh);                                   // fresh stock after any cooking
      const input = buildInputs({ snapshot, ref: MATCH_REF, memberIds: [...selected], mealSlot: slot === 'ANY' ? null : slot, today: today() });
      const { ranked, excluded } = await rankRecipes(input, units);
      const run = await saveRun({ hh, userId: ctx.user.id, mealSlot: slot === 'ANY' ? null : slot, maxResults: 5, maxMissing: 3, engineVersion: ENGINE_VERSION,
        members: input.members, ranked, excluded, candidateCount: input.recipes.length, durationMs: Math.round(performance.now() - started) });
      render(run.results, excluded);
    } catch (e) {
      console.error(e);
      error.textContent = 'Meals couldn’t be matched right now. Your other features still work.';
    } finally { find.disabled = false; find.textContent = 'Find meals'; }
  };

  const factor = (r, code) => r.factors.find(f => f.code === code)?.explanation ?? '';
  function line(ic, cls, text) { return h('p', { class: `match-line ${cls}` }, icon(ic, 18), h('span', { text })); }

  function render(list, excluded) {
    clear(results);
    results.append(
      h('h2', { text: list.length ? 'Suggested for you' : 'No safe matches yet' }),
      h('p', { class: 'hint', text: list.length ? 'Ranked by what you already have, what needs using soon, and your family’s preferences.'
        : 'Nothing fits everyone with what you have. Try fewer people, another meal, or add food to your inventory.' }));
    for (const r of list) {
      const card = h('article', { class: `match-card${r.rank === 1 ? ' best' : ''}`, 'aria-label': r.title });
      const actions = h('div', { class: 'match-actions' });
      const soft = factor(r, 'HEALTH_RULE'), pref = factor(r, 'PREFERENCE');
      append(card, [
        h('div', { class: 'match-head' }, h('h3', { text: r.title }), r.rank === 1 ? h('span', { class: 'tag blue', text: 'Best match' }) : null),
        line('shield', 'ok', factor(r, 'SAFETY')),
        line('box', 'blue', factor(r, 'INVENTORY')),
        r.useSoon.length ? line('clock', 'soon', factor(r, 'USE_SOON')) : null,
        r.missing.length ? line('basket', 'muted', factor(r, 'PURCHASE_MINIMIZATION')) : null,
        soft ? line('info', 'muted', soft) : null,
        pref && !pref.startsWith('No stated') ? line('heart', 'muted', pref) : null,
        actions]);
      const recipe = MATCH_REF.recipes.find(x => x.id === r.recipeId);
      const showCook = () => {
        let servings = recipe.servings;
        const confirm = h('button', { type: 'button', class: 'btn btn-primary', text: 'Cook this' });
        clear(actions).append(h('div', { class: 'cook-panel' },
          h('p', { class: 'hint', text: 'The ingredients will be taken out of your inventory, oldest use-by date first.' }),
          h('div', { class: 'counter' }, h('div', {}, h('div', { class: 'name', text: 'Servings' })), stepper({ value: servings, min: 1, max: 20, label: 'servings', onChange: v => { servings = v; } })),
          h('div', { class: 'row' }, confirm, h('button', { type: 'button', class: 'btn-text', text: 'Cancel', onclick: idle }))));
        confirm.onclick = async () => {
          confirm.disabled = true;
          try {
            const c = await confirmMeal({ hh, userId: ctx.user.id, matchResultId: r.matchResultId, servings, mealSlot: slot === 'ANY' ? null : slot, today: today(), ref: MATCH_REF, units });
            clear(actions).append(h('p', { class: 'match-line ok' }, icon('check', 18), h('span', { text: 'Saved to your meals' })));
            card.querySelector('.match-head').append(h('span', { class: 'tag ok', text: 'Cooked' }));
            toast(c.shortfalls.length ? `Enjoy! Not enough in stock for: ${c.shortfalls.join(', ')}.` : 'Enjoy! The ingredients were taken out of your inventory.');
          } catch (e) { console.error(e); confirm.disabled = false; toast('The meal couldn’t be saved. Nothing was changed.'); }
        };
      };
      const idle = () => clear(actions).append(h('button', { type: 'button', class: 'btn btn-primary', text: 'Cook this', onclick: showCook }));
      idle();
      results.append(card);
    }
    if (excluded.length) results.append(h('details', { class: 'disclosure not-suggested' },
      h('summary', { text: `Not suggested (${excluded.length})` }),
      h('div', {}, h('p', { class: 'hint', text: 'Why some recipes were left out' }), excluded.map(e => h('div', { class: 'excluded' },
        h('b', { text: MATCH_REF.recipes.find(x => x.id === e.recipeId)?.title ?? 'Recipe' }),
        h('span', { class: ['ALLERGEN', 'INTOLERANCE'].includes(e.reason) ? 'danger' : '', text: `${REASONS[e.reason] ?? e.reason}: ${e.detail}` }))))));
    results.querySelector('h2')?.focus?.();
  }

  root.append(h('div', { class: 'frame' },
    h('header', { class: 'topbar' },
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Back to home', onclick: () => ctx.go('home') }, icon('back')),
      h('h1', { tabindex: '-1', style: { fontSize: 'var(--step-1)' }, text: 'What can we cook?' })),
    h('main', { class: 'content', id: 'main' }, h('div', { class: 'stack' },
      h('section', { class: 'q-block' }, h('h2', { text: 'Cooking for' }), h('p', { class: 'hint', text: 'Allergies and diets of everyone selected are checked first.' }), memberChips),
      h('section', { class: 'q-block' }, h('h2', { text: 'Meal' }), slotChips),
      find, error, results))));
  return { dispose() { snapshot = null; } };
}
