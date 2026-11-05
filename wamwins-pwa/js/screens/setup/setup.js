import { h, icon, wordmark, brandLogo, toast, clear } from '../../core/dom.js';
import { STEPS } from '../../inquiry/questions.js';
import { ensureSession, loadDraft, saveAnswers, deriveTree } from '../../inquiry/draft.js';

// Each step is its own module, loaded only when that step is opened.
const LOADERS = {
  about: () => import('./step-about.js'), household: () => import('./step-household.js'), kitchens: () => import('./step-kitchens.js'),
  family: () => import('./step-family.js'), food: () => import('./step-food.js'), review: () => import('./step-review.js'),
};
const ORDER = ['about', 'household', 'kitchens', 'family', 'food', 'review'];

export async function mount(root, ctx) {
  let stepId = ORDER.includes(ctx.arg) ? ctx.arg : 'about';
  const session = await ensureSession(ctx.user);
  if (ORDER.indexOf(stepId) > 1 && !session.household_id) { ctx.go('setup/household', true); return { dispose() {} }; }
  const draft = await loadDraft(session);
  const mod = await LOADERS[stepId]();
  const idx = ORDER.indexOf(stepId);
  const meta = STEPS[idx] || { title: 'Review your household', lead: 'Check your answers. WAMWins will create only what you see here.' };
  const step = await mod.create({ draft, user: ctx.user, session, refresh: () => renderTree(), go: ctx.go });

  // ---- live household tree (phone: pull-up sheet; >= 900px: side panel)
  const seen = new Set();
  const treeBody = h('div', { class: 'tree-body', id: 'tree-body' });
  const handleCount = h('span', { class: 'count' });
  const sheet = h('aside', { class: 'tree-sheet tree-panel', 'aria-label': 'Your household so far' },
    h('button', { type: 'button', class: 'handle', 'aria-expanded': 'false', 'aria-controls': 'tree-body' }, 'Your household so far', handleCount), treeBody);
  const handle = sheet.querySelector('.handle');
  handle.onclick = () => { const open = !sheet.classList.contains('open'); sheet.classList.toggle('open', open); handle.setAttribute('aria-expanded', String(open)); };
  function renderTree() {
    const t = deriveTree(draft);
    handleCount.textContent = `${t.moduleCount} modules`;
    const node = (key, cls, label) => { const fresh = seen.size > 0 && !seen.has(key); seen.add(key);
      return h('span', { class: `node ${cls}${fresh ? ' fresh' : ''}` }, h('span', { class: 'kind' }), h('span', { text: label })); };
    const tree = h('ul', { class: 'tree' },
      h('li', {}, node('household', 'kitchen', draft.household.name || 'Your household'),
        t.kitchens.length ? h('ul', {}, t.kitchens.map(k => h('li', {}, node(k.key, 'kitchen', k.equipment ? `${k.name} (${k.equipment} tool${k.equipment === 1 ? '' : 's'})` : k.name),
          k.storage.length ? h('ul', {}, k.storage.map(s => h('li', {}, node(s.key, 'storage', s.name),
            h('ul', {}, h('li', {}, node(`${s.key}#sec`, 'section', s.sections.join(', ') || 'Main area')),
              s.items ? h('li', {}, node(`${s.key}#items`, 'items', `${s.items} food item${s.items > 1 ? 's' : ''}`)) : null)))) : null))) : null),
      t.members ? h('li', {}, node('family', 'kitchen', `${t.members} family member${t.members > 1 ? 's' : ''}`)) : null);
    clear(treeBody).append(
      h('p', { class: 'tree-note', text: 'Built from your answers. Only these parts are set up for your household.' }),
      tree,
      h('div', { class: 'stack-s' }, h('h2', {}, 'Modules you’ll get', h('span', { class: 'count', text: `${t.moduleCount}` })),
        h('div', { class: 'module-pills' }, t.modules.filter(m => m.on).map(m => h('span', { class: 'on', text: m.name })))));
  }
  renderTree();

  // ---- frame
  const errorBox = h('p', { class: 'form-error', role: 'alert' });
  const next = h('button', { type: 'button', class: 'btn btn-primary', text: step.nextLabel?.() || (stepId === 'review' ? 'Create my household' : 'Continue') });
  step.onNextLabel = (label) => { next.textContent = label; };
  const back = idx > 0 ? h('button', { type: 'button', class: 'btn btn-ghost', 'aria-label': 'Back', onclick: () => ctx.go(`setup/${ORDER[idx - 1]}`) }, icon('back', 20)) : null;
  next.onclick = async () => {
    errorBox.textContent = '';
    const err = step.validate?.();
    if (err) { errorBox.textContent = err; errorBox.scrollIntoView({ block: 'center', behavior: 'smooth' }); return; }
    next.disabled = true;
    try {
      if (step.submit) { await step.submit(); return; }
      await saveAnswers(session, step.answers(), { current_step: ORDER[idx + 1] });
      await step.afterSave?.();
      ctx.go(`setup/${ORDER[idx + 1]}`);
    } catch (e) {
      console.error(e);
      errorBox.textContent = e?.message ? `Your answers could not be saved: ${e.message}` : 'Your answers could not be saved. Please try again.';
      next.disabled = false;
    }
  };
  const progress = idx < 5 ? h('div', { class: 'progress' },
    h('div', { class: 'progress-track', 'aria-hidden': 'true' }, STEPS.map((_, i) => h('span', { class: i < idx ? 'done' : i === idx ? 'now' : '' }))),
    h('p', { class: 'progress-label', text: `Step ${idx + 1} of 5` })) : null;

  root.append(h('div', { class: 'frame split has-tree-sheet' },
    h('header', { class: 'topbar' },
      h('span', { class: 'brand' }, brandLogo('bar'), h('span', { class: 'brand-text', 'aria-hidden': 'true' }, wordmark())),
      h('span', { class: 'spacer' }),
      h('button', { type: 'button', class: 'btn-text', text: 'Save & sign out', onclick: async () => { await ctx.auth.logout(); toast('Your answers are saved. Log in to continue.'); ctx.go('welcome'); } })),
    h('main', { class: 'content', id: 'main' }, progress,
      h('div', { class: 'q-head' }, h('h1', { tabindex: '-1', text: meta.title }), h('p', { text: meta.lead })),
      step.el, errorBox),
    h('nav', { class: 'actionbar', 'aria-label': 'Step navigation' }, back, next),
    sheet));
  root.querySelector('h1').focus({ preventScroll: true });
  return { dispose() { step.dispose?.(); } };
}
