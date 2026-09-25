🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# 🛠️ Development Tools

This folder holds the developer CLI tools that automate the workflow and keep code quality up in this Flutter Clean Architecture monorepo. `tools/` is a workspace member (package `core_tools`, see `tools/pubspec.yaml`), so every tool runs after a root `flutter pub get`. **Always run them from the repository root.**

One-page reference (command, purpose, exit codes, CI gate): [`docs/en/reference/03_tooling.md`](../docs/en/reference/03_tooling.md). Every tool's full detail — arguments, refusals, failure modes — is in [§ Full reference](#-full-reference-tool-by-tool) below.

> **Rule**: CLI tools in this folder **must not** use `print()`. Use `stdout.writeln()` and `stderr.writeln()`. A tool that shells out to `dart` / `flutter` detects FVM through `tools/shared/toolchain.dart` — never hardcode an `fvm` prefix.

---

## 📁 Directory Structure

```text
tools/
├── pubspec.yaml                     # The core_tools package (a workspace member)
├── arch_check/                      # 🛡️ Enforces the layering rules (CI Gate 1)
│   └── check.dart                   # R1-R15: dependency direction, pure-Dart domain, feature boundaries, scaling through context…
├── composer/                        # 🧩 Composes apps from app_manifest.yaml (CI Gate 0)
│   ├── composer.dart                # sync / verify / list — generates the workspace list, app dependencies, injection.dart
│   └── bootstrap.dart               # Partial checkout: prunes absent members so `pub get` resolves (no package imports)
├── docs_check/                      # 📚 Every path the docs name must exist (CI Gate 5)
│   ├── check.dart
│   ├── parity.dart                  # en <-> vi parity: headings per level, code blocks, table rows
│   ├── allowlist.txt                # Deliberately absent paths, each with its reason
│   └── parity_allowlist.txt         # Intentional en/vi shape differences, each with its reason
├── shared/                          # 🔗 Code shared between tools
│   ├── app_locator.dart             # Finds apps by app_manifest.yaml, picks one with --app <id>
│   ├── toolchain.dart               # FVM detection (.fvmrc + `fvm --version`) for every tool that runs dart/flutter
│   └── workspace.dart               # The one discovery walk (pubspecs, app manifests, lcov) and its skip set
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
│   └── templates/                   # Mustache templates (common, domain, data, feature/{bloc,provider,default,routing,localization,test})
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
│   ├── configure.dart               # Cross-platform script (Windows/macOS/Linux)
│   └── firebase_stubs.dart          # --stub-firebase: compile-only Firebase options + google-services.json (dart:io only)
├── coverage_report/                 # 📊 Per-package line coverage from lcov.info (CI Gate 3, advisory)
│   └── report.dart
├── test/                            # ✅ The tools' own tests (`cd tools && dart test`, CI Gate 1)
├── firebase/                        # 🔥 Multi-environment Firebase configuration
│   └── firebase_config.dart
├── theme_generator/                 # 🎨 Splash screen & app icons
│   └── theme_setting.dart
├── android_compliance/              # 📱 Android 15+ 16KB page-size check
│   ├── 16kb_check.sh                # macOS/Linux (the actual implementation)
│   └── 16kb_check.bat               # Windows — runs the .sh through Git Bash
├── dependency_sync.dart             # 📦 Syncs dependency versions from the catalog (Gate 4 with --check)
└── check_outdated.dart              # 🔄 Checks for outdated packages on pub.dev
```

---

## 🚀 Quick Usage

### 🛡️ Architecture Check (layering rules)
```bash
# Check the 15 architecture rules (R1–R15) — exits 1 on a violation (CI-ready):
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
The opposite case — a package directory under `modules/` or `platform/` that no app composes (left
behind after a module was dropped from every manifest) — fails `verify` and is a warning under
`sync`, naming the directory and the fix: delete it, or re-add it to a manifest.

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
missing one — initialise that submodule too. See `docs/en/guides/12_module_isolation.md` § 2.

### 📚 Docs Check (paths named in the docs)
```bash
# Every repo path a Markdown file names must exist — CI Gate 5:
dart tools/docs_check/check.dart

# Plus a copy-paste allowlist block for the dead references:
dart tools/docs_check/check.dart --verbose
```

The same run checks **en ↔ vi parity**: every `docs/en/**.md` with a `docs/vi` counterpart, and
every `<name>.md` with a `<name>.vi.md` beside it, must have the same number of headings per level,
fenced code blocks and table rows in both languages. A difference exits 1 with both counts; an
intentional one goes in `tools/docs_check/parity_allowlist.txt` as `<english file> <metric>` with a
reason.

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

Both the dry-run and `--apply` count the documentation references (`docs/`, `.claude/`, every
`*.md`) to paths about to be deleted. They are informational: after the removal,
`dart tools/docs_check/check.dart` (CI Gate 5) recognises them as pointing into a removed sample
bundle (every package of the bundle absent, per `tools/sample_manifest.yaml` — the removal tool
never edits that file), prints one INFO line per bundle and still passes. Fix those docs whenever
convenient. An unknown flag (e.g. `--aply`) or a wrong bundle name is refused with exit 64 rather
than ignored. Bundles: `auth`, `home`, `settings`, `onboarding`, `cache`, `dashboard`, `splash`.


### 🏗️ Module Generator (new modules)
```bash
# Syntax: dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<SM>] [<route>] [--group <g>] [--apps <id,id>]
# <type>: 1=Feature, 2=Domain, 3=Data, 4=Core (core_<name>), 5=Custom, 6=API (<name>_api at modules/<name>/api)
# <prefix> (Custom only): package-name prefix -> <prefix>_<name> at platform/<group>/<name>; pass "" for other types
# <SM> (Feature only): 1=Provider, 2=BLoC, 3=None
# <route> (Feature only): 1=IFeatureRouteModule, 2=INavDestinationModule (primary nav tab), 3=none
# --group (Core/Custom only): foundation|layers|infra|ui|state|shell — the platform/ group folder; default infra
# Pick 2 only for a primary tab after sign-in — see docs/{en,vi}/guides/04_routing.md.

# Feature 'profile' + Provider + stack routes (IFeatureRouteModule):
dart tools/module_generator/generate.dart 1 profile "" 1 1

# Feature 'chat' + BLoC + primary nav tab (INavDestinationModule):
dart tools/module_generator/generate.dart 1 chat "" 2 2

# Domain micro-package 'payment':
dart tools/module_generator/generate.dart 2 payment

# Data micro-package 'payment':
dart tools/module_generator/generate.dart 3 payment

# Core package 'logging' (core_logging at platform/infra/logging):
dart tools/module_generator/generate.dart 4 logging

# Core package 'charts' in the ui group (core_charts at platform/ui/charts):
dart tools/module_generator/generate.dart 4 charts --group ui

# Custom package 'billing' with prefix 'acme' (acme_billing at platform/infra/billing):
dart tools/module_generator/generate.dart 5 billing acme

# The 'chat' module's API package (chat_api: a ChatNavigator stub; feature_chat, if it exists, implements it):
dart tools/module_generator/generate.dart 6 chat

# Interactive (no arguments, needs a terminal):
dart tools/module_generator/generate.dart

# Only some apps: compose into mobile, leave admin alone (ids = app.id in apps/*/app_manifest.yaml):
dart tools/module_generator/generate.dart 1 chat "" 2 2 --apps mobile

# Show the syntax:
dart tools/module_generator/generate.dart --help
```

The CLI adds the module to every `app_manifest.yaml` (or only those `--apps` names) (Feature/Domain/Data/API to the `modules:` list,
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
- `--apps` must name at least one existing app id; an unknown id (or an empty value, or the flag twice) is refused and the known ids are listed.
- A feature missing `<SM>` or `<route>` is prompted for the missing value on a terminal (empty = `1`); with no terminal (or stdin at end of input) it fails instead of silently taking a default.
- Adding to `app_manifest.yaml` parses the manifest as YAML (no substring matching — `core_net` is no longer taken as "already present" because of `core_network`); if a manifest cannot be updated the tool exits 1 and rolls back.

A Feature starts with tests that pass as generated: `test/<name>_page_test.dart` (the page under
`ResponsiveInit` and its localizations, controller provided as the route provides it) plus
`test/<name>_provider_test.dart` or `test/<name>_bloc_test.dart` (none for SM `3`).

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
# ...plus compile-only Firebase stubs where no real file exists (no Firebase project yet; what CI runs):
dart tools/workspace_setup/configure.dart --stub-firebase

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
  `--stub-firebase` also writes — first, before codegen, and listed at the end — **only where absent**, a `firebase_options_<flavor>.dart` per
  flavor for each app with `lib/firebase/firebase_module.dart` and an
  `android/app/src/<flavor>/google-services.json` per Gradle flavor (package name read from
  `build.gradle.kts`). They make the app compile and build; nothing Firebase-backed works with them.
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

### 📊 Coverage Report
```bash
# After `flutter test --coverage` in each package — a per-package table, total included:
dart tools/coverage_report/report.dart
# Make it a gate: total below 60 %, or any package below 40 %, exits 1:
dart tools/coverage_report/report.dart --min 60 --min-package 40
```

Reads every `*/coverage/lcov.info`, excludes generated files (`*.g.dart`, `*.freezed.dart`,
`*.config.dart`, `*.module.dart`, `gen/`, …) and appends the table to `$GITHUB_STEP_SUMMARY` on
GitHub Actions. CI Gate 3 runs it after the tests, advisory (no threshold).

### 📱 Android 16KB Page Size
```bash
# Build a flavor's release APK, then check it (from the repo root):
./tools/android_compliance/16kb_check.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk   # macOS/Linux
.\tools\android_compliance\16kb_check.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

The argument can be an APK, an APEX or a directory of native libraries. The `.bat` only locates Git
Bash and runs the `.sh`.

---

## 📖 Full reference, tool by tool

Everything each tool does, refuses and prints — the long form of the one-page table in [`docs/en/reference/03_tooling.md`](../docs/en/reference/03_tooling.md). All tools are plain Dart; run them from the **repository root**.

### `arch_check`

Enforces the layering rules mechanically. **Gate 1 of `pr_quality_check.yml`** — it runs before `flutter analyze` because it only reads imports and `pubspec.yaml` files, needs no codegen, and finishes in roughly 200 ms.

```bash
dart tools/arch_check/check.dart          # exits 1 on any blocking violation
dart tools/arch_check/check.dart --help   # full rule descriptions
```

It takes no other argument: anything besides `--help` (a `--fix`, a typo of `--help`) exits `64` instead of passing for a clean run.

| Rule | What it checks |
|---|---|
| R1 | Dependency direction — no `platform/*` package may import or declare `feature_*` / `data_*` / `domain_*` or a module API package (`<id>_api`), except the approved edges |
| R2 | Domain is pure Dart — no `flutter` / UI / `dio` / `retrofit`, and no `core_*` / `platform_*` / `data_*` / `feature_*` package, imported or under `dependencies:`; `domain_core` and other `domain_*` packages only |
| R3 | Feature and module-API boundaries — no feature imports another feature or a `data_*` package (another module's `<id>_api` is fine); a module API package (`modules/<id>/api`) imports and declares only `platform/foundation/*` and Flutter/pub packages |
| R4 | Public `static const` live in a `utils/` directory (files under `styles/` — `core_base_ui`'s design tokens — are exempt). A package with no public constants needs no `utils/` |
| R5 | Every `package:` import used in `lib/` is declared under that package's `dependencies:` — a `dev_dependencies` entry does not count |
| R6 | Generated files still carry their generator header (advisory) |
| R7 | Responsive sizing goes through `BuildContext` — no bare `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm` receiver, in any file that mentions `core_responsive` |
| R8 | A `core_di` contract or module API type implemented under `modules/` — any layer — is resolved with `getItOrNull` / `getAllOrEmpty`, never a throwing `getIt` / `getAll`, outside the module that implements it |
| R9 | `platform_kernel` and every `*_contracts` package neither import nor **declare** a Flutter-bound package |
| R10 | Nothing in an app (`apps/<id>/`) imports a module (its API package included) — only `injection.dart`, the composition root, may name one. (`platform/shell/app_shell` is core, so R1 covers it) |
| R11 | Platform group direction — a `platform/*` package sits at `platform/<group>/<package>` and its `dependencies:` (not dev) name only platform packages its group may reach: `layers/domain` nothing; foundation → foundation, `layers/domain`; `layers/data` → foundation, `layers/domain`; infra → foundation, layers; ui → foundation, ui; state → foundation, layers, ui; shell → any |
| R12 | No PowerShell — no `*.ps1` anywhere in the working tree (Windows' default execution policy blocks unsigned scripts); write a cross-platform Dart script |
| R13 | No analyzer suppressions — no `// ignore:` / `// ignore_for_file:` line comment in any hand-written `.dart` (`tools/` and `test/` included; generated `*.g` / `.freezed` / `.config` / `.module` / `.gr` / `.mocks.dart`, `firebase_options_*` and `lib/src/gen/**` skipped). Text inside a string or a `///` doc comment is not reported |
| R14 | Data source folders are `data_sources/` — no directory named `datasources` (any case) under `modules/` or `platform/`, empty ones included |
| R15 | The `I` prefix is reserved for interfaces — under `modules/`, `platform/` and `apps/*/lib` a class named `I[A-Z]…` must be `abstract`, `interface` or `sealed`; a plain / `base` / `final` class or a non-abstract `mixin class` fails. A concrete class starting with a two-letter acronym (`IOClient`) is flagged too |

The three approved upward exceptions are hardcoded in the tool **and printed on every run**, with the reason for each — so they cannot quietly rot inside a comment. Adding a fourth means editing the allow-list in `check.dart` — without that the build fails — and recording the edge under RULE-01 in [`01_rules.md`](../docs/en/reference/01_rules.md) (both locales), which the tool does not read.

R7 exists because `flutter analyze` cannot see the difference. `core_responsive` ships no `num` extension, so `16.h` cannot resolve against it — but an extension declared in another package, or one someone adds locally, would type-check fine while reading a global that never notifies anyone. Only `context.h(16)` registers an `InheritedWidget` dependency on `ResponsiveScope` and therefore rebuilds when metrics change. The bare form is a silent stale-value bug, and a linter has no rule for it. The check only runs on files that reference `core_responsive`, and matches a numeric or closing-paren receiver followed by `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`.

R10 exists because removability is a promise the template makes in four documents and nothing was checking. `network_config_impl.dart` imported `data_auth` and `domain_auth` to read and refresh the session token, so deleting the auth module broke the app shell at compile time — the one place in the shell that undid what every other file was careful to preserve. `getItOrNull` cannot help: it guards a *lookup*, and the failure here is an *import*, which the compiler resolves long before any lookup runs. The fix is a contract (`ISessionGateway` in `core_di`, implemented by `data_auth`), and the check is one line of policy — an app may import a module package in exactly one file, the composition root, because that file's job is to name what it composes.

R11 exists because the group direction was documented in four places and held only by review. The group is read from the folder — the one thing that records it — so a package moved into the wrong group, or left outside any, fails as surely as a bad edge. Dev dependencies are excluded on purpose: they never reach a consumer's graph (`platform_app_shell`'s tests use `core_storage` for fakes).

R8 exists because removability is a property the app shell depends on, and nothing was holding it. The tool derives the set at run time: every type declared in `core_di` or in a module API package (`<id>_api`), narrowed to those with an `implements` / `extends` / `as:` binding in a package under `modules/` — any layer, so `ISessionGateway`, implemented in `data_auth`, is in the set as surely as a feature's navigator — and keyed by the module that implements it. A throwing lookup against one of those compiles — the calling package depends on `core_di`, not on the module — and then crashes at runtime in any build without that module. Contracts implemented in the app shell (`IThemeStorage`, `ILanguageStorage`) are always registered, so they are deliberately outside the set. A module is removed whole, so every package of the implementing module may resolve its contracts eagerly: if one of its packages is in the build, so is the registration.

R12–R15 read files, not the package graph: every file git does not ignore — tracked, new, and modules checked out as submodules (outside a git checkout, every file). R13 and R15 run a small Dart lexer (`tools/arch_check/dart_source.dart`) that blanks comments and string literals first, so text inside a string, a template or a doc comment is never reported. Each rule has a registry id: RULE-72 (R12), RULE-71 (R13), RULE-40 (R14), RULE-78 (R15).

R5 is the mirror image of `unused_checker`: that tool finds dependencies *declared but unused*, this one finds them *used but undeclared*. Pub Workspaces hide the second kind entirely — everything resolves locally through the shared `package_config.json` and only breaks when a package is extracted or published.

### `composer`

```bash
dart tools/composer/composer.dart list              # every app and its composition
dart tools/composer/composer.dart list --app admin  # one app only
dart tools/composer/composer.dart sync --app mobile # regenerate
dart tools/composer/composer.dart verify            # CI gate 0 — fails on drift
dart tools/composer/bootstrap.dart                  # partial checkout only — run before `flutter pub get`
```

`--app <id>` narrows `list`, `sync` and `verify` alike; the root `workspace:` list is still computed from every app. An unknown flag, or `--app` without an id, exits `64`. A pubspec or manifest that is not valid YAML — usually a duplicate key — is refused by name, `file:line` and parser message, exit `1`, instead of crashing the tool.

Every `app_manifest.yaml` is also **validated before any command runs**; each problem is printed as `apps/<id>/app_manifest.yaml: <key>: <problem>` (e.g. `di_groups[0].phase: expected \`before\` or \`after\`, got a string (\`befor\`)`), and the tool exits `1` having written nothing. Refused: a manifest that is empty or not a map; an unknown key at any level (`module:` for `modules:`); a missing or empty `di_groups`; a group without a `name` (a Dart identifier, unique per manifest) or with a `phase` other than `before`/`after`, or a `before` group after an `after` one; `packages` that is not a list; a `from_modules` that is not `domain`/`data`/`feature`, or a layer collected by two groups; a group with neither `packages` nor `from_modules`; a module that is not `{ id, layers }`, a duplicate module id, empty `layers`, a layer outside `domain`/`data`/`feature` or not collected by any group's `from_modules`; a package composed twice (by two groups, or by a group and `extra_dependencies`); and two manifests with the same `app.id`. Each of these used to crash with a stack trace or — worse — exit `0` having generated an `injection.dart` without the modules it silently dropped.

Three things had to agree and were maintained by hand: the root `workspace:` list, an app's path dependencies, and its `lib/di/injection.dart`. Adding a module meant editing all three in step, and getting it wrong fails at boot with `"<Type> is not registered"` — invisible to `flutter analyze`.

`composer` generates all three from the apps' `app_manifest.yaml` files — each app's own files from its manifest, and the shared root `workspace:` list from all of them together — but only between `composer:managed:<region>` and `composer:end:<region>` markers. External dependencies, flavors and asset declarations stay hand-written.

The root `workspace:` list is more than what the manifests name: composer follows each composed package's `dependencies` and `dev_dependencies` to every workspace package they reach. That is how `core_responsive`, `core_ui_kit` and `platform_kernel` — which register no DI module, so no `di_groups` entry names them — still become workspace members. A manifest's optional `extra_dependencies:` list is only for a workspace package the app's **own** `lib/` imports without composing it; neither sample app needs one.

A module's `api` layer (`- { id: auth, layers: [api, domain, data, feature] }`) needs no `di_groups` entry: its `<id>_api` package holds contracts only, so it becomes a workspace member and nothing else — no app dependency, no `injection.dart` line. `--strict` / `verify` still require it on disk. A group may collect it with `from_modules: api` should an API package ever register something.

Packages are resolved by **name**, discovered by scanning for `pubspec.yaml`. No directory is encoded anywhere, so moving packages needs no change to the tool or to any manifest. Module packages are matched under either naming convention — `domain_auth` and `auth_domain` both resolve.

`--strict` (implied by `verify`) turns "a manifest names a module that is not on disk" from a warning into an error. Without it, `sync` composes what it can find — which is what lets a developer work with only their own module checked out.

Both `sync` and `verify` also **refuse**, exit `1`, when a file they generate into — the root `pubspec.yaml`, an app's `pubspec.yaml` or `lib/di/injection.dart` — is missing, or has lost a region's `composer:managed:<region>` / `composer:end:<region>` marker. They name the file and the marker, and `sync` writes nothing. A missing marker used to be a warning followed by "up to date": deleting one and hand-editing what it had guarded passed Gate 0.

Both also **refuse** an app pubspec that declares a managed package by hand outside the markers. Pub rejects a duplicate key, so that one mistake stops the whole workspace resolving — and it is exactly the mistake composer itself once made.

A non-strict sync that skipped anything prints a **`PARTIAL COMPOSITION`** block: the committed files that run actually rewrote — only those; a file that already held this composition is not listed (the candidates are the root `pubspec.yaml`, plus the `pubspec.yaml` and `injection.dart` of each app it synced) — and the `git checkout --` line that restores them. The composition it wrote is correct locally and wrong to commit, and CI Gate 0 catches it either way, because `verify` regenerates from the manifest on a runner where every module is present. See [`12_module_isolation.md`](../docs/en/guides/12_module_isolation.md).

#### `bootstrap` — before composer can run

```bash
dart tools/composer/bootstrap.dart            # prune, from the managed regions, every member not on disk
dart tools/composer/bootstrap.dart --dry-run  # report only
```

`composer.dart` imports `package:path` and `package:yaml`, so it needs a resolved workspace — and a fresh **partial** checkout (a module submodule left uninitialised, i.e. an empty directory) does not resolve: the committed root `workspace:` list and each app's managed path dependencies still name it, and `flutter pub get` refuses the whole workspace. `tools/composer/bootstrap.dart` imports **no package** (only `dart:io` and the `dart:io`-only `OutputFormatter`), so it runs before pub has ever resolved. It removes, from the root `composer:managed:workspace` region and each app's `composer:managed:deps` region only, every entry whose directory has no `pubspec.yaml`, prints what it pruned and the `git checkout --` line that undoes it, and tells you to run `flutter pub get` → `composer.dart sync` → `workspace_setup/configure.dart`. `sync` then rewrites the regions from the manifests.

Exit `0` when it pruned or found nothing to prune (a full checkout — it writes nothing); `1`, writing nothing, when there is no `composer:managed:workspace` region (not run from the root) or when a present package has a **hand-written** path dependency on a missing directory (`modules/auth/data` without `modules/auth/domain`) — pruning cannot fix that, so it names the line and tells you to initialise that submodule too; `64` on an unknown argument. The full sequence: [`12_module_isolation.md` § 2](../docs/en/guides/12_module_isolation.md#2-work-in-a-partial-checkout).

### `docs_check`

**Gate 5 of `pr_quality_check.yml`.** Resolves every repository path the documentation names, collects every one that is not there, prints them grouped by file, then exits 1. References into a sample bundle you removed with `remove_sample` are the one exception — summarised as INFO, never a failure (below).

```bash
dart tools/docs_check/check.dart            # exits 1 on a dead reference, en ↔ vi parity mismatch or RULE-ID problem
dart tools/docs_check/check.dart --verbose  # plus a copy-paste allowlist block and every removed-sample reference
dart tools/docs_check/check.dart --help     # usage; any other argument exits 64
```

Two kinds of reference are checked in every Markdown file in the repository — only tool state, build output and fetched native dependencies (`.dart_tool`, `build`, `Pods`, …) are skipped. It used to cover just `docs/`, `.agents/`, `README.md` and `CLAUDE.md`; widening it found 11 dead links in the `.github` guides, a package README and the fastlane README:

| Kind | Example | How it is resolved |
|---|---|---|
| Backticked path | `` `platform/foundation/kernel/lib/platform_kernel.dart` `` | Repo-rooted, but only when the span starts with a real top-level directory |
| Markdown link | `[…](arch_check/check.dart)` | Relative to the **file containing the link**, not the working directory |

The top-level-directory test is what makes the check usable. A repository is full of backticked spans that look like paths and are not: `utils/` and `routing/` are conventions that exist in a dozen packages at once, `ViewState` is a type, `flutter pub get` is a command. Treating those as paths produced 817 "failures" on the first run and would have taught everyone to ignore the gate. Anchoring to `platform/`, `modules/`, `apps/`, `tools/`, `docs/`, `.agents/`, `.github/` leaves about 1 900 genuine references (at the time of writing) — and the spans that get skipped are exactly the ones a reviewer can verify by eye anyway.

Spans containing a space are skipped: they are shell lines. Spans containing a `*` or a `{` are globs, each describing a *set* rather than one file — they pass when at least one path fits. A span with a `<placeholder>` segment (`modules/<owner>/feature/lib/src/handlers`) is a **template** for the reader's own module, not a reference: only the literal part before the first placeholder must exist (`modules`), so a placeholder path never fails because no current module happens to have that folder. A placeholder path under the long-gone packages/domain directory still fails, because that literal part does not exist. The top-level list also keeps `packages/` and a bare `app/`, where nothing lives any more, so a document still pointing there fails instead of being skipped.

**Removed samples do not fail the gate.** `remove_sample.dart <bundle> --apply` deletes a bundle's packages but never edits `tools/sample_manifest.yaml`, and `docs_check` reads the bundle definitions there: a bundle whose packages are **all** absent from disk (bar a `modules/<id>/api` package remove_sample kept because something still imports it) is "removed", and a dead reference inside it — a package path, the emptied `modules/<id>` directory, one of its `orphaned_contracts` — is reported as one summary line per bundle instead of a failure:

```text
INFO: 118 reference(s) in 32 document(s) point to removed sample bundle "auth" — expected after remove_sample; update the docs at your leisure.
```

`--verbose` lists them. A bundle with even one package still on disk is not "removed" — a half-deleted sample is drift and fails as usual — and a dead path outside every removed bundle still exits 1. Once the docs no longer mention a removed sample, you may delete its bundle entry from the manifest.

Paths that are correctly absent live in `tools/docs_check/allowlist.txt`, one per line, each with the reason it is not on disk. Exactly three reasons qualify:

1. **Generated** — `apps/mobile/lib/di/injection.config.dart`, build output.
2. **Secret** — `apps/mobile/env.prod`, `apps/mobile/android/key.properties`; never committed.
3. **Tutorial** — a file the reader is *told to create* (`app_elevation.dart` in the design-system guide), or a placeholder standing in for the reader's own module (`modules/profile/feature`).

Anything else is drift, and the fix is to correct the document. An entry without a stated reason is not allowed — the moment the allowlist becomes a list of paths somebody silenced, the gate stops being worth running.

> [!NOTE]
> The check deliberately says nothing about whether a document is *correct*, only whether the things it points at exist. That is a low bar, and it is the only bar a machine can hold. Line-number citations (`generate.dart:90-101`) fail it by design — they are the fastest-rotting reference there is, and naming the symbol instead survives every edit above it.

**en ↔ vi parity.** The same run compares every translated pair — `docs/en/<path>.md` with `docs/vi/<path>.md`, and `<name>.md` with a `<name>.vi.md` beside it anywhere (`README.md`, `tools/README.md`, package READMEs) — by shape, since a translation cannot be diffed word for word: the count of headings at each level (`h1`–`h6`), of fenced code blocks (`code-blocks`) and of table rows (`table-rows`, quoted tables included) must match. Headings and tables inside a code block do not count. Every difference fails the run:

```text
1 parity mismatch(es):

  docs/en/guides/01_new_feature.md  table-rows: en 18 vs vi 17  (docs/vi/guides/01_new_feature.md)
```

A difference nearly always means a section, command or table row reached one language only — translate it across. A genuinely intentional one goes in `tools/docs_check/parity_allowlist.txt` as `<english file> <metric>` (or `*` for every metric) with a `#` reason; an entry without a reason is refused, and one that no longer matches any difference prints a `WARN` so it can be deleted. The list is empty today: every pair has the same shape. The logic lives in `tools/docs_check/parity.dart`.

**RULE-ID citations.** Every `RULE-<digits>` token in any Markdown file — code blocks, `SKILL.md` files and `tools/code_review/review_prompt.md` included — must be the id of a `| RULE-NN |` row in the registry of [`01_rules.md`](../docs/en/reference/01_rules.md). No id may be defined twice, and `docs/vi/reference/01_rules.md` must define exactly the same ids. Each failure is printed as `file:line` and exits 1. A retired rule keeps its row, marked retired, so old citations still resolve; an id is never reused. While no registry exists the check is skipped with one `INFO` line. The logic lives in `tools/docs_check/rule_ids.dart`.

**Stale translations (advisory).** A `docs/vi` file may start with a stamp naming the English commit it was synced to:

```text
<!-- translated-from: docs/en/<path>.md@<short-sha> -->
```

A normal run prints one `INFO` line counting the translations whose English source has commits after the stamped one — it never fails. `--stale-translations` lists them; `git diff <sha> -- <en file>` shows what to carry across. After syncing, commit the English change first, then run `--stamp-translations docs/vi/<file>.md`; without file arguments it stamps every `docs/vi` file as current, which is right only when first adopting stamps. The logic lives in `tools/docs_check/translations.dart`.

```bash
dart tools/docs_check/check.dart --stale-translations                       # list translations behind their English source
dart tools/docs_check/check.dart --stamp-translations docs/vi/<file>.md      # after syncing one
```

### `sample_cleanup`

Answers "which of this is example code, and how do I delete it without breaking the app?".

```bash
dart tools/sample_cleanup/remove_sample.dart --list    # classification table
dart tools/sample_cleanup/remove_sample.dart auth      # dry-run (default)
dart tools/sample_cleanup/remove_sample.dart auth --verbose  # dry-run, every doc reference listed
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

Its source of truth is [`tools/sample_manifest.yaml`](sample_manifest.yaml), which classifies every package as `framework`, `sample` or `shell`. No sample code lives inside a framework package: every sample is a package of its own, so removing one is always a whole-bundle operation.

The dry-run output is the part worth reading. Removing `auth` is not just three directories: it prints the exact lines to strip from the root `pubspec.yaml` and from every app's manifest, pubspec and `injection.dart`, the **API packages it keeps** (below), **and which other samples break and how** (the `breaks` list in `tools/sample_manifest.yaml` — empty for every sample today) — as well as the couplings that degrade safely, such as `feature_settings` hiding its logout row when `getItOrNull<IAuthActionHandler>()` is null, or `feature_home` showing the signed-out state when the route's `getItOrNull<ISessionStatusStream>()` is null.

Both the dry-run and `--apply` also count the **Markdown references** to the paths the removal deletes — backticked paths and relative links in every `*.md` (`docs/`, `.claude/`, READMEs), matched the way `docs_check` matches them. They are informational: `dart tools/docs_check/check.dart` (CI Gate 5) recognises them as pointing into a removed sample bundle, prints one INFO summary for the bundle and still passes — update those docs at your leisure. That is also why the tool never edits `tools/sample_manifest.yaml`: the bundle definition staying there is how `docs_check` knows. The first 15 are printed; `--verbose` lists them all.

**A module's API package is kept while something still imports it.** `auth` includes `auth_api`, but `feature_onboarding` and `feature_settings` depend on it; deleting it would break their compile. So any `modules/<id>/api` package of the bundle that a package outside the bundle still declares (`dependencies:` or `dev_dependencies:`) is **kept**: the dry run marks it `k` with its importers, `--apply` says so again, the root `workspace:` entry stays and every manifest entry that listed it is rewritten to `{ id: <id>, layers: [api] }`. Its contracts then have no implementation — the consumers' `getItOrNull` returns null and they take their fallback. Once nothing imports it, run `remove_sample <id> --apply` again and it goes too. `docs_check` treats a bundle whose only survivor is its API package as removed.

Bundles: `auth`, `home`, `settings`, `onboarding`, `dashboard`, `splash`, `cache` (`--list` prints them with the classification).

Writes are opt-in via `--apply`, and shared files are snapshotted first so a mid-run failure rolls back. Arguments are checked first: an unknown flag (`--aply`), flags without a bundle name, an unknown bundle name, or more than one bundle exits `64` (no arguments at all prints the usage and exits `0`) — a misspelt flag is never silently a dry run, nor ignored next to `--apply`.

### `module_generator`

Scaffolds a package and registers it across the workspace.

```bash
dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<sm>] [<route>] [--group <g>] [--apps <id,id>]
dart tools/module_generator/generate.dart --help   # usage
```

| Arg | Values |
|---|---|
| `<type>` | `1` feature · `2` domain · `3` data · `4` core · `5` custom |
| `<name>` | bare directory name (`profile`) — the package becomes `feature_profile`. Must be a Dart package name: lowercase letters, digits and `_`, starting with a letter, not a Dart keyword |
| `<prefix>` | type `5` only — the package-name prefix: `<prefix>_<name>` at `platform/<group>/<name>`, same naming rule as `<name>`. A layer word (`feature`, `domain`, `data`, `core`) is refused; use types 1–4. For types 1–4 it must be empty — pass `""` |
| `<sm>` | feature only — `1` Provider · `2` BLoC · `3` none |
| `<route>` | feature only — `1` `IFeatureRouteModule` · `2` `INavDestinationModule` · `3` none |
| `--group` | types `4`/`5` only — the `platform/` group folder: `foundation` · `layers` · `infra` · `ui` · `state` · `shell` (`--group ui`, `--group=ui`). Default `infra`. What belongs in each group: [`02_core.md`](../docs/en/architecture/02_core.md). An unknown group, or `--group` on types 1–3, exits 64 |
| `--apps` | optional, any type — compose the module into these apps only: comma-separated `app.id`s from `apps/*/app_manifest.yaml` (`--apps mobile`, `--apps=mobile,admin`). Default: every app |

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1   # feature + Provider + stack route
dart tools/module_generator/generate.dart 1 chat    "" 2 2   # feature + BLoC + bottom-nav tab
dart tools/module_generator/generate.dart 2 payment          # domain micro-package
dart tools/module_generator/generate.dart 3 payment          # data micro-package
dart tools/module_generator/generate.dart 4 charts --group ui # core_charts at platform/ui/charts
dart tools/module_generator/generate.dart 5 billing acme     # acme_billing at platform/infra/billing
dart tools/module_generator/generate.dart 1 chat    "" 2 2 --apps mobile   # mobile only — admin untouched
```

**Arguments are validated before anything is written**, and every refusal exits `64` with the usage: an invalid `<name>` or `<prefix>` (`Bad-Name`), a `<sm>` / `<route>` other than `1`/`2`/`3`, a `<prefix>` / `<sm>` / `<route>` passed to a type that does not take it, an unknown flag, more than five arguments, an `--apps` with no value, an empty list, given twice, or naming an id no `app_manifest.yaml` declares (the message lists the known ids), or a **package name already taken** by any `pubspec.yaml` in the repository. Pub resolves a workspace by name, so a duplicate used to surface only at `pub get`, after composer had rewritten the manifests — and a new directory does not mean a new name: `5 shell platform_app` is `platform_app_shell` (already at `platform/shell/app_shell`), `2 core` / `3 core` are `domain_core` / `data_core`.

With no arguments on a terminal it prompts for everything. A feature missing `<sm>` or `<route>` prompts for what is missing (an empty answer takes `1`). **Without a terminal** — CI, an agent's shell, stdin at end of input — a value that would be prompted for is an error, exit `64`, never a silent default: always pass all five arguments for a feature. All tool output is in English.

**What it does:** creates the directory tree (including `lib/src/utils/`, for every layer), renders templates (the new pubspec copies the root `pubspec.yaml`'s `environment:`), adds the module to every `app_manifest.yaml` — or only to the apps `--apps` names — runs `composer sync` (which regenerates the root `workspace:` list and each app's `pubspec.yaml` and `lib/di/injection.dart`), then dependency sync, `pub get`, `gen-l10n`, the barrel generator, `build_runner`, the barrel generator **again**, and `dart fix --apply` on the new package. Barrels run twice because the templates import sibling barrels, which must exist before `build_runner` reads the package, while the barrels also export generated files (`module.module.dart`, `lib/src/gen/**`) — so the last run has to follow codegen.

> [!IMPORTANT]
> It never writes the root `workspace:` list, an app's `pubspec.yaml` or `lib/di/injection.dart` itself. Those sit between `composer:managed` markers, and only `composer sync` writes them — an entry added outside the markers is one composer never removes, and hand edits inside them are the drift CI Gate 0 fails on.

**Safety behaviour**

- **Toolchain is verified first.** `assertToolchainAvailable()` runs before anything shared is touched, so a missing SDK fails immediately instead of at step 8.
- **Existing directories are refused.** It will not silently overwrite a package.
- **Rollback on failure.** The shared files it changes — every `app_manifest.yaml`, what `composer sync` rewrites (the root `pubspec.yaml`, each app's `pubspec.yaml` and `lib/di/injection.dart`) and the root `pubspec.lock` — are snapshotted before any write; if a later step fails they are restored, the new module directory is deleted, and the tool exits `1`. If the failure came after `pub get` or `build_runner` had started, the rollback also reruns `flutter pub get` and `dart run build_runner build --workspace`: the untracked generated files (`.dart_tool/package_config.json`, each app's `injection.config.dart`, `module.module.dart`) would otherwise still reference the deleted package. It reports the workspace clean only when all of that succeeded; otherwise it lists what is left and prints the commands to run.
- **Registration is verified.** Whether a manifest already lists the package is decided by parsing it as YAML, not by substring — a line test once took `core_net` for registered because `core_network` contains it, and the package silently joined no app with exit `0`. Each edit is re-parsed; if the module could not be added to a manifest (no `modules:` list, or no `core` DI group, in the expected shape), the run rolls back and exits `1`.
- **FVM is auto-detected** — by every tool that shells out, through `tools/shared/toolchain.dart` — requiring *both* a config file (`.fvmrc` or `.fvm/fvm_config.json`) *and* a working `fvm --version`. Either signal alone gives a wrong answer: this repo pins a version in `.fvmrc` while a given machine may not have `fvm` installed at all.

**What a new package declares.** Only the packages its templates import, so it passes `check_unused_packages` from the first run — add `core_network`, `core_storage` and the rest when the code needs them. A feature declares `core_di`, `core_common`, `core_base_ui` and `core_responsive` (every generated page lays out through `AdaptiveContent`, with `AppSpacing` / `AppTextStyles` sizing through context), plus `provider_state_management` + `domain_core` for Provider, or `bloc_state_management` + `core_ui_kit` for BLoC (its loading state is the kit's `LoadingWidget`); only a feature gets `flutter_localizations` and `intl`, which its generated `gen-l10n` output imports. A domain package gets `domain_core` and a repository contract `I<Name>Repository` (in `repositories/`, one placeholder `ping()` returning `Result<void>`). A data package gets `data_core` and a `<Name>RepositoryImpl extends BaseRepository` (in `repositories_impl/`); when `domain_<name>` already exists it also declares `domain_core` + `domain_<name>`, implements that contract and registers as it (`@LazySingleton(as: I<Name>Repository)`) — so generate the domain first. Core and custom packages start with no workspace dependency.

**Generated tests.** A feature starts with tests that pass untouched, so CI Gate 3 has something to run from the first commit: `test/<name>_page_test.dart` pumps the page under `ResponsiveInit` and the feature's localizations — with its real controller provided above it exactly as the route provides it — and checks the localized title and that it lays out on a phone and a tablet window; `test/<name>_provider_test.dart` (Provider) waits for `initialize()` and expects success, `test/<name>_bloc_test.dart` (BLoC) expects `initial` and then `success` after the `started` event. SM `3` gets the page test only. `flutter_test` is in the feature pubspec's `dev_dependencies`. Replace the real controller with a fake once it takes use cases (see `modules/auth/feature/test/auth_provider_test.dart`).

**Build time.** Nearly all of a run is `build_runner` over the whole workspace (~76 s of ~92 s measured on a warm cache), and ~50 s of that is recompiling the AOT builder script, which a new workspace package forces. `--build-filter` limited to the new package and the apps' `di/` saved nothing (77 s) and left 21 outputs elsewhere unbuilt until the next full build, so the generator keeps the full `build_runner build --workspace`.

**Nav destination order.** A `<route>` `2` feature's `INavDestinationModule.order` is 10 above the highest `order` any existing destination under `modules/*/feature` returns (10 when there is none), so generated tabs never tie. Renumber freely; only the relative order matters.

> [!NOTE]
> Beyond those stubs, entities, use cases, models and data sources are written by hand. See [`../guides/02_new_domain_data.md`](../docs/en/guides/02_new_domain_data.md).

### `barrel_generator`

```bash
dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib
dart tools/barrel_generator/generate.dart --help   # usage
```

Regenerates `*.dart` barrels for every directory under the given path, then runs `dart format` on it through the repo's toolchain (FVM when set up). Run it after **any** file add / rename / delete under `lib/` — and after `build_runner` / `gen-l10n`, because generated files present on disk are exported too (`core_ui_kit` reaches `core_base_ui`'s generated `Assets` that way).

Exit codes: `64` when the path does not exist (it prompts for another path only when run with no argument on a terminal), for a flag, or for a second path; `1` when `dart format` fails — the barrels are written but unformatted. A flag is never taken for a path (`--help` used to be read as a directory name), and `<pkg>/lib/` is the same as `<pkg>/lib` (a trailing separator used to produce `lib/.dart`).

Skipped directories: hidden ones, `lib/gen`, and the platform / build folders (`android`, `ios`, `web`, `build`, …) **outside** `lib/` only — matched as path segments relative to the package root, so `lib/src/widgets/web/` is exported like any other directory. `lib/src/gen` is walked as always.

Skips `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, `firebase_options*`, and files declaring `part of`. Other generated files — `module.module.dart`, `injection.config.dart`, `lib/src/gen/**` — are exported when present.

> [!CAUTION]
> It **removes every hand-written `export` line** from a barrel before regenerating. If you need to re-export something from another package, put the `export` in a regular source file and let the barrel pick that file up.

### `dependency_sync`

`pubspec_dependencies.yaml` at the repo root is the single source of truth for versions.

```bash
dart tools/dependency_sync.dart          # write versions into every package
dart tools/dependency_sync.dart --check  # verify only; exits 1 on drift
dart tools/dependency_sync.dart --help   # usage; any other flag exits 64 without syncing
```

Also repairs broken local `path:` entries. Use `--check` in CI and pre-commit.

> [!NOTE]
> The catalog and every pubspec are read with a YAML parser, so a trailing comment on a header (`dependencies: # runtime`) is fine. The catalog must be a map of at most `dependencies:` and `dev_dependencies:`, each a map of package → **version-constraint string**; anything else — an unknown section, a nested `git:`/`path:` source, an unquoted number, an empty value, a package pinned in both sections, invalid YAML — is refused as `pubspec_dependencies.yaml: <section>.<package>: <problem>` (or `file:line` for invalid YAML), exit `1`, in `--check` too, and nothing is written. An unparsable workspace pubspec is refused the same way before any file is touched. Rewrites replace only the characters of the one value, so comments and formatting stay. `dependency_overrides` is deliberately left alone, and a dependency given as a map (`path:`/`git:`/`sdk:`/`hosted:`) is never overwritten — only a workspace package's `path:` is repaired. Native Gradle dependencies (e.g. `play-services-auth` in `apps/mobile/android/app/build.gradle.kts`) are outside its scope entirely — they have no single source of truth.

### `unused_checker`

```bash
dart tools/unused_checker/check_script.dart              # all four, with a summary
dart tools/unused_checker/check_unused_assets.dart       # assets not referenced
dart tools/unused_checker/check_unused_translate.dart    # .arb keys never used
dart tools/unused_checker/check_unused_file.dart         # orphaned Dart files
dart tools/unused_checker/check_unused_packages.dart     # declared but unused deps
```

Each check resolves the repository root from its own location, so it works from any working directory; a root holding no package is a failure (exit `1`), never a clean result — run from a subdirectory they used to find 0 packages and report success. Every script takes `--help`; any other argument exits `64`.

[Rule 2](../docs/en/reference/01_rules.md#2-explicit-dependency-declaration) has two halves: `arch_check` R5 catches a package imported but not declared; `check_unused_packages.dart` catches one declared but never imported (it scans `lib/`, `bin/`, `test/` and `tool/` — a package with no `lib/`, like `core_tools`, is read whole — so a dependency used only by tests counts as used). Run both before every PR.

There is no blanket allowlist: a declaration is accepted without an import only where it is needed — `flutter` always; `flutter_localizations` and `intl` in a package with an `l10n.yaml` (the gen-l10n output imports them); `json_annotation` next to `json_serializable`; `flutter_svg` when `flutter_gen`'s `flutter_svg` integration is on. `check_unused_file.dart` starts from each `lib/main.dart`, `lib/di/`, routing files, injectable classes and any non-barrel file directly under `lib/`. A package barrel export is not a use: a file the barrel exports counts only when a file importing that barrel names one of its public declarations (a file declaring only extensions or re-exports counts once its barrel is imported), so a toolkit file nothing references is reported.

> [!WARNING]
> The asset / file / translation checkers work by textual reference and will report false positives for anything reached dynamically (a string-built asset path, a key looked up at runtime). Confirm before deleting.

### `check_outdated`

```bash
dart tools/check_outdated.dart
```

Reports packages in `pubspec_dependencies.yaml` with newer versions on pub.dev. In a terminal it then offers a checklist (all pre-selected); typing `a` writes the selected versions to the catalog and runs `dependency_sync` and `pub get`, `q` quits. Without a terminal (CI, a pipe) it only reports.

It exits `1` when resolving the catalog, `pub outdated`, reading its JSON, or applying an update (`dependency_sync`, `pub get`) fails, so a script can tell a failed check from an up-to-date one. It takes no arguments besides `--help`; anything else exits `64`.

### `workspace_setup`

```bash
dart tools/workspace_setup/configure.dart
dart tools/workspace_setup/configure.dart --stub-firebase   # plus compile-only Firebase stubs where absent
dart tools/workspace_setup/configure.dart --help   # what it runs, in order — runs nothing
```

Full setup for a fresh clone. It runs, in order: activate `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n` in every package with an `l10n.yaml`, `build_runner build --workspace`, then the barrel generator for every package with a `lib/` (apps skipped). It is **the** setup step. `pub get` + `build_runner` alone leaves the gitignored `lib/src/gen/gen.dart` barrels missing, and `flutter analyze` then fails on `gen/gen.dart`, `AppLocalizations` and `Assets`.

It works on the repository root whatever the working directory. `--help` / `-h` prints the steps and exits `0`; any argument other than `--stub-firebase` exits `64` **before anything runs** — the script used to ignore its arguments, so `--help` ran the full, destructive setup.

**`--stub-firebase`** — also write **compile-only** Firebase stand-ins, first, before any codegen (`build_runner` must resolve each `firebase_module.dart`'s imports; the list of what was written is printed at the end), for a checkout with no Firebase project, the same files CI writes (its jobs call this flag): a `firebase_options_<flavor>.dart` for every flavor an app's `lib/firebase/firebase_module.dart` imports, and an `android/app/src/<flavor>/google-services.json` for every product flavor of an app whose `android/app/build.gradle(.kts)` applies the Google Services plugin, with `package_name` = `applicationId` + that flavor's `applicationIdSuffix` read from the same file. **Only absent files are written** — real ones are always kept — and every path is printed, followed by a boxed warning that these are not real configs: the app compiles and an APK builds, but push notifications, the FCM token and every other Firebase call do not work. The content lives in `tools/workspace_setup/firebase_stubs.dart`, which imports only `dart:io`: `configure.dart` runs `pub get` itself, so nothing it imports may need a resolved package.

> [!CAUTION]
> There is **no** `configure.sh` and **no** `configure.bat`. Only `configure.dart` exists — invoke it with `dart`, never through a shell wrapper.

### `firebase`

```bash
dart tools/firebase/firebase_config.dart              # the workspace's only app
dart tools/firebase/firebase_config.dart --app mobile # one of several
dart tools/firebase/firebase_config.dart --help       # usage
```

Runs `flutterfire configure` inside the chosen app for each flavour and build mode, producing the three `lib/firebase/firebase_options_*.dart` files that the app's own `lib/firebase/firebase_module.dart` imports (for the sample app, `apps/mobile/lib/firebase/firebase_module.dart`), plus the per-flavour `GoogleService-Info.plist` and `google-services.json`. With more than one app and no `--app`, it lists the apps and exits rather than configure an arbitrary one.

> [!WARNING]
> Those generated files are git-ignored, and `firebase_module.dart` imports **all three unconditionally**. A fresh clone therefore does not compile until this has been run — even for a dev-only build. See [`../getting-started/01_setup.md`](../docs/en/getting-started/01_setup.md).

Must be run from the repository root; the script checks for `pubspec.yaml` and exits otherwise.

It needs the **Firebase CLI installed and logged in**: Node.js + npm, `npm install -g firebase-tools`, and an interactive `firebase login` with a Google account that can access your Firebase project. The script no longer installs the CLI for you: if `firebase` is not on `PATH` it prints the install instructions and exits `1`. When the session is missing or expired it runs `firebase login` **at most twice**, then exits `1` asking you to log in yourself (`firebase login` returns success without logging in when it cannot open a prompt, so an unbounded retry never ended). The FlutterFire CLI, by contrast, is activated through `dart pub global activate` when missing.

The script is interactive — there is no flag form for its answers — so it **refuses to run without a terminal** (exit `1`). An argument other than `--app <id>` / `--help` exits `64`. It prompts for one project ID, which it uses for **every** flavor. For one project per flavor, or for compile-only stubs when you have no Firebase project, see [`../getting-started/01_setup.md`](../docs/en/getting-started/01_setup.md) § 3.

### `theme_generator`

```bash
dart tools/theme_generator/theme_setting.dart              # the workspace's only app
dart tools/theme_generator/theme_setting.dart --app mobile # one of several
dart tools/theme_generator/theme_setting.dart --help       # usage
```

Drives `flutter_native_splash` and `icons_launcher` from the per-flavour configs at the repo root (`flutter_native_splash-*.yaml`, `icons_launcher-*.yaml`).

Before writing anything it checks the app can take them: the app needs `android/` and `ios/` (the configs enable both platforms), must declare `flutter_native_splash` and `icons_launcher` in its `pubspec.yaml`, and the config files must be at the repo root. Any gap is listed and the tool exits `1`. **`--app admin` is refused today** — `apps/admin` has no platform directories and declares neither package. If a generator fails midway, every file it created or changed under the app's `android/`, `ios/` and `web/` is restored, and the tool exits `1`; the copied configs are removed either way. An argument other than `--app <id>` / `--help` exits `64`.

### `android_compliance`

```bash
# Build a release APK of one flavor first (cd apps/mobile && flutter build apk --flavor dev --release), then:
./tools/android_compliance/16kb_check.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk     # macOS / Linux
.\tools\android_compliance\16kb_check.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

Checks an APK (zip alignment, then the ELF alignment of its native `.so` libraries), an APEX, or a directory of native libraries for Android 15+ 16 KB page-size compliance. It takes exactly one path; with none it prints the usage and exits `1`, and `--help` prints it with exit `0`. A file must be an `.apk`, an `.apex` or a single `.so` — anything else (an `.aab` included) exits `1`. An APK that `unzip` cannot read (not a zip, truncated) exits `1`; only "no `lib/*` entry" (unzip exit `11`) is the no-native-libraries pass — every unzip failure used to be reported as that pass. The `.sh` is executable, so the `./` call works as written; the `.bat` is a thin wrapper that runs the `.sh` through Git Bash and returns its exit code. The only tools in the repo that are shell scripts rather than Dart.

### `code_review`

```bash
dart tools/code_review/code_review.dart --all
dart tools/code_review/code_review.dart --changed
dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart
dart tools/code_review/code_review.dart --all --focus architecture,security
dart tools/code_review/code_review.dart --all --language vi   # this run only
```

Gemini-backed review driven by `tools/code_review/review_prompt.md`. Needs a Gemini API key: `GEMINI_API_KEY`, `--api-key`, or — when the tool prompts for one and you agree to save it — the gitignored `tools/code_review/.gemini_api_key`. With no key and no terminal to prompt on (CI, a pipe), it says where to set one on stderr and exits `1`. The key is sent in the `x-goog-api-key` header, never in the URL, and is scrubbed from every error message, so a network failure cannot print it to a terminal or CI log. Run from the repository root, `--all` reviews every `lib/` under `apps/`, `modules/` and `platform/`. A `--file` or `--folder` that does not exist exits `1` before the API key is even read — it used to print "File not found", review nothing and exit `0`. Valid `--focus` values: `security`, `performance`, `bugs`, `style`, `architecture`, `testing`.

- **Always excluded**, whatever `--exclude` adds: generated files (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gen.dart`, `*.mocks.dart`, `lib/src/gen/**`, `firebase_options_*.dart`), tests, and every git-ignored file. (A single `--exclude` used to switch the built-in exclusions off.)
- **`--language`** applies to that run only and is not saved; the default is `reportLanguage` in the tracked `code_review_config.json`, changed with `--config`.
- **The report is always Markdown.** `--format` accepts only `markdown`, kept so scripts passing `--format markdown` still work.
- An unknown option or a stray positional argument exits `64`.

> [!NOTE]
> The GitHub workflow runs this in **advisory mode** — its "fail on critical issues" step has `exit 1` commented out, so it never blocks a PR. See [`../operations/01_cicd.md`](../docs/en/operations/01_cicd.md).

### `coverage_report`

```bash
flutter test --coverage                              # in each package: writes <pkg>/coverage/lcov.info (gitignored)
dart tools/coverage_report/report.dart               # every */coverage/lcov.info under the root
dart tools/coverage_report/report.dart --min 60      # exit 1 when the TOTAL is below 60 %
dart tools/coverage_report/report.dart --min-package 40   # exit 1 when ANY package is below 40 %
```

Prints per-package line coverage as a Markdown table — package, path, files, lines, covered, % and a total row — and appends it to `$GITHUB_STEP_SUMMARY` when that is set (`--no-summary` turns that off). CI Gate 3 runs every package's tests with `--coverage` and then this step, advisory: no threshold, `continue-on-error`, and it runs even when a test failed. Generated files — `*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gr.dart`, `*.mocks.dart`, anything under `gen/` — are excluded, and a line is counted once however many `DA:` records name it. Only files some test loaded appear in `lcov.info`, so an untested file nothing imports does not lower the number. With no `lcov.info` found it exits `1`; a bad argument exits `64`.

### Tests for the tools (`tools/test/`)

Every gate in `pr_quality_check.yml` is one of the scripts above, and a gate that has quietly stopped failing looks exactly like a clean PR. `tools/test/` is what stops that: it runs as the second half of CI Gate 1, right after `arch_check`.

```bash
cd tools && dart test                            # the whole suite, ~15 s
cd tools && dart test test/arch_check_test.dart  # one tool
```

Each test builds a throwaway workspace with `Directory.systemTemp.createTemp` — a few pubspecs, a manifest, a source file — runs the tool against it as a subprocess and asserts the exit code and the output. Nothing touches the real repository. `test/support/tool_harness.dart` compiles each tool to a kernel snapshot once per test file (a snapshot starts in ~0.5 s instead of ~1.7 s), and for `docs_check`, which finds the repository from its own script location, copies the snapshot into the temp workspace at `tools/docs_check/`.

| File | Covers |
|:---|:---|
| `arch_check_test.dart` | A clean and a violating fixture for every rule R1–R15 (R6 warns and still exits `0`), the group DAG edge by edge (ui → state, infra → infra, anything from `domain_core`, foundation → shell, a package outside a group folder) and the module API rules (own domain, another API, a non-foundation platform package, a throwing lookup, R1/R10 imports); an empty workspace fails; an unknown flag exits `64` |
| `composer_test.dart` | `sync` then `verify` passes; an `api` layer is a workspace member only, an API package reached only through a feature joins the workspace, a missing one fails `verify`; a hand-edited region, a module missing from disk, `phase: befor`, an unknown layer and a duplicate module exit `1` naming the key path; a package on disk that no app composes fails `verify` and only warns under `sync` |
| `dependency_sync_test.dart` | `--check`: in step passes; a version mismatch, a malformed catalog and invalid YAML exit `1` |
| `docs_check_test.dart` | A dead path or link exits `1`; a `<placeholder>` span, an allowlisted path and a removed sample bundle (INFO) exit `0`; the root comes from the script, not the cwd; en ↔ vi parity: a missing heading, code block or table row exits `1` with both counts, fences are ignored, an allowlisted difference passes, a stale entry warns, an entry without a reason is refused |
| `module_generator_test.dart` | `--apps` with an unknown id, no value, an empty list or given twice exits `64` and writes nothing; type 6 (API) refuses `<SM>`, a prefix, `--group`, a taken `<name>_api` and resolves to `modules/<name>/api`; `registerInAppManifests` touches every manifest by default and only the listed ones with `apps:`, and adds `api` first to a module's `layers:` |
| `unused_checker_test.dart` | `check_unused_packages`: an unimported declaration is reported (exit `2`), a test-only import counts, each import-less allowance holds only with its reason (`l10n.yaml`, `json_serializable`, `flutter_gen`); `check_unused_file`: a file only its own barrel exports is reported, naming a declaration uses its file, DI and routing files are entry points |
| `firebase_stubs_test.dart` | `--stub-firebase`'s stubs: one Dart file per imported flavor, one `google-services.json` per Gradle product flavor with the suffixed package name (not `signingConfigs`), real files kept, apps without Firebase or the plugin skipped; `configure.dart` reaches no `package:` import |
| `coverage_report_test.dart` | lcov parsing (generated files dropped, a line counted once), the table and total, the job summary, `--min` / `--min-package`, exit `1` with no `lcov.info`, `64` on bad arguments |
| `barrel_generator_test.dart` | A trailing slash on the path; a `web/` directory inside `lib/` is exported, the platform `web/` beside it is not; hand-written exports are replaced |
| `bootstrap_test.dart` | `--dry-run` reports a missing workspace member and app dependency and writes nothing; without it the managed regions are pruned |
| `remove_sample_test.dart` | An API package another module imports is kept (dry run names it, `--apply` keeps its directory and workspace entry and rewrites the manifest to `layers: [api]`), a second run once nothing imports it deletes it, an unimported one goes with its module |

When you change a gate, add the case that would have caught the bug. `package:test` is the only dev dependency (pinned in `pubspec_dependencies.yaml`); fakes are plain files on disk.

---

**Next:** [`04_review_checklist.md`](../docs/en/reference/04_review_checklist.md) · [`01_rules.md`](../docs/en/reference/01_rules.md) · [`../getting-started/03_daily_workflow.md`](../docs/en/getting-started/03_daily_workflow.md)

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
