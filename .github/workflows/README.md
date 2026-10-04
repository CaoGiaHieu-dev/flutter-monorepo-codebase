# GitHub Actions workflows

Four workflows live here. Only one of them runs the quality gates, and only a failing check run of that one can stop a merge (whether it does depends on the branch protection of the repository, which is not stored here). The full description, including
what each gate protects and what is still missing, is in
[`docs/en/operations/01_cicd.md`](../../docs/en/operations/01_cicd.md)
([Vietnamese](../../docs/vi/operations/01_cicd.md)); this page is the index.

| Workflow | Trigger | What it does | Blocks a merge? |
|:--|:--|:--|:--|
| [`pr_quality_check.yml`](pr_quality_check.yml) | PR to `main` / `develop` / `master`, or manual | Job `quality`: `flutter pub get`, then in order — Gate 0 `composer verify`, Gate 1 `arch_check` (R1–R21) and the gate tools' own tests in `tools/test/` (both before any codegen), `configure.dart --stub-firebase` (codegen), the barrel-drift check (the regenerated barrels must equal the committed ones, RULE-75), Gate 2 `flutter analyze`, Gate 3 `flutter test` in every package with a `test/` directory except `tools/`, an advisory coverage report, Gate 4 `dependency_sync --check`, Gate 5 `docs_check`, and the blocking unused-dependency audit (RULE-06). Job `generator-smoke` (after `quality`): generates a BLoC feature with `tools/module_generator/generate.dart 1 smoke "" 2 2`, then `flutter analyze`, the module's own tests, `arch_check`, `composer verify` and the unused-dependency check on it — catches template regressions. Job `generator-smoke-compose` (after `quality`, independent of `generator-smoke`): generates a Provider feature with a stack route (`generate.dart 1 smoke_p "" 1 1`), its API package (`6 smoke_p`), a domain and a data package (`2` and `3 smoke_d`), the paths nothing else renders — a feature with no state management and no route (`1 smoke_n "" 3 3`), a data package without a domain (`3 smoke_nd`), a core and a custom package (`4 smoke_core`, `5 smoke_custom acme`) — and a whole app (`composer new smoke_app --platforms android,ios --modules smoke_p,smoke_d`), then `pub get`, `build_runner`, the barrels of the new packages, `composer verify`, `flutter analyze`, `arch_check`, `dependency_sync --check`, the new feature's and the new app's tests, the DI smoke tests of `apps/mobile` and `apps/admin` and the unused-dependency check. Job `build` (after `quality`): `flutter build apk --flavor dev --debug` from `apps/mobile` with stubbed Firebase config — the only check that sees generated code and Gradle | **yes** — a failing step fails its job and the check run; `build` runs after the gates and is the proof the app builds |
| [`code_review.yml`](code_review.yml) | PR touching `apps/*/lib`, `modules/**` or `platform/**` Dart files, or manual | Runs `tools/code_review/code_review.dart` (Gemini) on the changed files (manual `changed` = diff against the default branch), uploads the report as an artifact and posts inline suggestions on the PR. Files the report marks HIGH only warn | no |
| [`flutter_build.yml`](flutter_build.yml) | Manual only (`workflow_dispatch`) | Builds a signed, obfuscated release APK from `apps/mobile`, uploads its obfuscation symbols as an artifact, and distributes it with the Firebase CLI (`firebase appdistribution:distribute`) | no |
| [`fastlane.yml`](fastlane.yml) | Manual only (`workflow_dispatch`) | Runs the Fastlane lanes in `apps/mobile/fastlane`, then uploads the obfuscation symbols as an artifact | no |

> [!WARNING]
> The two release workflows run **none** of the quality gates themselves. Cut releases from a
> branch that has passed `pr_quality_check.yml`.

## Secrets

| Secret | Used by |
|:--|:--|
| `GEMINI_API_KEY` | `code_review.yml` |
| `GITHUB_TOKEN` | `code_review.yml` (provided by GitHub; posts the PR review) |
| Release secrets | `flutter_build.yml`, `fastlane.yml` — signing, App Distribution, the per-flavor Firebase options / `google-services.json`, `ENV_PROD_B64`, and for fastlane `FASTLANE_CONFIG_YAML_B64` plus the credential files it names. Full list: [`docs/en/operations/01_cicd.md` § 7](../../docs/en/operations/01_cicd.md#7-secrets) |

`pr_quality_check.yml` needs no secrets. It stubs the git-ignored `firebase_options_*.dart` files
for every `apps/*/lib/firebase/` so the workspace compiles, and its `build` job also stubs
the `dev` flavor's `apps/mobile/android/app/src/<flavor>/google-services.json` so Gradle can
build the debug APK.

`pr_quality_check.yml`, `flutter_build.yml` and `fastlane.yml` declare a top-level
`permissions: contents: read`. Every workflow takes its Flutter version from `.fvmrc`; in
`fastlane.yml` the optional `flutter_version` input overrides it (empty = `.fvmrc`, resolved in
the "Resolve the Flutter version" step) and the lane also checks it. Actions are on their current
Node 24 majors; `tj-actions/changed-files` is pinned to a commit SHA.

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
