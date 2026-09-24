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
| An import is used but maybe not declared | `dart tools/arch_check/check.dart` (R5) | RULE-06 |
| A dependency is declared but maybe unused | `dart tools/unused_checker/check_unused_packages.dart` | RULE-06 |
| Clean up dead files, assets, translations | `dart tools/unused_checker/check_script.dart` | — |
| Propose version upgrades | `dart tools/check_outdated.dart` | — |
| Review a change with the AI reviewer | `dart tools/code_review/code_review.dart --changed` | — |

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
