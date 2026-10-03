---
name: run_repo_tooling
description: Use when a task needs one of the repo's maintenance tools — regenerating barrel files after adding, renaming or deleting a lib/ file; syncing or checking dependency versions against pubspec_dependencies.yaml; finding unused files, assets, translations or packages; checking pub.dev for outdated packages; or running the Gemini AI code review. Covers which tool to run, from where, and how to read its exit code.
---

# Run repo tooling

Every tool runs from the **repository root** with plain `dart` (no `fvm` prefix — RULE-73), and
every tool takes `--help`. An unknown argument exits `64`. The full reference, including each
tool's edge cases and exit codes, is [`docs/en/reference/03_tooling.md`](../../../docs/en/reference/03_tooling.md).

| Situation | Command | Rule |
|:--|:--|:--|
| Added, renamed or deleted a file under a package's `lib/` | `dart tools/barrel_generator/generate.dart <package>/lib` | RULE-75 |
| Changed a version in `pubspec_dependencies.yaml` | `dart tools/dependency_sync.dart` | RULE-74 |
| Verify versions only (CI, pre-commit) | `dart tools/dependency_sync.dart --check` | RULE-74 |
| Edited an `app_manifest.yaml` | `dart tools/composer/composer.dart sync --app <id>`, then `verify` | RULE-16, RULE-81 |
| Read what an app declares and what the shell resolves from it (who implements each contract) | `dart tools/composer/composer.dart describe --app <id>` | RULE-80, RULE-81 |
| Look up a manifest key, a contract id, a derived default, a check or a problem code | `dart tools/composer/composer.dart describe --catalog` | — |
| Create a third app | `dart tools/composer/composer.dart new <id> --platforms <a,b> [--modules <x,y>]` | RULE-80 |
| An import is used but maybe not declared | `dart tools/arch_check/check.dart` (R5) | RULE-06 |
| A dependency is declared but maybe unused | `dart tools/unused_checker/check_unused_packages.dart` | RULE-06 |
| Clean up dead files, assets, translations | `dart tools/unused_checker/check_script.dart` | — |
| Propose version upgrades | `dart tools/check_outdated.dart` | — |
| Review a change with the AI reviewer | `dart tools/code_review/code_review.dart --changed` | — |

## Composer: describe and new

- `describe --app <id>` prints the report that also sits in the app's `README.md` (generated, between
  `composer:managed:report` markers — never edit it). `describe --catalog` is the key reference: every
  manifest key with its default and its reader, the 22-row contract catalog, the derived defaults, the
  pubspec keys, checks V1–V14 and problem codes P01–P05 / C01–C09. Do not copy that table into prose.
- `new` renders `tools/composer/app_template/` into `apps/<id>/`, derives `capabilities:` from what the
  requested modules register, then runs `sync` and `verify`. It refuses an existing id or a platform a
  module blocks **before writing anything**, and it **never runs `flutter create`**: it prints the line
  (`cd apps/<id> && flutter create --platforms=… --org com.example --project-name <id>_app .`) for you
  to run when a runner is wanted. Afterwards: `flutter pub get`, `dart run build_runner build
  --workspace`, `cd apps/<id> && flutter test`. See the `configure_app` skill.
- `verify` is Gate 0 and does more than drift: it holds the declaration to the source (V3, V7, V10–V12).
  `sync` prints those as warnings and still writes; `verify` fails on them.

## Barrel generator

- Pass one package's **`lib` directory** per run; re-run for every package you touched
  (both `modules/<name>/domain/lib` and `modules/<name>/data/lib`).
- Run it **after** `dart run build_runner build --workspace` and `flutter gen-l10n`: it exports the
  generated files present on disk, so running it first drops those exports.
- It deletes every hand-written `export` line. A deliberate re-export goes in a normal source file
  (see `platform/foundation/kernel/lib/src/error/failures.dart`).
- Exit `64`: missing path, a flag, or a second path. Exit `1`: `dart format` failed (barrels written, unformatted).

## Dependency sync

- The catalog holds shared pub.dev versions only; workspace packages use `path:` entries, which the
  tool repairs when they point at the wrong directory. Native Gradle / CocoaPods dependencies are
  edited by hand.
- After a sync, tell the user to run `flutter pub get` and commit the updated `pubspec.lock`.
- Workspace setup is `dart tools/workspace_setup/configure.dart` — there is no `configure.sh` / `.bat`.

## Unused checker

- Results are **advisory**. Confirm before deleting: a file may be reached only through a barrel, a
  `part` directive or build output; an asset may be referenced from an `.arb` or native code.
- The `cache` sample module has no production caller on purpose — remove it with
  `dart tools/sample_cleanup/remove_sample.dart cache --apply`, not on the checker's word.
- Run it before a release and after removing a module.

## AI code review

```bash
dart tools/code_review/code_review.dart --changed                    # uncommitted changes (default choice)
dart tools/code_review/code_review.dart --staged                     # what is staged
dart tools/code_review/code_review.dart --file <path> --file <path>  # specific files
dart tools/code_review/code_review.dart --folder modules/home/feature/lib
dart tools/code_review/code_review.dart --all --focus architecture   # slow
```

- Needs a Gemini key: `GEMINI_API_KEY`, `--api-key`, or the gitignored
  `tools/code_review/.gemini_api_key`. In an agent shell there is no prompt — without a key it
  exits `1`; set the environment variable. Never write a key into `code_review_config.json`.
- Its checklist is `tools/code_review/review_prompt.md`, built from the rule registry. When you
  relay findings, cite the `RULE-NN` the reviewer names and link
  [`01_rules.md`](../../../docs/en/reference/01_rules.md) rather than paraphrasing the rule.
- For a human-style review of the same change, use
  [`04_review_checklist.md`](../../../docs/en/reference/04_review_checklist.md).
