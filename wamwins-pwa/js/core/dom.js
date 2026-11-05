// Safe DOM builder: user text is only ever set via textContent / attributes, never innerHTML.
export function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'text') el.textContent = v;
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (v === true) el.setAttribute(k, '');
    else el.setAttribute(k, String(v));
  }
  append(el, children);
  return el;
}
export function append(el, children) {
  for (const c of children.flat(Infinity)) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}
export function clear(el) { while (el.firstChild) el.firstChild.remove(); return el; }

const ICONS = {
  home: 'M3 11.5 12 4l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',
  user: 'M12 12a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9zm-8 9a8 8 0 0 1 16 0',
  users: 'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm-7 10a7 7 0 0 1 14 0M17 4.5a3.5 3.5 0 0 1 0 7M22 21a6 6 0 0 0-4-5.6',
  chef: 'M7 14v6h10v-6M6 14a4 4 0 1 1 1.5-7.7A5 5 0 0 1 16.5 6.3 4 4 0 1 1 18 14z',
  heart: 'M12 20s-7-4.4-9-9a4.8 4.8 0 0 1 9-3 4.8 4.8 0 0 1 9 3c-2 4.6-9 9-9 9z',
  box: 'M3 7.5 12 3l9 4.5v9L12 21l-9-4.5zM3 7.5 12 12l9-4.5M12 12v9',
  shield: 'M12 3 4 6v6c0 5 3.4 8.2 8 9 4.6-.8 8-4 8-9V6zm-3.5 9 2.5 2.5 4.5-5',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm7.4-3a7.4 7.4 0 0 0-.1-1.2l2-1.6-2-3.4-2.4 1a7 7 0 0 0-2-1.2L14.5 3h-5l-.4 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.4 2 1.6a7.4 7.4 0 0 0 0 2.4l-2 1.6 2 3.4 2.4-1a7 7 0 0 0 2 1.2l.4 2.6h5l.4-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.4-2-1.6c.1-.4.1-.8.1-1.2z',
  back: 'M15 5l-7 7 7 7', chev: 'M9 5l7 7-7 7', plus: 'M12 5v14M5 12h14', x: 'M6 6l12 12M18 6 6 18', check: 'M5 12.5 10 17l9-10',
  lock: 'M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3', wifiOff: 'M3 3l18 18M8.5 16.5a5 5 0 0 1 7 0M5 13a10 10 0 0 1 5-2.8M19 13a10 10 0 0 0-3-2M2 9.5a15 15 0 0 1 4.5-2.9M22 9.5A15 15 0 0 0 11 5.1M12 20h.01',
  download: 'M12 4v11m-5-5 5 5 5-5M5 20h14', trash: 'M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3', search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zm10 3-5-5',
};
export function icon(name, size = 22) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('width', size); svg.setAttribute('height', size); svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '2');
  svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round'); svg.setAttribute('aria-hidden', 'true');
  const p = document.createElementNS(ns, 'path'); p.setAttribute('d', ICONS[name] || ''); svg.append(p);
  return svg;
}

export function wordmark(size) {
  return h('span', { class: 'wordmark', style: size ? { fontSize: size } : undefined, 'aria-label': 'WAMWins' },
    h('span', { class: 'wam', text: 'WAM' }), h('span', { class: 'wins', text: 'Wins' }), h('sup', { class: 'tm', 'aria-hidden': 'true', text: '™' }));
}
/** Brand assets: the app icon is the logo on phones; the desktop logo is used on tablets and desktops. */
export const BRAND = {
  icon: 'assets/brand/app-icon.png',
  desktop: 'assets/brand/logo-desktop.png',              // mark + wordmark + tagline
  desktopCompact: 'assets/brand/logo-desktop-compact.png', // mark + wordmark (top bars, where the tagline would be unreadable)
};
export const LOGO_SRC = BRAND.icon;
/** Tablet/desktop = at least 640px wide AND 500px tall (landscape phones keep the mobile logo). */
export const LARGE_SCREEN = '(min-width: 640px) and (min-height: 500px)';
export function brandLogo(kind = 'hero') {
  const big = kind === 'hero' ? BRAND.desktop : BRAND.desktopCompact;
  return h('picture', { class: `brand-logo brand-logo--${kind}` },
    h('source', { media: LARGE_SCREEN, srcset: big }),
    h('img', { src: BRAND.icon, alt: 'WAMWins', width: kind === 'hero' ? 96 : 36, height: kind === 'hero' ? 96 : 36, decoding: 'async' }));
}

export function toast(message, action) {
  const region = document.getElementById('toast-region');
  const t = h('div', { class: 'toast' }, h('span', { text: message }),
    action ? h('button', { class: 'btn-text', type: 'button', text: action.label, onclick: () => { action.run(); t.remove(); } }) : null);
  region.append(t);
  if (!action) setTimeout(() => t.remove(), 4000);
  return t;
}

/** Field with label, hint and an error line wired for screen readers. */
let uid = 0;
export function field({ label, hint, input, error = '' }) {
  const id = input.id || `f${++uid}`; input.id = id;
  const err = h('p', { class: 'field-error', id: `${id}-err`, 'aria-live': 'polite', text: error });
  const hintEl = hint ? h('p', { class: 'hint', id: `${id}-hint`, text: hint }) : null;
  input.setAttribute('aria-describedby', [hint ? `${id}-hint` : '', `${id}-err`].filter(Boolean).join(' '));
  const wrap = h('div', { class: 'field' }, h('label', { for: id, text: label }), hintEl, input, err);
  wrap.setError = (msg) => { err.textContent = msg || ''; input.setAttribute('aria-invalid', msg ? 'true' : 'false'); };
  input.addEventListener('input', () => { if (err.textContent) wrap.setError(''); });
  return wrap;
}

/** Number stepper (used for "how many?" questions). */
export function stepper({ value = 0, min = 0, max = 20, label, onChange }) {
  const out = h('output', { 'aria-live': 'polite', text: String(value) });
  const dec = h('button', { type: 'button', 'aria-label': `Fewer ${label}`, text: '−' });
  const inc = h('button', { type: 'button', 'aria-label': `More ${label}`, text: '+' });
  const sync = () => { out.textContent = String(value); dec.disabled = value <= min; inc.disabled = value >= max; };
  dec.onclick = () => { if (value > min) { value--; sync(); onChange(value); } };
  inc.onclick = () => { if (value < max) { value++; sync(); onChange(value); } };
  sync();
  return h('div', { class: 'stepper', role: 'group', 'aria-label': label }, dec, out, inc);
}

/** Multi-select chips. */
export function chips(options, selected, onChange, { warn = false, disabled = false } = {}) {
  const set = new Set(selected);
  return h('div', { class: 'chips' }, options.map(o => {
    const b = h('button', { type: 'button', class: `chip${warn ? ' warn' : ''}`, 'aria-pressed': String(set.has(o.code)), disabled, text: o.name });
    b.onclick = () => { set.has(o.code) ? set.delete(o.code) : set.add(o.code); b.setAttribute('aria-pressed', String(set.has(o.code))); onChange([...set]); };
    return b;
  }));
}

/** Single choice (radio semantics). */
export function choices(options, value, onChange) {
  const group = h('div', { class: 'choice-list', role: 'radiogroup' });
  const items = options.map(o => {
    const b = h('button', { type: 'button', role: 'radio', class: 'choice', 'aria-checked': String(o.code === value) },
      h('span', { class: 'dot' }), h('span', {}, h('b', { style: { fontWeight: 500 }, text: o.name }), o.hint ? h('span', { class: 'hint', style: { display: 'block' }, text: o.hint }) : null));
    b.onclick = () => { items.forEach(i => i.setAttribute('aria-checked', 'false')); b.setAttribute('aria-checked', 'true'); onChange(o.code); };
    return b;
  });
  return append(group, items);
}
