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

Use the `run_command` tool to execute the scripts. After completion, present a summary of the cleanup recommendations.

## Notes

- `check_unused_packages.dart` is the one that also catches **architectural** mistakes, not
  just bloat: it compares each package's declared dependencies against what its `lib/`
  actually imports. Because Pub Workspaces share one `package_config.json`, an *undeclared*
  dependency still compiles — this is how you find it. Keep it green.
- Results are **advisory**. Verify before deleting: a file can look orphaned while being
  reachable only through a barrel, a `part` directive, or `build_runner` output; an asset can
  be referenced from an `.arb` file or from native Android/iOS code.
- Known intentional "unused" items in the template — do **not** delete on the tool's word alone:
  - the sample cache chain (`CacheEntriesDao` → `CacheEntryLocalDataSource` →
    `CacheEntryRepositoryImpl` → the three cache use cases) is reference/test scaffolding with
    no production caller;
  - `AuthRemoteDataSource` is a Retrofit reference that the live Firebase-backed
    `AuthRepositoryImpl` does not call.
- Run it before a release and after removing a feature package.
