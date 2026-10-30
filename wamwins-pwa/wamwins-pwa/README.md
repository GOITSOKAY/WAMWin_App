# WAMWins Basic — PWA bundle

Mobile web app (installable PWA) for WAMWins Basic, ready to wrap for Android and iOS.
Without configuration it runs fully on the device. With a Supabase project it signs users in
and syncs every household to your PostgreSQL database (`database/`).

## Folder

| Path | What it is |
| --- | --- |
| `index.html` | App shell (critical CSS inline) |
| `config.js` | **Your Supabase URL and anon key** (edit this; not cached by file hash) |
| `js/` | Code-split modules with content-hashed names, loaded on first use |
| `sw.js`, `manifest.webmanifest`, `icons/` | Offline cache, install metadata, icons |
| `database/` | PostgreSQL schema `01`–`14` (original) + `15_supabase.sql` + `16_app_catalog.sql` |
| `src/` | Readable source and `build.py` |

## Connect to Supabase (about 15 minutes)

1. Create a project at supabase.com (PostgreSQL 15+).
2. **SQL Editor**: run the files in `database/` in this order, one at a time, stopping on any error:
   `01_schema.sql`, `02_seed_reference.sql`, `04_profiling.sql`, `06_age_rules.sql`, `08_kitchen_catalog.sql`,
   `09_kitchen_catalog_seed.sql`, `10_kitchen_cutover.sql`, `12_about_you.sql`, `13_comments.sql`,
   **`15_supabase.sql`**, **`16_app_catalog.sql`**.
   Test files (`03`, `05`, `07`, `11`, `14`) are for a scratch project only.
3. **Settings → API → Exposed schemas**: add `core, ref, hh, health, match` (15_supabase.sql also sets this by SQL).
4. **Authentication → URL Configuration**: set *Site URL* to where the app is hosted and add it under *Redirect URLs*.
   Keep **Confirm email** on (Authentication → Providers → Email).
5. Optional: **Authentication → Providers** → enable Google and Apple with their client IDs.
6. Copy **Project URL** and **anon public key** (Settings → API) into `config.js`.
7. Host this folder on any static HTTPS host (Netlify, Vercel, Cloudflare Pages, Firebase Hosting).

## How sync works

- Sign-up, email verification, password reset and Google/Apple sign-in use Supabase Auth.
  `15_supabase.sql` creates the matching `core.users` row and makes `core.uid()` return the signed-in user.
- The first sync calls `core.create_household`; later changes are written with row-level security on.
- Food needs go through `health.save_answers`, *About you* through `core.save_about_you`.
- Stock amounts are never written directly: each change is an `hh.inventory_transactions` row (append-only ledger).
- Removed records are soft-deleted (`deleted_at`) so history is kept. *Delete my household* calls `core.delete_household`.
- The device copy is the offline cache. Changes made offline upload when the connection returns;
  opening the app on another device downloads the latest household.

## Build

`python3 src/build.py` (needs esbuild). Test locally with `python3 -m http.server` in this folder.
Native apps: `npm i @capacitor/core @capacitor/cli && npx cap init WAMWins com.wamdigital.wamwins --web-dir .`
then `npx cap add android` / `npx cap add ios`.
