// One-time setup for the WAMWins Flutter app. Run from the `mobile` folder:
//
//     dart tool/setup.dart
//
// It (1) checks Flutter, (2) creates the android/ and ios/ folders with YOUR Flutter version (existing
// app code is never overwritten), (3) names the app "WAMWins" under the icon, (4) downloads packages,
// (5) generates the app icon and splash screen, and (6) runs the conformance tests. Safe to run again.
import 'dart:io';

Future<bool> step(String title, String exe, List<String> args, {bool optional = false}) async {
  stdout.writeln('\n==> $title');
  final p = await Process.start(exe, args, runInShell: true, mode: ProcessStartMode.inheritStdio);
  final code = await p.exitCode;
  if (code != 0) {
    stderr.writeln(optional ? '    (skipped: "$exe ${args.join(' ')}" exited with $code)' : '\nSetup stopped: "$exe ${args.join(' ')}" failed (exit code $code).');
    if (!optional) exit(code);
    return false;
  }
  return true;
}

void patch(String path, RegExp re, String replacement, String what) {
  final f = File(path);
  if (!f.existsSync()) return stdout.writeln('    skip $what ($path not found)');
  final s = f.readAsStringSync();
  final n = s.replaceAllMapped(re, (m) => replacement.replaceAll(r'$1', m.groupCount >= 1 ? (m[1] ?? '') : '').replaceAll(r'$2', m.groupCount >= 2 ? (m[2] ?? '') : ''));
  f.writeAsStringSync(n);
  stdout.writeln('    ${n == s ? 'already set' : 'set'}: $what');
}

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync() || !File('lib/main.dart').existsSync()) {
    stderr.writeln('Run this from the "mobile" folder (the one with pubspec.yaml).');
    exit(1);
  }
  await step('Checking Flutter', 'flutter', ['--version']);
  final platforms = Platform.isMacOS ? 'android,ios' : 'android';
  await step('Creating platform folders ($platforms)', 'flutter',
      ['create', '.', '--org', 'com.wamdigital', '--project-name', 'wamwins', '--platforms', platforms]);
  stdout.writeln('\n==> Naming the app "WAMWins"');
  patch('android/app/src/main/AndroidManifest.xml', RegExp(r'android:label="[^"]*"'), 'android:label="WAMWins"', 'Android app name');
  patch('ios/Runner/Info.plist', RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'), r'$1WAMWins$2', 'iOS display name');
  patch('ios/Runner/Info.plist', RegExp(r'(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)'), r'$1WAMWins$2', 'iOS bundle name');
  // reference photos: iOS asks permission with these explanations (camera and photo library)
  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync() && !plist.readAsStringSync().contains('NSCameraUsageDescription')) {
    plist.writeAsStringSync(plist.readAsStringSync().replaceFirst('<dict>', '<dict>\n\t<key>NSCameraUsageDescription</key>\n\t<string>Take reference photos of your kitchen and storage. WAMWins does not analyze them.</string>'
        '\n\t<key>NSPhotoLibraryUsageDescription</key>\n\t<string>Choose reference photos of your kitchen and storage. WAMWins does not analyze them.</string>'));
    stdout.writeln('    set: iOS camera and photo library permission texts');
  }
  await step('Downloading packages', 'flutter', ['pub', 'get']);
  await step('Making the app icon', 'dart', ['run', 'flutter_launcher_icons'], optional: true);
  await step('Making the splash screen', 'dart', ['run', 'flutter_native_splash:create'], optional: true);
  final testsOk = await step('Running the tests (backup format, meal safety, logic, brand)', 'flutter', ['test'], optional: true);
  stdout.writeln('''

============================================================
 WAMWins is set up.${testsOk ? '' : '  Some tests failed - please send the output above.'}
 Start a phone emulator (or plug in a phone), then run:

     flutter run

 Tip: "flutter devices" lists what you can run on.
============================================================''');
}
