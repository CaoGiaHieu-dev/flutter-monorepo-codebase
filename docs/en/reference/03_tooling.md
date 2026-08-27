# Tooling Reference

**This file answers:** which script do I run, with what arguments, and when?

**After reading you can:** pick the right tool for any maintenance task and know its failure modes before it bites you.

All tools live in `tools/` and are plain Dart — run them from the **repository root**.

---

## Problem → tool

| Problem | Command |
|---|---|
| Create a new feature / domain / data / core package | `dart tools/module_generator/generate.dart …` |
| Added, renamed or deleted a file under `lib/` | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Changed a dependency version | `dart tools/dependency_sync.dart` |
| CI needs to reject version drift | `dart tools/dependency_sync.dart --check` |
| Suspect dead assets / files / translations / packages | `dart tools/unused_checker/check_script.dart` |
| Want to know what is outdated on pub.dev | `dart tools/check_outdated.dart` |
| Fresh clone, need everything wired up | `dart tools/workspace_setup/configure.dart` |
| Set up Firebase for dev / staging / prod | `dart tools/firebase/firebase_config.dart` |
| Regenerate splash screen and app icons | `dart tools/theme_generator/theme_setting.dart` |
| Check Android 15+ 16 KB page-size compliance | `./tools/android_compliance/16kb_ckeck.sh` |
| AI review of a change | `dart tools/code_review/code_review.dart --changed` |

---

## `module_generator`

Scaffolds a package and registers it across the workspace.

```bash
dart tools/module_generator/generate.dart <type> <name> [<dir>] [<sm>] [<route>]
```

| Arg | Values |
|---|---|
| `<type>` | `1` feature · `2` domain · `3` data · `4` core · `5` custom |
| `<name>` | bare directory name (`profile`) — the package becomes `feature_profile` |
| `<dir>` | only for type `5` |
| `<sm>` | feature only — `1` Provider · `2` BLoC · `3` none |
| `<route>` | feature only — `1` `IFeatureRouteModule` · `2` `IDashboardTabModule` · `3` none |

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1   # feature + Provider + stack route
dart tools/module_generator/generate.dart 1 chat    "" 2 2   # feature + BLoC + bottom-nav tab
dart tools/module_generator/generate.dart 2 payment          # domain micro-package
dart tools/module_generator/generate.dart 3 payment          # data micro-package
```

Run with fewer arguments and it prompts interactively.

**What it does:** creates the directory tree (including `lib/src/utils/`, for every layer), renders templates, adds the package to the root `workspace:` list and `app/pubspec.yaml`, registers the DI module in `app/lib/di/injection.dart`, then runs dependency sync, `pub get`, `gen-l10n`, the barrel generator, `build_runner`, and `dart fix --apply`.

**Safety behaviour**

- **Toolchain is verified first.** `assertToolchainAvailable()` runs before anything shared is touched, so a missing SDK fails immediately instead of at step 8.
- **Existing directories are refused.** It will not silently overwrite a package.
- **Rollback on failure.** The three shared files (root `pubspec.yaml`, `app/pubspec.yaml`, `app/lib/di/injection.dart`) are snapshotted before any write; if a later step fails they are restored and the new module directory is deleted.
- **FVM is auto-detected**, requiring *both* a config file (`.fvmrc` or `.fvm/fvm_config.json`) *and* a working `fvm --version`. Either signal alone gives a wrong answer: this repo pins a version in `.fvmrc` while a given machine may not have `fvm` installed at all.

> [!NOTE]
> Domain and data modules get directories and pubspec wiring only — entities, use cases and repositories are written by hand. See [`../guides/02_new_domain_data.md`](../guides/02_new_domain_data.md).

---

## `barrel_generator`

```bash
dart tools/barrel_generator/generate.dart packages/<layer>/<package>/lib
```

Regenerates `*.dart` barrels for every directory under the given path, then formats. Run it after **any** file add / rename / delete under `lib/`.

Skips `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, and files declaring `part of`.

> [!CAUTION]
> It **removes every hand-written `export` line** from a barrel before regenerating. If you need to re-export something from another package, put the `export` in a regular source file and let the barrel pick that file up.

---

## `dependency_sync`

`pubspec_dependencies.yaml` at the repo root is the single source of truth for versions.

```bash
dart tools/dependency_sync.dart          # write versions into every package
dart tools/dependency_sync.dart --check  # verify only; exits 1 on drift
```

Also repairs broken local `path:` entries. Use `--check` in CI and pre-commit.

> [!NOTE]
> It parses line-by-line rather than with a YAML parser, so `dependency_overrides` and multi-line/anchor syntax are not handled. Native Gradle dependencies (e.g. `play-services-auth` in `app/android/app/build.gradle.kts`) are outside its scope entirely — they have no single source of truth.

---

## `unused_checker`

```bash
dart tools/unused_checker/check_script.dart              # all four, with a summary
dart tools/unused_checker/check_unused_assets.dart       # assets not referenced
dart tools/unused_checker/check_unused_translate.dart    # .arb keys never used
dart tools/unused_checker/check_unused_file.dart         # orphaned Dart files
dart tools/unused_checker/check_unused_packages.dart     # declared but unused deps
```

`check_unused_packages.dart` is the one that enforces [rule 2](01_rules.md#2-explicit-dependency-declaration) — run it before every PR.

> [!WARNING]
> The asset / file / translation checkers work by textual reference and will report false positives for anything reached dynamically (a string-built asset path, a key looked up at runtime). Confirm before deleting.

---

## `check_outdated`

```bash
dart tools/check_outdated.dart
```

Reports packages with newer versions on pub.dev. Update `pubspec_dependencies.yaml`, then run `dependency_sync`.

---

## `workspace_setup`

```bash
dart tools/workspace_setup/configure.dart
```

Full setup for a fresh clone: activates `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n`, `build_runner`.

> [!CAUTION]
> There is **no** `configure.sh` and **no** `configure.bat`. Only `configure.dart` exists. Older docs and CI steps referencing the shell wrappers were broken and have been corrected.

---

## `firebase`

```bash
dart tools/firebase/firebase_config.dart
```

Runs `flutterfire configure` for each flavour, producing the three `firebase_options_*.dart` files that `packages/core/common/lib/src/firebase/firebase_module.dart` imports.

> [!WARNING]
> Those generated files are git-ignored, and `firebase_module.dart` imports **all three unconditionally**. A fresh clone therefore does not compile until this has been run — even for a dev-only build. See [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Must be run from the repository root; the script checks for `pubspec.yaml` and exits otherwise.

---

## `theme_generator`

```bash
dart tools/theme_generator/theme_setting.dart
```

Drives `flutter_native_splash` and `icons_launcher` from the per-flavour configs at the repo root (`flutter_native_splash-*.yaml`, `icons_launcher-*.yaml`).

---

## `android_compliance`

```bash
./tools/android_compliance/16kb_ckeck.sh    # macOS / Linux
.\tools\android_compliance\16kb_ckeck.bat   # Windows
```

Checks native `.so` libraries for Android 15+ 16 KB page-size alignment. The only tools in the repo that are shell scripts rather than Dart.

> [!NOTE]
> The filename really is `16kb_ckeck` — a typo that is preserved because scripts and docs reference it.

---

## `code_review`

```bash
dart tools/code_review/code_review.dart --all
dart tools/code_review/code_review.dart --changed
dart tools/code_review/code_review.dart --file app/lib/main.dart
dart tools/code_review/code_review.dart --all --focus architecture,security
```

Gemini-backed review driven by `tools/code_review/review_prompt.md`. Needs an API key in `tools/code_review/code_review_config.json` (ships empty; do not commit a real key).

> [!NOTE]
> The GitHub workflow runs this in **advisory mode** — its "fail on critical issues" step has `exit 1` commented out, so it never blocks a PR. See [`../operations/01_cicd.md`](../operations/01_cicd.md).

---

## Known inconsistency

`tools/workspace_setup/configure.dart` and `tools/theme_generator/theme_setting.dart` detect FVM by checking **only** `.fvm/fvm_config.json`. This repo pins its version in `.fvmrc`, which those two scripts do not look at, so they always fall through to the global `dart` / `flutter`. That happens to be correct on a machine without FVM, but it is not the robust detection that `module_generator` now performs.

---

**Next:** [`04_review_checklist.md`](04_review_checklist.md) · [`01_rules.md`](01_rules.md) · [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md)
