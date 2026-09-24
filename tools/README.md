🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# 🛠️ Development Tools

This folder holds the developer CLI tools that automate the workflow and keep code quality up in this Flutter Clean Architecture monorepo. `tools/` is a workspace member (package `core_tools`, see `tools/pubspec.yaml`), so every tool runs after a root `flutter pub get`. **Always run them from the repository root.**

Full reference (arguments, exit codes, failure modes of each tool): [`docs/en/reference/03_tooling.md`](../docs/en/reference/03_tooling.md).

> **Rule**: CLI tools in this folder **must not** use `print()`. Use `stdout.writeln()` and `stderr.writeln()`. A tool that shells out to `dart` / `flutter` detects FVM through `tools/shared/toolchain.dart` — never hardcode an `fvm` prefix.

---

## 📁 Directory Structure

```text
tools/
├── pubspec.yaml                     # The core_tools package (a workspace member)
├── arch_check/                      # 🛡️ Enforces the layering rules (CI Gate 1)
│   └── check.dart                   # R1-R10: dependency direction, pure-Dart domain, feature boundaries, scaling through context…
├── composer/                        # 🧩 Composes apps from app_manifest.yaml (CI Gate 0)
│   ├── composer.dart                # sync / verify / list — generates the workspace list, app dependencies, injection.dart
│   └── bootstrap.dart               # Partial checkout: prunes absent members so `pub get` resolves (no package imports)
├── docs_check/                      # 📚 Every path the docs name must exist (CI Gate 5)
│   ├── check.dart
│   └── allowlist.txt                # Deliberately absent paths, each with its reason
├── shared/                          # 🔗 Code shared between tools
│   ├── app_locator.dart             # Finds apps by app_manifest.yaml, picks one with --app <id>
│   └── toolchain.dart               # FVM detection (.fvmrc + `fvm --version`) for every tool that runs dart/flutter
├── sample_cleanup/                  # 🧹 Classifies and safely removes sample code
│   └── remove_sample.dart           # --list / dry-run / --apply, with rollback
├── sample_manifest.yaml             # 📑 Source of truth: which package is sample/framework/shell
├── module_generator/                # 🏗️ New-module CLI (Feature/Domain/Data/Core/Custom)
│   ├── generate.dart                # Main entry point
│   ├── src/
│   │   ├── input_actions.dart       # CLI arguments & interactive input, name validation
│   │   ├── module_type.dart         # ModuleType, StateManagementType, FeatureRouteContribution enums; ModuleConfig
│   │   ├── pubspec_generator.dart   # Generates pubspec.yaml with the right dependencies for the layer
│   │   └── common_helpers.dart      # Creates folders/templates, writes app_manifest.yaml, runs commands, rollback
│   └── templates/                   # Mustache templates (common, domain, data, feature/{bloc,provider,default,routing,localization})
├── barrel_generator/                # 📦 Generates barrel files (export *.dart)
│   └── generate.dart                # Scans lib/ and writes the barrels
├── code_review/                     # 🤖 AI-powered code review (Gemini)
│   ├── code_review.dart             # Entry point
│   ├── lib/                         # The tool's core
│   ├── review_prompt.md             # The detailed AI prompt
│   ├── code_review_config.json      # Settings (language, batching) — never holds the API key
│   └── README.md                    # Detailed docs (README.vi.md: Vietnamese)
├── unused_checker/                  # 🧹 Finds and cleans up unused resources
│   ├── check_script.dart            # Runs every check at once
│   ├── check_unused_assets.dart     # Unused assets
│   ├── check_unused_file.dart       # Orphaned files
│   ├── check_unused_packages.dart   # Packages declared but never imported
│   ├── check_unused_translate.dart  # Unused translation keys
│   ├── monorepo_helper.dart         # Shared: repo root, package discovery
│   └── output_formatter.dart        # Shared: output formatting
├── workspace_setup/                 # ⚙️ Whole-workspace setup
│   └── configure.dart               # Cross-platform script (Windows/macOS/Linux)
├── firebase/                        # 🔥 Multi-environment Firebase configuration
│   └── firebase_config.dart
├── theme_generator/                 # 🎨 Splash screen & app icons
│   └── theme_setting.dart
├── android_compliance/              # 📱 Android 15+ 16KB page-size check
│   ├── 16kb_ckeck.sh                # macOS/Linux (the actual implementation)
│   └── 16kb_ckeck.bat               # Windows — runs the .sh through Git Bash
├── dependency_sync.dart             # 📦 Syncs dependency versions from the catalog (Gate 4 with --check)
└── check_outdated.dart              # 🔄 Checks for outdated packages on pub.dev
```

---

## 🚀 Quick Usage

### 🛡️ Architecture Check (layering rules)
```bash
# Check the 10 architecture rules (R1–R10) — exits 1 on a violation (CI-ready):
dart tools/arch_check/check.dart

# Full description of each rule:
dart tools/arch_check/check.dart --help
```

It runs before `flutter analyze` in CI: it only reads imports and pubspecs and needs no codegen,
so it finishes in a few hundred ms (the tool prints its own timing), and it is the only thing that
can see layering — `analysis_options.yaml` has no idea that core must not import a feature. Any
argument other than `--help` is refused (exit 64).

R7 is also beyond the analyzer. `core_responsive` ships no extension on `num`, so `16.h` does not
compile — but an extension left over in another package, or one someone adds, would still
type-check while reading a global that notifies nobody. Only `context.h(16)` registers an
`InheritedWidget` dependency and rebuilds when the metrics change.

### 🧩 Composer (composing apps from manifests)
```bash
# Regenerate the workspace list, each app's dependencies and injection.dart from every app_manifest.yaml:
dart tools/composer/composer.dart sync

# Check only (CI Gate 0) — exits 1 on drift, writes nothing; implies --strict:
dart tools/composer/composer.dart verify

# Show what an app composes (--app narrows to one app; works with list/sync/verify):
dart tools/composer/composer.dart list --app admin
```

Only the region between the `composer:managed` and `composer:end` markers is generated; the rest
of those files stays hand-written. `--strict` turns a module declared in a manifest but absent
from disk into an error instead of a warning. An unknown command or flag is refused (exit 64). A
pubspec/manifest that is not valid YAML (usually a duplicate key) is refused with the file and line
instead of crashing; a package both inside the `composer:managed:deps` region and declared by hand
gets its own message. A structurally invalid manifest (a `phase` other than `before`/`after`, an
unknown layer, a duplicate id, an unknown key, …) is refused before any command with
`apps/<id>/app_manifest.yaml: <key>: <problem>`, exit 1, nothing written. When a module declared in
a manifest is not on disk, the PARTIAL COMPOSITION warning lists only the files that run actually
rewrote.

```bash
# Partial checkout (a module submodule not initialised): composer needs a resolved workspace, and pub
# refuses one that lists a member with no pubspec.yaml. This imports no package, so it runs first:
dart tools/composer/bootstrap.dart            # --dry-run to report only
flutter pub get
dart tools/composer/composer.dart sync
dart tools/workspace_setup/configure.dart
```

`bootstrap` only removes — from the root `composer:managed:workspace` region and each app's
`composer:managed:deps` region — entries whose directory has no `pubspec.yaml`, and prints the
`git checkout --` line that undoes it. A full checkout has nothing to prune (exit 0, nothing
written). Exit 1, nothing written, when a present package has a hand-written path dependency on a
missing one — initialise that submodule too. See `docs/en/guides/12_module_isolation.md` § 3.

### 📚 Docs Check (paths named in the docs)
```bash
# Every repo path a Markdown file names must exist — CI Gate 5:
dart tools/docs_check/check.dart

# Plus a copy-paste allowlist block for the dead references:
dart tools/docs_check/check.dart --verbose
```

It checks every `*.md` in the repository: backticked spans that start with a real top-level
directory, and Markdown links (resolved relative to the file containing them). Deliberately absent
paths (generated files, secrets, "create this file yourself") live in
`tools/docs_check/allowlist.txt` with their reason. Exits 1 on an unexplained dead reference, 64 on
an unknown argument.

### 🧹 Sample Cleanup (removing sample code)
```bash
# Which packages are sample, framework or shell:
dart tools/sample_cleanup/remove_sample.dart --list

# Preview removing the 'auth' bundle (dry-run by default, writes nothing):
dart tools/sample_cleanup/remove_sample.dart auth

# Remove it for real:
dart tools/sample_cleanup/remove_sample.dart auth --apply

# List every documentation reference that will go dead (only the first 15 by default):
dart tools/sample_cleanup/remove_sample.dart auth --verbose
```

The dry-run also prints which other samples would break and where — information the manual
feature-removal guide cannot give you.

Both the dry-run and `--apply` count the documentation references (`docs/`, `.agents/`, every
`*.md`) to paths about to be deleted. They are informational: after the removal,
`dart tools/docs_check/check.dart` (CI Gate 5) recognises them as pointing into a removed sample
bundle (every package of the bundle absent, per `tools/sample_manifest.yaml` — the removal tool
never edits that file), prints one INFO line per bundle and still passes. Fix those docs whenever
convenient. An unknown flag (e.g. `--aply`) or a wrong bundle name is refused with exit 64 rather
than ignored. Bundles: `auth`, `home`, `settings`, `onboarding`, `cache`, `dashboard`, `splash`.


### 🏗️ Module Generator (new modules)
```bash
# Syntax: dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<SM>] [<route>]
# <type>: 1=Feature, 2=Domain, 3=Data, 4=Core (core_<name>), 5=Custom
# <prefix> (Custom only): package-name prefix -> <prefix>_<name> at platform/<name>; pass "" for other types
# <SM> (Feature only): 1=Provider, 2=BLoC, 3=None
# <route> (Feature only): 1=IFeatureRouteModule, 2=INavDestinationModule (primary nav tab), 3=none
# Pick 2 only for a primary tab after sign-in — see docs/{en,vi}/guides/04_routing.md.

# Feature 'profile' + Provider + stack routes (IFeatureRouteModule):
dart tools/module_generator/generate.dart 1 profile "" 1 1

# Feature 'chat' + BLoC + primary nav tab (INavDestinationModule):
dart tools/module_generator/generate.dart 1 chat "" 2 2

# Domain micro-package 'payment':
dart tools/module_generator/generate.dart 2 payment

# Data micro-package 'payment':
dart tools/module_generator/generate.dart 3 payment

# Core package 'logging' (core_logging at platform/logging):
dart tools/module_generator/generate.dart 4 logging

# Custom package 'billing' with prefix 'acme' (acme_billing at platform/billing):
dart tools/module_generator/generate.dart 5 billing acme

# Interactive (no arguments, needs a terminal):
dart tools/module_generator/generate.dart

# Show the syntax:
dart tools/module_generator/generate.dart --help
```

The CLI adds the module to every `app_manifest.yaml` (Feature/Domain/Data to the `modules:` list,
Core/Custom to the `core` DI group), scaffolds the route DI stub, then **runs by itself**
`dart tools/composer/composer.dart sync` (regenerating the workspace list, the apps' dependencies
and `injection.dart`), `dependency_sync`, `flutter pub get`, `gen-l10n` (Feature only), the barrel
generator, `build_runner`, the barrel generator again (so generated files are exported too), and
`dart fix --apply`. There is no need to run composer sync by hand.
There is **no** need (and you **should not**) edit a `$…Route` list in `app_router.dart` — the host
collects routes through DI. A failure midway rolls back and exits 1.

Arguments are validated **before** anything is written (an error → exit 64 with the usage):
- `<name>` (and `<prefix>`) must be a valid Dart package name: lowercase letters, digits, `_`, starting with a letter, not a Dart keyword (`Bad-Name` is refused at once); a package name already in the repo is refused too.
- `<SM>` and `<route>` accept only `1`/`2`/`3`; `<prefix>`, `<SM>`, `<route>` passed to the wrong module type are refused; unknown flags are refused.
- A feature missing `<SM>` or `<route>` is prompted for the missing value on a terminal (empty = `1`); with no terminal (or stdin at end of input) it fails instead of silently taking a default.
- Adding to `app_manifest.yaml` parses the manifest as YAML (no substring matching — `core_net` is no longer taken as "already present" because of `core_network`); if a manifest cannot be updated the tool exits 1 and rolls back.

### 📦 Barrel Files Generator
```bash
# Generate for one package:
dart tools/barrel_generator/generate.dart modules/profile/feature/lib

# Generate for a domain micro-package:
dart tools/barrel_generator/generate.dart modules/auth/domain/lib

# Show the syntax:
dart tools/barrel_generator/generate.dart --help
```

Without a path it uses `lib`. Run it **after** `gen-l10n` / `build_runner`: barrels also export the
generated files on disk. Hand-written `export` lines in a barrel are replaced. `dart format` runs
through the repo's toolchain (FVM when present). Exits 64 when the path does not exist (it prompts
for another only when run with no argument on a terminal) or on a flag, 1 when generation or
formatting fails.

### 📦 Dependency Sync (version catalog)
```bash
# Sync versions from pubspec_dependencies.yaml down to every package, then pub get:
dart tools/dependency_sync.dart

# Report drift only (writes nothing) — exits 1 on any; CI Gate 4 / pre-commit:
dart tools/dependency_sync.dart --check
```

### 🔄 Outdated Dependencies Checker
```bash
# Check for outdated packages on pub.dev:
dart tools/check_outdated.dart
```

Resolves every catalog package in a sandbox, runs `pub outdated`, then (on a terminal) offers a
checklist to bump the catalog and re-runs `dependency_sync` + `pub get`. Without a terminal it only
reports and leaves the catalog alone. Exits non-zero when resolution, `pub outdated` or applying an
update fails.

### 🤖 Code Review (AI-powered)
```bash
# Review every file (every lib/ under apps/, modules/, platform/):
dart tools/code_review/code_review.dart --all

# Review one file:
dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart

# Review uncommitted changes (git diff HEAD):
dart tools/code_review/code_review.dart --changed

# Focus on architecture + security:
dart tools/code_review/code_review.dart --all --focus architecture,security

# Vietnamese report for this run (not written to code_review_config.json):
dart tools/code_review/code_review.dart --all --language vi
```

Generated files (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gen.dart`,
`*.mocks.dart`, anything under `gen/` / `generated/`, `firebase_options_*.dart`), tests and
gitignored files are always excluded. Reports are always Markdown; `--format` accepts only
`markdown`. API key: `--api-key`, the `GEMINI_API_KEY` variable, or the gitignored
`tools/code_review/.gemini_api_key`; get one at https://aistudio.google.com/app/apikey. Details:
[`code_review/README.md`](code_review/README.md).

### 🧹 Unused Checker (cleanup)
```bash
# Run every check (recommended) — exits 1 if any check fails:
dart tools/unused_checker/check_script.dart

# Or run one kind at a time (each script has --help):
dart tools/unused_checker/check_unused_assets.dart
dart tools/unused_checker/check_unused_packages.dart
dart tools/unused_checker/check_unused_translate.dart
dart tools/unused_checker/check_unused_file.dart
```

The results are suggestions: there is sample code and deliberately unused scaffolding.
`check_unused_packages.dart` runs in CI as an advisory step (it never blocks a merge). Remove a
sample with `remove_sample.dart`, not on the word of `unused_checker`.

### ⚙️ Workspace Setup & Config
```bash
# Workspace setup (the setup step on a fresh clone):
dart tools/workspace_setup/configure.dart   # cross-platform

# Firebase config (writes to apps/<id>/lib/firebase/ and that app's ios/, android/):
dart tools/firebase/firebase_config.dart --app mobile

# Theme (splash + icons):
dart tools/theme_generator/theme_setting.dart --app mobile

# The workspace holds two apps today (mobile, admin), so --app is required. Both tools have --help.
```

- `configure.dart` runs, in order: `dart pub global activate flutterfire_cli` →
  `flutter clean` → `flutter pub get` → `flutter gen-l10n` in every package with an `l10n.yaml` →
  `dart run build_runner build --workspace` → the barrel generator for every package with a `lib/`
  (apps skipped). It stops at the first failing command with that command's exit code.
- `firebase_config.dart` is interactive (needs a terminal) and needs the Firebase CLI installed
  (`npm install -g firebase-tools`) and logged in (`firebase login`) — the tool does **not** install
  the Firebase CLI (it does install the FlutterFire CLI through `dart pub global activate` when
  missing); without the Firebase CLI it prints install instructions and exits 1, and when not logged
  in it offers `firebase login` at most twice, then exits 1.
- `theme_setting.dart` uses the `flutter_native_splash-<flavor>.yaml` / `icons_launcher-<flavor>.yaml`
  configs at the repo root, needs `android/` and `ios/` in the app, and `flutter_native_splash` +
  `icons_launcher` in the app's `pubspec.yaml` — anything missing is reported before anything is
  written (`--app admin` is refused today because admin has no platform folders). If a generator
  fails, every file it created or changed under `android/`, `ios/`, `web/` is restored.

### 📱 Android 16KB Page Size
```bash
# Build a flavor's release APK, then check it (from the repo root):
./tools/android_compliance/16kb_ckeck.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk   # macOS/Linux
.\tools\android_compliance\16kb_ckeck.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

The argument can be an APK, an APEX or a directory of native libraries. The `.bat` only locates Git
Bash and runs the `.sh`.

---

## 🔑 Prerequisites

- **Dart SDK**: >= 3.13.3
- **Flutter SDK**: >= 3.47.4 (`.fvmrc` pins `3.47.4`; FVM is optional)
- **Ruby**: >= 3.0 (for Fastlane, only needed for CI/CD builds)
- **Gemini API key**: Only for the code review tool
- **Firebase CLI** (`npm install -g firebase-tools`, logged in with `firebase login`): Only for `firebase_config.dart`

---

## 💡 Best Practices

### New-module workflow:
```bash
# 1. Create the domain + data micro-packages (the generator runs composer sync, build_runner, barrels itself):
dart tools/module_generator/generate.dart 2 payment
dart tools/module_generator/generate.dart 3 payment

# 2. Implement (Entities → Repository Interfaces → UseCases → Models → DataSources → RepositoryImpl)

# 3. Generate DI / Freezed / JSON code:
dart run build_runner build --workspace

# 4. Generate barrel files — AFTER build_runner, since barrels export generated files too:
dart tools/barrel_generator/generate.dart modules/payment/domain/lib
dart tools/barrel_generator/generate.dart modules/payment/data/lib
```

### Periodic cleanup workflow:
```bash
# 1. Find unused resources:
dart tools/unused_checker/check_script.dart

# 2. Find outdated packages:
dart tools/check_outdated.dart

# 3. Sync versions:
dart tools/dependency_sync.dart
```

---

**Built with ❤️ for Flutter Clean Architecture Development**
