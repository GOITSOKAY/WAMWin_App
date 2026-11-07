// Hash router: works from any static host, inside an installed PWA and inside Capacitor.
// Screens are loaded on demand and disposed when you leave them (only the current screen in memory).
const SCREENS = {
  welcome: () => import('../screens/welcome.js'),
  login: () => import('../screens/login.js'),
  register: () => import('../screens/register.js'),
  setup: () => import('../screens/setup/setup.js'),
  home: () => import('../screens/home.js'),
  settings: () => import('../screens/settings.js'),
  match: () => import('../screens/match.js'),
  inventory: () => import('../screens/inventory.js'),
};
export const PUBLIC = new Set(['welcome', 'login', 'register']);
// Hosted single-file preview: navigation is kept in memory (the host page owns the URL fragment).
const memory = !!window.__WAMWINS_SINGLE_FILE__;
let memPath = '';
export const NAV_EVENT = memory ? 'wamwins:navigate' : 'hashchange';
export function parse() {
  const [name = '', arg = ''] = (memory ? memPath : location.hash.replace(/^#\/?/, '')).split('/');
  return { name, arg };
}
let depth = 0;
export function go(path, replace = false) {
  if (memory) { memPath = path; if (!replace) depth++; window.dispatchEvent(new Event(NAV_EVENT)); return; }
  const hash = `#/${path}`;
  if (location.hash === hash) { window.dispatchEvent(new HashChangeEvent('hashchange')); return; }
  if (replace) { location.replace(hash); } else { depth++; location.hash = hash; }
}
export const canGoBack = () => depth > 0;
export const loadScreen = (name) => (SCREENS[name] || SCREENS.welcome)();
export const hasScreen = (name) => name in SCREENS;
