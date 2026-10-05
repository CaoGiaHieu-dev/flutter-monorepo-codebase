# GitHub Actions setup

What each workflow does is listed in [`workflows/README.md`](workflows/README.md). This page is
only what you have to configure once in the repository settings.

## 1. The merge gate — nothing to configure

`pr_quality_check.yml` needs no secrets. To make it actually block merges, add its four jobs as
required status checks: **Settings → Branches → Branch protection rules → Require status checks
to pass**, and select **PR Quality Check / Analyze, test and audit** (the gates),
**PR Quality Check / Build the dev APK (debug)** (the only check that proves the app builds),
**PR Quality Check / Module generator smoke test** and
**PR Quality Check / Generator smoke test (Provider, API, domain/data, core/custom, new app)** (the only checks that run
the module and app templates). Branch protection matches a check by its exact name, so copy it from the Checks tab of a run
rather than retyping it: a name that no job reports blocks every merge, or is silently not required.

## 2. AI code review — optional

`code_review.yml` calls Gemini. Add the key under **Settings → Secrets and variables → Actions**:

| Name | Value |
|:--|:--|
| `GEMINI_API_KEY` | an API key from [Google AI Studio](https://aistudio.google.com/app/apikey) |

Without the key (a fresh adopter, or a pull request from a fork, where secrets are empty) the
workflow checks for it first and skips the review and comment steps with a `::notice::` — the job
stays green and the rest of the PR is unaffected. The workflow never blocks a merge. To change the report language for manual runs, pick it in the `workflow_dispatch`
form (default `en`); PR runs use `reportLanguage` from
`tools/code_review/code_review_config.json` (`en`).

## 3. Release builds — only if you use them

| Workflow | Secrets |
|:--|:--|
| `flutter_build.yml` | Signing, App Distribution (`FIREBASE_SERVICE_ACCOUNT_KEY`, `FIREBASE_ANDROID_APP_ID`; the tester group is the `groups` input, default `test`, and must exist in Firebase), and the gitignored build inputs for the flavor built (Firebase options, `google-services.json`, `ENV_PROD_B64` for prod) |
| `fastlane.yml` | `FASTLANE_CONFIG_YAML_B64` (your `Config.yaml`), the same per-flavor build inputs, and the credential files `Config.yaml` names for the chosen distribution |

Both upload the build's obfuscation symbols as a workflow artifact (`debug-symbols-…`, kept 90
days); download and archive them with the release, or its crash stack traces stay unreadable.

The full, per-flavor list of secret names and what each decodes to is in
[`docs/en/operations/01_cicd.md` § 7](../docs/en/operations/01_cicd.md#7-secrets). A missing
secret is reported by name and fails the run before any build starts.

Both are manual (`workflow_dispatch`) and run none of the quality gates, so dispatch them only
from a branch that has passed `pr_quality_check.yml`.

## 4. Dependency updates — nothing to configure

`.github/dependabot.yml` opens weekly update pull requests for three ecosystems only: `pub` (a notification — the
versions live in `pubspec_dependencies.yaml`, so such a PR fails Gate 4 until the catalog is edited and
`dart tools/dependency_sync.dart` applied), `gradle` (`apps/mobile/android`) and `github-actions`. There is no `bundler`
entry: the Gemfiles pin no versions and no `Gemfile.lock` is committed, so there is nothing for Dependabot to update.
Security alerts are separate (**Settings → Code security**).

## 5. Check it works

Open a pull request that touches any Dart file under `apps/`, `modules/` or `platform/`. The
**Checks** tab should show all four *PR Quality Check* jobs and, if the key is set, *AI Code Review*.

## Further reading

- [CI/CD in detail](../docs/en/operations/01_cicd.md) — every gate, and what is still missing
- [Fastlane and releases](../docs/en/operations/02_fastlane_release.md)
- [Code review tool](../tools/code_review/README.md)
