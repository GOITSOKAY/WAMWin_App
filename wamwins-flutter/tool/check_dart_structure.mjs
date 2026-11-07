// Structural check for Dart sources without a Dart SDK: balanced (), [], {} with strings, raw strings,
// triple-quoted strings, string interpolation and comments handled; flags unterminated strings.
// Usage: node tool/check_dart_structure.mjs
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
const roots = ['lib', 'test', 'integration_test'].map(d => new URL(`../${d}/`, import.meta.url).pathname);
const walk = (d) => readdirSync(d).flatMap(f => statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]);
let bad = 0, files = 0;
for (const file of roots.flatMap(walk).filter(f => f.endsWith('.dart'))) {
  files++;
  const s = readFileSync(file, 'utf8'); const stack = []; const pairs = { ')': '(', ']': '[', '}': '{' };
  let i = 0, line = 1, err = null;
  const skipString = (q, raw) => {                          // i points after opening quote(s)
    const triple = q.length === 3;
    while (i < s.length) {
      if (s[i] === '\n') { if (!triple) return `unterminated string`; line++; }
      if (!raw && s[i] === '\\') { i += 2; continue; }
      if (s.startsWith(q, i)) { i += q.length; return null; }
      if (!raw && s[i] === '$' && s[i + 1] === '{') {         // interpolation: balance braces inside
        let depth = 1; i += 2;
        while (i < s.length && depth) { if (s[i] === '{') depth++; else if (s[i] === '}') depth--; else if (s[i] === "'" || s[i] === '"') { const qq = s[i]; i++; const e = skipString(qq, false); if (e) return e; continue; } if (s[i] === '\n') line++; i++; }
        continue;
      }
      i++;
    }
    return 'unterminated string at end of file';
  };
  while (i < s.length && !err) {
    const c = s[i];
    if (c === '\n') { line++; i++; continue; }
    if (s.startsWith('//', i)) { while (i < s.length && s[i] !== '\n') i++; continue; }
    if (s.startsWith('/*', i)) { const e = s.indexOf('*/', i + 2); line += (s.slice(i, e).match(/\n/g) || []).length; i = e + 2; continue; }
    const raw = c === 'r' && (s[i + 1] === "'" || s[i + 1] === '"') && !/[A-Za-z0-9_]/.test(s[i - 1] || '');
    const qs = raw ? i + 1 : i;
    if (s[qs] === "'" || s[qs] === '"') {
      const q = s.startsWith(s[qs].repeat(3), qs) ? s[qs].repeat(3) : s[qs];
      i = qs + q.length; const startLine = line; const e = skipString(q, raw); if (e) err = `${e} (line ${startLine})`; continue;
    }
    if ('([{'.includes(c)) stack.push([c, line]);
    else if (')]}'.includes(c)) { const top = stack.pop(); if (!top || top[0] !== pairs[c]) err = `unexpected '${c}' at line ${line}${top ? ` (open '${top[0]}' from line ${top[1]})` : ''}`; }
    i++;
  }
  if (!err && stack.length) err = `unclosed '${stack.at(-1)[0]}' from line ${stack.at(-1)[1]}`;
  if (err) { bad++; console.error(`FAIL ${file.split('/mobile/')[1]}: ${err}`); }
}
console.log(bad ? `${bad} of ${files} Dart files have structural errors` : `Dart structure OK: ${files} files`);
process.exit(bad ? 1 : 0);
