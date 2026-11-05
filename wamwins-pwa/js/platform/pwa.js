import { toast } from '../core/dom.js';
import { isNative } from './native.js';

let deferred = null;
const listeners = new Set();
/** Install prompt (Android/desktop Chromium) and iOS "Add to Home Screen" hint. */
export function installState() {
  const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const ios = /iphone|ipad|ipod/i.test(navigator.userAgent) && !standalone && !isNative();
  return { canPrompt: !!deferred && !standalone && !isNative(), ios,
    prompt: async () => { if (!deferred) return; deferred.prompt(); await deferred.userChoice; deferred = null; listeners.forEach(f => f()); } };
}
export function onInstallChange(f) { listeners.add(f); return () => listeners.delete(f); }

export function initPwa() {
  addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferred = e; listeners.forEach(f => f()); });
  addEventListener('appinstalled', () => { deferred = null; toast('WAMWins is installed.'); });
  // Service worker: web/PWA only. Native shells (Capacitor) ship the files inside the app.
  if (!('serviceWorker' in navigator) || isNative() || window.__WAMWINS_SINGLE_FILE__ || !window.isSecureContext) return;
  navigator.serviceWorker.register('sw.js').then(reg => {
    const offerUpdate = (w) => toast('A new version of WAMWins is ready.', { label: 'Reload', run: () => w.postMessage('SKIP_WAITING') });
    if (reg.waiting && navigator.serviceWorker.controller) offerUpdate(reg.waiting);
    reg.addEventListener('updatefound', () => {
      const w = reg.installing;
      w?.addEventListener('statechange', () => { if (w.state === 'installed' && navigator.serviceWorker.controller) offerUpdate(w); });
    });
  }).catch(() => {});
  // Reload only when an UPDATE takes over. On the very first visit the new worker also claims the
  // page (controllerchange fires) - reloading then would wipe whatever the person is typing.
  const hadController = !!navigator.serviceWorker.controller;
  let reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => { if (hadController && !reloading) { reloading = true; location.reload(); } });
}
