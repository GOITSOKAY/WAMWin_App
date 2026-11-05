import { h, icon } from '../core/dom.js';
import { authLayout } from './auth-layout.js';
import { installState } from '../platform/pwa.js';

export async function mount(root, ctx) {
  const point = (ic, yellow, title, text) => h('li', {}, h('span', { class: `ico${yellow ? ' y' : ''}` }, icon(ic)), h('div', {}, h('b', { text: title }), h('span', { text })));
  const install = installState();
  root.append(authLayout(
    h('h1', { class: 'welcome-title' }, 'Welcome to WAMWins', h('sup', { class: 'tm', text: '™' })),
    h('p', { class: 'welcome-intro', style: { color: 'var(--text-2)' }, text: 'Tell us about your household, kitchens and family once. WAMWins uses your answers to suggest meals that are safe for everyone and use what you already have.' }),
    h('ul', { class: 'welcome-points' },
      point('users', false, 'Built around your family', 'Allergies and diets are checked before anything is suggested.'),
      point('box', true, 'Only what you really have', 'Your kitchens, storage and tools, set up exactly as they are at home.'),
      point('wifiOff', false, 'Works without internet', 'Everything is saved on this device and stays available offline.')),
    h('div', { class: 'stack-s' },
      h('button', { class: 'btn btn-primary btn-block', type: 'button', text: 'Create account', onclick: () => ctx.go('register') }),
      h('button', { class: 'btn btn-ghost btn-block', type: 'button', text: 'Log in', onclick: () => ctx.go('login') }),
      install.canPrompt ? h('button', { class: 'btn-text', type: 'button', onclick: () => install.prompt() }, icon('download', 18), ' Install the app') : null),
    h('p', { class: 'privacy-line' }, icon('shield', 18),
      h('span', { text: 'Your household’s information is private. Only people you invite can see it, and your password is never stored in readable form.' }))));
  root.querySelector('h1').focus?.();
  return { dispose() {} };
}
