# Tooling Reference

**This page answers:** which script do I run, with what arguments, what does its exit code mean, and which CI gate runs it?

One table per tool. Every tool lives in `tools/`, is plain Dart (bar the 16 KB check), and runs from the **repository root**. The long form — every argument, refusal and failure mode — is in [`tools/README.md` § Full reference](../../../tools/README.md#-full-reference-tool-by-tool).

Exit codes follow one convention across the tools: `0` success, `1` the check failed or the work could not be done, `64` a bad argument (nothing was run or written).

---

## Problem → tool

| Problem | Command |
|---|---|
| **Check the layering rules hold** | `dart tools/arch_check/check.dart` |
| **Check the docs still describe this tree** | `dart tools/docs_check/check.dart` |
| **Changed a gate tool — prove it still fails where it should** | `cd tools && dart test` |
| **Which packages are sample code I can delete?** | `dart tools/sample_cleanup/remove_sample.dart --list` |
| **Delete a sample package safely** | `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` (omit `--apply` to preview) — `<bundle>` is one of `auth`, `home`, `settings`, `onboarding`, `dashboard`, `splash`, `cache` |
| Create a new feature / domain / data / core package | `dart tools/module_generator/generate.dart …` |
| Added, renamed or deleted a file under `lib/` | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Changed a dependency version | `dart tools/dependency_sync.dart` |
| CI needs to reject version drift | `dart tools/dependency_sync.dart --check` |
| Suspect dead assets / files / translations / packages | `dart tools/unused_checker/check_script.dart` |
| Want to know what is outdated on pub.dev | `dart tools/check_outdated.dart` |
| Fresh clone, need everything wired up | `dart tools/workspace_setup/configure.dart` |
| No Firebase project, but the app must compile and build | `dart tools/workspace_setup/configure.dart --stub-firebase` |
| How much of each package do the tests cover? | `flutter test --coverage` per package, then `dart tools/coverage_report/report.dart` |
| Set up Firebase for dev / staging / prod | `dart tools/firebase/firebase_config.dart --app mobile` |
| Regenerate splash screen and app icons | `dart tools/theme_generator/theme_setting.dart --app mobile` |
| Check Android 15+ 16 KB page-size compliance | `./tools/android_compliance/16kb_ckeck.sh <apk>` |
| AI review of a change | `dart tools/code_review/code_review.dart --changed` |

## CI gates at a glance

`.github/workflows/pr_quality_check.yml` runs these, in this order. Pipelines in full: [`../operations/01_cicd.md`](../operations/01_cicd.md).

| Gate | Command | Blocks the merge? |
|:--|:--|:--|
| 0 | `dart tools/composer/composer.dart verify` | Yes |
| 1 | `dart tools/arch_check/check.dart`, then `cd tools && dart test` | Yes |
| 2 | `flutter analyze` | Yes |
| 3 | `flutter test --coverage` in every package with a `test/`, then `dart tools/coverage_report/report.dart` | Tests yes; coverage report no (advisory) |
| 4 | `dart tools/dependency_sync.dart --check` | Yes |
| 5 | `dart tools/docs_check/check.dart` | Yes |
| — | `dart tools/unused_checker/check_unused_packages.dart` | No (advisory step) |
| — | `dart tools/code_review/code_review.dart` (own workflow) | No (advisory) |

---

## `arch_check`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/arch_check/check.dart` | Enforce the layering rules R1–R15 on imports, pubspecs and file names | `0` clean (R6 only warns) · `1` a blocking violation · `64` any argument but `--help` | 1 |
| `dart tools/arch_check/check.dart --help` | Describe every rule | `0` | — |

- Reads imports and `pubspec.yaml` files only, needs no codegen, and finishes in a few hundred ms.
- The three approved upward edges are printed on every run. A fourth needs the allow-list in `check.dart` and RULE-01 updated together.
- Each rule, with why it exists: [details](../../../tools/README.md#arch_check). The registry row each rule enforces: R1 RULE-01 · R2 RULE-03 · R3 RULE-04 · R4 RULE-09 · R5 RULE-06 · R6 RULE-76 · R7 RULE-30 · R8 RULE-12 · R9 RULE-07 · R10 RULE-05 · R11 RULE-02 · R12 RULE-72 · R13 RULE-71 · R14 RULE-40 · R15 RULE-78.

## `composer`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/composer/composer.dart list [--app <id>]` | Print each app's composition | `0` · `1` invalid manifest · `64` bad flag | — |
| `dart tools/composer/composer.dart sync [--app <id>]` | Regenerate the root `workspace:` list, each app's path dependencies and `injection.dart` from `app_manifest.yaml` | `0` · `1` invalid manifest or YAML, a lost `composer:managed` marker, a managed package declared by hand · `64` bad flag | — |
| `dart tools/composer/composer.dart verify` | Same, but write nothing and fail on drift; implies `--strict` | `0` · `1` drift, a module missing from disk, or any `sync` refusal · `64` bad flag | 0 |

- Only the regions between `composer:managed:<region>` and `composer:end:<region>` are generated; never hand-edit them (RULE-16).
- A non-strict `sync` that skipped a missing module prints a `PARTIAL COMPOSITION` block and the `git checkout --` line that restores the files.
- Manifest validation, package discovery and the `api` layer: [details](../../../tools/README.md#composer).

### `bootstrap` — before composer can run

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/composer/bootstrap.dart [--dry-run]` | In a partial checkout, prune every managed entry whose directory has no `pubspec.yaml`, so `flutter pub get` can resolve | `0` pruned, or nothing to prune · `1` no managed region, or a present package has a hand-written path dependency on a missing one · `64` bad argument | — |

It imports no package, so it runs before pub has ever resolved. The full sequence: [`12_module_isolation.md` § 2](../guides/12_module_isolation.md#2-work-in-a-partial-checkout). Details: [`bootstrap`](../../../tools/README.md#bootstrap--before-composer-can-run).

## `docs_check`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/docs_check/check.dart` | Every repo path and relative link in every `*.md` exists; en ↔ vi parity; every `RULE-NN` is in the registry | `0` · `1` a dead reference, a parity mismatch or an unknown/duplicate RULE-ID · `64` bad argument | 5 |
| `dart tools/docs_check/check.dart --verbose` | Plus a copy-paste allowlist block and every removed-sample reference | as above | — |
| `dart tools/docs_check/check.dart --stale-translations` | List `docs/vi` files behind their English source | `0` (advisory) | — |
| `dart tools/docs_check/check.dart --stamp-translations docs/vi/<file>.md` | Stamp a synced translation | `0` | — |

- Correctly absent paths live in `tools/docs_check/allowlist.txt`, each with its reason; intentional shape differences in `tools/docs_check/parity_allowlist.txt`.
- References into a sample bundle removed with `remove_sample` are summarised as one INFO line per bundle, never a failure.
- Path resolution, placeholders, parity metrics and translation stamps: [details](../../../tools/README.md#docs_check).

## `sample_cleanup`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/sample_cleanup/remove_sample.dart --list` | Classify every package as `framework`, `sample` or `shell` | `0` | — |
| `dart tools/sample_cleanup/remove_sample.dart <bundle> [--verbose]` | Dry run: what would be removed, what breaks, what degrades safely, which docs go dead | `0` · `64` unknown flag or bundle, or more than one bundle | — |
| `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` | Remove the bundle | `0` · `1` failed partway (shared files rolled back; deleted directories are not) · `64` as above | — |

- Source of truth: [`tools/sample_manifest.yaml`](../../../tools/sample_manifest.yaml). The tool never edits it, which is how `docs_check` recognises a removed bundle.
- A bundle's `<id>_api` package is kept while another package still imports it.
- Details: [`sample_cleanup`](../../../tools/README.md#sample_cleanup).

## `module_generator`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<sm>] [<route>] [--group <g>] [--apps <id,id>]` | Scaffold a package, compose it into the apps, run codegen and barrels | `0` · `1` a step failed (rolled back) · `64` invalid or missing argument, name taken, unknown app id | Smoke-tested in its own CI job |
| `dart tools/module_generator/generate.dart --help` | Usage | `0` | — |

| Arg | Values |
|---|---|
| `<type>` | `1` feature · `2` domain · `3` data · `4` core · `5` custom |
| `<name>` | A Dart package name (`profile` → `feature_profile`) |
| `<prefix>` | Type `5` only; pass `""` for types 1–4 |
| `<sm>` | Feature only — `1` Provider · `2` BLoC · `3` none |
| `<route>` | Feature only — `1` `IFeatureRouteModule` · `2` `INavDestinationModule` · `3` none |
| `--group` | Types `4`/`5` only — the `platform/` group folder; default `infra` |
| `--apps` | Any type — compose into these apps only; default every app |

- Without a terminal, a missing value is an error, never a default: always pass all five arguments for a feature.
- A feature ships tests that pass as generated. A walked example: [`../getting-started/04_first_feature_tutorial.md`](../getting-started/04_first_feature_tutorial.md).
- What it writes, its safety behaviour and build time: [details](../../../tools/README.md#module_generator).

## `barrel_generator`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/barrel_generator/generate.dart <pkg>/lib` | Regenerate every `*.dart` barrel under the path, then `dart format` it | `0` · `1` `dart format` failed (barrels written) · `64` path missing, a flag, or a second path | — |

- Run it after any file add, rename or delete under `lib/` — and **after** `build_runner` / `gen-l10n`, because generated files are exported too (RULE-75).
- It removes every hand-written `export` line. Details: [`barrel_generator`](../../../tools/README.md#barrel_generator).

## `dependency_sync`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/dependency_sync.dart` | Write the versions of `pubspec_dependencies.yaml` into every package; repair broken local `path:` entries | `0` · `1` invalid catalog or pubspec · `64` bad flag | — |
| `dart tools/dependency_sync.dart --check` | Report drift, write nothing | `0` · `1` drift or an invalid catalog · `64` bad flag | 4 |

Versions live only in the catalog (RULE-74). Details: [`dependency_sync`](../../../tools/README.md#dependency_sync).

## `unused_checker`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/unused_checker/check_script.dart` | Run all four checks, with a summary | `0` · `1` a check failed · `64` bad argument | — |
| `dart tools/unused_checker/check_unused_packages.dart` | Dependencies declared but never imported | `0` · `1` · `64` | Advisory step |
| `dart tools/unused_checker/check_unused_assets.dart` | Assets not referenced | `0` · `1` · `64` | — |
| `dart tools/unused_checker/check_unused_translate.dart` | ARB keys never used | `0` · `1` · `64` | — |
| `dart tools/unused_checker/check_unused_file.dart` | Orphaned Dart files | `0` · `1` · `64` | — |

- `check_unused_packages` is the mirror of `arch_check` R5 (RULE-06): run both before a PR.
- The asset, file and translation checks match text, so anything reached dynamically is a false positive. Details: [`unused_checker`](../../../tools/README.md#unused_checker).

## `check_outdated`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/check_outdated.dart` | Report catalog packages with newer versions on pub.dev; on a terminal, offer to bump them | `0` · `1` resolution, `pub outdated` or applying an update failed · `64` bad argument | — |

Details: [`check_outdated`](../../../tools/README.md#check_outdated).

## `workspace_setup`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/workspace_setup/configure.dart` | Full setup: activate `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n`, `build_runner`, barrels | `0` · the failing command's exit code · `64` bad argument | Runs before Gates 2–5 |
| `dart tools/workspace_setup/configure.dart --stub-firebase` | The same, plus compile-only Firebase stubs where no real file exists | as above | Used by CI |
| `dart tools/workspace_setup/configure.dart --help` | Print the steps, run nothing | `0` | — |

`pub get` + `build_runner` alone is not setup: the gitignored `lib/src/gen/gen.dart` barrels come from the barrel pass. There is no `configure.sh` or `.bat`. Details: [`workspace_setup`](../../../tools/README.md#workspace_setup).

## `firebase`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/firebase/firebase_config.dart [--app <id>]` | Run `flutterfire configure` for each flavor and build mode of one app | `0` · `1` no terminal, Firebase CLI missing or not logged in, not run from the root · `64` bad argument | — |

Interactive only; needs the Firebase CLI installed and logged in. `--app` is required while the workspace holds two apps. Details: [`firebase`](../../../tools/README.md#firebase).

## `theme_generator`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/theme_generator/theme_setting.dart [--app <id>]` | Generate the splash screen and app icons from the per-flavor configs at the root | `0` · `1` the app cannot take them, or a generator failed (files restored) · `64` bad argument | — |

`--app admin` is refused today: admin has no platform directories. Details: [`theme_generator`](../../../tools/README.md#theme_generator).

## `android_compliance`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `./tools/android_compliance/16kb_ckeck.sh <apk\|apex\|dir>` | Check Android 15+ 16 KB page-size compliance (zip and ELF alignment) | `0` the analysis ran — an unaligned library is reported in the summary, not through the exit code · `1` no argument, a wrong file type, an unreadable APK or a missing SDK tool | — |
| `.\tools\android_compliance\16kb_ckeck.bat <apk>` | The same on Windows, through Git Bash | as above | — |

Build a release APK of one flavor first. The filename typo (`ckeck`) is kept on purpose. Details: [`android_compliance`](../../../tools/README.md#android_compliance).

## `code_review`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/code_review/code_review.dart --changed \| --all \| --file <f> [--focus …] [--language vi]` | Gemini-backed review against `tools/code_review/review_prompt.md` | `0` · `1` no API key without a terminal, or a missing `--file` / `--folder` · `64` bad option | Advisory workflow |

Needs a Gemini API key (`GEMINI_API_KEY`, `--api-key`, or the gitignored `tools/code_review/.gemini_api_key`). Details: [`code_review`](../../../tools/README.md#code_review) and [`tools/code_review/README.md`](../../../tools/code_review/README.md).

## `coverage_report`

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `dart tools/coverage_report/report.dart [--min <pct>] [--min-package <pct>] [--no-summary]` | Per-package line coverage from every `*/coverage/lcov.info`, generated files excluded | `0` · `1` no `lcov.info` found, or a threshold missed · `64` bad argument | 3 (advisory) |

Run `flutter test --coverage` in each package first. Details: [`coverage_report`](../../../tools/README.md#coverage_report).

## Tests for the tools (`tools/test/`)

| Command | Purpose | Exit codes | CI gate |
|:--|:--|:--|:--|
| `cd tools && dart test` | Every gate tool run against throwaway workspaces, asserting exit code and output (~15 s) | `0` · `1` a test failed | 1 |

When you change a gate, add the case that would have caught the bug (RULE-64). What each test file covers: [details](../../../tools/README.md#tests-for-the-tools-toolstest).

---

**Next:** [`04_review_checklist.md`](04_review_checklist.md) · [`01_rules.md`](01_rules.md) · [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md)
