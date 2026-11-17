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

// Privacy usage strings and permissions (shown by the OS before any access; plain words, no dark patterns).
// Voice commands are a higher-tier feature: the microphone is requested only after the person turns voice on.
const addPlist = (key, text) => patch('ios/Runner/Info.plist', new RegExp(`(<dict>)(?![\\s\\S]*<key>${key}<\\/key>)`),
  `$1\n\t<key>${key}</key>\n\t<string>${text}</string>`, `iOS ${key}`);
addPlist('NSMicrophoneUsageDescription', 'WAMWins listens only after you tap the microphone, for one voice command. Recordings are not kept.');
addPlist('NSSpeechRecognitionUsageDescription', 'WAMWins turns your voice command into text, on your device when possible. Recordings are not kept.');
addPlist('NSCameraUsageDescription', 'Take reference photos of your kitchen and storage. Photos stay with your household and are not analyzed.');
addPlist('NSPhotoLibraryUsageDescription', 'Choose reference photos of your kitchen and storage. Photos stay with your household and are not analyzed.');
patch('android/app/src/main/AndroidManifest.xml', /(<manifest[^>]*>)(?![\s\S]*android\.permission\.RECORD_AUDIO)/,
  '$1\n    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <queries><intent><action android:name="android.speech.RecognitionService"/></intent></queries>', 'Android microphone permission (voice commands)');
