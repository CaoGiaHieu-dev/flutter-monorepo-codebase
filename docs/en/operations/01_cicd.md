# CI/CD

This page answers: **what pipelines exist, what each one does, which secrets they need, and what is currently broken in them.** After reading it you can configure the repository secrets, trigger a build, and reproduce every CI step locally before you push.

> [!IMPORTANT]
> The release pipelines depend on **repository secrets** for every gitignored input — Firebase options, `google-services.json`, `env.prod`, the release keystore, fastlane's `Config.yaml` ([§7](#7-secrets)). Without them they stop at their first step, naming the missing secret. Do not assume a green checkmark exists until you have configured them and run the pipeline once.

---

## 1. Pipeline inventory

Five pipelines ship with the template — four on GitHub Actions, one on Azure DevOps.

| Pipeline | File | Trigger | Output |
|:---|:---|:---|:---|
| Build and Distribute | `.github/workflows/flutter_build.yml` | Manual (`workflow_dispatch`) | Signed release APK → Firebase App Distribution |
| AI Code Review | `.github/workflows/code_review.yml` | PR to `main`/`develop`/`master` + manual | Markdown report artifact + PR comments |
| Fastlane build and distribute | `.github/workflows/fastlane.yml` | Manual (`workflow_dispatch`) | Delegates to Fastlane lanes |
| **PR Quality Check** | `.github/workflows/pr_quality_check.yml` | **PR to `main`/`develop`/`master`** + manual | Pass/fail — blocks the merge |
| Azure Build + Distribute | `azure-ci-cd.yml` | `trigger: none` (manual only) | Prod APK artifact → Firebase |

`pr_quality_check.yml` is the only pipeline that gates a merge. It runs six blocking gates in order — composition drift, architecture rules, `flutter analyze`, per-package tests, dependency-catalog drift, documentation accuracy — plus one advisory audit. See [§6](#6-the-quality-gate).

---

## 2. `flutter_build.yml` — Build and Distribute

The main Android release pipeline. It is manual-only: **Actions → Build and Release → Run workflow**.

### Inputs

| Input | Required | Default | Notes |
|:---|:---|:---|:---|
| `flavor` | yes | `prod` | `dev` / `staging` / `prod` |
| `version` | yes | `1.0.0` | Becomes `--build-name` |
| `notes` | no | — | Appended to the Firebase release notes |

The build number is not an input — it uses `${{ github.run_number }}`, so it increments automatically per workflow run.

### Steps, in order

1. **Checkout** — `actions/checkout@v4`.
2. **Set Up Java** — Oracle distribution, **Java 17**. Matches `sourceCompatibility`/`targetCompatibility` in `apps/mobile/android/app/build.gradle.kts`.
3. **Set Up Flutter** — `subosito/flutter-action@v2`, pinned to **`3.47.4`**, channel `stable`, with cache enabled.
4. **Restore gitignored build inputs from secrets** — for the chosen flavor only, each from a base64 secret ([§7](#7-secrets)):
   - `firebase_options_<flavor>.dart` in `apps/mobile/lib/firebase/`; the two other flavors get a compile-only stub, because `firebase_module.dart` imports all three and injectable registers only the built flavor's options;
   - `apps/mobile/android/app/src/<flavor>/google-services.json` — the `com.google.gms.google-services` Gradle plugin fails the build without it;
   - `apps/mobile/env.prod` (prod only — `env.dev` / `env.stg` are committed);
   - prod only: `apps/mobile/android/keystore.jks` + `key.properties` (`storeFile=../keystore.jks`). dev and staging are signed with the committed dev keystore.

   A missing secret fails this step with an error naming it — before any codegen or Gradle time is spent. It runs **before** code generation because `build_runner` must be able to resolve `firebase_module.dart`'s imports.
5. **Get dependencies from the committed lockfile** — `flutter pub get --enforce-lockfile`. The workspace `pubspec.lock` is committed; a lockfile that no longer matches the pubspecs fails here instead of being silently re-resolved.
6. **Install Dependencies** — `dart tools/workspace_setup/configure.dart`. This single Dart script does pub get, l10n generation and `build_runner` for the whole workspace.
7. **Build APK** — note the `cd apps/mobile` on its own line first:
   ```bash
   cd apps/mobile
   flutter build apk --flavor="$FLAVOR" --build-name="$VERSION" --build-number="$GITHUB_RUN_NUMBER" \
     --dart-define-from-file="$GITHUB_WORKSPACE/apps/mobile/$ENV_FILE" \
     --obfuscate --split-debug-info="$GITHUB_WORKSPACE/obfuscate/" \
     --no-tree-shake-icons --verbose
   ```
   `ENV_FILE` is `env.dev` / `env.stg` / `env.prod`, set by step 4 — the same flavor-to-file mapping Fastlane uses.
8. **Upload and Distribute** — `nickwph/firebase-app-distribution-action@v1`, uploading `apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk`.

> [!NOTE]
> **The `cd apps/mobile` is not optional.** `flutter build apk` run from the repository root fails with a confusing `android/app/build.gradle not found`, because the Flutter project lives in `apps/mobile/`, not at the workspace root. The same applies when you build locally — see [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

The artifact name interpolates the flavor (`app-${{ inputs.flavor }}-release.apk`), so it stays correct for all three flavors. That is the right pattern; Azure does **not** do this — see [§5](#5-azure-ci-cdyml--azure-devops).

> [!WARNING]
> The Firebase App ID is **not** per flavor: every flavor uploads to `secrets.FIREBASE_ANDROID_APP_ID`. The flavors have different application IDs (`.dev`, `.stg`), so each is a different Firebase app — set the secret to the app of the flavor you dispatch, or split it per flavor.

### Cost note

The job runs on `macos-latest` even though it only builds Android. macOS runners are billed at a much higher multiplier than Linux on GitHub-hosted plans. Unless you intend to add the (currently commented-out) iOS build back into this same job, `ubuntu-latest` builds Android just as well and far cheaper.

---

## 3. `code_review.yml` — AI Code Review

Runs the repo's own Gemini-powered reviewer (`tools/code_review/code_review.dart`) and posts results back to the pull request.

**Triggers**: pull requests to `main` / `develop` / `master` touching `apps/*/lib/**/*.dart`, `modules/**/*.dart` or `platform/**/*.dart` (generated files excluded), plus manual dispatch with a scope selector (`changed` / `all` / `domain` / `data` / `platform` / `presentation`) and a report language (`en` / `vi` / `ja` / `ko` / `zh`).

**What it does**: resolves changed files with `tj-actions/changed-files`, runs the reviewer, uploads the Markdown report as an artifact (30-day retention), then parses that report and posts **inline review comments** on the exact lines when they fall inside the PR diff. Findings outside the diff are grouped into a separate per-file comment.

### Flutter version pinning

Dependency installation runs `dart tools/workspace_setup/configure.dart`, and `flutter_version` defaults to `3.47.4`, matching the root `pubspec.yaml` constraint.

> [!NOTE]
> `flutter_version` is only bound on `workflow_dispatch`. On a `pull_request` event `github.event.inputs.flutter_version` is empty, so `subosito/flutter-action@v2` receives an empty `flutter-version` and resolves the latest stable instead of the pinned one. Harmless for an AI review; do not copy this pattern into a pipeline that builds artefacts.

### The "Fail on Critical Issues" step does not fail

The final step counts 🔴 markers in the report and then deliberately does nothing with the count:

```bash
if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "::error::Found $CRITICAL_COUNT critical issues in code review"
  echo "::warning::Please review the detailed report and fix critical issues"
  # Don't fail the build, just warn
  # exit 1
fi
```

`exit 1` is commented out, so **the AI review is advisory only and never blocks a merge**. If you want it to gate, uncomment that line — but do so only after you trust the reviewer's false-positive rate on your codebase, otherwise every PR stalls.

---

## 4. `fastlane.yml` — Fastlane build and distribute

Manual dispatch that hands the whole build over to Fastlane, run **from the repository root** (the root `fastlane/Fastfile` imports the lanes from `apps/mobile/fastlane/`; see [`02_fastlane_release.md` §1](02_fastlane_release.md#1-why-you-can-run-it-from-anywhere)).

### Inputs

| Input | Default | Notes |
|:---|:---|:---|
| `build-on` | `self-hosted` | `self-hosted` or `macos-latest`. Anything that builds iOS must be a Mac with signing set up |
| `platform` | `both` | `both` → `fastlane flutter` (iOS first, then Android); `android` → `fastlane android build`; `ios` → `fastlane ios build` |
| `flutter_version` | `3.47.4` | Installed by `subosito/flutter-action` **and** passed to the lane, which stops if the Flutter it finds differs |
| `version` | `1.0.0` | `--build-name` |
| `build_number` | *(empty)* | Empty means `auto`: latest on the store (`distribute_store`) or on Firebase (`distribute_firebase`) plus one; with no distribution target, the build number in `apps/mobile/pubspec.yaml`. A literal must be a positive integer |
| `flavor` | `prod` | `dev` / `staging` / `prod` |
| `change_log` | `Initial release` | Release notes. Always wins over anything else (no stale temp file can replace it) |
| `build_type` | `apk` | Android only |
| `distribute_store` | `false` | Play Store and/or TestFlight, depending on `platform` |
| `track` | `internal` | Play track, used only with `distribute_store` |
| `distribute_firebase` | `true` | Firebase App Distribution |

### Steps

1. **Checkout**, **Java 17**.
2. **Ruby 3.3 + `bundle install`** at the repository root (`ruby/setup-ruby` with `bundler-cache` on GitHub-hosted runners, a plain `bundle install` on `self-hosted`). The root `Gemfile` lists `fastlane` and `cocoapods` and loads the plugins from `apps/mobile/fastlane/Pluginfile` through `fastlane/Pluginfile`, so there is no `fastlane add_plugin` step — that command is interactive and fails on a runner.
3. **Flutter** at `flutter_version`.
4. **Restore gitignored build inputs from secrets** — `apps/mobile/fastlane/Config.yaml`, the flavor's Firebase options (other flavors stubbed), `google-services.json` (Android), `GoogleService-Info.plist` (iOS, optional), `env.prod` and the release keystore (prod), and the credential files `Config.yaml` points at — only those the chosen distribution needs. Every missing secret is reported by name, then the step fails.
5. **Build and distribute** — `bundle exec fastlane <lane> …`. Inputs reach the script through `env:`, never interpolated into it, so a change log containing quotes or `$(…)` is passed verbatim. The lane does its own toolchain setup: `flutter pub get --enforce-lockfile`, `gen-l10n`, `build_runner`.

> [!NOTE]
> iOS **code signing** (certificates, provisioning profiles) is not set up by any workflow. `platform: both` / `ios` needs a runner whose keychain already has them — in practice a `self-hosted` Mac.


---

## 5. `azure-ci-cd.yml` — Azure DevOps

Two stages on a self-hosted pool named `codebase`. `trigger: none`, so it only runs when started manually or by a release.

**Stage `Build`**: capture the short commit SHA into `commitTag` → download `env.prod`, `firebase_options_prod.dart` and `google-services.prod.json` as Azure *secure files* and copy them into place (dev/staging Firebase options get a compile-only stub) → install Flutter at `$(flutter-version)` → `flutter clean` → `flutter pub get --enforce-lockfile` → "Flutter Config" → download `key.properties` and `keystore.jks` as secure files into `apps/mobile/android/` → build the prod APK with `--dart-define-from-file=$(Build.SourcesDirectory)/apps/mobile/env.prod` → publish it as artifact `android`.

**Stage `Distribute`**: download the artifact, then `firebase appdistribution:distribute` it.

Pipeline variables must be defined in the Azure Variables tab: `flutter-version`, `flutterPath`, `version`, `numberBuild`, `note`, and `FIREBASE-ANDROID-ID`.

The artefact filename, the `configure.dart` call and the env file are consistent: the build publishes `app-prod-release.apk`, the Distribute stage downloads and uploads that same name, "Flutter Config" runs `dart tools/workspace_setup/configure.dart`, and the dart-define file is `apps/mobile/env.prod` — the same file Fastlane and `flutter_build.yml` use for prod. A secure file missing from the library fails its `DownloadSecureFile@1` task, before anything is built.

The pipeline builds **prod only** (`--flavor=prod`, `app-prod-release.apk`).

The iOS build and iOS distribute tasks are present but fully commented out.

---

## 6. The quality gate

`pr_quality_check.yml` runs on every pull request to `main`, `develop` or `master`. It is the only pipeline that can block a merge.

| # | Gate | Command | Blocking |
|:--|:---|:---|:---|
| 0 | Composition matches every app's manifest | `dart tools/composer/composer.dart verify` | yes |
| 1 | Architecture rules | `dart tools/arch_check/check.dart` | yes |
| 2 | Static analysis | `flutter analyze` | yes |
| 3 | Tests, per package | `flutter test` in every package that has a `test/` directory | yes |
| 4 | Catalog drift | `dart tools/dependency_sync.dart --check` | yes |
| 5 | Documentation accuracy | `dart tools/docs_check/check.dart` | yes |
| — | Unused dependency audit | `dart tools/unused_checker/check_unused_packages.dart` | no (advisory) |

Gates 0 and 1 run first on purpose: they only read manifests, imports and pubspecs, needs no codegen, and finishes in about 200 ms — so a composition or layering mistake fails in seconds instead of after a full analyze-and-test cycle. Gate 1 is also the only gate that can see layering at all; nothing in `analysis_options.yaml` knows that core must not import a feature.

Gate 3 loops per package because this is a Pub Workspace: tests live in each package's own `test/` — today mostly under `platform/*/test/` — and a single `flutter test` at the root does not pick them up.

> [!IMPORTANT]
> A clean `flutter analyze` does **not** prove the app builds. `analysis_options.yaml` excludes `**.freezed.dart`, `**.g.dart`, `**.config.dart` and `**.module.dart`, so the analyser never looks at generated code. Move a type between packages and a `.freezed.dart` file can end up referencing a symbol it cannot see: analyze stays green while the APK build fails. Only a real build catches that class of error.

**Still missing:** the release pipelines (`flutter_build.yml`, `fastlane.yml`, `azure-ci-cd.yml`) are all `workflow_dispatch` and run **no** gates of their own. A manual dispatch from a branch that never opened a PR will build, sign and distribute unverified code. If that matters to you, add gates 0–5 to `flutter_build.yml` between "Install Dependencies" and "Build APK", or require that releases only ever be cut from a merged branch.

---

## 7. Secrets

### GitHub Actions

Every file below is gitignored, so a clean runner has none of them; the release workflows decode them from secrets. `<FLAVOR>` is `DEV`, `STAGING` or `PROD` — only the flavor being built is needed. Unless marked *raw*, a secret holds the **base64** of the file.

| Secret | Written to | Needed by | How to produce it |
|:---|:---|:---|:---|
| `FIREBASE_OPTIONS_<FLAVOR>_DART_B64` | `firebase_options_<flavor>.dart` in `apps/mobile/lib/firebase/` | `flutter_build.yml`, `fastlane.yml` — every build of that flavor | `cd apps/mobile/lib/firebase && base64 -w0 firebase_options_dev.dart` (generate the file with `dart tools/firebase/firebase_config.dart --app mobile`) |
| `GOOGLE_SERVICES_<FLAVOR>_JSON_B64` | `apps/mobile/android/app/src/<flavor>/google-services.json` | both — every Android build of that flavor | `base64 -w0 apps/mobile/android/app/src/dev/google-services.json` |
| `GOOGLE_SERVICE_INFO_<FLAVOR>_PLIST_B64` | `ios/flavors/<flavor>/GoogleService-Info.plist` under `apps/mobile/` | `fastlane.yml`, iOS builds — optional (warning if unset) | `base64 -w0 apps/mobile/ios/flavors/dev/GoogleService-Info.plist` |
| `ENV_PROD_B64` | `apps/mobile/env.prod` | both — **prod** builds (`env.dev` / `env.stg` are committed) | `base64 -w0 apps/mobile/env.prod`. Replaces the former `ENV` secret, which was decoded to a root `.env` for every flavor |
| `KEYSTORE_BASE64` | `apps/mobile/android/keystore.jks` | both — **prod** Android builds | `base64 -w0 upload-keystore.jks` |
| `KEYSTORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS` | `apps/mobile/android/key.properties` (*raw*) | both — **prod** Android builds | Keystore password, key password, key alias |
| `FASTLANE_CONFIG_YAML_B64` | `apps/mobile/fastlane/Config.yaml` | `fastlane.yml` — always | `base64 -w0 apps/mobile/fastlane/Config.yaml` |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | *raw* JSON. `flutter_build.yml` passes it to the upload action; `fastlane.yml` writes it to `firebase.credentials_map.<flavor>` from `Config.yaml` | both — Firebase distribution | Contents of the Firebase service-account JSON |
| `GOOGLE_PLAY_JSON_KEY_B64` | `paths.google_play_key_prod` from `Config.yaml` | `fastlane.yml` — `distribute_store` + Android | `base64 -w0 google-play-store.json` |
| `APP_STORE_CONNECT_API_KEY_P8_B64` | `paths.app_store_connect_key_filepath` from `Config.yaml` | `fastlane.yml` — `distribute_store` + iOS | `base64 -w0 AuthKey_XXXX.p8` |
| `FIREBASE_ANDROID_APP_ID` | — | `flutter_build.yml` | Firebase App ID, e.g. `1:1234567890:android:abcdef` |
| `GEMINI_API_KEY` | — | `code_review.yml` | Create at <https://aistudio.google.com/app/apikey> |
| `GITHUB_TOKEN` | — | `code_review.yml` | Provided automatically by GitHub — do not create it |

Add them under **Settings → Secrets and variables → Actions → New repository secret**.

The prod keystore secrets are **required** for prod: without `key.properties`, Gradle would silently sign prod with the committed dev keystore ([`02_fastlane_release.md` §4](02_fastlane_release.md#4-signing)), so the workflow refuses to build instead. Relative paths in `Config.yaml` are resolved against `apps/mobile/`, exactly as the lanes resolve them.

> [!CAUTION]
> `base64` without `-w0` inserts line breaks on Linux, which breaks `base64 -d` in the workflow. On macOS, plain `base64 -i <file>` produces a single line already. Always verify with `base64 -d` locally before pasting.

### Azure DevOps

Azure uses the **Secure files** library rather than secrets: upload these under **Pipelines → Library → Secure files**, with exactly these names:

| Secure file | Copied to |
|:---|:---|
| `env.prod` | `apps/mobile/env.prod` |
| `firebase_options_prod.dart` | `firebase_options_prod.dart` in `apps/mobile/lib/firebase/` |
| `google-services.prod.json` | `apps/mobile/android/app/src/<flavor>/google-services.json`, flavor `prod` |
| `key.properties` | `apps/mobile/android/key.properties` — with `storeFile=../keystore.jks` |
| `keystore.jks` | `apps/mobile/android/keystore.jks` |

`FIREBASE-ANDROID-ID` is a pipeline variable.

---

## 8. Reproducing CI locally

Run these before pushing; they are the same commands the pipelines use.

```bash
# 1. Full workspace setup — same as the CI "Install Dependencies" step
#    (release pipelines first run `flutter pub get --enforce-lockfile`)
dart tools/workspace_setup/configure.dart

# 2. The same gates pr_quality_check.yml runs, in the same order
dart tools/composer/composer.dart verify
dart tools/arch_check/check.dart
flutter analyze
dart tools/dependency_sync.dart --check
dart tools/docs_check/check.dart

# 3. Tests, per package (gate 3 — see §6)
(cd platform/storage && flutter test)
(cd platform/database && flutter test)
# ...repeat for any package with a test/ directory

# 4. The exact release build CI performs — note the cd
cd apps/mobile
flutter build apk --flavor=dev --build-name=1.0.0 --build-number=1 \
  --dart-define-from-file=env.dev --obfuscate --split-debug-info=../../obfuscate/ \
  --no-tree-shake-icons
```

> [!NOTE]
> Locally the dart-define path is `env.dev` (relative to `apps/mobile/`). CI uses the same files — `apps/mobile/env.<dev|stg|prod>` — but addresses them absolutely, through `$GITHUB_WORKSPACE` on GitHub and `$(Build.SourcesDirectory)` on Azure, because counting `../` from the app broke the moment the app moved one directory deeper.

A first build on a clean machine also needs `flutterfire configure` to have been run — the generated `firebase_options_*.dart` files and `google-services.json` are gitignored and `apps/mobile/lib/firebase/firebase_module.dart` imports all three options files unconditionally. (`pr_quality_check.yml` stubs the options for every app that has a `lib/firebase/firebase_module.dart`, which is enough for analysis and tests but not for a real build; the release pipelines restore the real ones from secrets — [§7](#7-secrets).) See [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 9. Fix checklist

Open items, in rough priority order:

- [ ] `flutter_build.yml` — run the six `pr_quality_check.yml` gates before building, so a manual dispatch cannot ship unverified code
- [ ] `code_review.yml` — decide whether to uncomment `exit 1` (only after you trust the reviewer's false-positive rate)
- [ ] `flutter_build.yml` — consider `ubuntu-latest` instead of `macos-latest` for Android-only builds
- [ ] `flutter_build.yml` — make `FIREBASE_ANDROID_APP_ID` per flavor ([§2](#2-flutter_buildyml--build-and-distribute))
- [ ] `fastlane.yml` — set up iOS code signing (e.g. `match`) if iOS is to build on GitHub-hosted runners

---

## See also

- [`02_fastlane_release.md`](02_fastlane_release.md) — lanes, signing and the release process
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — first run, Firebase bootstrap, flavors
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — every script under `tools/`
