import { h, icon } from '../core/dom.js';
import { authLayout } from './auth-layout.js';
import { installState, onInstallChange } from '../platform/pwa.js';
import { openInfo } from '../components/info.js';

// Order: brand (layout) -> title -> INSTALL APP -> intro -> value points -> Create Account -> Log In -> privacy.
export async function mount(root, ctx) {
  const point = (ic, yellow, title, text) => h('li', {}, h('span', { class: `ico${yellow ? ' y' : ''}` }, icon(ic)), h('div', {}, h('b', { text: title }), h('span', { text })));
  const installBox = h('div', { class: 'install-box' });
  function drawInstall() {
    const s = installState();
    let btn;
    if (s.standalone) btn = h('p', { class: 'install-done', role: 'status' }, icon('check', 18), h('span', { text: 'WAMWins is installed on this device' }));
    else if (s.canPrompt) btn = h('button', { type: 'button', class: 'btn btn-ghost btn-block install-btn', onclick: () => s.prompt() }, icon('download', 20), h('span', { text: 'Install the app' }));
    else btn = h('button', { type: 'button', class: 'btn btn-ghost btn-block install-btn', 'aria-haspopup': 'dialog', onclick: (e) => openInfo({ returnTo: e.currentTarget, title: 'Install WAMWins',
      body: s.ios ? ['On iPhone or iPad: tap the Share button in Safari, then “Add to Home Screen”.', 'WAMWins then opens like an app and works offline.']
        : ['Use your browser’s menu and choose “Install app” or “Add to Home screen”.', 'If you don’t see it, your browser may not support installing apps; WAMWins still works here in the browser.'] }) },
      icon('download', 20), h('span', { text: 'Install the app' }));
    installBox.replaceChildren(btn);
  }
  drawInstall();
  const off = onInstallChange(drawInstall);
  root.append(authLayout(
    h('h1', { class: 'welcome-title' }, 'Welcome to WAMWins', h('sup', { class: 'tm', text: '™' })),
    installBox,
    h('p', { class: 'welcome-intro', style: { color: 'var(--text-2)' }, text: 'WAMWins helps organize your household resources, understand family needs, and match what you already have with practical solutions.' }),
    h('p', { class: 'welcome-intro', style: { color: 'var(--text-2)' }, text: 'WAMWins Basic starts with your household, family, kitchen, food and meal matching.' }),
    h('ul', { class: 'welcome-points' },
      point('users', false, 'Built around your family', 'Allergies and diets are checked before anything is suggested.'),
      point('box', true, 'Only what you really have', 'Your kitchens, storage, appliances and food, set up exactly as they are at home.'),
      point('wifiOff', false, 'Works without internet', 'Your entries stay available offline on this device. Signing in on your other devices comes with WAMWins online accounts.')),
    h('div', { class: 'stack-s' },
      h('button', { class: 'btn btn-primary btn-block', type: 'button', text: 'Create Account', onclick: () => ctx.go('register') }),
      h('button', { class: 'btn btn-ghost btn-block', type: 'button', text: 'Log In', onclick: () => ctx.go('login') })),
    h('p', { class: 'privacy-line' }, icon('shield', 18),
      h('span', { text: 'Your household’s information is private. Only people you invite can see it, and your password is never stored in readable form.' }))));
  root.querySelector('h1').focus?.();
  return { dispose() { off(); } };
}
