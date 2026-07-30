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

Use the `run_command` tool to execute the scripts. Remind the user to run `flutter pub get` if modifications were made to the `pubspec.yaml` files.
