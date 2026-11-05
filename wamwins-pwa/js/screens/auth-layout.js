import { h, wordmark, brandLogo } from '../core/dom.js';

/** Brand field (logo, wordmark, tagline) + content sheet. Phone: stacked; landscape/desktop: side by side. */
export function authLayout(...content) {
  return h('main', { class: 'auth' },
    h('section', { class: 'auth-brand on-brand', 'aria-label': 'WAMWins' },
      brandLogo('hero'),
      // On phones the app icon has no lettering, so the wordmark and tagline are set in type;
      // the desktop logo already contains both, so they are hidden on tablets and desktops.
      h('div', { class: 'brand-text', 'aria-hidden': 'true' }, wordmark(), h('p', { class: 'tagline', text: 'Smart Solutions. Better Outcomes.' }))),
    h('section', { class: 'auth-sheet' }, h('div', { class: 'auth-sheet-inner' }, content)));
}
export function passwordInput(id, autocomplete) {
  const input = h('input', { class: 'input', id, type: 'password', autocomplete, required: true, minlength: 10, spellcheck: 'false' });
  const toggle = h('button', { type: 'button', class: 'btn-text', 'aria-pressed': 'false', 'aria-controls': id, text: 'Show' });
  toggle.onclick = () => { const show = input.type === 'password'; input.type = show ? 'text' : 'password'; toggle.textContent = show ? 'Hide' : 'Show'; toggle.setAttribute('aria-pressed', String(show)); };
  return { input, wrap: h('div', { class: 'pw-wrap' }, input, toggle) };
}
