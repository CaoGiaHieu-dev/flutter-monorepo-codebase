# GitHub Actions workflows

Four workflows live here. Only one of them can block a merge. The full description, including
what each gate protects and what is still missing, is in
[`docs/en/operations/01_cicd.md`](../../docs/en/operations/01_cicd.md)
([Vietnamese](../../docs/vi/operations/01_cicd.md)); this page is the index.

| Workflow | Trigger | What it does | Blocks a merge? |
|:--|:--|:--|:--|
| [`pr_quality_check.yml`](pr_quality_check.yml) | PR to `main` / `develop` / `master`, or manual | Job `quality`: `flutter pub get --enforce-lockfile`, then Gates 0–5 in order — `composer verify`, `arch_check` (both before any codegen), `flutter analyze`, `flutter test` in every package with a `test/` directory, `dependency_sync --check`, `docs_check` — then an advisory unused-dependency audit. Job `build` (after `quality`): `flutter build apk --flavor dev --debug` from `apps/mobile` with stubbed Firebase config — the only check that sees generated code and Gradle | **yes** (both jobs) |
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

Every workflow takes its Flutter version from `.fvmrc` (`flutter-version-file`), except
`fastlane.yml`, whose `flutter_version` input the lane also checks. Actions are on their current
Node 24 majors; `tj-actions/changed-files` is pinned to a commit SHA.

## Running the gates locally

```bash
flutter pub get --enforce-lockfile
dart tools/composer/composer.dart verify
dart tools/arch_check/check.dart
dart tools/workspace_setup/configure.dart
flutter analyze
dart tools/dependency_sync.dart --check
dart tools/docs_check/check.dart
(cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev)
```

Tests run per package — see [`docs/en/getting-started/03_daily_workflow.md`](../../docs/en/getting-started/03_daily_workflow.md).
