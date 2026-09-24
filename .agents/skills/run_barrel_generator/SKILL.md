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

Run the command in the shell, from the repository root, and report the status. A path that does
not exist exits with code `64` (it prompts for another path only when run with no argument on a
terminal); a failing `dart format` (run through the repo's toolchain, FVM when set up) exits `1`
with the barrels written but unformatted; a flag or a second path exits `64` — a flag is never
taken for a path. Check the exit code. `--help` prints the usage.

## Notes

- Pass the package's **`lib` directory**, one package per run. Re-run for every package you
  touched (e.g. both `modules/x/domain/lib` and `modules/x/data/lib`).
- It skips `*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*_test.dart`, `firebase_options*`,
  and any file declaring `part of`. Other generated files **are** exported when present:
  `module.module.dart`, `injection.config.dart` (harmless), and the gen-l10n / flutter_gen
  output under `lib/src/gen/` — that one is load-bearing: `core_ui_kit` reaches `Assets`
  through `core_base_ui`'s barrel.
- It rewrites the `export` lines of each barrel. **Hand-written `export` statements in a
  barrel will be removed.** If a file must re-export something manually, put that export in a
  normal source file instead — this is why
  `platform/foundation/kernel/lib/src/error/failures.dart` (the `AppFailure` compatibility shim)
  is a regular file, not a barrel.
- New `utils/` folders get their own `utils.dart` barrel automatically, wired into `src.dart`.
- Run it **after** `build_runner` and `gen-l10n`, as `tools/workspace_setup/configure.dart`
  does. Run before them, the generated exports above are missing from the barrels.
