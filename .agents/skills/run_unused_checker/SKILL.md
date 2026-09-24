---
name: run_unused_checker
description: Guide for running the project's unused asset, package, and file detector script suite.
---

# 🧹 Run Unused Checker Suite

The project includes an automated suite of scripts to detect unused code, assets, packages, and translation strings.

## Execution Instructions

When a developer requests to "clean up project", "find dead code", "check unused assets", etc.:

1. Run the overall checker suite (recommended):
   ```bash
   dart tools/unused_checker/check_script.dart
   ```
   *This command runs all checks including unused assets, packages, translation strings, and files.*

2. To run checks on specific components only:
   - Dead/unused files: `dart tools/unused_checker/check_unused_file.dart`
   - Unused packages: `dart tools/unused_checker/check_unused_packages.dart`
   - Unused assets: `dart tools/unused_checker/check_unused_assets.dart`
   - Unused translations: `dart tools/unused_checker/check_unused_translate.dart`

Run the scripts in the shell, from the repository root. After completion, present a summary of the cleanup recommendations.

## Notes

- `check_unused_packages.dart` finds dependencies a package **declares but never imports**
  (it scans `lib/`, `bin/`, `test/` and `tool/`, and reads a package with no `lib/` — `core_tools` — whole). The opposite mistake — importing a package you never
  declared, which still compiles because Pub Workspaces share one `package_config.json` — is
  caught by `dart tools/arch_check/check.dart` rule **R5**, not by this tool.
- Results are **advisory**. Verify before deleting: a file can look orphaned while being
  reachable only through a barrel, a `part` directive, or `build_runner` output; an asset can
  be referenced from an `.arb` file or from native Android/iOS code.
- Known intentional "unused" items in the template — do **not** delete on the tool's word alone:
  - the `cache` sample module (`CacheEntriesDao` → `CacheEntryLocalDataSource` →
    `CacheEntryRepositoryImpl` → the two cache use cases) is reference/test scaffolding with
    no production caller — remove it with `dart tools/sample_cleanup/remove_sample.dart cache --apply` if you do not want it;
- Run it before a release and after removing a feature package.
