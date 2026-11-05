import { h, icon, choices, field, toast } from '../core/dom.js';
import { deleteEverything } from '../data/db.js';
import { applyTheme, currentTheme } from '../platform/theme.js';
import { installState } from '../platform/pwa.js';

export async function mount(root, ctx) {
  const install = installState();
  const confirmInput = h('input', { class: 'input', type: 'text', autocomplete: 'off', placeholder: 'DELETE' });
  const fConfirm = field({ label: 'Type DELETE to confirm', input: confirmInput });
  const dangerZone = h('div', { class: 'stack-s', hidden: true }, fConfirm,
    h('button', { type: 'button', class: 'btn btn-danger', text: 'Delete all data on this device', onclick: async () => {
      if (confirmInput.value.trim() !== 'DELETE') return fConfirm.setError('Type DELETE in capital letters.');
      await ctx.auth.logout(); await deleteEverything(); localStorage.clear(); sessionStorage.clear();
      toast('All WAMWins data was deleted from this device.'); ctx.go('welcome');
    } }));
  root.append(h('div', { class: 'frame' },
    h('header', { class: 'topbar' },
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Back to home', onclick: () => ctx.go('home') }, icon('back')),
      h('h1', { tabindex: '-1', style: { fontSize: 'var(--step-1)' }, text: 'Settings' })),
    h('main', { class: 'content', id: 'main' }, h('div', { class: 'stack-l' },
      h('section', { class: 'stack-s' }, h('h2', { text: 'Account' }),
        h('div', { class: 'settings-list' }, h('div', {}, h('span', { text: 'Name' }), h('span', { class: 'hint', text: ctx.user.display_name })),
          h('div', {}, h('span', { text: 'Email' }), h('span', { class: 'hint', text: ctx.user.email })))),
      h('section', { class: 'stack-s' }, h('h2', { text: 'Appearance' }),
        choices([{ code: 'system', name: 'Match my device' }, { code: 'light', name: 'Light' }, { code: 'dark', name: 'Dark' }], currentTheme(), v => applyTheme(v))),
      install.canPrompt || install.ios ? h('section', { class: 'stack-s' }, h('h2', { text: 'Install the app' }),
        install.canPrompt ? h('button', { type: 'button', class: 'btn btn-blue', onclick: () => install.prompt() }, icon('download', 20), 'Install WAMWins')
          : h('p', { class: 'hint', text: 'On iPhone or iPad: tap Share, then “Add to Home Screen”.' })) : null,
      h('section', { class: 'panel', 'aria-labelledby': 'p-h' }, h('h2', { id: 'p-h' }, 'Your data stays private'),
        h('p', { text: 'Your household information is protected by several layers of security. Only people you invite into your household can see it, and health details are visible only to members you allow.' }),
        h('p', { class: 'hint', text: 'Your password is stored only as a protected one-way code, so it can’t be read back, even from this device.' })),
      h('section', { class: 'stack-s' },
        h('button', { type: 'button', class: 'btn btn-ghost btn-block', text: 'Sign out', onclick: async () => { await ctx.auth.logout(); toast('Signed out.'); ctx.go('welcome'); } }),
        h('button', { type: 'button', class: 'btn-text', style: { color: 'var(--danger)' }, text: 'Delete all WAMWins data on this device…', onclick: (e) => { dangerZone.hidden = false; e.target.hidden = true; confirmInput.focus(); } }),
        dangerZone)))));
  return { dispose() {} };
}
