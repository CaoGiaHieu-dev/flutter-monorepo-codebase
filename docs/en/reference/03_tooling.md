# Tooling Reference

**This file answers:** which script do I run, with what arguments, and when?

**After reading you can:** pick the right tool for any maintenance task and know its failure modes before it bites you.

All tools live in `tools/` and are plain Dart — run them from the **repository root**.

---

## Problem → tool

| Problem | Command |
|---|---|
| **Check the layering rules hold** | `dart tools/arch_check/check.dart` |
| **Check the docs still describe this tree** | `dart tools/docs_check/check.dart` |
| **Which packages are sample code I can delete?** | `dart tools/sample_cleanup/remove_sample.dart --list` |
| **Delete a sample package safely** | `dart tools/sample_cleanup/remove_sample.dart <name>` |
| Create a new feature / domain / data / core package | `dart tools/module_generator/generate.dart …` |
| Added, renamed or deleted a file under `lib/` | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Changed a dependency version | `dart tools/dependency_sync.dart` |
| CI needs to reject version drift | `dart tools/dependency_sync.dart --check` |
| Suspect dead assets / files / translations / packages | `dart tools/unused_checker/check_script.dart` |
| Want to know what is outdated on pub.dev | `dart tools/check_outdated.dart` |
| Fresh clone, need everything wired up | `dart tools/workspace_setup/configure.dart` |
| Set up Firebase for dev / staging / prod | `dart tools/firebase/firebase_config.dart --app mobile` |
| Regenerate splash screen and app icons | `dart tools/theme_generator/theme_setting.dart --app mobile` |
| Check Android 15+ 16 KB page-size compliance | `./tools/android_compliance/16kb_ckeck.sh` |
| AI review of a change | `dart tools/code_review/code_review.dart --changed` |

---

## `arch_check`

Enforces the layering rules mechanically. **Gate 1 of `pr_quality_check.yml`** — it runs before `flutter analyze` because it only reads imports and `pubspec.yaml` files, needs no codegen, and finishes in roughly 200 ms.

```bash
dart tools/arch_check/check.dart          # exits 1 on any blocking violation
dart tools/arch_check/check.dart --help   # full rule descriptions
```

| Rule | What it checks |
|---|---|
| R1 | Dependency direction — no `platform/*` package may import or declare `feature_*` / `data_*` / `domain_*`, except the approved edges |
| R2 | Domain is pure Dart — no `flutter` / `dio` / `retrofit` import, no `flutter` under `dependencies:` |
| R3 | Feature boundaries — no feature imports another feature or a `data_*` package |
| R4 | Public `static const` live in a `utils/` directory (files under `styles/` — `core_base_ui`'s design tokens — are exempt) |
| R5 | Every `package:` import used in `lib/` is declared in that package's `pubspec.yaml` |
| R6 | Generated files still carry their generator header (advisory) |
| R7 | Responsive sizing goes through `BuildContext` — no bare `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm` receiver, in any file that mentions `core_responsive` |
| R8 | A `core_di` contract implemented in a feature package is resolved with `getItOrNull` / `getAllOrEmpty`, never a throwing `getIt` / `getAll` |
| R9 | `platform_kernel` and every `*_contracts` package neither import nor **declare** a Flutter-bound package |
| R10 | Nothing in an app (`apps/<id>/`) imports a module — only `injection.dart`, the composition root, may name one. (`platform/app_shell` is core, so R1 covers it) |

The three approved upward exceptions are hardcoded in the tool **and printed on every run**, with the reason for each — so they cannot quietly rot inside a comment. Adding a fourth means editing the allow-list in `check.dart` — without that the build fails — and recording the edge in `.agents/AGENTS.md` §2, which the tool does not read.

R7 exists because `flutter analyze` cannot see the difference. `core_responsive` ships no `num` extension, so `16.h` cannot resolve against it — but an extension declared in another package, or one someone adds locally, would type-check fine while reading a global that never notifies anyone. Only `context.h(16)` registers an `InheritedWidget` dependency on `ResponsiveScope` and therefore rebuilds when metrics change. The bare form is a silent stale-value bug, and a linter has no rule for it. The check only runs on files that reference `core_responsive`, and matches a numeric or closing-paren receiver followed by `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`.

R10 exists because removability is a promise the template makes in four documents and nothing was checking. `network_config_impl.dart` imported `data_auth` and `domain_auth` to read and refresh the session token, so deleting the auth module broke the app shell at compile time — the one place in the shell that undid what every other file was careful to preserve. `getItOrNull` cannot help: it guards a *lookup*, and the failure here is an *import*, which the compiler resolves long before any lookup runs. The fix is a contract (`IAuthSessionGateway` in `core_di`, implemented by `data_auth`), and the check is one line of policy — an app may import a module package in exactly one file, the composition root, because that file's job is to name what it composes.

R8 exists because removability is a property the app shell depends on, and nothing was holding it. The tool derives the set at run time: every type declared in `core_di`, narrowed to those with an `implements` / `extends` / `as:` binding in a `modules/*/feature` package. A throwing lookup against one of those compiles — the calling package depends on `core_di`, not on the feature — and then crashes at runtime in any build without that feature. Contracts implemented in the app shell (`IThemeStorage`, `ILanguageStorage`) are always registered, so they are deliberately outside the set. The owning feature is exempt from its own contract: if the package is in the build, so is its registration.

R5 is the mirror image of `unused_checker`: that tool finds dependencies *declared but unused*, this one finds them *used but undeclared*. Pub Workspaces hide the second kind entirely — everything resolves locally through the shared `package_config.json` and only breaks when a package is extracted or published.

---

## `composer`

```bash
dart tools/composer/composer.dart list              # every app and its composition
dart tools/composer/composer.dart sync --app mobile # regenerate
dart tools/composer/composer.dart verify            # CI gate 0 — fails on drift
```

Three things had to agree and were maintained by hand: the root `workspace:` list, an app's path dependencies, and its `lib/di/injection.dart`. Adding a module meant editing all three in step, and getting it wrong fails at boot with `"<Type> is not registered"` — invisible to `flutter analyze`.

`composer` generates all three from the apps' `app_manifest.yaml` files — each app's own files from its manifest, and the shared root `workspace:` list from all of them together — but only between `composer:managed:<region>` and `composer:end:<region>` markers. External dependencies, flavors and asset declarations stay hand-written.

The root `workspace:` list is more than what the manifests name: composer follows each composed package's `dependencies` and `dev_dependencies` to every workspace package they reach. That is how `core_responsive`, `core_ui_kit` and `platform_kernel` — which register no DI module, so no `di_groups` entry names them — still become workspace members. A manifest's optional `extra_dependencies:` list is only for a workspace package the app's **own** `lib/` imports without composing it; neither sample app needs one.

Packages are resolved by **name**, discovered by scanning for `pubspec.yaml`. No directory is encoded anywhere, so moving packages needs no change to the tool or to any manifest. Module packages are matched under either naming convention — `domain_auth` and `auth_domain` both resolve.

`--strict` (implied by `verify`) turns "a manifest names a module that is not on disk" from a warning into an error. Without it, `sync` composes what it can find — which is what lets a developer work with only their own module checked out.

Both `sync` and `verify` also **refuse** an app pubspec that declares a managed package by hand outside the markers. Pub rejects a duplicate key, so that one mistake stops the whole workspace resolving — and it is exactly the mistake composer itself once made.

A non-strict sync that skipped anything prints a **`PARTIAL COMPOSITION`** block: the committed files it just rewrote (the root `pubspec.yaml`, plus the `pubspec.yaml` and `injection.dart` of each app it synced), and the `git checkout --` line that restores them. The composition it wrote is correct locally and wrong to commit, and CI Gate 0 catches it either way, because `verify` regenerates from the manifest on a runner where every module is present. See [`12_module_isolation.md`](../guides/12_module_isolation.md).

---

## `docs_check`

**Gate 5 of `pr_quality_check.yml`.** Resolves every repository path the documentation names and fails on the first one that is not there.

```bash
dart tools/docs_check/check.dart            # exits 1 on any dead reference
dart tools/docs_check/check.dart --verbose  # plus a copy-paste allowlist block
```

Two kinds of reference are checked in every Markdown file in the repository — only tool state, build output and fetched native dependencies (`.dart_tool`, `build`, `Pods`, …) are skipped. It used to cover just `docs/`, `.agents/`, `README.md` and `CLAUDE.md`; widening it found 11 dead links in the `.github` guides, a package README and the fastlane README:

| Kind | Example | How it is resolved |
|---|---|---|
| Backticked path | `` `platform/kernel/lib/platform_kernel.dart` `` | Repo-rooted, but only when the span starts with a real top-level directory |
| Markdown link | `[…](../../../tools/arch_check/check.dart)` | Relative to the **file containing the link**, not the working directory |

The top-level-directory test is what makes the check usable. A repository is full of backticked spans that look like paths and are not: `utils/` and `routing/` are conventions that exist in a dozen packages at once, `ViewState` is a type, `flutter pub get` is a command. Treating those as paths produced 817 "failures" on the first run and would have taught everyone to ignore the gate. Anchoring to `platform/`, `modules/`, `apps/`, `tools/`, `docs/`, `.agents/`, `.github/` leaves roughly 1 300 genuine references — and the spans that get skipped are exactly the ones a reviewer can verify by eye anyway.

Spans containing a space are skipped: they are shell lines. Spans containing a `*`, a `{` or a `<` are globs or placeholders, each describing a *set* rather than one file — they are checked as globs (`<name>` matches like `*`) and pass when at least one path fits. The top-level list also keeps `packages/` and a bare `app/`, where nothing lives any more, so a document still pointing there fails instead of being skipped.

Paths that are correctly absent live in `tools/docs_check/allowlist.txt`, one per line, each with the reason it is not on disk. Exactly three reasons qualify:

1. **Generated** — `apps/mobile/lib/di/injection.config.dart`, build output.
2. **Secret** — `apps/mobile/env.prod`, `apps/mobile/android/key.properties`; never committed.
3. **Tutorial** — a file the reader is *told to create* (`app_elevation.dart` in the design-system guide), or a placeholder standing in for the reader's own module (`modules/profile/feature`).

Anything else is drift, and the fix is to correct the document. An entry without a stated reason is not allowed — the moment the allowlist becomes a list of paths somebody silenced, the gate stops being worth running.

> [!NOTE]
> The check deliberately says nothing about whether a document is *correct*, only whether the things it points at exist. That is a low bar, and it is the only bar a machine can hold. Line-number citations (`generate.dart:90-101`) fail it by design — they are the fastest-rotting reference there is, and naming the symbol instead survives every edit above it.

---

## `sample_cleanup`

Answers "which of this is example code, and how do I delete it without breaking the app?".

```bash
dart tools/sample_cleanup/remove_sample.dart --list    # classification table
dart tools/sample_cleanup/remove_sample.dart auth      # dry-run (default)
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

Its source of truth is [`tools/sample_manifest.yaml`](../../../tools/sample_manifest.yaml), which classifies every package as `framework`, `sample` or `shell`. No sample code lives inside a framework package: every sample is a package of its own, so removing one is always a whole-bundle operation.

The dry-run output is the part worth reading. Removing `auth` is not just three directories: it prints the exact lines to strip from the root `pubspec.yaml` and from every app's manifest, pubspec and `injection.dart`, the `core_di` contracts that become dead, **and which other samples break and how** (the `breaks` list in `tools/sample_manifest.yaml` — empty for every sample today) — as well as the couplings that degrade safely, such as `feature_settings` hiding its logout row when `getItOrNull<IAuthActionHandler>()` is null, or `feature_home` showing the signed-out state when the route's `getItOrNull<IAuthStatusStream>()` is null.

Writes are opt-in via `--apply`, and shared files are snapshotted first so a mid-run failure rolls back.

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
| `<dir>` | type `5` only — the package-name prefix: `<dir>_<name>` at `platform/<name>`. A layer word (`feature`, `domain`, `data`, `core`) is refused; use types 1–4 |
| `<sm>` | feature only — `1` Provider · `2` BLoC · `3` none |
| `<route>` | feature only — `1` `IFeatureRouteModule` · `2` `INavDestinationModule` · `3` none |

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1   # feature + Provider + stack route
dart tools/module_generator/generate.dart 1 chat    "" 2 2   # feature + BLoC + bottom-nav tab
dart tools/module_generator/generate.dart 2 payment          # domain micro-package
dart tools/module_generator/generate.dart 3 payment          # data micro-package
```

Run with fewer arguments and it prompts interactively.

**What it does:** creates the directory tree (including `lib/src/utils/`, for every layer), renders templates, adds the module to every `app_manifest.yaml`, runs `composer sync` (which regenerates the root `workspace:` list and each app's `pubspec.yaml` and `lib/di/injection.dart`), then dependency sync, `pub get`, `gen-l10n`, the barrel generator, `build_runner`, and `dart fix --apply` on the new package.

> [!IMPORTANT]
> It never writes the root `workspace:` list, an app's `pubspec.yaml` or `lib/di/injection.dart` itself. Those sit between `composer:managed` markers, and only `composer sync` writes them — an entry added outside the markers is one composer never removes, and hand edits inside them are the drift CI Gate 0 fails on.

**Safety behaviour**

- **Toolchain is verified first.** `assertToolchainAvailable()` runs before anything shared is touched, so a missing SDK fails immediately instead of at step 8.
- **Existing directories are refused.** It will not silently overwrite a package.
- **Rollback on failure.** The shared files it changes — every `app_manifest.yaml`, and what `composer sync` rewrites (the root `pubspec.yaml`, each app's `pubspec.yaml` and `lib/di/injection.dart`) — are snapshotted before any write; if a later step fails they are restored and the new module directory is deleted.
- **FVM is auto-detected** — by every tool that shells out, through `tools/shared/toolchain.dart` — requiring *both* a config file (`.fvmrc` or `.fvm/fvm_config.json`) *and* a working `fvm --version`. Either signal alone gives a wrong answer: this repo pins a version in `.fvmrc` while a given machine may not have `fvm` installed at all.

> [!NOTE]
> Domain and data modules get directories and pubspec wiring only — entities, use cases and repositories are written by hand. See [`../guides/02_new_domain_data.md`](../guides/02_new_domain_data.md).

---

## `barrel_generator`

```bash
dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib
```

Regenerates `*.dart` barrels for every directory under the given path, then formats. Run it after **any** file add / rename / delete under `lib/` — and after `build_runner` / `gen-l10n`, because generated files present on disk are exported too (`core_ui_kit` reaches `core_base_ui`'s generated `Assets` that way).

Skips `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, `firebase_options*`, and files declaring `part of`.

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
> It parses line-by-line rather than with a YAML parser, so `dependency_overrides` and multi-line/anchor syntax are not handled. Native Gradle dependencies (e.g. `play-services-auth` in `apps/mobile/android/app/build.gradle.kts`) are outside its scope entirely — they have no single source of truth.

---

## `unused_checker`

```bash
dart tools/unused_checker/check_script.dart              # all four, with a summary
dart tools/unused_checker/check_unused_assets.dart       # assets not referenced
dart tools/unused_checker/check_unused_translate.dart    # .arb keys never used
dart tools/unused_checker/check_unused_file.dart         # orphaned Dart files
dart tools/unused_checker/check_unused_packages.dart     # declared but unused deps
```

[Rule 2](01_rules.md#2-explicit-dependency-declaration) has two halves: `arch_check` R5 catches a package imported but not declared; `check_unused_packages.dart` catches one declared but never imported (it scans `lib/`, `bin/`, `test/` and `tool/` — a package with no `lib/`, like `core_tools`, is read whole — so a dependency used only by tests counts as used). Run both before every PR.

> [!WARNING]
> The asset / file / translation checkers work by textual reference and will report false positives for anything reached dynamically (a string-built asset path, a key looked up at runtime). Confirm before deleting.

---

## `check_outdated`

```bash
dart tools/check_outdated.dart
```

Reports packages in `pubspec_dependencies.yaml` with newer versions on pub.dev. In a terminal it then offers a checklist (all pre-selected); typing `a` writes the selected versions to the catalog and runs `dependency_sync` and `pub get`, `q` quits. Without a terminal (CI, a pipe) it only reports.

---

## `workspace_setup`

```bash
dart tools/workspace_setup/configure.dart
```

Full setup for a fresh clone: activates `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n`, `build_runner`, then the barrel generator for every package.

> [!CAUTION]
> There is **no** `configure.sh` and **no** `configure.bat`. Only `configure.dart` exists — invoke it with `dart`, never through a shell wrapper.

---

## `firebase`

```bash
dart tools/firebase/firebase_config.dart              # the workspace's only app
dart tools/firebase/firebase_config.dart --app mobile # one of several
```

Runs `flutterfire configure` inside the chosen app for each flavour and build mode, producing the three `lib/firebase/firebase_options_*.dart` files that the app's own `lib/firebase/firebase_module.dart` imports (for the sample app, `apps/mobile/lib/firebase/firebase_module.dart`), plus the per-flavour `GoogleService-Info.plist` and `google-services.json`. With more than one app and no `--app`, it lists the apps and exits rather than configure an arbitrary one.

> [!WARNING]
> Those generated files are git-ignored, and `firebase_module.dart` imports **all three unconditionally**. A fresh clone therefore does not compile until this has been run — even for a dev-only build. See [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Must be run from the repository root; the script checks for `pubspec.yaml` and exits otherwise.

---

## `theme_generator`

```bash
dart tools/theme_generator/theme_setting.dart              # the workspace's only app
dart tools/theme_generator/theme_setting.dart --app mobile # one of several
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
dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart
dart tools/code_review/code_review.dart --all --focus architecture,security
```

Gemini-backed review driven by `tools/code_review/review_prompt.md`. Needs a Gemini API key: `GEMINI_API_KEY`, `--api-key`, or — when the tool prompts for one and you agree to save it — the gitignored `tools/code_review/.gemini_api_key`. Run from the repository root, `--all` reviews every `lib/` under `apps/`, `modules/` and `platform/`. Valid `--focus` values: `security`, `performance`, `bugs`, `style`, `architecture`, `testing`. The report is always Markdown.

> [!NOTE]
> The GitHub workflow runs this in **advisory mode** — its "fail on critical issues" step has `exit 1` commented out, so it never blocks a PR. See [`../operations/01_cicd.md`](../operations/01_cicd.md).

---

**Next:** [`04_review_checklist.md`](04_review_checklist.md) · [`01_rules.md`](01_rules.md) · [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md)
