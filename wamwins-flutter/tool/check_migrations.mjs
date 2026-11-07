// Applies assets/db/migrations exactly as lib/core/db.dart does (sorted flat names, id = name with first "__" -> "/")
// and checks the ids/order equal the reference runner's (src/data/MigrationRunner.ts). Usage: node tool/check_migrations.mjs
import { readdirSync, readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
const flat = readdirSync(new URL('../assets/db/migrations/', import.meta.url)).filter(f => f.endsWith('.sql')).sort();
const ids = flat.map(f => f.replace('__', '/'));
const ref = []; const base = new URL('../../database/sqlite/migrations/', import.meta.url);
for (const d of readdirSync(base).sort()) for (const f of readdirSync(new URL(`${d}/`, base)).filter(f => f.endsWith('.sql')).sort()) ref.push(`${d}/${f}`);
if (JSON.stringify(ids) !== JSON.stringify(ref)) { console.error('ORDER MISMATCH', ids, ref); process.exit(1); }
const db = new DatabaseSync(':memory:'); db.exec('PRAGMA foreign_keys = ON');
for (const f of flat) db.exec(readFileSync(new URL(`../assets/db/migrations/${f}`, import.meta.url), 'utf8'));
const n = db.prepare("SELECT COUNT(*) n FROM sqlite_master WHERE type='table'").get().n;
const q = db.prepare("SELECT COUNT(*) n FROM question q JOIN questionnaire x ON x.id=q.questionnaire_id WHERE x.code='HOUSEHOLD_PROFILE'").get().n;
console.log(`migrations OK: ${flat.length} files in reference order, ${n} tables, HOUSEHOLD_PROFILE questions: ${q}`);
