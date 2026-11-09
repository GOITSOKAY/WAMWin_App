// Extracts every SQL string passed to db.run / db.select / db.first / db.count in lib/**/*.dart and compiles
// it (sqlite3 prepare) against the real shared schema built from assets/db/migrations. Catches misspelled
// tables/columns and syntax errors in the Dart app without a Flutter toolchain. Usage: node tool/check_sql.mjs
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
const lib = new URL('../lib/', import.meta.url).pathname;
const mig = new URL('../assets/db/migrations/', import.meta.url).pathname;
const db = new DatabaseSync(':memory:'); db.exec('PRAGMA foreign_keys = ON');
for (const f of readdirSync(mig).sort()) db.exec(readFileSync(join(mig, f), 'utf8'));
const walk = (d) => readdirSync(d).flatMap(f => statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]);
// Sample values for Dart interpolations: placeholder lists (_ph(n), $m, $p) become one '?', limits become numbers.
const SAMPLE = { t: 'member_food_rule', table: 'household_appliance', cls: 'APPLIANCE', m: '?', p: '?', maxCandidates: '200', where: "i.household_id = ? AND i.deleted_at IS NULL AND i.quantity > 0 AND lower(COALESCE(m.canonical_name, i.label)) LIKE ? AND i.use_soon_on <= ?" };
let checked = 0, failed = 0;
for (const file of walk(lib).filter(f => f.endsWith('.dart'))) {
  const src = readFileSync(file, 'utf8');
  const re = /\bdb\.(run|select|first|count)\(\s*/g; let m;
  while ((m = re.exec(src))) {
    let i = re.lastIndex, sql = '';
    for (;;) {                                         // adjacent Dart string literals form the statement
      while (/\s/.test(src[i])) i++;
      const tq = src.startsWith("'''", i) ? "'''" : src.startsWith('"""', i) ? '"""' : null;
      if (tq) { const e = src.indexOf(tq, i + 3); sql += src.slice(i + 3, e); i = e + 3; continue; }
      if (src[i] === "'" || src[i] === '"') { const q = src[i]; let j = i + 1; while (src[j] !== q) { if (src[j] === '\\') j++; j++; } sql += src.slice(i + 1, j); i = j + 1; continue; }
      break;
    }
    if (!sql) continue;
    sql = sql.replace(/\$\{_ph\([^}]*\)\}/g, '?').replace(/\$\{?(\w+)\}?/g, (_, v) => SAMPLE[v] ?? v).replace(/\\'/g, "'");
    checked++;
    try { db.prepare(sql); } catch (e) { failed++; console.error(`FAIL ${file.replace(lib, 'lib/')}: ${e.message}\n   ${sql.replace(/\s+/g, ' ').slice(0, 160)}`); }
  }
}
console.log(failed ? `${failed} of ${checked} SQL statements failed` : `SQL OK: ${checked} statements compile against the shared schema`);
process.exit(failed ? 1 : 0);
