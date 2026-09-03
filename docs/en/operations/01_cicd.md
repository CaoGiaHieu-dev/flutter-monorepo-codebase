# CI/CD

This page answers: **what pipelines exist, what each one does, which secrets they need, and what is currently broken in them.** After reading it you can configure the repository secrets, trigger a build, and reproduce every CI step locally before you push.

> [!IMPORTANT]
> Several pipelines in this repository are **currently broken**. They are documented here as they actually are, with the fix for each. Do not assume a green checkmark exists until you have run them.

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

`pr_quality_check.yml` is the only pipeline that gates a merge. It runs four blocking gates in order — architecture rules, `flutter analyze`, per-package tests, dependency-catalog drift — plus one advisory audit. See [§6](#6-the-quality-gate).

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
2. **Set Up Java** — Oracle distribution, **Java 17**. Matches `sourceCompatibility`/`targetCompatibility` in `app/android/app/build.gradle.kts`.
3. **Set Up Flutter** — `subosito/flutter-action@v2`, pinned to **`3.47.2`**, channel `stable`, with cache enabled.
4. **Install Dependencies** — `dart tools/workspace_setup/configure.dart`. This single Dart script does pub get, l10n generation and `build_runner` for the whole workspace.
5. **Decode Env** — `echo -n ${{ secrets.ENV }} | base64 -d > .env` (written to the **repo root**).
6. **Decode Keystore** — `secrets.KEYSTORE_BASE64` → `app/android/keystore.jks`.
7. **Create key.properties** — writes `storePassword`, `keyPassword`, `keyAlias` and a fixed `storeFile=../keystore.jks` into `app/android/key.properties`.
8. **Build APK** — note the `cd app` on its own line first:
   ```bash
   cd app
   flutter build apk --flavor=$FLAVOR --build-name=$VERSION --build-number=$RUN_NUMBER \
     --dart-define-from-file=../.env --obfuscate --split-debug-info=../obfuscate/ \
     --no-tree-shake-icons --verbose
   ```
9. **Upload and Distribute** — `nickwph/firebase-app-distribution-action@v1`, uploading `app/build/app/outputs/flutter-apk/app-<flavor>-release.apk`.

> [!NOTE]
> **The `cd app` is not optional.** `flutter build apk` run from the repository root fails with a confusing `android/app/build.gradle not found`, because the Flutter project lives in `app/`, not at the workspace root. The same applies when you build locally — see [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

The artifact name interpolates the flavor (`app-${{ inputs.flavor }}-release.apk`), so it stays correct for all three flavors. That is the right pattern; Azure does **not** do this — see [§5](#5-azure-ci-cdyml--azure-devops).

### Cost note

The job runs on `macos-latest` even though it only builds Android. macOS runners are billed at a much higher multiplier than Linux on GitHub-hosted plans. Unless you intend to add the (currently commented-out) iOS build back into this same job, `ubuntu-latest` builds Android just as well and far cheaper.

---

## 3. `code_review.yml` — AI Code Review

Runs the repo's own Gemini-powered reviewer (`tools/code_review/code_review.dart`) and posts results back to the pull request.

**Triggers**: pull requests to `main` / `develop` / `master` touching `app/lib/**/*.dart` or `packages/**/*.dart` (generated files excluded), plus manual dispatch with a scope selector (`changed` / `all` / `domain` / `data` / `presentation`) and a report language (`en` / `vi` / `ja` / `ko` / `zh`).

**What it does**: resolves changed files with `tj-actions/changed-files`, runs the reviewer, uploads the Markdown report as an artifact (30-day retention), then parses that report and posts **inline review comments** on the exact lines when they fall inside the PR diff. Findings outside the diff are grouped into a separate per-file comment.

### One remaining quirk

Dependency installation runs `dart tools/workspace_setup/configure.dart`, and `flutter_version` defaults to `3.47.2`, matching the root `pubspec.yaml` constraint.

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

Manual dispatch that hands the whole build over to Fastlane. Sets up Java 17, Ruby 3.3 (skipped on `self-hosted`), Flutter (channel `stable`, **no pinned version**), installs Fastlane and the `firebase_app_distribution` plugin, then invokes a lane.

It invokes the real cross-platform lane, `fastlane flutter` (declared in `app/fastlane/modules/flutter_lanes.rb` as `lane :flutter do |options|`), and `flutter_version` defaults to `3.47.2`.

> [!WARNING]
> The invocation still passes `auto_increment:` (`fastlane.yml:99`), and **no lane reads it** — `grep -rn auto_increment app/fastlane/` returns nothing. Auto-increment is triggered by passing `build_number:auto` instead; see [`02_fastlane_release.md`](02_fastlane_release.md). The argument is silently ignored, so a dispatch relying on it gets whatever `build_number` was passed, not an incremented one.

Because the Flutter setup step passes only `channel: stable` without `flutter-version`, the `flutter_version` input never reaches the toolchain; it is forwarded to Fastlane, which uses it to decide whether to drive `fvm`.


---

## 5. `azure-ci-cd.yml` — Azure DevOps

Two stages on a self-hosted pool named `codebase`. `trigger: none`, so it only runs when started manually or by a release.

**Stage `Build`**: capture the short commit SHA into `commitTag` → install Flutter at `$(flutter-version)` → `flutter clean` → `flutter pub get` → "Flutter Config" → download `key.properties` and `keystore.jks` as Azure *secure files* into `app/android/` → build the prod APK → publish it as artifact `android`.

**Stage `Distribute`**: download the artifact, then `firebase appdistribution:distribute` it.

Pipeline variables must be defined in the Azure Variables tab: `flutter-version`, `flutterPath`, `version`, `numberBuild`, `note`, and `FIREBASE-ANDROID-ID`.

### One remaining defect

The artefact filename and the `configure.dart` call are both correct now: the build publishes `app-prod-release.apk` and the Distribute stage downloads and uploads that same name, and "Flutter Config" runs `dart tools/workspace_setup/configure.dart`.

> [!WARNING]
> **`.env` is never created, but the build requires it.**
>
> The build passes `--dart-define-from-file=../.env` (`azure-ci-cd.yml:104`), yet no step in the pipeline produces `.env`. The two `DownloadSecureFile@1` tasks fetch only `key.properties` and `keystore.jks`. Add a third secure file for `.env` and copy it to `$(Build.SourcesDirectory)`, mirroring what `flutter_build.yml` does with `secrets.ENV`. Without it every `String.fromEnvironment` falls back to its empty default.

The iOS build and iOS distribute tasks are present but fully commented out.

---

## 6. The quality gate

`pr_quality_check.yml` runs on every pull request to `main`, `develop` or `master`. It is the only pipeline that can block a merge.

| # | Gate | Command | Blocking |
|:--|:---|:---|:---|
| 1 | Architecture rules | `dart tools/arch_check/check.dart` | yes |
| 2 | Static analysis | `flutter analyze` | yes |
| 3 | Tests, per package | `flutter test` in each `packages/*/*/test` | yes |
| 4 | Catalog drift | `dart tools/dependency_sync.dart --check` | yes |
| — | Unused dependency audit | `dart tools/unused_checker/check_unused_packages.dart` | no (advisory) |

Gate 1 runs first on purpose: it only reads imports and pubspecs, needs no codegen, and finishes in about 200 ms — so a layering mistake fails in seconds instead of after a full analyze-and-test cycle. It is also the only gate that can see layering at all; nothing in `analysis_options.yaml` knows that core must not import a feature.

Gate 3 loops per package because this is a Pub Workspace: tests live under `packages/<layer>/<pkg>/test/`, and a single `flutter test` at the root does not pick them up.

> [!IMPORTANT]
> A clean `flutter analyze` does **not** prove the app builds. `analysis_options.yaml` excludes `**.freezed.dart`, `**.g.dart`, `**.config.dart` and `**.module.dart`, so the analyser never looks at generated code. This has bitten the template before: moving `AppFailure` between packages left `bloc_view_state.freezed.dart` referencing a type it could no longer see, and analyze stayed green while the APK build failed. Only a real build catches that class of error.

**Still missing:** the release pipelines (`flutter_build.yml`, `fastlane.yml`, `azure-ci-cd.yml`) are all `workflow_dispatch` and run **no** gates of their own. A manual dispatch from a branch that never opened a PR will build, sign and distribute unverified code. If that matters to you, add gates 1–4 to `flutter_build.yml` between "Install Dependencies" and "Build APK", or require that releases only ever be cut from a merged branch.

---

## 7. Secrets

### GitHub Actions

| Secret | Used by | How to produce it |
|:---|:---|:---|
| `ENV` | `flutter_build.yml` | Base64 of the dart-define env file: `base64 -w0 app/env.prod` (macOS: `base64 -i app/env.prod`) |
| `KEYSTORE_BASE64` | `flutter_build.yml` | Base64 of your release keystore: `base64 -w0 upload-keystore.jks` |
| `KEYSTORE_PASSWORD` | `flutter_build.yml` | Keystore password |
| `KEY_PASSWORD` | `flutter_build.yml` | Key password |
| `KEY_ALIAS` | `flutter_build.yml` | Key alias |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | `flutter_build.yml` | Contents of the Firebase service-account JSON |
| `FIREBASE_ANDROID_APP_ID` | `flutter_build.yml` | Firebase App ID, e.g. `1:1234567890:android:abcdef` |
| `GEMINI_API_KEY` | `code_review.yml` | Create at <https://aistudio.google.com/app/apikey> |
| `GITHUB_TOKEN` | `code_review.yml` | Provided automatically by GitHub — do not create it |

Add them under **Settings → Secrets and variables → Actions → New repository secret**.

> [!CAUTION]
> `base64` without `-w0` inserts line breaks on Linux, which breaks `base64 -d` in the workflow. On macOS, plain `base64 -i <file>` produces a single line already. Always verify with `base64 -d` locally before pasting.

### Azure DevOps

Azure uses the **Secure files** library rather than secrets for binaries: upload `key.properties`, `keystore.jks` and (once you add the missing step) `.env` under **Pipelines → Library → Secure files**. `FIREBASE-ANDROID-ID` is a pipeline variable.

---

## 8. Reproducing CI locally

Run these before pushing; they are the same commands the pipelines use.

```bash
# 1. Full workspace setup — same as the CI "Install Dependencies" step
dart tools/workspace_setup/configure.dart

# 2. The same gates pr_quality_check.yml runs, in the same order
dart tools/arch_check/check.dart
flutter analyze
dart tools/dependency_sync.dart --check

# 3. Tests, per package (gate 3 — see §6)
(cd packages/core/storage && flutter test)
(cd packages/core/database && flutter test)
# ...repeat for any package with a test/ directory

# 4. The exact release build CI performs — note the cd
cd app
flutter build apk --flavor=dev --build-name=1.0.0 --build-number=1 \
  --dart-define-from-file=env.dev --obfuscate --split-debug-info=../obfuscate/ \
  --no-tree-shake-icons
```

> [!NOTE]
> Locally the dart-define path is `env.dev` (relative to `app/`), while CI writes its env file to the repo root and therefore passes `../.env`. Same mechanism, different location.

A first build on a clean machine also needs `flutterfire configure` to have been run — the generated `firebase_options_*.dart` files are gitignored and `packages/core/common/lib/src/firebase/firebase_module.dart` imports all three unconditionally. See [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 9. Fix checklist

Already fixed in this template:

- [x] `code_review.yml` — uses `dart tools/workspace_setup/configure.dart`; default `flutter_version` is `3.47.2`
- [x] `fastlane.yml` — calls the real `flutter` lane; default `flutter_version` is `3.47.2`
- [x] `azure-ci-cd.yml` — distributes `app-prod-release.apk`; "Flutter Config" runs `configure.dart`
- [x] `pr_quality_check.yml` — exists and gates every PR (arch rules, analyze, tests, catalog drift)

Still open, in rough priority order:

- [ ] `azure-ci-cd.yml` — add a secure file + copy step for `.env`; the prod build currently gets no dart-defines
- [ ] `fastlane.yml` — drop the ignored `auto_increment:` argument, or make a lane read it
- [ ] `flutter_build.yml` — run the four `pr_quality_check.yml` gates before building, so a manual dispatch cannot ship unverified code
- [ ] `code_review.yml` — decide whether to uncomment `exit 1` (only after you trust the reviewer's false-positive rate)
- [ ] `flutter_build.yml` — consider `ubuntu-latest` instead of `macos-latest` for Android-only builds

---

## See also

- [`02_fastlane_release.md`](02_fastlane_release.md) — lanes, signing and the release process
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — first run, Firebase bootstrap, flavors
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — every script under `tools/`
