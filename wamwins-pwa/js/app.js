import { V1_STEP_MAP } from './inquiry/step-map.js';
import { h, clear, brandLogo } from './core/dom.js';
import { parse, go, loadScreen, hasScreen, PUBLIC, canGoBack, NAV_EVENT } from './core/router.js';
import { Auth } from './security/auth.js';
import { openDb, tx } from './data/db.js';
import { initPwa } from './platform/pwa.js';
import { initNative } from './platform/native.js';
import { applyTheme } from './platform/theme.js';

/**
 * WAMWins app entry = the Inquiry & Profiling entry module.
 * Start -> (session?) -> resume profiling where it stopped, or Home when the household is set up.
 * Only the current screen is loaded; a failing screen shows a recoverable error, never a blank app.
 */
const root = document.getElementById('app');
let current = null, renderId = 0;

async function resumePath(user) {
  const [sessions, memberships] = await tx(['questionnaire_session', 'household_membership'], 'readonly', async t =>
    [await t.byIndex('questionnaire_session', 'user_id', user.id), await t.byIndex('household_membership', 'user_id', user.id)]);
  if (memberships.some(m => m.status === 'ACTIVE') && sessions.some(s => s.status === 'COMPLETED')) return 'home';
  const open = sessions.find(s => s.status === 'IN_PROGRESS');
  const step = open?.current_step || 'about';
  return `setup/${(open?.questionnaire_version ?? 1) < 2 ? (V1_STEP_MAP[step] ?? 'about') : step}`;   // v1 sessions resume in v2
}

async function render() {
  const id = ++renderId;
  let { name, arg } = parse();
  try {
    const user = await Auth.currentUser();
    if (!user && !PUBLIC.has(name)) return go('welcome', true);
    if (user && (PUBLIC.has(name) || !name || !hasScreen(name))) return go(await resumePath(user), true);
    if (user && (name === 'home' || name === 'match' || name === 'inventory') && (await resumePath(user)) !== 'home') return go(await resumePath(user), true);
    const mod = await loadScreen(name);
    if (id !== renderId) return;                                  // a newer navigation won
    current?.dispose?.();
    clear(root);
    current = await mod.mount(root, { user, arg, go, auth: Auth });
    window.scrollTo(0, 0);
    root.querySelector('h1')?.focus?.({ preventScroll: true });
  } catch (err) {
    console.error(err);
    current?.dispose?.(); current = null;
    clear(root).append(h('main', { class: 'boot', role: 'alert' },
      brandLogo('hero'),
      h('h1', { text: 'This screen couldn’t open' }),
      h('p', { text: err?.message || 'Something went wrong. Your saved answers are safe.' }),
      h('button', { class: 'btn btn-primary', type: 'button', text: 'Try again', onclick: () => render() })));
  }
}

async function start() {
  applyTheme();
  matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', () => applyTheme());
  initPwa();
  initNative({ canGoBack });
  try { await openDb(); } catch (e) {
    clear(root).append(h('main', { class: 'boot', role: 'alert' }, h('h1', { text: 'WAMWins can’t save data here' }),
      h('p', { text: `${e.message} Try another browser, or turn off private browsing.` })));
    return;
  }
  addEventListener(NAV_EVENT, render);
  render();
}
start();
