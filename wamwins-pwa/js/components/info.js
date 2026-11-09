import { h, icon } from '../core/dom.js';

// InfoButton + InfoModal: a small (i) control that explains a question or process.
// Accessible: real <button> with a label; modal is role="dialog" aria-modal, traps focus, closes on ESC or the
// close button, and returns focus to the (i) button afterwards.
export function infoButton({ label, title, body }) {
  const btn = h('button', { type: 'button', class: 'info-btn', 'aria-label': `More information: ${label}`, 'aria-haspopup': 'dialog' }, icon('info', 18));
  btn.onclick = () => openInfo({ title, body, returnTo: btn });
  return btn;
}

export function openInfo({ title, body, returnTo }) {
  const id = `info-${Math.random().toString(36).slice(2)}`;
  const close = h('button', { type: 'button', class: 'icon-btn info-close', 'aria-label': 'Close' }, icon('close', 20));
  const paras = (Array.isArray(body) ? body : [body]).map(p => h('p', { text: p }));
  const dialog = h('div', { class: 'info-modal', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': `${id}-t`, tabindex: '-1' },
    h('div', { class: 'info-head' }, h('h2', { id: `${id}-t`, text: title }), close), h('div', { class: 'info-body' }, paras),
    h('button', { type: 'button', class: 'btn btn-primary', text: 'Got it' }));
  const backdrop = h('div', { class: 'info-backdrop' }, dialog);
  const focusables = () => [...dialog.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')].filter(e => !e.disabled);
  function done() { document.removeEventListener('keydown', onKey, true); backdrop.remove(); returnTo?.focus?.(); }
  function onKey(e) {
    if (e.key === 'Escape') { e.preventDefault(); done(); return; }
    if (e.key !== 'Tab') return;
    const f = focusables(); if (!f.length) return;
    if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f.at(-1).focus(); }
    else if (!e.shiftKey && document.activeElement === f.at(-1)) { e.preventDefault(); f[0].focus(); }
  }
  close.onclick = done; dialog.querySelector('.btn-primary').onclick = done;
  backdrop.onclick = (e) => { if (e.target === backdrop) done(); };
  document.addEventListener('keydown', onKey, true);
  document.body.append(backdrop);
  dialog.querySelector('.btn-primary').focus();
  return done;
}

/** Question heading with an (i) next to it. */
export function labelWithInfo(text, info, tag = 'h2') {
  return h(tag, { class: 'with-info' }, h('span', { text }), infoButton({ label: text, ...info }));
}
