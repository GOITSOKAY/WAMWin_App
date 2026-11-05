# WAMWins™

**Smart Solutions. Better Outcomes.**

This repository is the live WAMWins app: a mobile-first web app that people can also install on
their phone, tablet or computer, and that keeps working offline. It is published with
**GitHub Pages**: every file here is the website, exactly as it is served.

---

## Launch it (one time, about 10 minutes)

1. **Create a repository** on GitHub (for example `wamwins`). Public works on every GitHub plan.
2. **Upload everything in this folder** to the repository's top level: *Add file → Upload files*,
   then drag in all files and folders (not the outer folder itself). Include the hidden files
   `.gitignore` and `.nojekyll`. On a Mac press `Cmd+Shift+.` in Finder to see them; on Windows
   turn on *View → Hidden items*.
3. **Turn on GitHub Pages**: *Settings → Pages → Build and deployment → Deploy from a branch*,
   branch `main`, folder `/ (root)`, **Save**.
4. After about a minute the app is live at `https://YOUR-USERNAME.github.io/REPOSITORY-NAME/`.

## Connect your domain

Do this **before** inviting people: accounts and household data are stored per web address,
so anyone who signs up on the `github.io` address would start over on your domain.

1. **Verify the domain (recommended):** profile picture → *Settings → Pages → Add a domain*.
   Add the TXT record GitHub shows you at your domain provider, then click *Verify*.
2. **Add the domain to this repository first:** *Settings → Pages → Custom domain* → type it →
   **Save**. GitHub adds a file named `CNAME` to the repository. Keep it.
3. **Add DNS records at your domain provider**

   Subdomain, e.g. `app.yourdomain.com` (simplest):

   | Type | Name | Value |
   |---|---|---|
   | CNAME | `app` | `YOUR-USERNAME.github.io` |

   Main domain, e.g. `yourdomain.com`:

   | Type | Name | Value |
   |---|---|---|
   | A | `@` | `185.199.108.153` |
   | A | `@` | `185.199.109.153` |
   | A | `@` | `185.199.110.153` |
   | A | `@` | `185.199.111.153` |
   | CNAME | `www` | `YOUR-USERNAME.github.io` |

   Use your username only, never the repository name. Do not add wildcard (`*`) records.
4. **Wait** (usually under an hour, up to 24 hours), then tick **Enforce HTTPS** in *Settings → Pages*.
   HTTPS is required: offline mode, installing the app and password protection depend on it.

## Publish an update

1. Replace the changed files in this repository.
2. Open `sw.js` and raise the version on the first line, e.g. `wamwins-shell-v2` → `wamwins-shell-v3`.
   This tells phones that already installed WAMWins to download the new version; they will see
   *"A new version of WAMWins is ready — Reload"*.
3. Commit. GitHub Pages republishes automatically within a minute or two.

If you work from the full WAMWins project, run `node scripts/package-github.mjs` in `frontend/`:
it rebuilds this whole folder (and raises the `sw.js` version for you).

## What's in here

| Path | Purpose |
|---|---|
| `index.html` | The app's starting page |
| `manifest.webmanifest` | Name, colours and icons used when the app is installed |
| `sw.js` | Offline support and updates |
| `css/`, `js/` | The app |
| `assets/brand/` | Logos: app icon (phones) and desktop logo (tablets, desktops) |
| `assets/icons/` | Home-screen, browser-tab and Android icons |
| `assets/fonts/` | Poppins font and its licence (`OFL.txt`) |
| `404.html` | Sends any unknown address back to the app |
| `.nojekyll` | Tells GitHub Pages to publish the files exactly as they are |
| `.gitignore` | Keeps system files, tooling output, secrets and backups out of the repository |

## Good to know

- People's accounts and household data are stored securely **on their own device**. Signing in on
  another device and password reset by email will arrive when the WAMWins cloud service is connected.
- The Android and iOS apps are built separately from the full project with Capacitor and published
  through Google Play and the App Store.
- Fonts: Poppins, © The Poppins Project Authors, used under the SIL Open Font License 1.1
  (`assets/fonts/OFL.txt`).

© WAM Digital. WAMWins™ is a trademark of WAM Digital.
