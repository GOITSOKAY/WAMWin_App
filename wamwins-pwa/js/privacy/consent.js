import { h, icon } from '../core/dom.js';
import { tx } from '../data/db.js';
import { CONSENT, DOCS, textHash } from './notices.js';

/**
 * Consent ledger (append-only consent_record rows) + the consent pop-up.
 * A row: consent_type, granted, document_code, document_version, text_hash (SHA-256 of the exact words shown),
 * method, subject_ref (whose data, for consents given on someone's behalf), recorded_at.
 * Withdrawing = a new row with granted:false. The latest row for (type, subject) decides.
 */
export async function consentHistory(userId) {
  const rows = await tx(['consent_record'], 'readonly', t => t.byIndex('consent_record', 'user_id', userId));
  return rows.sort((a, b) => a.recorded_at.localeCompare(b.recorded_at));
}
export async function latestConsent(userId, type, subjectRef = null) {
  return (await consentHistory(userId)).filter(r => r.consent_type === type && (r.subject_ref ?? null) === subjectRef).at(-1) ?? null;
}
/** Granted, and for the current version of the document (a new version asks again). */
export async function hasConsent(userId, type, subjectRef = null) {
  const r = await latestConsent(userId, type, subjectRef);
  return !!r?.granted && (r.document_version ?? '1') === CONSENT[type].version;
}
export async function recordConsent(userId, type, granted, { subjectRef = null, method = 'POPUP', shown = null } = {}) {
  const def = CONSENT[type];
  const row = { id: crypto.randomUUID(), user_id: userId, consent_type: type, granted: !!granted, document_code: def.doc,
    document_version: def.version, text_hash: shown ? await textHash(shown) : null, method, subject_ref: subjectRef,
    user_agent: navigator.userAgent.slice(0, 160), recorded_at: new Date().toISOString() };
  await tx(['consent_record'], 'readwrite', t => t.add('consent_record', row));
  return row;
}

/** Modal shell shared by the consent pop-up and the notice viewer: role=dialog, focus trap, ESC, focus return. */
export function modal({ title, body, actions, wide = false, onClose }) {
  const id = `m-${Math.random().toString(36).slice(2)}`;
  const close = h('button', { type: 'button', class: 'icon-btn info-close', 'aria-label': 'Close' }, icon('close', 20));
  const dialog = h('div', { class: `info-modal consent-modal${wide ? ' wide' : ''}`, role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': `${id}-t`, tabindex: '-1' },
    h('div', { class: 'info-head' }, h('h2', { id: `${id}-t`, text: title }), close),
    h('div', { class: 'info-body consent-body' }, body),
    actions ? h('div', { class: 'consent-actions' }, actions) : null);
  const backdrop = h('div', { class: 'info-backdrop' }, dialog);
  const prev = document.activeElement;
  const focusables = () => [...dialog.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')].filter(e => !e.disabled);
  function onKey(e) {
    if (e.key === 'Escape') { e.preventDefault(); done(null); return; }
    if (e.key !== 'Tab') return;
    const f = focusables(); if (!f.length) return;
    if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f.at(-1).focus(); }
    else if (!e.shiftKey && document.activeElement === f.at(-1)) { e.preventDefault(); f[0].focus(); }
  }
  let closed = false;
  function done(v) { if (closed) return; closed = true; document.removeEventListener('keydown', onKey, true); backdrop.remove(); prev?.focus?.(); onClose?.(v); }
  close.onclick = () => done(null);
  document.addEventListener('keydown', onKey, true);
  document.body.append(backdrop);
  return { dialog, done };
}

/**
 * Consent pop-up. Nothing is pre-ticked; the agree button stays off until the box is ticked (no dark patterns:
 * "Not now" is as easy as agreeing). Resolves true/false and records the decision with the exact text shown.
 * Declining is recorded too, so it is never asked in a loop.
 */
export function askConsent(userId, type, { subjectRef = null, extra = [], subjectName = null } = {}) {
  const def = CONSENT[type];
  return new Promise(resolve => {
    const box = h('input', { type: 'checkbox', id: `c-${type}` });
    const agree = h('button', { type: 'button', class: 'btn btn-primary', text: def.agree, disabled: true });
    const decline = h('button', { type: 'button', class: 'btn btn-ghost', text: def.decline });
    box.onchange = () => { agree.disabled = !box.checked; };
    const shown = [def.title, subjectName, def.lead, ...(def.list ?? []), ...extra.map(e => typeof e === 'string' ? e : e.textContent), def.check];
    const docLink = h('button', { type: 'button', class: 'btn-text', text: `Read the ${DOCS[def.doc].title}`, onclick: () => openDoc(def.doc) });
    const { done } = modal({
      title: def.title,
      body: [subjectName ? h('p', { class: 'consent-subject' }, icon('user', 18), h('b', { text: subjectName })) : null,
        h('p', { text: def.lead }), def.list ? h('ul', { class: 'consent-list' }, def.list.map(x => h('li', { text: x }))) : null,
        ...extra.map(e => typeof e === 'string' ? h('p', { text: e }) : e), docLink,
        h('label', { class: 'check consent-check', for: `c-${type}` }, box, h('span', { text: def.check }))],
      actions: [decline, agree],
      onClose: async (v) => {
        const granted = v === true;
        if (v !== null || granted) await recordConsent(userId, type, granted, { subjectRef, shown });
        resolve(granted);
      },
    });
    agree.onclick = () => done(true);
    decline.onclick = () => done(false);
    box.focus();
  });
}

/** Shows a legal document in a dialog (readable before and after sign-in). */
export function openDoc(code) {
  const d = DOCS[code];
  modal({ title: d.title, wide: true, body: [h('p', { class: 'hint', text: `Version ${d.version}` }), ...docBody(d)],
    actions: [h('button', { type: 'button', class: 'btn btn-primary', text: 'Close', onclick: (e) => e.target.closest('.info-backdrop').querySelector('.info-close').click() })] });
}
export function docBody(d) {
  return d.sections.map(s => h('section', { class: 'doc-section' }, s.h ? h('h3', { text: s.h }) : null,
    ...(s.p ?? []).map(p => h('p', { text: p })), s.list ? h('ul', {}, s.list.map(x => h('li', { text: x }))) : null));
}
/** Small row of links to the notices (registration, settings, footer). */
export function legalLinks() {
  return h('p', { class: 'legal-links' },
    ...[['PRIVACY_NOTICE', 'Privacy Notice'], ['CONSUMER_HEALTH_DATA_POLICY', 'Consumer Health Data Policy'], ['TERMS', 'Terms of Use']]
      .flatMap(([c, t], i) => [i ? h('span', { 'aria-hidden': 'true', text: ' · ' }) : null, h('button', { type: 'button', class: 'btn-text', text: t, onclick: () => openDoc(c) })]));
}
