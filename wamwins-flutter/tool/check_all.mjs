// Runs every check that does not need the Flutter SDK. Usage (from mobile/): node tool/check_all.mjs
import { execFileSync } from 'node:child_process';
for (const s of ['sync_shared.mjs', 'check_migrations.mjs', 'check_sql.mjs', 'replay_flow.mjs', 'replay_inventory.mjs', 'check_dart_structure.mjs', 'check_imports.mjs']) {
  process.stdout.write(`\n> ${s}\n`);
  execFileSync(process.execPath, ['--no-warnings', new URL(s, import.meta.url).pathname], { stdio: 'inherit' });
}
console.log('\nAll toolchain-free checks passed. Next: flutter test (see README).');
