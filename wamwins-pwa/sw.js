/* WAMWins service worker: offline app shell (cache-first for versioned assets, network-first for the page). */
const VERSION = 'wamwins-shell-v7';   // v2: new logos (bump on every release so installed apps update)
const SHELL = [
  './', 'index.html', 'manifest.webmanifest', 'css/app.css',
  'assets/brand/app-icon.png', 'assets/brand/logo-desktop.png', 'assets/brand/logo-desktop-compact.png', 'assets/icons/icon-192.png', 'assets/icons/icon-512.png', 'assets/icons/maskable-512.png', 'assets/icons/favicon-32.png',
  'assets/fonts/Poppins-Regular.ttf', 'assets/fonts/Poppins-Medium.ttf', 'assets/fonts/Poppins-Bold.ttf',
  'js/app.js', 'js/core/dom.js', 'js/core/router.js', 'js/data/db.js', 'js/security/auth.js', 'js/tier/capabilities.js',
  'js/platform/pwa.js', 'js/platform/native.js', 'js/platform/theme.js',
  'js/inquiry/reference.js', 'js/inquiry/questions.js', 'js/inquiry/draft.js', 'js/inquiry/provisioning.js',
  'js/screens/auth-layout.js', 'js/screens/welcome.js', 'js/screens/login.js', 'js/screens/register.js', 'js/screens/home.js', 'js/screens/settings.js',
  'js/screens/setup/setup.js', 'js/screens/setup/step-about.js', 'js/screens/setup/step-household.js', 'js/screens/setup/step-kitchens.js',
  'js/screens/setup/step-family.js', 'js/screens/setup/step-food.js', 'js/screens/setup/step-review.js',
  'js/screens/match.js', 'js/matching/engine.js', 'js/matching/reference.js', 'js/matching/units.js', 'js/matching/inputs.js', 'js/matching/store.js',
  'js/screens/inventory.js', 'js/inventory/ledger.js', 'js/inventory/new-food-form.js',
  'js/inquiry/adapter.js', 'js/inquiry/step-map.js', 'js/screens/setup/step-health.js', 'js/screens/setup/step-appliances.js', 'js/screens/setup/step-kitchenware.js',
  'js/components/info.js', 'js/components/tier-locked.js', 'js/components/autocomplete.js', 'js/components/reference-image.js',
];
self.addEventListener('install', (e) => { e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL))); });
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('message', (e) => { if (e.data === 'SKIP_WAITING') self.skipWaiting(); });
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  if (req.mode === 'navigate') {
    e.respondWith(fetch(req).then(r => { const copy = r.clone(); caches.open(VERSION).then(c => c.put('index.html', copy)); return r; })
      .catch(() => caches.match('index.html')));
    return;
  }
  e.respondWith(caches.match(req, { ignoreSearch: true }).then(hit => hit || fetch(req).then(r => {
    if (r.ok) { const copy = r.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
    return r;
  })));
});
