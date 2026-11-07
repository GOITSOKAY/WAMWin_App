# WAMWins™ — Flutter app (Android & iOS)

The native WAMWins app, built with Flutter and Dart. It is the **same system** as the website/PWA,
not a separate product: same database files, same questions and rules, same brand, same backup format
(see `../docs/CLIENT_CONFORMANCE.md`).

**What it does today:** Welcome → Create account / Log in → five profiling steps (About you, Your household,
Kitchens & equipment, Family & health, Food on hand) → Review → Home → **What can we cook?** (safety-first
meal matching for the people you choose, with reasons) → **Cook this** (records the meal and takes the
ingredients out of inventory) → **Inventory** (add food from the list, your own foods or a new one; use, add more, throw away,
correct, move, mark opened or expired, return; details, history, use-soon/expired/running-low alerts; edit your own foods) → Settings. Works fully offline; accounts and data are stored securely on the device until WAMWins
cloud sign-in is connected.

**New here? Read `HOW-TO-OPEN.md`** — step-by-step, including installing Flutter and starting an emulator.

## Build and run (first time)
Requirements: Flutter stable **3.24 or newer** (Dart 3.5+); Android Studio (Android) and/or Xcode on a Mac (iOS); Node.js 18+ (for the helper scripts).

```bash
cd mobile
dart tool/setup.dart                        # one time: platform folders, app name, packages, icon, splash, tests
flutter run                                 # on a connected phone/tablet or emulator
flutter test integration_test/app_flow_test.dart -d <device-id>   # full journey on a device
```
Application id / bundle id: `com.wamdigital.wamwins` (same as the Capacitor config).

## Release builds
```bash
flutter build appbundle      # Google Play (configure upload signing first: android/key.properties)
flutter build ipa            # App Store (signing team set in Xcode)
```

## How it follows the shared rules
| Rule | In this app |
|---|---|
| B1 shared database | `assets/db/migrations` are the shared SQLite files, copied **unchanged** by `tool/sync_shared.mjs` and applied in the same order, recorded in `schema_migration_history`. SQLite ≥ 3.37 is bundled (`sqlite3_flutter_libs`) because many phones ship older versions. |
| B2 rules in the database | Inventory ledger, append-only history, module states, platform guarantees: enforced by the shared triggers. |
| C1 backup format | `lib/backup/wambk.dart` reads/writes WAMBK1; `test/conformance_test.dart` must pass the reference vectors. |
| C2 keys on the device | Session token in the OS keystore (`flutter_secure_storage`); only its SHA-256 in the database. |
| C3 meal matching | `lib/matching/` is a line-by-line port of the reference engine; `test/matching_conformance_test.dart` must reproduce `test/vectors/matching-scenario.json` (same exclusions with reasons, same recommendations) and checks cooking deducts inventory once. |
| C4 capabilities | `lib/tier/capabilities.dart`: entitlements, never tier numbers; new households start on WAMWins Basic. |
| C5 load on demand | One screen alive at a time; profiling draft and catalogue live only while profiling is open. |
| C6 fault isolation | A screen that fails shows "Try again"; the app keeps running. |
| C7 brand | Poppins, Royal Blue/Golden Yellow/White/Light Gray; app icon on phones, desktop logo on tablets; WAMWins™; light/dark. |
| C8 security | PBKDF2-SHA-256 310,000 iterations (computed off the UI thread), constant-time check, lockout, no secrets in the app. |

## Keeping shared files in step
After any change to `database/sqlite`, `conformance/vectors` or the brand assets, run from `mobile/`:
```bash
node tool/check_all.mjs      # sync + every check that doesn't need Flutter
```
From the repository root, `npx tsx mobile/tool/check_matching_fixture.ts` additionally proves the matching test household and
the app's matching/cooking SQL against the reference engine and the inventory-ledger triggers.

It copies the shared files, verifies migration order, compiles every SQL statement in the Dart code against
the real schema, replays the app's full write path (sign-up → household → provisioning → delete-all) against
all constraints and triggers, and checks Dart structure and imports.

## Verification status (be aware)
The Dart code was written without a Flutter toolchain available, so it has **not yet been compiled or run**.
Verified without Flutter: migration order and schema (26 shared files), all 117 SQL statements, the matching test household against the reference engine, the matching/cooking SQL against the ledger triggers, the complete
write path against every constraint/trigger, Dart bracket/string structure, and imports. The first
`flutter pub get`, `flutter analyze` and `flutter test` on your machine are the remaining checks; please send
me any errors and I'll fix them.
