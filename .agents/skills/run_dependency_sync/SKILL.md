---
name: run_dependency_sync
description: Guide for running the dependency version synchronization tool across the monorepo workspace.
---

# 📦 Run Dependency Sync & Checker

This codebase manages library dependency versions centrally via `pubspec_dependencies.yaml`.

## Execution Instructions

### 1. Synchronize Version Configurations
When requested to "update dependency versions", "sync dependencies", or after manually updating package versions inside `pubspec_dependencies.yaml`:

To push (overwrite) versions from the centralized catalog to all sub-packages:
```bash
dart tools/dependency_sync.dart
```

To run a dry-run check without updating the files:
```bash
dart tools/dependency_sync.dart --check
```

### 2. Check for Outdated Packages on pub.dev
When requested to "check outdated packages", "check library updates", or when proposing version upgrades:
```bash
dart tools/check_outdated.dart
```

### 3. Detect Undeclared / Unused Package Dependencies
Pub Workspaces share a single `package_config.json`, so a package you **use but never
declare** still compiles — and breaks as soon as it is extracted or published. Catch this
with:
```bash
dart tools/unused_checker/check_unused_packages.dart
```
Fix by adding the missing entry to the consuming `pubspec.yaml` (in `dependencies`, not
`dev_dependencies`, when production code uses it), or removing the unused one.

Use the `run_command` tool to execute the scripts. Remind the user to run `flutter pub get` if modifications were made to the `pubspec.yaml` files.

## Notes

- `pubspec_dependencies.yaml` is the single source of truth for **shared pub.dev versions**.
  Never hardcode a version in a package's `pubspec.yaml` — edit the catalog and re-sync.
- It does **not** manage local `path:` dependencies between workspace packages, nor native
  Gradle/CocoaPods dependencies — those are edited by hand.
- `--check` exits non-zero on drift, so it is the form to use in CI / pre-commit hooks.
- Workspace setup (`flutter pub get` + codegen + l10n in one go):
  ```bash
  dart tools/workspace_setup/configure.dart
  ```
  There is **no** `configure.sh` / `configure.bat` — that script does not exist.
