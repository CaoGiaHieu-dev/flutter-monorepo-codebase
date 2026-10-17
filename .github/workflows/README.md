# GitHub Actions workflows

Five workflows live here. Only one of them runs the quality gates, and only a failing check run of that one can stop a merge (whether it does depends on the branch protection of the repository, which is not stored here). The full description, including
what each gate protects and what is still missing, is in
[`docs/en/operations/01_cicd.md`](../../docs/en/operations/01_cicd.md)
([Vietnamese](../../docs/vi/operations/01_cicd.md)); this page is the index.

| Workflow | Trigger | What it does | Blocks a merge? |
|:--|:--|:--|:--|
| [`pr_quality_check.yml`](pr_quality_check.yml) | PR to `main` / `develop` / `master`, or manual | Job `quality`: `flutter pub get`, then in order — Gate 0 `composer verify`, Gate 1 `arch_check` (R1–R22) and the gate tools' own tests in `tools/test/` (both before any codegen), `configure.dart --stub-firebase` (codegen), the barrel-drift check (the regenerated barrels must equal the committed ones, RULE-75), Gate 2 `flutter analyze`, Gate 3 `flutter test` in every package with a `test/` directory except `tools/`, an advisory coverage report, Gate 4 `dependency_sync --check`, Gate 5 `docs_check`, the blocking unused-dependency audit (RULE-06), and last `composer describe --ci-matrix pr` (the `platforms` matrix). The configure step also generates every app's `runner: scaffold` runners (gitignored). Job `generator-smoke` (after `quality`): generates a BLoC feature with `tools/module_generator/generate.dart 1 smoke "" 2 2`, then `flutter analyze`, the module's own tests, `arch_check`, `composer verify` and the unused-dependency check on it — catches template regressions. Job `generator-smoke-compose` (after `quality`, independent of `generator-smoke`): generates a Provider feature with a stack route (`generate.dart 1 smoke_p "" 1 1`), its API package (`6 smoke_p`), a domain and a data package (`2` and `3 smoke_d`), the paths nothing else renders — a feature with no state management and no route (`1 smoke_n "" 3 3`), a data package without a domain (`3 smoke_nd`), a core and a custom package (`4 smoke_core`, `5 smoke_custom acme`) — and a whole app (`composer new smoke_app --platforms android,ios,web,linux --modules smoke_p,smoke_d`), then `pub get`, `build_runner`, the barrels of the new packages, `composer runners --app smoke_app --platform web`, `composer verify`, `flutter analyze`, `arch_check`, `dependency_sync --check`, the new feature's and the new app's tests, the DI smoke tests of `apps/mobile` and `apps/admin`, the unused-dependency check, and the new app's web boot test. Job `platforms` (after `quality`, one job per app that declares web or Linux): the app's `integration_test/boot_test.dart` in headless Chrome and on Linux twice — see [below](#the-platform-boots). Job `build` (after `quality`): `flutter build apk --flavor dev --debug` from `apps/mobile` with stubbed Firebase config — the only check that sees generated code and Gradle | **yes** — a failing step fails its job and the check run; `build` runs after the gates and is the proof the app builds, `platforms` the proof it boots |
| [`platforms_full.yml`](platforms_full.yml) | Push to `main` touching `platform/**`, `modules/**`, `tools/composer/**`, `tools/workspace_setup/**`, `tools/shared/**`, `tools/barrel_generator/**`, `apps/**`, `pubspec_dependencies.yaml`, `.fvmrc` or the workflow itself; the merge queue; weekly (Monday 03:17 UTC); a PR labelled `ci:platforms`; manual | The platforms a PR does not boot, from `composer describe --ci-matrix full`: macOS and Windows boot tests, the iOS simulator build (and boot), the Android APK (and emulator boot), and web release and Wasm builds of every web app. A scheduled failure opens or updates the issue "Platforms (full matrix) failing" — see [below](#the-platform-boots) | only as a required check of the merge queue, if branch protection names it |
| [`code_review.yml`](code_review.yml) | PR touching `apps/*/lib`, `modules/**` or `platform/**` Dart files, or manual | Runs `tools/code_review/code_review.dart` (Gemini) on the changed files (manual `changed` = diff against the default branch), uploads the report as an artifact and posts inline suggestions on the PR. Files the report marks HIGH only warn. Without `GEMINI_API_KEY` (a fresh adopter, a fork PR) a first step notices it and the review and comment steps are skipped, not failed | no |
| [`flutter_build.yml`](flutter_build.yml) | Manual only (`workflow_dispatch`) | Builds a signed, obfuscated release APK from `apps/mobile`, uploads its obfuscation symbols as an artifact, and distributes it with the Firebase CLI (`firebase appdistribution:distribute`) | no |
| [`fastlane.yml`](fastlane.yml) | Manual only (`workflow_dispatch`) | Runs the Fastlane lanes in `apps/mobile/fastlane`, then uploads the obfuscation symbols as an artifact | no |

> [!WARNING]
> The two release workflows run **none** of the quality gates themselves. Cut releases from a
> branch that has passed `pr_quality_check.yml`.

## Secrets

| Secret | Used by |
|:--|:--|
| `GEMINI_API_KEY` | `code_review.yml` (optional: without it the review is skipped with a notice) |
| `GITHUB_TOKEN` | `code_review.yml` (provided by GitHub; posts the PR review); `platforms_full.yml` `report` (opens the failure issue) |
| `FIREBASE_CONFIG_ARCHIVE` | `platforms_full.yml` (optional): a base64 tar.gz of an app's gitignored Firebase files, extracted into `apps/<id>/`. Without it the legs where push is on build but do not boot |
| Release secrets | `flutter_build.yml`, `fastlane.yml` — signing, App Distribution, the per-flavor Firebase options / `google-services.json`, `ENV_PROD_B64`, and for fastlane `FASTLANE_CONFIG_YAML_B64` plus the credential files it names. Full list: [`docs/en/operations/01_cicd.md` § 7](../../docs/en/operations/01_cicd.md#7-secrets) |

Dependabot (`.github/dependabot.yml`) covers `pub`, `gradle` and `github-actions` only; there is no `bundler` entry, because the Gemfiles pin no versions and no `Gemfile.lock` is committed.

`pr_quality_check.yml` needs no secrets. It stubs the git-ignored `firebase_options_*.dart` files
for every `apps/*/lib/firebase/` so the workspace compiles (`code_review.yml` runs `configure.dart --stub-firebase` for the same reason), and its `build` job also stubs
the `dev` flavor's `apps/mobile/android/app/src/<flavor>/google-services.json` so Gradle can
build the debug APK.

`pr_quality_check.yml`, `platforms_full.yml`, `flutter_build.yml` and `fastlane.yml` declare a top-level
`permissions: contents: read`; `platforms_full.yml`'s `report` job alone adds `issues: write` and `actions: read`. Every workflow takes its Flutter version from `.fvmrc`; in
`fastlane.yml` the optional `flutter_version` input overrides it (empty = `.fvmrc`, resolved in
the "Resolve the Flutter version" step) and the lane also checks it. Actions are on their current
Node 24 majors; `tj-actions/changed-files` is pinned to a commit SHA.

## The platform boots

A build is not a boot: the web blank page compiled, analyzed and passed every unit test. Each app
owns `integration_test/boot_test.dart`, which runs `main()` on a real device until the first frame
reaches the engine, and both workflows run it. Neither lists apps or platforms: the rows come from
the manifests through `dart tools/composer/composer.dart describe --ci-matrix pr|full` (one line of
JSON), so a new app or platform needs no edit here.

| Where | What it boots | Runner |
|:--|:--|:--|
| `pr_quality_check.yml` / `platforms`, every PR | each app that declares web or Linux (`--ci-matrix pr`): the web with `flutter drive -d web-server` in headless Chrome, with the matched chromedriver from `browser-actions/setup-chrome`; Linux with `flutter test -d linux` under Xvfb, once with an unlocked gnome-keyring on a private session bus, once with `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/bus` (no Secret Service, so `secure_storage: memory_fallback` keeps secure values in memory) | ubuntu |
| `pr_quality_check.yml` / `generator-smoke-compose`, every PR | the app `composer new` just wrote, on the web | ubuntu |
| `platforms_full.yml` / `boot` | one leg per (app, android / ios / macos / windows) the app declares (`--ci-matrix full`): macOS and Windows boot tests; iOS simulator build, booted when push is off or the Firebase secret is set; Android APK, emulator boot (API 34, x86_64) when push is off or the secret is set | the row's `os` |
| `platforms_full.yml` / `web-release` | no boot: `flutter build web --release`, then with `--wasm`, for every web app | ubuntu |

Every job that runs a boot test sets `timeout-minutes`: a Linux keyring prompt or a hung device never
ends on its own.

**The label.** On a pull request, `platforms_full.yml` runs only while it carries the label
`ci:platforms` (added, then on every push). Add it to a PR that touches native-sensitive code
(the shell, storage, the database, a runner, the composer). Create the label once in the repository;
GitHub has none by default.

**Triggers of `platforms_full.yml`.** A push to `main` that touches `platform/**`, `modules/**`,
`tools/composer/**`, the tools every leg runs through `configure.dart` (`tools/workspace_setup/**`,
`tools/shared/**`, `tools/barrel_generator/**`), `apps/**`, `pubspec_dependencies.yaml`, `.fvmrc` or
the workflow file itself; `merge_group`; weekly,
Monday 03:17 UTC (dependency float, since no lockfile is committed, and runner-image drift); the
label; `workflow_dispatch`. Only a scheduled failure opens or comments on the issue "Platforms (full
matrix) failing", with the failed legs and the run URL.

**`FIREBASE_CONFIG_ARCHIVE`.** Optional. A leg where the derived push is on (`boot: firebase`)
needs the real Firebase files to boot; the `--stub-firebase` stand-ins only compile. Make the
archive from the app directory and store it base64-encoded:

```bash
cd apps/mobile
tar -czf - lib/firebase/firebase_options_*.dart android/app/src/*/google-services.json \
  ios/flavors/*/GoogleService-Info.plist | base64 -w0
```

It is extracted into `apps/<id>/` before `configure.dart`, which then writes a stub only where a
file is still absent. Without the secret those legs build and skip the boot, with a notice.

**Caches.** No lockfile is committed, so every `subosito/flutter-action` keys its pub cache on
`hashFiles('pubspec_dependencies.yaml', '**/pubspec.yaml')`; the default key hashes
`**/pubspec.lock` and would never change. The legs that build natively cache the build-hook
downloads (`.dart_tool/hooks_runner/shared`, the sqlite3 prebuilt), restored after `configure.dart`
because its `flutter clean` deletes `.dart_tool/`, and the `sqlite3.wasm` cache
(`~/.cache/flutter_monorepo/sqlite3`), restored before `configure.dart` because its last step,
`composer runners`, is what reads it; both are keyed on `pubspec_dependencies.yaml`. `composer runners` checks the
wasm's sha256 on every copy, so an edited cache fails. `platforms_full.yml` also caches Gradle
(`setup-java` `cache: gradle`), CocoaPods (`apps/<id>/ios/Pods` on the app's `Podfile` and the
catalog) and Windows' `build/windows/x64/extracted`. Codegen output is never cached: each leg
runs `configure.dart` as an adopter does.

Locally: `apps/<id>/README.md` and guide 13 § 7 print the same commands per platform.

## Running the gates locally

```bash
flutter pub get
dart tools/composer/composer.dart verify
dart tools/arch_check/check.dart
(cd tools && dart test)
dart tools/workspace_setup/configure.dart --stub-firebase
flutter analyze
dart tools/dependency_sync.dart --check
dart tools/docs_check/check.dart
dart tools/unused_checker/check_unused_packages.dart
(cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev)
```

Tests run per package, `tools/` excepted — the loop is in [`CONTRIBUTING.md`](../../CONTRIBUTING.md) § 3 and
[`docs/en/getting-started/03_daily_workflow.md`](../../docs/en/getting-started/03_daily_workflow.md).
