# 01 · Setup & First Run

**This page answers:** what do I need installed, and what exact commands take me from `git clone` to a running app?

**After reading you can:** boot the app on a device in the `dev` flavor, and know why the two most common first-run failures happen.

---

## 1. Prerequisites

| Requirement | Version | Where the version comes from |
| :--- | :--- | :--- |
| Flutter SDK | **3.47.4** or newer | `pubspec.yaml` → `environment.flutter: ">=3.47.4"` |
| Dart SDK | **3.13.3** or newer | `pubspec.yaml` → `environment.sdk: ">=3.13.3 <4.0.0"` |
| JDK | **17 or newer** (builds on 21) | `apps/mobile/android/app/build.gradle.kts` → `JavaVersion.VERSION_17` is the bytecode target, not a ceiling |
| Android SDK | compileSdk **37**, NDK `28.2.13676358` | `apps/mobile/android/app/build.gradle.kts` |
| Xcode + CocoaPods | iOS deployment target **15.0** | `apps/mobile/ios/Podfile` |
| Ruby ≥ 3.0 | only for Fastlane | see [operations/02_fastlane_release.md](../operations/02_fastlane_release.md) |
| Node.js + npm, a Google account, a Firebase project | only for **real** Firebase config (§3) | the Firebase CLI is an npm package; skip all three if you use the §3 stubs |

### FVM is optional

The repo pins a Flutter version in `.fvmrc`:

```json
{
  "flutter": "3.47.4"
}
```

You may use either path — pick one and stay consistent:

```bash
# Path A — FVM (recommended for teams, keeps everyone on the pinned version)
dart pub global activate fvm
fvm install            # installs the version from .fvmrc
fvm flutter --version  # should print 3.47.4

# Path B — global Flutter SDK
flutter --version      # must be >= 3.47.4
```

> [!NOTE]
> Every command in this documentation is written for **Path B** (plain `flutter` / `dart`).
> If you use FVM, prefix them: `fvm flutter ...` and `fvm dart ...`.

---

## 2. Clone and set up the workspace

This is a **Pub Workspace**. All 31 workspace members (28 packages, the two apps, and `tools`) share exactly one dependency resolution. One setup script prepares every one of them:

```bash
git clone <repo-url>
cd flutter-monorepo-codebase

dart tools/workspace_setup/configure.dart
```

**`configure.dart` is the setup step** — not a shortcut for `pub get` + `build_runner`. It runs, in order, stopping at the first failure:

1. `dart pub global activate flutterfire_cli` — only the real-Firebase path in [§3](#3-generate-the-firebase-options-required--the-repo-does-not-compile-without-it) uses it.
2. `flutter clean` at the root.
3. `flutter pub get` at the root — resolves the whole workspace against the one root `pubspec.lock`.
4. `flutter gen-l10n` in every package that has an `l10n.yaml` (today `platform/ui/design_system` and the auth, home, onboarding, settings and splash features).
5. `dart run build_runner build --workspace` — injectable, freezed, json_serializable, retrofit, go_router_builder, drift, flutter_gen.
6. `dart tools/barrel_generator/generate.dart <package>/lib` for every package with a `lib/` — the apps are skipped, because their `injection.dart` is composer's output.

It uses `fvm` automatically when your machine is set up for it. There is no `configure.sh` or `configure.bat` wrapper — a Dart script runs identically on every platform.

> [!IMPORTANT]
> **`flutter pub get` + `build_runner` alone is not a working setup.** The `lib/src/src.dart` of `core_base_ui`, and of every feature with translations, exports `gen/gen.dart`. That barrel (plus `gen/language/language.dart`) is gitignored, and only step 6 writes it. Stop after step 5 and `flutter analyze` reports around 17 errors of this shape:
>
> ```
> error • Target of URI doesn't exist: 'gen/gen.dart' • platform/ui/design_system/lib/src/src.dart:3:8 • uri_does_not_exist
> error • Undefined name 'AppLocalizations' • …
> error • Undefined name 'Assets' • …
> ```
>
> The fix is to run `dart tools/workspace_setup/configure.dart`.

To run the steps by hand, run all of them, in this order. The barrel pass must come **after** gen-l10n and build_runner, because it exports the files they write (bash shown):

```bash
flutter pub get
# gen-l10n in each package that has an l10n.yaml
(cd platform/ui/design_system && flutter gen-l10n)
for f in auth home onboarding settings splash; do (cd modules/$f/feature && flutter gen-l10n); done
dart run build_runner build --workspace
# barrels for every package with a lib/, apps excluded
for d in platform/*/* modules/*/*; do [ -d "$d/lib" ] && dart tools/barrel_generator/generate.dart "$d/lib"; done
```

What to expect on a clean run:

- build_runner prints several `W injectable_config_builder … Missing dependencies` warnings. They are expected: each micro-package's DI module is generated on its own and names types another package registers. The app's `injection.config.dart` puts them together.
- **One lock file, at the root, committed.** `pubspec.lock` is tracked (the root `.gitignore` unignores `/pubspec.lock`), so everyone resolves the same versions. Commit it when a dependency change moves it. If per-package `pubspec.lock` files appear, something ran `pub get` from the wrong directory. Delete them, because only the root one is used.

---

## 3. Generate the Firebase options (required — the repo does not compile without it)

> [!CAUTION]
> **A fresh clone will not compile.** This is the single most common first-run failure.

`apps/mobile/lib/firebase/firebase_module.dart` imports three files by name:

```dart
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_staging.dart' as stg;
```

Those three files are **generated per-project and git-ignored** (`apps/mobile/.gitignore` ignores `firebase_options_*.dart`), because they carry your own Firebase project identifiers.

They belong to the **app**, not to `platform/`: Firebase options name one bundle ID, so each app that uses Firebase owns its own `lib/firebase/`. They used to live in `core_common`, which handed the mobile app's options to every other app in the workspace. Until they exist, `flutter analyze` reports:

```
error • Target of URI doesn't exist: 'firebase_options_dev.dart' • apps/mobile/lib/firebase/firebase_module.dart:4:8 • uri_does_not_exist
error • Target of URI doesn't exist: 'firebase_options_prod.dart' • apps/mobile/lib/firebase/firebase_module.dart:5:8 • uri_does_not_exist
error • Target of URI doesn't exist: 'firebase_options_staging.dart' • apps/mobile/lib/firebase/firebase_module.dart:6:8 • uri_does_not_exist
```

You have two ways out: a real Firebase project (§3.1), or compile-only stubs (§3.2).

### 3.1 With a Firebase project — the helper script

What you need first:

- **Node.js + npm**, and the **Firebase CLI** installed globally: `npm install -g firebase-tools`.
- A **Google account** and a **Firebase project** you can access. Create one at the Firebase console.
- An interactive **`firebase login`** in a terminal that can open a browser.

Then run from the repository root:

```bash
dart tools/firebase/firebase_config.dart --app mobile
```

The script requires the Firebase CLI to be installed and logged in. If it is missing, the script prints install instructions and exits 1; it tries `firebase login` at most twice, refuses to run without a terminal, and `--help` prints its usage. `configure.dart` has already activated `flutterfire_cli`. It asks for three things: a **Firebase project ID**, a **base bundle ID / package name** (`com.example.codebase`), and the flavors (default `dev staging prod`). Then it runs `flutterfire configure` inside `apps/mobile/` for every flavor and build mode. It writes `lib/firebase/firebase_options_<flavor>.dart`, `ios/flavors/<flavor>/GoogleService-Info.plist` and `android/app/src/<flavor>/google-services.json`, all relative to `apps/mobile/`. The Android package gets `.dev` / `.stg` / no suffix, and the iOS bundle ID gets `.dev` / `.staging` / no suffix. `--app` may be omitted while the workspace has a single app.

> [!NOTE]
> The helper puts **all flavors in the one project ID** you type. To keep dev, staging and prod in separate Firebase projects, run FlutterFire by hand instead, once per environment, **from `apps/mobile/`**:

```bash
cd apps/mobile

flutterfire configure \
  --project=<your-dev-firebase-project> \
  --out=lib/firebase/firebase_options_dev.dart \
  --android-package-name=com.example.codebase.dev \
  --android-out=android/app/src/dev/google-services.json

flutterfire configure \
  --project=<your-staging-firebase-project> \
  --out=lib/firebase/firebase_options_staging.dart \
  --android-package-name=com.example.codebase.stg \
  --android-out=android/app/src/staging/google-services.json

flutterfire configure \
  --project=<your-prod-firebase-project> \
  --out=lib/firebase/firebase_options_prod.dart \
  --android-package-name=com.example.codebase \
  --android-out=android/app/src/prod/google-services.json
```

All three Dart files must exist even if you only intend to run `dev`. `firebase_module.dart` imports all three unconditionally, so a missing `prod` file breaks the `dev` build too.

> [!IMPORTANT]
> The three Dart files are enough to **compile**: analyze and tests pass with them, and CI stubs them for exactly that. **Building an Android app** also needs `apps/mobile/android/app/src/<flavor>/google-services.json`. Without it, the Google Services Gradle plugin fails `process<Flavor>DebugGoogleServices`. The helper script writes it. The manual commands above write it only because of the `--android-package-name` / `--android-out` flags.

### 3.2 No Firebase project yet? Use stubs

To get the app compiling and an APK building without a Firebase account, create stand-in files by hand. The app **builds**, but everything Firebase-backed (push notifications, FCM token) will not work, and Firebase calls at runtime may log errors. Replace the stubs with real config (§3.1) before you rely on any of it.

Or let the setup script write them: `dart tools/workspace_setup/configure.dart --stub-firebase` writes every file below. That is the Dart options for each flavor, and a `google-services.json` for each Android flavor with the package name read from `build.gradle.kts`. It writes only files that do not exist yet, and lists what it stubbed.

**1. Three Dart files.** Create them in `apps/mobile/lib/firebase/`, named `firebase_options_dev.dart`, `firebase_options_staging.dart` and `firebase_options_prod.dart`, each with this content. It is the exact stub `tools/workspace_setup/firebase_stubs.dart` writes (what `configure.dart --stub-firebase` and CI use):

```dart
// CI-only stub. Not a real Firebase configuration: analysis and unit
// tests never initialise Firebase, they only need this to compile.
// Generate the real file with `flutterfire configure`.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
    apiKey: 'ci-stub',
    appId: 'ci-stub',
    messagingSenderId: 'ci-stub',
    projectId: 'ci-stub',
  );
}
```

**2. One `google-services.json` per flavor you build.** It goes in `apps/mobile/android/app/src/<flavor>/google-services.json`, and `package_name` must equal that flavor's application ID. For `dev` it is `com.example.codebase.dev`, for `staging` it is `com.example.codebase.stg`, and for `prod` it is `com.example.codebase` (`applicationId` + `applicationIdSuffix` in `apps/mobile/android/app/build.gradle.kts`). The `dev` one:

```json
{
  "project_info": {
    "project_number": "000000000000",
    "project_id": "local-stub"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:000000000000:android:0000000000000000",
        "android_client_info": {
          "package_name": "com.example.codebase.dev"
        }
      },
      "api_key": [
        { "current_key": "local-stub" }
      ]
    }
  ],
  "configuration_version": "1"
}
```

With those in place, `cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev` succeeds. All of these files are gitignored, so they can't be committed by accident.

---

## 4. Code generation after setup

`configure.dart` ran the whole codegen chain once. From then on, re-run only the part your change touched:

```bash
dart run build_runner build --workspace   # after changing an annotation
```

- `--workspace` runs the builders across **every** workspace package in one pass. Running build_runner inside a single package is not supported here.
- Do **not** pass `-d` / `--delete-conflicting-outputs`. That flag was removed from build_runner, which now ignores it and prints `W These options have been removed and were ignored: --delete-conflicting-outputs`.
- Added, renamed or deleted a file under a package's `lib/`? Re-run the barrel generator for that package **after** codegen: `dart tools/barrel_generator/generate.dart <package>/lib`. See [03_daily_workflow.md](03_daily_workflow.md).

> [!WARNING]
> Never hand-edit `*.g.dart`, `*.freezed.dart`, `*.module.dart` or `injection.config.dart`.
> They are overwritten on every run. Change the source annotation instead.

---

## 5. Environment files and flavors

Three flavors ship with the template: `dev`, `staging`, `prod`. Values reach Dart through `--dart-define-from-file` and reach Android through Gradle's `dart-defines` decoding in `apps/mobile/android/app/build.gradle.kts`.

| Flavor | Env file | Application ID suffix | Status |
| :--- | :--- | :--- | :--- |
| `dev` | `apps/mobile/env.dev` | `.dev` | ✅ present |
| `staging` | `apps/mobile/env.stg` | `.stg` | ✅ present |
| `prod` | `apps/mobile/env.prod` | *(none)* | ❌ **you must create it** |

### Creating `apps/mobile/env.prod`

It is not in the repo — production secrets are yours to supply. Copy the **key names** below (values redacted; read `apps/mobile/env.dev` for the shape):

```properties
BASE_URL=
WEB_DOMAIN=
APP_LINK_MODE=
APP_NAME=
```

Three of them surface in Dart through `EnvConstants` (`platform/foundation/kernel/lib/src/utils/env_constants.dart`), which reads them with `String.fromEnvironment`:

```dart
class EnvConstants {
  EnvConstants._();

  static const String BASE_URL = String.fromEnvironment('BASE_URL');
  static const String WEB_DOMAIN = String.fromEnvironment('WEB_DOMAIN');
  static const String APP_NAME = String.fromEnvironment('APP_NAME');
}
```

> [!NOTE]
> `APP_LINK_MODE` is **not** declared in `EnvConstants`: only the iOS entitlements read it (`applinks:$(WEB_DOMAIN)$(APP_LINK_MODE)` in `apps/mobile/ios/Runner/Runner.entitlements`). Keep it in the env file even though Dart never reads it. `WEB_DOMAIN` is also the host of the Android App Links intent-filter — an empty value becomes the reserved `example.invalid`, never "every https link" — see [`04_routing.md` §9](../guides/04_routing.md#9-set-up-deep-links). Add a key your product needs (a maps API key, a socket URL) to the env files and to `EnvConstants` together.

> [!WARNING]
> `apps/mobile/env.dev` and `apps/mobile/env.stg` are **committed on purpose** — a fresh clone must build — so keep them free of secrets. `apps/mobile/env.prod` is ignored by name in `apps/mobile/.gitignore` (the root `*.env` pattern would not match it); `git check-ignore -v apps/mobile/env.prod` confirms it before you put production values in.

---

## 6. Run the app

Both `flutter run` and `flutter build` must be invoked **from `apps/mobile/`**. The workspace root has no `android/` or `ios/` project, so a `-t apps/mobile/lib/main.dart` run from the root cannot work.

> [!NOTE]
> **`apps/mobile` is Android + iOS only.** It commits no `linux/`, `macos/`, `windows/` or `web/`
> runner, so `flutter run -d linux` or `flutter build linux` there stops with *No Linux desktop
> project configured*. For a desktop build, use the second app: [`apps/admin/README.md`](../../../apps/admin/README.md)
> generates its desktop runners and runs it. To give an app a platform it lacks, run
> `flutter create --platforms=linux .` (or `macos`, `windows`) **inside that app's directory** —
> never at the workspace root — and delete the `test/widget_test.dart` and `analysis_options.yaml`
> it writes, as that README explains. This repo configures `--flavor` for Android and iOS only; drop the flag on desktop.

### From the CLI

```bash
cd apps/mobile
flutter run --flavor dev --dart-define-from-file=env.dev
```

### Building an APK

```bash
cd apps/mobile
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

> [!CAUTION]
> Running `flutter run` or `flutter build apk` from the repo root fails with a confusing message such as
> `Target file "lib/main.dart" not found` (`lib\main.dart` on Windows), or
> `Flutter failed to read a file at ".../android/app/build.gradle"`.
> The Android project lives at `apps/mobile/android`, so the command must be invoked from `apps/mobile/`.
> Note the env path also changes: `env.dev` (relative to `apps/mobile/`), not `apps/mobile/env.dev`.

The artifact lands at `apps/mobile/build/app/outputs/flutter-apk/app-dev-debug.apk`.

### Android: Built-in Kotlin is on

`apps/mobile/android/gradle.properties` sets `android.builtInKotlin=true`. Leave it on.

Flutter is migrating plugins off the Kotlin Gradle Plugin (KGP) and onto the
Kotlin support built into the Flutter Gradle plugin. A plugin that has already
migrated compiles its Java sources against classes generated from its own Kotlin
sources. Here it was `google_sign_in_android` that surfaced this, before the auth
sample stopped depending on it. With the flag off, those Kotlin sources are never
compiled, and the build dies on symbols that look like they should exist:

```
GoogleSignInPlugin.java:218: error: cannot find symbol
  ResultUtilsKt.completeWithValue(...)
```

The message names the plugin, not the flag, so it reads like a broken
dependency version. It is not — pinning an older plugin version does not help.

At the time of writing, `firebase_core` had **not** migrated and still applied KGP
(`firebase_auth` and `photo_manager` were in the same state, and have since left
the workspace). A plugin like that builds fine today and only emits a warning:

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): ...
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

That warning is a real deadline, not noise. If a future Flutter release turns it
into an error, upgrade the plugins the warning names to versions that support
Built-in Kotlin. There is nothing to change in this repo.
Trust the warning's list over this page's: it is computed from what you actually
depend on.

### Android: app backup is off

`apps/mobile/android/app/src/main/AndroidManifest.xml` sets `android:allowBackup="false"`, `android:fullBackupContent="false"` and `android:dataExtractionRules="@xml/data_extraction_rules"`, whose rules exclude every domain from cloud backup **and** device-to-device transfer (Android 12+ ignores `allowBackup` for the latter).

The reason is `core_storage`'s secure layer. `flutter_secure_storage` keeps its ciphertext in a SharedPreferences file, but the key that decrypts it lives in the Android Keystore, which is never backed up. A restore onto a new phone would bring back values the app can no longer decrypt — a signed-out user at best, a read error at worst.

The trade-off: a reinstall or a new phone starts from a clean app — no preferences, theme or onboarding flag. To keep plain preferences, turn backup back on and exclude only the secure-storage file. Do it in both `<cloud-backup>` and `<device-transfer>` of `apps/mobile/android/app/src/main/res/xml/data_extraction_rules.xml`, plus a matching `fullBackupContent` file for Android 11 and lower:

```xml
<exclude domain="sharedpref" path="FlutterSecureStorage.xml" />
```

Confirm the file name on a device first (`adb shell run-as <applicationId> ls shared_prefs`) — it depends on the `flutter_secure_storage` version and options.

### From VS Code

`.vscode/launch.json` already defines three configurations — **App (Dev)**, **App (Staging)**, **App (Prod)**. Pick one from the Run and Debug panel. Each sets `--flavor` and `--dart-define-from-file` for you (the env path is relative to `apps/mobile/`, which is where the Dart extension anchors the project).

---

## 7. Verify your setup

```bash
flutter analyze                     # expect: No issues found!
cd platform/infra/storage && flutter test && cd ../..
```

If `flutter analyze` is not clean:

| You see | Cause | Fix |
| :--- | :--- | :--- |
| `Target of URI doesn't exist: 'firebase_options_dev.dart'` (and `_prod`, `_staging`) in `firebase_module.dart` | The gitignored Firebase options are missing | [Step 3](#3-generate-the-firebase-options-required--the-repo-does-not-compile-without-it), real or stubbed |
| `Target of URI doesn't exist: 'gen/gen.dart'`, `Undefined name 'AppLocalizations'`, `Undefined name 'Assets'` (about 17 errors) | Setup stopped short of the barrel pass, typically after running only `pub get` + `build_runner` | Run `dart tools/workspace_setup/configure.dart` |
| `Undefined class '_$…'`, `… .g.dart` / `.freezed.dart` not found | Codegen has not run, or is stale | Run `dart tools/workspace_setup/configure.dart` (or `dart run build_runner build --workspace` if setup already ran once) |

---

## Where to go next

| You want to… | Read |
| :--- | :--- |
| Understand what each package does | [02_project_tour.md](02_project_tour.md) |
| Know which command to run when | [03_daily_workflow.md](03_daily_workflow.md) |
| Understand the architecture | [../architecture/01_overview.md](../architecture/01_overview.md) |
| **Next step:** build, test and remove your first feature, end to end | [04_first_feature_tutorial.md](04_first_feature_tutorial.md) |
| Build a real feature | [../guides/01_new_feature.md](../guides/01_new_feature.md) |
