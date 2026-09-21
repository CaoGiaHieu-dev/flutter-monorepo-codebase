---
name: run_barrel_generator
description: Guide for running the barrel file generator script to automatically update export entrypoints.
---

# 📦 Run Barrel Generator

The project automatically generates `*.dart` exports at the root of packages to manage monorepo entrypoints.

## Execution Instructions

When a developer adds, deletes, or renames files under a package's `lib` directory, or when requested to "generate barrel files", "update exports", etc.:

1. Run the generator script using Dart:
   ```bash
   dart tools/barrel_generator/generate.dart <path_to_lib_directory>
   ```
   *Example: `dart tools/barrel_generator/generate.dart modules/home/feature/lib`*

Use the `run_command` tool to execute the command and report the status.

## Notes

- Pass the package's **`lib` directory**, one package per run. Re-run for every package you
  touched (e.g. both `modules/x/domain/lib` and `modules/x/data/lib`).
- The generator skips generated and non-public files: `*.g.dart`, `*.freezed.dart`,
  `*.mocks.dart`, `*_test.dart`, and any file declaring `part of`.
- It rewrites the `export` lines of each barrel. **Hand-written `export` statements in a
  barrel will be removed.** If a file must re-export something manually, put that export in a
  normal source file instead — this is why
  `platform/kernel/lib/src/error/failures.dart` (the `AppFailure` compatibility shim)
  is a regular file, not a barrel.
- New `utils/` folders get their own `utils.dart` barrel automatically, wired into `src.dart`.
- Run it **before** `build_runner` when you have added files, so codegen sees the new exports.
