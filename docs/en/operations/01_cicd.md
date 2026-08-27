# CI/CD

This page answers: **what pipelines exist, what each one does, which secrets they need, and what is currently broken in them.** After reading it you can configure the repository secrets, trigger a build, and reproduce every CI step locally before you push.

> [!IMPORTANT]
> Several pipelines in this repository are **currently broken**. They are documented here as they actually are, with the fix for each. Do not assume a green checkmark exists until you have run them.

---

## 1. Pipeline inventory

Four pipelines ship with the template — three on GitHub Actions, one on Azure DevOps.

| Pipeline | File | Trigger | Output |
|:---|:---|:---|:---|
| Build and Distribute | `.github/workflows/flutter_build.yml` | Manual (`workflow_dispatch`) | Signed release APK → Firebase App Distribution |
| AI Code Review | `.github/workflows/code_review.yml` | PR to `main`/`develop`/`master` + manual | Markdown report artifact + PR comments |
| Fastlane build and distribute | `.github/workflows/fastlane.yml` | Manual (`workflow_dispatch`) | Delegates to Fastlane lanes |
| Azure Build + Distribute | `azure-ci-cd.yml` | `trigger: none` (manual only) | Prod APK artifact → Firebase |

> [!WARNING]
> `.github/workflows/README.md` documents a fourth GitHub workflow called `pr_quality_check.yml` that runs analyze, tests and coverage as a "quality gate". **That file does not exist.** Only `code_review.yml`, `fastlane.yml` and `flutter_build.yml` are present. There is no automated quality gate on pull requests today — see [§5](#5-missing-quality-gate).

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
3. **Set Up Flutter** — `subosito/flutter-action@v2`, pinned to **`3.47.1`**, channel `stable`, with cache enabled.
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

The artifact name interpolates the flavor (`app-${{ inputs.flavor }}-release.apk`), so it stays correct for all three flavors. That is the right pattern; Azure does **not** do this — see [§4](#4-azure-ci-cdyml).

### Cost note

The job runs on `macos-latest` even though it only builds Android. macOS runners are billed at a much higher multiplier than Linux on GitHub-hosted plans. Unless you intend to add the (currently commented-out) iOS build back into this same job, `ubuntu-latest` builds Android just as well and far cheaper.

---

## 3. `code_review.yml` — AI Code Review

Runs the repo's own Gemini-powered reviewer (`tools/code_review/code_review.dart`) and posts results back to the pull request.

**Triggers**: pull requests to `main` / `develop` / `master` touching `app/lib/**/*.dart` or `packages/**/*.dart` (generated files excluded), plus manual dispatch with a scope selector (`changed` / `all` / `domain` / `data` / `presentation`) and a report language (`en` / `vi` / `ja` / `ko` / `zh`).

**What it does**: resolves changed files with `tj-actions/changed-files`, runs the reviewer, uploads the Markdown report as an artifact (30-day retention), then parses that report and posts **inline review comments** on the exact lines when they fall inside the PR diff. Findings outside the diff are grouped into a separate per-file comment.

### Two defects that stop this workflow from running

> [!CAUTION]
> **This workflow fails at the "Get dependencies" step on every run.**
>
> ```yaml
> - name: 📦 Get dependencies
>   run: |
>       chmod +x tools/workspace_setup/configure.sh
>       ./tools/workspace_setup/configure.sh
> ```
>
> `tools/workspace_setup/configure.sh` **does not exist** — the directory contains only `configure.dart`. Replace both lines with:
>
> ```yaml
> - name: 📦 Get dependencies
>   run: dart tools/workspace_setup/configure.dart
> ```
>
> (`flutter_build.yml` has already been corrected this way; this workflow was missed.)

> [!WARNING]
> **The default Flutter version is too low.** `flutter_version` defaults to `"3.47.0"`, but the root `pubspec.yaml` requires `flutter: ">=3.47.1"`. A manual dispatch that accepts the default will fail during `pub get`. Change the default to `3.47.1`.
>
> Note also that this input is only bound on `workflow_dispatch`. On a `pull_request` event `github.event.inputs.flutter_version` is empty, so `subosito/flutter-action@v2` receives an empty `flutter-version` and resolves the latest stable instead.

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

> [!CAUTION]
> **This workflow invokes a lane that does not exist.**
>
> ```yaml
> run: |
>   fastlane flutter_build \
>     flutter_version:... version:... flavor:... \
>     auto_increment:... build_number:...
> ```
>
> There is no `flutter_build` lane. The real cross-platform lane is named **`flutter`** (declared in `app/fastlane/modules/flutter_lanes.rb` as `lane :flutter do |options|`). Fastlane will abort with *"Could not find lane 'flutter_build'"*.
>
> It also passes `auto_increment:`, which **no lane reads**. Auto-increment is triggered by passing `build_number:auto` instead — see [`02_fastlane_release.md`](02_fastlane_release.md#build-numbers).
>
> Corrected invocation:
> ```yaml
> run: |
>   fastlane flutter \
>     flutter_version:${{ inputs.flutter_version }} \
>     version:${{ inputs.version }} \
>     flavor:${{ inputs.flavor }} \
>     change_log:"${{ inputs.change_log }}" \
>     build_type:${{ inputs.build_type }} \
>     distribute_store:${{ inputs.distribute_store }} \
>     distribute_firebase:${{ inputs.distribute_firebase }} \
>     build_number:${{ inputs.build_number || 'auto' }}
> ```

The `flutter_version` input also defaults to `"3.47.0"` — same problem as `code_review.yml`. And because the Flutter setup step passes only `channel: stable` without `flutter-version`, that input never reaches the toolchain anyway; it is forwarded to Fastlane, which uses it to decide whether to drive `fvm`.

---

## 5. `azure-ci-cd.yml` — Azure DevOps

Two stages on a self-hosted pool named `codebase`. `trigger: none`, so it only runs when started manually or by a release.

**Stage `Build`**: capture the short commit SHA into `commitTag` → install Flutter at `$(flutter-version)` → `flutter clean` → `flutter pub get` → "Flutter Config" → download `key.properties` and `keystore.jks` as Azure *secure files* into `app/android/` → build the prod APK → publish it as artifact `android`.

**Stage `Distribute`**: download the artifact, then `firebase appdistribution:distribute` it.

Pipeline variables must be defined in the Azure Variables tab: `flutter-version`, `flutterPath`, `version`, `numberBuild`, `note`, and `FIREBASE-ANDROID-ID`.

### Three defects

> [!CAUTION]
> **1 — The distribute step uploads a filename that is never produced.**
>
> The build publishes `app-prod-release.apk` (correct, because the build passes `--flavor=prod`), but the Distribute stage runs:
>
> ```bash
> firebase appdistribution:distribute app-release.apk --app $(FIREBASE-ANDROID-ID) ...
> ```
>
> `app-release.apk` does not exist in the downloaded artifact. Change it to `app-prod-release.apk`.

> [!CAUTION]
> **2 — "Flutter Config" calls the same nonexistent script, and is malformed on top of that.**
>
> ```yaml
> script: >-
>   chmod +x tools/workspace_setup/configure.sh
>   ./tools/workspace_setup/configure.sh
> ```
>
> Two problems. `configure.sh` does not exist. And `>-` is a *folded* YAML scalar, which joins those two lines with a space into the single command `chmod +x tools/workspace_setup/configure.sh ./tools/workspace_setup/configure.sh` — so even if the file existed, it would only be chmod'ed, never executed. Replace the whole `script:` body with `dart tools/workspace_setup/configure.dart`.

> [!WARNING]
> **3 — `.env` is never created, but the build requires it.**
>
> The build passes `--dart-define-from-file=../.env`, yet no step in the pipeline produces `.env`. The two `DownloadSecureFile@1` tasks fetch only `key.properties` and `keystore.jks`. Add a third secure file for `.env` (and copy it to `$(Build.SourcesDirectory)`), mirroring what `flutter_build.yml` does with `secrets.ENV`.

The iOS build and iOS distribute tasks are present but fully commented out.

---

## 6. Missing quality gate

> [!WARNING]
> **No pipeline runs `flutter analyze` or `flutter test` before building and distributing a release.**
>
> `flutter_build.yml` goes straight from dependency installation to `flutter build apk` and then ships the artifact to testers. A change that fails analysis or breaks every test will still be built, signed and distributed. The `pr_quality_check.yml` that `.github/workflows/README.md` advertises as covering this does not exist.

Add these two steps to `flutter_build.yml` between step 4 (Install Dependencies) and step 7 (Build APK):

```yaml
      - name: Analyze
        run: flutter analyze

      - name: Test
        run: |
          set -e
          for pkg in packages/core/* packages/data/* packages/domain/* packages/features/*; do
            if [ -d "$pkg/test" ]; then
              echo "::group::flutter test $pkg"
              (cd "$pkg" && flutter test)
              echo "::endgroup::"
            fi
          done
```

The loop is necessary because this is a Pub Workspace: tests live per-package under `packages/<layer>/<pkg>/test/`, and a single `flutter test` at the root does not pick them up.

Consider also adding the catalog drift check, which is cheap and catches a whole class of merge mistakes:

```yaml
      - name: Check dependency catalog
        run: dart tools/dependency_sync.dart --check
```

`--check` exits non-zero when any package's pinned versions have drifted from `pubspec_dependencies.yaml`.

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

# 2. The quality gate CI is missing
flutter analyze
dart tools/dependency_sync.dart --check

# 3. Tests, per package (mirrors the loop suggested in §6)
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

Everything above, as a to-do list:

- [ ] `code_review.yml` — replace `configure.sh` with `dart tools/workspace_setup/configure.dart`
- [ ] `code_review.yml` — bump default `flutter_version` to `3.47.1`
- [ ] `code_review.yml` — decide whether to uncomment `exit 1`
- [ ] `fastlane.yml` — rename lane `flutter_build` → `flutter`, drop `auto_increment:`
- [ ] `fastlane.yml` — bump default `flutter_version` to `3.47.1`
- [ ] `azure-ci-cd.yml` — distribute `app-prod-release.apk`, not `app-release.apk`
- [ ] `azure-ci-cd.yml` — replace the folded `configure.sh` script with `dart tools/workspace_setup/configure.dart`
- [ ] `azure-ci-cd.yml` — add a secure file + copy step for `.env`
- [ ] `flutter_build.yml` — add analyze + test steps before the build
- [ ] `flutter_build.yml` — consider `ubuntu-latest` instead of `macos-latest`
- [ ] `.github/workflows/README.md` — remove the `pr_quality_check.yml` section, or add the workflow

---

## See also

- [`02_fastlane_release.md`](02_fastlane_release.md) — lanes, signing and the release process
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — first run, Firebase bootstrap, flavors
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — every script under `tools/`
