# How to open the WAMWins app (Flutter)

You need a computer with **Flutter** and **Android Studio** (for Android). iPhone builds also need a **Mac with Xcode**.
Setup takes about 30–60 minutes the first time (mostly downloads); after that, opening the app takes a minute.

## 1. Install the tools (once)
1. **Flutter** — follow the official guide for your system: https://docs.flutter.dev/get-started/install
   (choose Windows or macOS, then "Android" as the target). Use the current **stable** version.
2. **Android Studio** — https://developer.android.com/studio . During its first launch accept the default
   setup (it installs the Android SDK). Then in Android Studio: *Settings → Plugins* → install **Flutter**.
3. Open a terminal (Windows: *PowerShell*; Mac: *Terminal*) and run:
   ```
   flutter doctor --android-licenses
   flutter doctor
   ```
   Answer **y** to the licences. `flutter doctor` should show green ticks for Flutter and Android toolchain.

## 2. Unzip the app
Unzip `wamwins-flutter.zip` somewhere simple, e.g. `Documents/wamwins-flutter`.

## 3. One-time setup (one command)
In the terminal, go into the folder and run the setup:
```
cd Documents/wamwins-flutter
dart tool/setup.dart
```
It creates the Android (and on a Mac, iPhone) project files with your Flutter version, names the app
**WAMWins**, makes the icon and splash screen, downloads packages and runs the tests.

## 4. Open it
**Option A — Android emulator (no phone needed)**
1. Android Studio → *More Actions → Virtual Device Manager* → *Create device* → choose e.g. **Pixel 8** → download a
   system image → *Finish* → press ▶ to start it.
2. In the terminal (still in the `wamwins-flutter` folder): `flutter run`

**Option B — your own Android phone**
1. On the phone: *Settings → About phone* → tap *Build number* 7 times; then *Developer options* → turn on *USB debugging*.
2. Connect it by USB, allow the computer on the phone, then run `flutter run`.

**Option C — in Android Studio**: *Open* → select the `wamwins-flutter` folder → pick your device at the top → press ▶.

The first build takes a few minutes; later starts are fast. While it runs, press **r** in the terminal to reload after a
change, **q** to quit.

**iPhone (Mac only):** run `open ios/Runner.xcworkspace`, choose your Apple ID team under *Signing & Capabilities*,
then `flutter run` with the iPhone or Simulator selected.

## 5. What to try
Create an account → answer the five setup steps → **Create my household** → on Home tap **What can we cook?** →
**Find meals** → **Cook this**. Try a family member with a peanut allergy and watch the peanut toast disappear,
with the reason under *Not suggested*.

## If something goes wrong
| Message | What to do |
|---|---|
| `flutter: command not found` / not recognized | Flutter isn't on your PATH — repeat the PATH step of the Flutter install guide, then open a new terminal. |
| `No connected devices` | Start the emulator first (step 4A) or check USB debugging; `flutter devices` lists what's available. |
| Android licence / SDK errors | `flutter doctor --android-licenses`, then `flutter doctor` and follow its hints. |
| A warning about the **NDK version** | Copy the version number it suggests into `android/app/build.gradle(.kts)` as `ndkVersion = "…"`, then `flutter run` again. |
| Any red **error** with a file name under `lib/` | Copy the whole message and send it to me — I'll fix the code. |

Note: accounts and households live on the device until WAMWins cloud sign-in is connected, so an account made in
the app is separate from one made on the website.
