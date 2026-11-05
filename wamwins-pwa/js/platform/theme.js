const KEY = 'wamwins.theme';
export function currentTheme() { try { return localStorage.getItem(KEY) || 'system'; } catch { return 'system'; } }
export function applyTheme(v = currentTheme()) {
  try { localStorage.setItem(KEY, v); } catch {}
  if (v === 'system') document.documentElement.removeAttribute('data-theme'); else document.documentElement.dataset.theme = v;
  const dark = v === 'dark' || (v === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#071433' : '#0B49D1');
}
