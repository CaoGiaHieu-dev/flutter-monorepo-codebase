---
name: run_repo_tooling
description: Use when a task needs one of the repo's maintenance tools — regenerating the package barrel after adding, renaming or deleting a lib/ file; composer sync / verify / describe / new; syncing or checking dependency versions; docs_check and translation stamps; finding unused files, assets, translations or packages; coverage_report; setting up a fresh or partial checkout; the tools' own tests; or the Gemini AI code review. Covers which tool to run, from where, and how to read its exit code. Removing a module or a sample is remove_module, not this skill.
---

# Run repo tooling

> **Use [`remove_module`](../remove_module/SKILL.md) instead when** the task is to remove a module or a shipped sample (it covers
> `remove_sample` and the follow-up). For per-app decisions use [`configure_app`](../configure_app/SKILL.md); to scaffold a package
> use [`create_feature_module`](../create_feature_module/SKILL.md).

Every tool runs from the **repository root** with plain `dart` (no `fvm` prefix — RULE-73), prints with
`stdout.writeln` / `stderr.writeln` (RULE-65), and takes `--help`. An unknown argument exits `64`; the
convention is `0` success, `1` the check failed or the work could not be done, `64` a bad argument. The
exception is the individual `unused_checker` scripts (`2` = findings); `composer` with no command at all exits `64`
(usage on stderr). The full reference, with each tool's edge cases, is
[`docs/en/reference/03_tooling.md`](../../../docs/en/reference/03_tooling.md).

| Situation | Command | Rule |
|:--|:--|:--|
| Added, renamed or deleted a file under a package's `lib/` | `dart tools/barrel_generator/generate.dart <package>/lib` | RULE-75 |
| Edited an `app_manifest.yaml` | `dart tools/composer/composer.dart sync [--app <id>]`, then `verify` | RULE-16, RULE-81 |
| Read what an app declares and what the shell resolves | `dart tools/composer/composer.dart describe --app <id>` | RULE-80, RULE-81 |
| Look up a manifest key, contract id, derived default, check or problem code | `dart tools/composer/composer.dart describe --catalog` | — |
| Create a third app | `dart tools/composer/composer.dart new <id> --platforms <a,b> [--modules <x,y>]` | RULE-80 |
| Changed a version in `pubspec_dependencies.yaml` | `dart tools/dependency_sync.dart` | RULE-74 |
| Verify versions only (CI, pre-commit) | `dart tools/dependency_sync.dart --check` | RULE-74 |
| An import is used but maybe not declared | `dart tools/arch_check/check.dart` (R5) | RULE-06 |
| A dependency is declared but maybe unused | `dart tools/unused_checker/check_unused_packages.dart` | RULE-06 |
| Check the layering and hygiene rules (R1–R21) | `dart tools/arch_check/check.dart` | — |
| Docs reference a path or rule that does not exist; en/vi parity | `dart tools/docs_check/check.dart` | RULE-79 |
| Changed a gate tool | `cd tools && dart test` (add the case that would have caught the bug) | RULE-64 |
| Delete a shipped sample module | `dart tools/sample_cleanup/remove_sample.dart <bundle> [--apply]` | — |
| Clean up dead files, assets, translations | `dart tools/unused_checker/check_script.dart` | — |
| Propose version upgrades | `dart tools/check_outdated.dart` | — |
| Coverage per package | `flutter test --coverage` in each package, then `dart tools/coverage_report/report.dart` | — |
| Fresh clone | `dart tools/workspace_setup/configure.dart` (`--stub-firebase` for compile-only Firebase files) | — |
| Partial checkout, `pub get` refuses | `dart tools/composer/bootstrap.dart [--dry-run]` | — |
| Review a change with the AI reviewer | `dart tools/code_review/code_review.dart --changed` | — |

## Barrel generator

There is **one barrel per package**, `lib/<package_name>.dart`, committed; inside a package a file imports the
concrete file, never the barrel (RULE-75).

- Pass one package's **`lib` directory** per run: `dart tools/barrel_generator/generate.dart modules/<name>/domain/lib`,
  and again for every package you touched. It exports every library file under `lib/`, sorted, then runs
  `dart format`; it also exports generated libraries present on disk (`module.module.dart`, `lib/src/gen/**`) and
  deletes directory barrels.
- Run it after adding, renaming or deleting a `lib/` file, and **after** `flutter gen-l10n` and
  `dart run build_runner build --workspace` for the package's own barrel, so the generated exports are listed. The
  one exception: when annotated code imports a type you just added to **another** package, regenerate that package's
  barrel *before* `build_runner`, or injectable cannot see the type.
- It replaces every `export` directive in the barrel: a deliberate re-export of another package goes in a normal
  source file (see `platform/foundation/kernel/lib/src/error/failures.dart`). Never hand-add an `export`.
- Exit `64`: no path, a path that is not a package's `lib/`, a flag, or a second path. Exit `1`: generation or
  `dart format` failed. CI fails the PR when a barrel drifts from the generator (the "Barrels match the generator"
  step after `configure.dart`).

## Composer: sync, verify, describe, new

- `sync [--app <id>] [--strict]` regenerates the `composer:managed` regions: the root `workspace:` list, each app's
  path dependencies, the `imports` and `modules` regions of `lib/di/injection.dart` (outside them only comments), the `facts` region of `lib/app/app_profile.dart` and the
  `report` region of the app's `README.md`. Never hand-edit them (RULE-16). Exit `1`: invalid manifest, a lost
  marker, a refused declaration. A non-strict `sync` that skipped a module missing on disk prints a `PARTIAL
  COMPOSITION` block.
- `verify [--app <id>]` is Gate 0: the same resolution, writes nothing, exit `1` on drift; implies `--strict`; fails
  on a module or platform package no app composes, and holds the declaration to the source (V3 capabilities, V7
  platforms, V10 `FirebaseOptions`, V11 env files, V12 the smoke test builds every factory, V13 no code outside the generated regions of
  `injection.dart`, V15 native flavors, V16 DI group `why` and order, V17 the root as the only workspace node). `sync` prints those as warnings and still writes.
- `describe --app <id>` prints the report that also sits in the app's `README.md`; `describe --catalog` is the key
  reference — every manifest key with its default and reader, the 21-row contract catalog, the derived defaults,
  checks V1–V17 and problem codes P01–P05 / C01–C12. Do not copy that table into prose.
- `new <id> --platforms <a,b> [--modules <x,y>] [--name "<Display Name>"]` renders `tools/composer/app_template/`
  into `apps/<id>/`, derives `capabilities:` from what the modules register, then runs `sync` and `verify`. It
  refuses an existing id or a platform a module blocks **before writing anything**, and **never runs `flutter
  create`**: it prints the line for you to run when a runner is wanted. Afterwards `flutter pub get`,
  `dart run build_runner build --workspace`, `cd apps/<id> && flutter test` — [`configure_app`](../configure_app/SKILL.md).
- `list [--app <id>] [--strict]` prints each app's composition. Exit `64`: unknown command or argument.

## Dependency sync

- The catalog `pubspec_dependencies.yaml` holds shared pub.dev versions only; workspace packages use `path:` entries,
  which the tool repairs when they point at the wrong directory. A package writes a third-party dependency with an
  empty value (`dio:`) and the sync fills it in. Native Gradle / CocoaPods dependencies are edited by hand.
- A plain run rewrites drifted versions **and runs `pub get` itself**; `pubspec.lock` is generated and
  git-ignored, so there is nothing of it to commit. `--check` only reports. Exit `1` on drift, an invalid catalog, or a member's hosted dependency the
  catalog does not pin.

## docs_check

`dart tools/docs_check/check.dart` is Gate 5: every repo path and relative link in every `*.md` exists, en ↔ vi parity
(same count of headings per level, fenced code blocks and table rows), every `RULE-NN` is a registry row. Exit `1` on a
dead reference, a parity mismatch or an unknown/duplicate rule id. `--verbose` adds an allowlist block;
`--stale-translations` lists `docs/vi` files behind their English source (advisory, exit `0`);
`--stamp-translations docs/vi/<file>.md` stamps a synced translation — commit the English change first.
Workflow: [`update_docs`](../update_docs/SKILL.md).

## remove_sample

`dart tools/sample_cleanup/remove_sample.dart --list` classifies every package (`framework`, `sample`, `shell`);
`<bundle>` is a dry run that writes nothing; `<bundle> --apply` removes the bundle, runs `composer reconcile` (declares `absent` every capability whose last provider is gone) and then
`composer sync`; with every bundle gone `modules/` keeps only `.gitkeep`. Bundles: `auth`, `home`, `settings`, `onboarding`, `dashboard`,
`splash`, `cache`. It keeps a bundle's `<id>_api` while another package imports it. Exit `1`: failed partway
(shared files rolled back; deleted directories are not); `64`: unknown flag or bundle. A module you generated is not
a sample: [`remove_module`](../remove_module/SKILL.md).

## Unused checker

- `check_unused_packages.dart` is a **blocking** CI step (a declared dependency nothing imports, RULE-06); exit `2`
  on findings, `1` on failure or no packages, `0` clean. `check_script.dart` runs all four checks (assets,
  translations, files, packages) and exits `0` unless a check failed.
- The asset, file and translation checks are **advisory** text matches. Confirm before deleting: a file may be
  reached only through a barrel, a `part` directive or build output; an asset may be referenced from an `.arb` or
  native code.
- The `cache` sample module has no production caller on purpose — remove it with `remove_sample cache --apply`,
  not on the checker's word.

## Setup and partial checkouts

- `dart tools/workspace_setup/configure.dart` on a fresh clone: `flutter pub get`, `flutter gen-l10n` in every package
  with an `l10n.yaml`, `dart run build_runner build --workspace`, then the barrels (only needed after a `lib/` file
  changes; harmless otherwise). It stops at the first failing command; there is no `configure.sh` / `.bat`.
  `--stub-firebase` first writes compile-only `lib/firebase/firebase_options_<flavor>.dart` where none exists (what CI runs).
- `dart tools/composer/bootstrap.dart [--dry-run]` in a partial checkout prunes composer-managed entries whose directory
  has no `pubspec.yaml`, so `pub get` can resolve; then `pub get`, `composer sync`, `configure.dart`. Exit `1`: no managed
  region, or a present package depends on a missing one.

## Coverage

`flutter test --coverage` in each package, then `dart tools/coverage_report/report.dart [--min <pct>] [--min-package <pct>]`:
per-package line coverage from every `*/coverage/lcov.info`. Advisory in CI; exit `1` on a missed threshold or no
`lcov.info`.

## Tests for the tools

`cd tools && dart test` runs every gate tool against throwaway workspaces, asserting exit code and output (CI Gate 1).
When you change a gate tool (`arch_check`, `composer`, `docs_check`, `dependency_sync`, the barrel generator, …) add the
case that would have caught the bug (RULE-64).

## AI code review

```bash
dart tools/code_review/code_review.dart --changed                    # uncommitted changes (default choice)
dart tools/code_review/code_review.dart --staged                     # what is staged
dart tools/code_review/code_review.dart --file <path> --file <path>  # specific files
dart tools/code_review/code_review.dart --folder modules/home/feature/lib
dart tools/code_review/code_review.dart --all --focus architecture   # slow
```

- Needs a Gemini key: `GEMINI_API_KEY`, `--api-key`, or the gitignored `tools/code_review/.gemini_api_key`. On a
  terminal it prompts when none is found; **without a terminal it exits `1`**, so set the environment variable. Never
  write a key into `code_review_config.json`. It is advisory and never a merge gate.
- Its checklist is `tools/code_review/review_prompt.md`, built from the rule registry. When you relay findings, cite the
  `RULE-NN` the reviewer names and link [`01_rules.md`](../../../docs/en/reference/01_rules.md) rather than paraphrasing.
  For a human-style review use [`04_review_checklist.md`](../../../docs/en/reference/04_review_checklist.md).

## Verify

```bash
dart tools/arch_check/check.dart                         # Gate 1
cd tools && dart test                                    # Gate 1 (cont.) — after any change to a tool
dart tools/composer/composer.dart verify                 # Gate 0
dart tools/dependency_sync.dart --check                  # Gate 4
dart tools/docs_check/check.dart                         # Gate 5
dart tools/unused_checker/check_unused_packages.dart     # blocking audit
```

The package tests, `flutter analyze`, the DI smoke test and the debug APK are named in each task's own skill.
