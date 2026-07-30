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
