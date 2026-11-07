/**
 * Copies the SHARED, single-source files into the Flutter app (run after any change to them):
 *   database/sqlite/migrations/<dir>/<file>.sql  ->  assets/db/migrations/<dir>__<file>.sql   (rule B1: unchanged)
 *   database/sqlite/modules/<dir>/<file>.sql     ->  assets/db/modules/<dir>__<file>.sql
 *   frontend/www/assets/brand, fonts             ->  assets/brand, assets/fonts
 *   frontend/resources/icon.png, splash          ->  assets/launcher
 *   conformance/vectors                          ->  test/vectors
 * Usage (from mobile/):  node tool/sync_shared.mjs
 */
import { cpSync, mkdirSync, readdirSync, rmSync, copyFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
const root = new URL('../../', import.meta.url).pathname, app = new URL('../', import.meta.url).pathname;
const flat = (src, dest) => {
  rmSync(dest, { recursive: true, force: true }); mkdirSync(dest, { recursive: true });
  let n = 0;
  for (const d of readdirSync(src).sort()) for (const f of readdirSync(join(src, d)).filter(f => f.endsWith('.sql')).sort()) { copyFileSync(join(src, d, f), join(dest, `${d}__${f}`)); n++; }
  return n;
};
const m = flat(join(root, 'database/sqlite/migrations'), join(app, 'assets/db/migrations'));
const mm = flat(join(root, 'database/sqlite/modules'), join(app, 'assets/db/modules'));
for (const [s, d] of [['frontend/www/assets/brand', 'assets/brand'], ['frontend/www/assets/fonts', 'assets/fonts'], ['conformance/vectors', 'test/vectors']]) {
  rmSync(join(app, d), { recursive: true, force: true }); cpSync(join(root, s), join(app, d), { recursive: true });
}
mkdirSync(join(app, 'assets/launcher'), { recursive: true });
copyFileSync(join(root, 'frontend/resources/icon.png'), join(app, 'assets/launcher/icon.png'));
copyFileSync(join(root, 'frontend/www/assets/brand/app-icon.png'), join(app, 'assets/launcher/splash-logo.png'));
console.log(`synced ${m} migrations, ${mm} module migrations, brand, fonts, launcher art, conformance vectors`);
