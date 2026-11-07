// Every relative / package:wamwins import resolves to a file; every other package import is declared in pubspec.yaml.
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
const app = new URL('../', import.meta.url).pathname;
const pub = readFileSync(join(app, 'pubspec.yaml'), 'utf8');
const declared = new Set([...pub.matchAll(/^\s{2}([a-z_0-9]+):/gm)].map(m => m[1]));
const walk = (d) => readdirSync(d).flatMap(f => statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]);
let bad = 0, n = 0;
for (const file of ['lib', 'test', 'integration_test'].flatMap(d => walk(join(app, d))).filter(f => f.endsWith('.dart'))) {
  for (const m of readFileSync(file, 'utf8').matchAll(/^import '([^']+)'/gm)) {
    n++; const spec = m[1];
    if (spec.startsWith('dart:')) continue;
    let ok;
    if (spec.startsWith('package:wamwins/')) ok = existsSync(join(app, 'lib', spec.slice('package:wamwins/'.length)));
    else if (spec.startsWith('package:')) ok = declared.has(spec.slice(8).split('/')[0]) || ['flutter', 'flutter_test', 'integration_test'].includes(spec.slice(8).split('/')[0]);
    else ok = existsSync(resolve(dirname(file), spec));
    if (!ok) { bad++; console.error(`FAIL ${file.replace(app, '')}: ${spec}`); }
  }
}
console.log(bad ? `${bad} unresolved imports` : `Imports OK: ${n} imports resolve`);
process.exit(bad ? 1 : 0);
