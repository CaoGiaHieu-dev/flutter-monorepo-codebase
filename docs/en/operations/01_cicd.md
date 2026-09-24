# CI/CD

This page answers: **what pipelines exist, what each one does, which secrets they need, and what is currently broken in them.** After reading it you can configure the repository secrets, trigger a build, and reproduce every CI step locally before you push.

> [!IMPORTANT]
> The release pipelines depend on **repository secrets** for every gitignored input — Firebase options, `google-services.json`, `env.prod`, the release keystore, fastlane's `Config.yaml` ([§7](#7-secrets)). Without them they stop at their first step, naming the missing secret. Do not assume a green checkmark exists until you have configured them and run the pipeline once.

---

## 1. Pipeline inventory

Five pipelines ship with the template — four on GitHub Actions, one on Azure DevOps.

| Pipeline | File | Trigger | Output |
|:---|:---|:---|:---|
| Build and Distribute | `.github/workflows/flutter_build.yml` | Manual (`workflow_dispatch`) | Signed release APK → Firebase App Distribution, plus its obfuscation symbols as an artifact |
| AI Code Review | `.github/workflows/code_review.yml` | PR to `main`/`develop`/`master` + manual | Markdown report artifact + PR comments |
| Fastlane build and distribute | `.github/workflows/fastlane.yml` | Manual (`workflow_dispatch`) | Delegates to Fastlane lanes |
| **PR Quality Check** | `.github/workflows/pr_quality_check.yml` | **PR to `main`/`develop`/`master`** + manual | Pass/fail — blocks the merge; then a debug dev APK build and a module-generator smoke test |
| Azure Build + Distribute | `azure-ci-cd.yml` | `trigger: none` (manual only) | Prod APK + obfuscation symbols artifacts → Firebase |

`pr_quality_check.yml` is the only pipeline that gates a merge. It runs six blocking gates in order — composition drift, architecture rules, `flutter analyze`, per-package tests, dependency-catalog drift, documentation accuracy — plus one advisory audit, with the gate tools' own test suite run right after Gate 1 — and then, in two more jobs, builds the app (a debug `dev` APK), which no gate can prove, and smoke-tests the module generator. See [§6](#6-the-quality-gate).

---

## 2. `flutter_build.yml` — Build and Distribute

The main Android release pipeline. It is manual-only: **Actions → Build and Distribute → Run workflow**.

### Inputs

| Input | Required | Default | Notes |
|:---|:---|:---|:---|
| `flavor` | yes | `prod` | `dev` / `staging` / `prod` |
| `version` | yes | `1.0.0` | Becomes `--build-name` |
| `notes` | no | — | Appended to the Firebase release notes |
| `groups` | no | `test` | Firebase App Distribution tester group aliases, comma-separated, passed as `--groups`. Each alias must exist in the Firebase console; empty = upload the release without inviting anyone |

The build number is not an input — it uses `${{ github.run_number }}`, so it increments automatically per workflow run.

### Steps, in order

1. **Checkout** — `actions/checkout@v7`.
2. **Set Up Java** — Oracle distribution, **Java 17**. Matches `sourceCompatibility`/`targetCompatibility` in `apps/mobile/android/app/build.gradle.kts`.
3. **Set Up Flutter** — `subosito/flutter-action@v2` with `flutter-version-file: .fvmrc`, so the version is the one `.fvmrc` pins (**`3.47.4`** today) — the same single source `pr_quality_check.yml` and `code_review.yml` read. Channel `stable`, cache enabled.
4. **Restore gitignored build inputs from secrets** — for the chosen flavor only, each from a base64 secret ([§7](#7-secrets)):
   - `firebase_options_<flavor>.dart` in `apps/mobile/lib/firebase/`; the two other flavors get a compile-only stub, because `firebase_module.dart` imports all three and injectable registers only the built flavor's options;
   - `apps/mobile/android/app/src/<flavor>/google-services.json` — the `com.google.gms.google-services` Gradle plugin fails the build without it;
   - `apps/mobile/env.prod` (prod only — `env.dev` / `env.stg` are committed);
   - prod only: `apps/mobile/android/keystore.jks` + `key.properties` (`storeFile=../keystore.jks`). dev and staging are signed with the committed dev keystore.

   A missing secret fails this step with an error naming it — before any codegen or Gradle time is spent. It runs **before** code generation because `build_runner` must be able to resolve `firebase_module.dart`'s imports.
5. **Get dependencies from the committed lockfile** — `flutter pub get --enforce-lockfile`. The workspace `pubspec.lock` is committed; a lockfile that no longer matches the pubspecs fails here instead of being silently re-resolved.
6. **Install Dependencies** — `dart tools/workspace_setup/configure.dart`. This single Dart script does pub get, l10n generation, `build_runner` and the barrel pass for the whole workspace.
7. **Build APK** — note the `cd apps/mobile` on its own line first:
   ```bash
   cd apps/mobile
   flutter build apk --flavor="$FLAVOR" --build-name="$VERSION" --build-number="$GITHUB_RUN_NUMBER" \
     --dart-define-from-file="$GITHUB_WORKSPACE/apps/mobile/$ENV_FILE" \
     --obfuscate --split-debug-info="$GITHUB_WORKSPACE/obfuscate/" \
     --no-tree-shake-icons --verbose
   ```
   `ENV_FILE` is `env.dev` / `env.stg` / `env.prod`, set by step 4 — the same flavor-to-file mapping Fastlane uses.
8. **Upload obfuscation symbols** — `--obfuscate` makes every stack trace from the build unreadable without the symbol files `--split-debug-info` wrote to `obfuscate/`, and they are not inside the APK. They are uploaded as the artifact `debug-symbols-<flavor>-<version>+<run>` (90-day retention), **before** distribution so a failed upload cannot lose them. Read a crash with `flutter symbolize -i <stack-trace-file> -d <artifact>/app.android-arm64.symbols`.
9. **Distribute** — the Firebase CLI itself: Node 22 (`actions/setup-node@v6`), `npm install --global firebase-tools@15`, then `firebase appdistribution:distribute apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk --app <FIREBASE_ANDROID_APP_ID> --release-notes-file … --groups <groups>`. It authenticates through `GOOGLE_APPLICATION_CREDENTIALS`, pointing at the `FIREBASE_SERVICE_ACCOUNT_KEY` JSON written to a `umask 077` temp file that is deleted when the step ends. The release notes (`Build version`, `Flavor`, `Notes`) go through a file and every input through `env:`, so quotes or `$(…)` in `notes` are passed verbatim. A missing secret fails the step by name. (This replaced the third-party `nickwph/firebase-app-distribution-action@v1`; the secret names did not change.)

> [!NOTE]
> **The `cd apps/mobile` is not optional.** `flutter build apk` run from the repository root fails with a confusing `android/app/build.gradle not found`, because the Flutter project lives in `apps/mobile/`, not at the workspace root. The same applies when you build locally — see [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

The artifact path is built from the flavor (`app-$FLAVOR-release.apk`), so it stays correct for all three flavors. That is the right pattern; Azure does **not** do this — see [§5](#5-azure-ci-cdyml--azure-devops).

> [!WARNING]
> The Firebase App ID is **not** per flavor: every flavor uploads to `secrets.FIREBASE_ANDROID_APP_ID`. The flavors have different application IDs (`.dev`, `.stg`), so each is a different Firebase app — set the secret to the app of the flavor you dispatch, or split it per flavor.

### Cost note

The job runs on `macos-latest` even though it only builds Android. macOS runners are billed at a much higher multiplier than Linux on GitHub-hosted plans. Unless you intend to add the (currently commented-out) iOS build back into this same job, `ubuntu-latest` builds Android just as well and far cheaper.

---

## 3. `code_review.yml` — AI Code Review

Runs the repo's own Gemini-powered reviewer (`tools/code_review/code_review.dart`) and posts results back to the pull request.

**Triggers**: pull requests to `main` / `develop` / `master` touching `apps/*/lib/**/*.dart`, `modules/**/*.dart` or `platform/**/*.dart` (generated files excluded), plus manual dispatch with a scope selector (`changed` / `all` / `domain` / `data` / `platform` / `presentation`) and a report language (`en` / `vi` / `ja` / `ko` / `zh`).

**What it does**: resolves changed files with `tj-actions/changed-files` (pinned to a commit SHA — its tags were rewritten in the March 2025 supply-chain compromise), runs the reviewer, uploads the Markdown report as an artifact (30-day retention), then parses that report and posts **inline review comments** on the exact lines when they fall inside the PR diff. Findings outside the diff are grouped into a separate per-file comment.

**Permissions**: the workflow declares `contents: read`, `pull-requests: write` (the review with inline comments) and `issues: write` (the per-file and "no issues" comments), so it works under a repository whose default `GITHUB_TOKEN` is read-only. The changed-file list reaches the review script through `env:` — one file per line, never interpolated into the script — and the PR's file list is read with `github.paginate`, so a PR touching more than 30 files still gets inline comments on all of them.

**Manual `changed` scope**: diffs the checked-out branch against its merge-base with the repository's default branch (fetched explicitly; the checkout has full history), keeps the Dart files under an app's `lib/` or `test/`, `modules/` and `platform/`, minus generated ones, and reviews them with `--file`. It does **not** use the tool's own `--changed`, which means `git diff HEAD` — uncommitted changes — and is always empty on a fresh checkout. Dispatched on the default branch itself, it finds nothing and says so.

### Flutter version pinning

Dependency installation runs `dart tools/workspace_setup/configure.dart`. Flutter comes from `.fvmrc` (`flutter-version-file`) on every run — pull requests included — unless a manual run fills in the optional `flutter_version` input. (Before, `flutter_version` was bound only on `workflow_dispatch`, so every PR run installed whatever stable was newest.)

### The "Fail on Critical Issues" step does not fail

The final step counts the files the report marks HIGH priority — the one `**<Priority label>:** 🔴 HIGH` line each file section carries (written by `tools/code_review/lib/services/report_service.dart`; the label is translated, the value is not). It used to count every 🔴 in the report, which always included the legend row `| 🔴 **High** | … |`, so the count was never zero. Then it deliberately does nothing with the count:

```bash
if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "::error::$CRITICAL_COUNT file(s) with HIGH-priority findings in the code review"
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
| `track` | `internal` | Play track, used only with `distribute_store`: `internal`, `alpha` (closed testing), `beta` (open testing) or `production` — the Play Console's built-in tracks. A custom closed-testing track is addressed by its own name: add it to the input's `options` list |
| `distribute_firebase` | `true` | Firebase App Distribution |

### Steps

1. **Checkout**, **Java 17**.
2. **Ruby 3.3 + `bundle install`** at the repository root (`ruby/setup-ruby` with `bundler-cache` on GitHub-hosted runners, a plain `bundle install` on `self-hosted`). The root `Gemfile` lists `fastlane` and `cocoapods` and loads the plugins from `apps/mobile/fastlane/Pluginfile` through `fastlane/Pluginfile`, so there is no `fastlane add_plugin` step — that command is interactive and fails on a runner.
3. **Flutter** at `flutter_version`.
4. **Restore gitignored build inputs from secrets** — `apps/mobile/fastlane/Config.yaml`, the flavor's Firebase options (other flavors stubbed), `google-services.json` (Android), `GoogleService-Info.plist` (iOS, optional), `env.prod` and the release keystore (prod), and the credential files `Config.yaml` points at — only those the chosen distribution needs. The Firebase service account goes to `firebase.credentials_map.<flavor>`, or `.default` when the flavor has no entry — the same fallback the lanes use. The App Store Connect key is written only if `paths.app_store_connect_key_filepath` ends in `AuthKey_<app_store_connect.api_key_id>.p8`, the one name `xcrun altool` finds it by ([`02_fastlane_release.md` §2](02_fastlane_release.md#2-configuration)). Every missing secret is reported by name, then the step fails.
5. **Build and distribute** — `bundle exec fastlane <lane> …`. Inputs reach the script through `env:`, never interpolated into it, so a change log containing quotes or `$(…)` is passed verbatim. The lane does its own toolchain setup: `flutter pub get --enforce-lockfile`, `gen-l10n`, `build_runner`, then the barrel pass (`tools/barrel_generator/generate.dart` per package) — the `lib/src/gen/gen.dart` barrels are gitignored, so a clean runner compiles nothing without it.
6. **Upload obfuscation symbols** — the lanes build with `--split-debug-info=apps/mobile/obfuscate`; that directory is uploaded as the artifact `debug-symbols-<platform>-<flavor>-<version>+<run>` (90 days), even when distribution failed after the build.

> [!NOTE]
> iOS **code signing** (certificates, provisioning profiles) is not set up by any workflow. `platform: both` / `ios` needs a runner whose keychain already has them — in practice a `self-hosted` Mac.


---

## 5. `azure-ci-cd.yml` — Azure DevOps

Two stages on a self-hosted pool named `codebase`. `trigger: none`, so it only runs when started manually or by a release.

**Stage `Build`**: capture the short commit SHA into `commitTag` → download `env.prod`, `firebase_options_prod.dart` and `google-services.prod.json` as Azure *secure files* and copy them into place (dev/staging Firebase options get a compile-only stub) → install Flutter at `$(flutter-version)` → `flutter clean` → `flutter pub get --enforce-lockfile` → "Flutter Config" → download `key.properties` and `keystore.jks` as secure files into `apps/mobile/android/` → build the prod APK with `--dart-define-from-file=$(Build.SourcesDirectory)/apps/mobile/env.prod` → publish it as artifact `android`, and the obfuscation symbols (`obfuscate/`, which `flutter symbolize` needs to read the build's stack traces) as artifact `debug-symbols`.

**Stage `Distribute`**: download the artifact → `UseNode@1` (Node 22) → download the secure file `firebase-service-account.json` → `npx --yes firebase-tools@15 appdistribution:distribute app-prod-release.apk --app … --release-notes-file … --groups "test"`, with `GOOGLE_APPLICATION_CREDENTIALS` set to the secure file's path. Nothing is installed globally on the agent, and `$(note)` / `$(FIREBASE-ANDROID-ID)` reach the script through `env:`, not macro-expanded into it. `test` is the tester group alias: it must exist in Firebase App Distribution — edit the task to invite another group.

Pipeline variables must be defined in the Azure Variables tab: `flutter-version`, `flutterPath`, `version`, `numberBuild`, `note`, and `FIREBASE-ANDROID-ID`. The Firebase credential is a secure file, not a variable ([§7](#azure-devops)).

The artefact filename, the `configure.dart` call and the env file are consistent: the build publishes `app-prod-release.apk`, the Distribute stage downloads and uploads that same name, "Flutter Config" runs `dart tools/workspace_setup/configure.dart`, and the dart-define file is `apps/mobile/env.prod` — the same file Fastlane and `flutter_build.yml` use for prod. A secure file missing from the library fails its `DownloadSecureFile@1` task, before anything is built.

The pipeline builds **prod only** (`--flavor=prod`, `app-prod-release.apk`).

The iOS build and iOS distribute tasks are present but fully commented out.

---

## 6. The quality gate

`pr_quality_check.yml` runs on every pull request to `main`, `develop` or `master`. It is the only pipeline that can block a merge.

Job `quality`, step by step: checkout → Flutter from `.fvmrc` → **`flutter pub get --enforce-lockfile`** → Gate 0 → Gate 1 → the gate tools' tests (`cd tools && dart test`) → stub the Firebase options → `dart tools/workspace_setup/configure.dart` (clean, pub get, gen-l10n, `build_runner`, barrels) → Gates 2–5 → the advisory audit. The `--enforce-lockfile` step is what holds a PR to the committed `pubspec.lock`: it fails when the lockfile no longer matches the pubspecs, where the plain `flutter pub get` inside `configure.dart` would silently re-resolve it.

| # | Gate | Command | Blocking |
|:--|:---|:---|:---|
| 0 | Composition matches every app's manifest | `dart tools/composer/composer.dart verify` | yes |
| 1 | Architecture rules | `dart tools/arch_check/check.dart` | yes |
| 1 | …and the gate tools' own tests | `cd tools && dart test` | yes |
| 2 | Static analysis | `flutter analyze` | yes |
| 3 | Tests, per package | `flutter test` in every package that has a `test/` directory, except `tools/` | yes |
| 4 | Catalog drift | `dart tools/dependency_sync.dart --check` | yes |
| 5 | Documentation accuracy | `dart tools/docs_check/check.dart` | yes |
| — | Unused dependency audit | `dart tools/unused_checker/check_unused_packages.dart` | no (advisory) |

Gates 0 and 1 run first on purpose: they only read manifests, imports and pubspecs and need no codegen — `pub get` is enough, since `tools/` is a workspace member — and each finishes in a second or two, so a composition or layering mistake fails right after dependency resolution instead of after the full setup, analyze and test cycle. Gate 1 is also the only gate that can see layering at all; nothing in `analysis_options.yaml` knows that core must not import a feature.

Every gate is a script under `tools/`, and a gate that has quietly stopped failing looks exactly like a clean PR. So the gates have tests of their own, in `tools/test/`, run as the second half of Gate 1: each test builds a throwaway workspace in a temp directory, runs the tool against it as a subprocess (compiled to kernel once per file, so the suite takes about 15 seconds) and asserts the exit code and output. They cover `arch_check` (a clean and a violating fixture for every rule R1–R10; R6 must warn and still exit 0), `composer verify` (a synced manifest passes; `phase: befor`, an unknown layer, a duplicate module and a module missing from disk are refused with their key path), `dependency_sync --check` (a mismatch and a malformed catalog exit 1), `docs_check` (a dead reference exits 1, a `<placeholder>` span and a removed sample bundle do not, the root comes from the script's location), the barrel generator (a trailing slash, a `web/` directory inside `lib/`) and composer `bootstrap --dry-run` (a missing member is reported and nothing written). Change a gate, add a case there. Like Gates 0 and 1 they need no codegen, which is why they run before the setup rather than in Gate 3.

Gate 3 loops per package because this is a Pub Workspace: tests live in each package's own `test/` — today under `platform/*/test/` and `modules/*/*/test/`, nineteen packages — and a single `flutter test` at the root does not pick them up. It skips `tools/`, whose tests already ran.

> [!IMPORTANT]
> A clean `flutter analyze` does **not** prove the app builds. `analysis_options.yaml` excludes `**.freezed.dart`, `**.g.dart`, `**.config.dart` and `**.module.dart`, so the analyser never looks at generated code. Move a type between packages and a `.freezed.dart` file can end up referencing a symbol it cannot see: analyze stays green while the APK build fails. Only a real build catches that class of error.

That is what the second job, **`build`**, is for. It is not a numbered gate — it `needs: quality`, so it starts only once every gate has passed and a layering or analyze failure never pays for a Gradle build — but it is part of the same required check run, and a red build fails the workflow. It sets up **Java 17** (AGP 9 / Gradle 9 need 17+, and 17 matches the app's `jvmTarget`), Flutter from `.fvmrc`, runs `flutter pub get --enforce-lockfile`, writes the compile-only Firebase stubs — the three options files plus the `dev` flavor's `apps/mobile/android/app/src/<flavor>/google-services.json`, the stub from [`../getting-started/01_setup.md` §3.2](../getting-started/01_setup.md#32-no-firebase-project-yet-use-stubs) — runs `configure.dart`, then, from `apps/mobile/`:

```bash
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

Debug needs no release keystore and `env.dev` is committed, so the job needs no secrets.

The third job, **`generator-smoke`**, also `needs: quality`. Nothing else exercises the module generator's templates — they are Mustache files no analyzer reads — so a template that emits an unused dependency, a layering violation or code that no longer analyzes would otherwise reach the next developer who runs it. The job does what that developer would: pub get, the Firebase options stubs, `configure.dart`, then

```bash
dart tools/module_generator/generate.dart 1 smoke "" 2 2   # BLoC feature, bottom-nav tab
```

— the widest template: routing, localization, DI and every `app_manifest.yaml` — and holds the result to the gates: `flutter analyze`, `arch_check`, `composer verify`, and `check_unused_packages`, which fails only when the unused dependency is in `feature_smoke` (anywhere else it stays the quality job's advisory, shown as a warning). Nothing is committed; the checkout is thrown away.

Make **all three** jobs required status checks in the branch protection rule.

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
| `FIREBASE_SERVICE_ACCOUNT_KEY` | *raw* JSON. `flutter_build.yml` writes it to a temp file for the Firebase CLI's `GOOGLE_APPLICATION_CREDENTIALS`; `fastlane.yml` writes it to `firebase.credentials_map.<flavor>` (else `.default`) from `Config.yaml` | both — Firebase distribution | Contents of the Firebase service-account JSON (a service account with the *Firebase App Distribution Admin* role) |
| `GOOGLE_PLAY_JSON_KEY_B64` | `paths.google_play_key_prod` from `Config.yaml` | `fastlane.yml` — `distribute_store` + Android | `base64 -w0 google-play-store.json` |
| `APP_STORE_CONNECT_API_KEY_P8_B64` | `paths.app_store_connect_key_filepath` from `Config.yaml` — which must end in `AuthKey_<api_key_id>.p8`, or the step fails | `fastlane.yml` — `distribute_store` + iOS | `base64 -w0 AuthKey_XXXX.p8` |
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
| `firebase-service-account.json` | Not copied: the Distribute stage points `GOOGLE_APPLICATION_CREDENTIALS` at it for the Firebase CLI. The same service-account JSON as GitHub's `FIREBASE_SERVICE_ACCOUNT_KEY` |

`FIREBASE-ANDROID-ID` is a pipeline variable.

---

## 8. Reproducing CI locally

Run these before pushing; they are the same commands the pipelines use.

```bash
# 1. The committed lockfile, then Gates 0 and 1 — exactly the start of
#    pr_quality_check.yml; neither gate needs codegen
flutter pub get --enforce-lockfile
dart tools/composer/composer.dart verify
dart tools/arch_check/check.dart
(cd tools && dart test)                # the gate tools' own tests

# 2. Full workspace setup — the CI "Install dependencies and run code
#    generation" step — then the remaining gates, in the same order
dart tools/workspace_setup/configure.dart
flutter analyze
dart tools/dependency_sync.dart --check
dart tools/docs_check/check.dart

# 3. Tests, per package (gate 3 — see §6)
(cd platform/storage && flutter test)
(cd platform/database && flutter test)
# ...repeat for any package with a test/ directory

# 4. The generator-smoke job — in a scratch clone, not your working tree:
#    it registers `smoke` in every manifest and rewrites the lockfile
#    dart tools/module_generator/generate.dart 1 smoke "" 2 2
#    flutter analyze && dart tools/arch_check/check.dart && dart tools/composer/composer.dart verify

# 5. The build job of pr_quality_check.yml (needs the Firebase stubs or real
#    files — see below) — note the cd
(cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev)

# 6. The exact release build CI performs — note the cd
cd apps/mobile
flutter build apk --flavor=dev --build-name=1.0.0 --build-number=1 \
  --dart-define-from-file=env.dev --obfuscate --split-debug-info=../../obfuscate/ \
  --no-tree-shake-icons
```

> [!NOTE]
> Locally the dart-define path is `env.dev` (relative to `apps/mobile/`). CI uses the same files — `apps/mobile/env.<dev|stg|prod>` — but addresses them absolutely, through `$GITHUB_WORKSPACE` on GitHub and `$(Build.SourcesDirectory)` on Azure, because counting `../` from the app broke the moment the app moved one directory deeper.

A first build on a clean machine also needs `flutterfire configure` to have been run — the generated `firebase_options_*.dart` files and `google-services.json` are gitignored and `apps/mobile/lib/firebase/firebase_module.dart` imports all three options files unconditionally. (`pr_quality_check.yml`'s `quality` job stubs the options for every app that has a `lib/firebase/firebase_module.dart`, which is enough for analysis and tests; its `build` job also stubs the `dev` `google-services.json`, which is enough for a debug build but not for a working Firebase; the release pipelines restore the real ones from secrets — [§7](#7-secrets).) See [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

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
