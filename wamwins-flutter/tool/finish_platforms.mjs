// After `flutter create . --org com.wamdigital --project-name wamwins --platforms android,ios`:
// shows "WAMWins" under the icon on Android and iOS. Usage (from mobile/): node tool/finish_platforms.mjs
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
const patch = (file, re, to, what) => {
  if (!existsSync(file)) return console.log(`skip ${what}: ${file} not found (run flutter create first)`);
  const s = readFileSync(file, 'utf8'); const n = s.replace(re, to);
  writeFileSync(file, n); console.log(`${n === s ? 'unchanged' : 'patched'}: ${what}`);
};
patch('android/app/src/main/AndroidManifest.xml', /android:label="[^"]*"/, 'android:label="WAMWins"', 'Android app name');
patch('ios/Runner/Info.plist', /(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*(<\/string>)/, '$1WAMWins$2', 'iOS display name');
patch('ios/Runner/Info.plist', /(<key>CFBundleName<\/key>\s*<string>)[^<]*(<\/string>)/, '$1WAMWins$2', 'iOS bundle name');
