import { h, icon } from '../core/dom.js';
import { DOCS, LEGAL } from '../privacy/notices.js';
import { docBody, legalLinks } from '../privacy/consent.js';

// Public page: the Privacy Notice, Consumer Health Data Privacy Policy and Terms of Use, readable without an account.
// #/legal/PRIVACY_NOTICE · #/legal/CONSUMER_HEALTH_DATA_POLICY · #/legal/TERMS
export async function mount(root, ctx) {
  const code = DOCS[ctx.arg] ? ctx.arg : 'PRIVACY_NOTICE';
  const d = DOCS[code];
  root.append(h('div', { class: 'frame' },
    h('header', { class: 'topbar' },
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Back', onclick: () => ctx.back() }, icon('back')),
      h('h1', { tabindex: '-1', style: { fontSize: 'var(--step-1)' }, text: d.title })),
    h('main', { class: 'content legal-doc', id: 'main' }, h('div', { class: 'stack' },
      h('p', { class: 'hint', text: `${LEGAL.operator} · ${LEGAL.product} · Effective ${LEGAL.effective} · Version ${d.version}` }),
      ...docBody(d), legalLinks()))));
  return { dispose() {} };
}
