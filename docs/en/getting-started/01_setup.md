# 01 · Setup & First Run

**This page answers:** what do I need installed, and what exact commands take me from `git clone` to a running app?

**After reading you can:** boot the app on a device in the `dev` flavor, and know why the two most common first-run failures happen.

---

## 1. Prerequisites

| Requirement | Version | Where the version comes from |
| :--- | :--- | :--- |
| Flutter SDK | **3.47.2** or newer | `pubspec.yaml` → `environment.flutter: ">=3.47.2"` |
| Dart SDK | **3.13.1** or newer | `pubspec.yaml` → `environment.sdk: ">=3.13.1 <4.0.0"` |
| JDK | **17** | `app/android/app/build.gradle.kts` → `JavaVersion.VERSION_17` |
| Android SDK | compileSdk **37**, NDK `28.2.13676358` | `app/android/app/build.gradle.kts` |
| Xcode + CocoaPods | iOS deployment target **15.0** | `app/ios/Podfile` |
| Ruby ≥ 3.0 | only for Fastlane | see [operations/02_fastlane_release.md](../operations/02_fastlane_release.md) |

### FVM is optional

The repo pins a Flutter version in `.fvmrc`:

```json
{
  "flutter": "3.47.2"
}
```

You may use either path — pick one and stay consistent:

```bash
# Path A — FVM (recommended for teams, keeps everyone on the pinned version)
dart pub global activate fvm
fvm install            # installs the version from .fvmrc
fvm flutter --version  # should print 3.47.2

# Path B — global Flutter SDK
flutter --version      # must be >= 3.47.2
```

> [!NOTE]
> Every command in this documentation is written for **Path B** (plain `flutter` / `dart`).
> If you use FVM, prefix them: `fvm flutter ...` and `fvm dart ...`.

---

## 2. Clone and install dependencies

This is a **Pub Workspace**. There is exactly one dependency resolution for all 24 workspace members (22 packages plus `app` and `tools`), so you run `pub get` **once, at the repo root** — never inside a sub-package.

```bash
git clone <repo-url>
cd flutter-monorepo-codebase

flutter pub get        # resolves the whole workspace, writes one root pubspec.lock
```

If you see per-package `pubspec.lock` files appear, something ran `pub get` from the wrong directory — delete them; only the root one is correct.

---

## 3. Generate the Firebase options (required — the repo does not compile without it)

> [!CAUTION]
> **A fresh clone will not compile.** This is the single most common first-run failure.

`packages/core/common/lib/src/firebase/firebase_module.dart` imports three files by name:

```dart
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_staging.dart' as stg;
```

Those three files are **generated per-project and git-ignored** (`packages/core/common/.gitignore` ignores `firebase_options_*.dart`), because they carry your own Firebase project identifiers. Until you generate them you will get:

```
Target of URI doesn't exist: 'firebase_options_dev.dart'
Undefined name 'DefaultFirebaseOptions'
```

**Fix — run FlutterFire once per environment:**

```bash
dart pub global activate flutterfire_cli

# Repeat for each flavor, writing into core_common with the matching file name:
flutterfire configure \
  --project=<your-dev-firebase-project> \
  --out=packages/core/common/lib/src/firebase/firebase_options_dev.dart

flutterfire configure \
  --project=<your-staging-firebase-project> \
  --out=packages/core/common/lib/src/firebase/firebase_options_staging.dart

flutterfire configure \
  --project=<your-prod-firebase-project> \
  --out=packages/core/common/lib/src/firebase/firebase_options_prod.dart
```

There is also a helper script: `dart tools/firebase/firebase_config.dart`.

All three files must exist even if you only intend to run `dev` — `firebase_module.dart` imports all three unconditionally, so a missing `prod` file breaks the `dev` build too.

---

## 4. Run code generation

The project leans heavily on codegen: `freezed`, `injectable`, `json_serializable`, `retrofit`, `drift`, `go_router_builder`, `flutter_gen`.

```bash
dart run build_runner build -d --workspace
```

- `-d` replaces the deprecated `--delete-conflicting-outputs`.
- `--workspace` runs the builders across **every** workspace package in one pass. Running build_runner inside a single package is not supported here.

> [!WARNING]
> Never hand-edit `*.g.dart`, `*.freezed.dart`, `*.module.dart` or `injection.config.dart`.
> They are overwritten on every run. Change the source annotation instead.

### Or do steps 2 + 4 in one shot

```bash
dart tools/workspace_setup/configure.dart
```

This cross-platform script runs: activate `flutterfire_cli` → `flutter clean` → `flutter pub get` → `gen-l10n` for every package that has ARB files → `build_runner build -d --workspace`.

> [!NOTE]
> There is **no** `configure.sh` or `configure.bat`. Older docs referenced them; only `configure.dart` exists.

---

## 5. Environment files and flavors

Three flavors ship with the template: `dev`, `staging`, `prod`. Values reach Dart through `--dart-define-from-file` and reach Android through Gradle's `dart-defines` decoding in `app/android/app/build.gradle.kts`.

| Flavor | Env file | Application ID suffix | Status |
| :--- | :--- | :--- | :--- |
| `dev` | `app/env.dev` | `.dev` | ✅ present |
| `staging` | `app/env.stg` | `.stg` | ✅ present |
| `prod` | `app/env.prod` | *(none)* | ❌ **you must create it** |

### Creating `app/env.prod`

It is not in the repo — production secrets are yours to supply. Copy the **key names** below (values redacted; read `app/env.dev` for the shape):

```properties
GOOGLE_MAP_API=
FACEBOOK_APP_ID=
FACEBOOK_TOKEN=
GOOGLE_APP=
BASE_URL=
SOCKET=
WEB_DOMAIN=
APP_LINK_MODE=
APP_SCHEMA=
APP_SCHEMA_VERSION=
APP_NAME=
```

Most of these surface in Dart through `EnvConstants` (`packages/core/common/lib/src/utils/env_constants.dart`), which reads them with `String.fromEnvironment`:

```dart
class EnvConstants {
  EnvConstants._();

  static const String GOOGLE_MAP_API = String.fromEnvironment('GOOGLE_MAP_API');
  static const String BASE_URL = String.fromEnvironment('BASE_URL');
  static const String SOCKET = String.fromEnvironment('SOCKET');
  // …
}
```

> [!NOTE]
> `APP_SCHEMA` and `APP_LINK_MODE` are **not** declared in `EnvConstants`. `APP_SCHEMA` is consumed on the Android side only, as a `resValue` string in `app/android/app/build.gradle.kts`. Keep them in the env file even though Dart never reads them directly.

> [!WARNING]
> `app/env.dev` and `app/env.stg` are currently **tracked by git** — the `.gitignore` pattern `*.env` does not match a file named `env.dev`. Treat their contents as non-secret sample values, and do not put real production credentials in `app/env.prod` until you have confirmed it is ignored.

---

## 6. Run the app

### From the CLI

```bash
flutter run -t app/lib/main.dart --flavor dev --dart-define-from-file=app/env.dev
```

### Building an APK — you must `cd app` first

```bash
cd app
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

> [!CAUTION]
> Running `flutter build apk` from the repo root fails with a confusing message such as
> `Target file "lib\main.dart" not found`, or
> `Flutter failed to read a file at ".../android/app/build.gradle"`.
> The Android project lives at `app/android`, so the build must be invoked from `app/`.
> Note the env path also changes: `env.dev` (relative to `app/`), not `app/env.dev`.

The artifact lands at `app/build/app/outputs/flutter-apk/app-dev-debug.apk`.

### Android: Built-in Kotlin is on

`app/android/gradle.properties` sets `android.builtInKotlin=true`. Leave it on.

Flutter is migrating plugins off the Kotlin Gradle Plugin (KGP) and onto the
Kotlin support built into the Flutter Gradle plugin. A plugin that has already
migrated — `google_sign_in_android`, for one — compiles its Java sources against
classes generated from its own Kotlin sources. With the flag off, those Kotlin
sources are never compiled, and the build dies on symbols that look like they
should exist:

```
GoogleSignInPlugin.java:218: error: cannot find symbol
  ResultUtilsKt.completeWithValue(...)
```

The message names the plugin, not the flag, so it reads like a broken
dependency version. It is not — pinning an older plugin version does not help.

Three plugins have **not** migrated yet and still apply KGP: `firebase_auth`,
`firebase_core`, `photo_manager`. They build fine today and only emit a warning:

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): ...
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

That warning is a real deadline, not noise. When a future Flutter release turns
it into an error, the fix is to upgrade those three plugins to versions that
support Built-in Kotlin — there is nothing to change in this repo.

### From VS Code

`.vscode/launch.json` already defines three configurations — **App (Dev)**, **App (Staging)**, **App (Prod)**. Pick one from the Run and Debug panel. Each sets `--flavor` and `--dart-define-from-file` for you (the env path is relative to `app/`, which is where the Dart extension anchors the project).

---

## 7. Verify your setup

```bash
flutter analyze                     # expect: No issues found!
cd packages/core/storage && flutter test && cd ../../..
```

If `flutter analyze` reports missing `firebase_options_*.dart`, go back to [step 3](#3-generate-the-firebase-options-required--the-repo-does-not-compile-without-it).

---

## Where to go next

| You want to… | Read |
| :--- | :--- |
| Understand what each package does | [02_project_tour.md](02_project_tour.md) |
| Know which command to run when | [03_daily_workflow.md](03_daily_workflow.md) |
| Understand the architecture | [../architecture/01_overview.md](../architecture/01_overview.md) |
| Build your first feature | [../guides/01_new_feature.md](../guides/01_new_feature.md) |
