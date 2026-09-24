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
| **Changed a gate tool — prove it still fails where it should** | `cd tools && dart test` |
| **Which packages are sample code I can delete?** | `dart tools/sample_cleanup/remove_sample.dart --list` |
| **Delete a sample package safely** | `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` (omit `--apply` to preview) — `<bundle>` is one of `auth`, `home`, `settings`, `onboarding`, `dashboard`, `splash`, `cache` |
| Create a new feature / domain / data / core package | `dart tools/module_generator/generate.dart …` |
| Added, renamed or deleted a file under `lib/` | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Changed a dependency version | `dart tools/dependency_sync.dart` |
| CI needs to reject version drift | `dart tools/dependency_sync.dart --check` |
| Suspect dead assets / files / translations / packages | `dart tools/unused_checker/check_script.dart` |
| Want to know what is outdated on pub.dev | `dart tools/check_outdated.dart` |
| Fresh clone, need everything wired up | `dart tools/workspace_setup/configure.dart` |
| No Firebase project, but the app must compile and build | `dart tools/workspace_setup/configure.dart --stub-firebase` |
| How much of each package do the tests cover? | `flutter test --coverage` per package, then `dart tools/coverage_report/report.dart` |
| Set up Firebase for dev / staging / prod | `dart tools/firebase/firebase_config.dart --app mobile` |
| Regenerate splash screen and app icons | `dart tools/theme_generator/theme_setting.dart --app mobile` |
| Check Android 15+ 16 KB page-size compliance | `./tools/android_compliance/16kb_ckeck.sh <apk>` |
| AI review of a change | `dart tools/code_review/code_review.dart --changed` |

---

## `arch_check`

Enforces the layering rules mechanically. **Gate 1 of `pr_quality_check.yml`** — it runs before `flutter analyze` because it only reads imports and `pubspec.yaml` files, needs no codegen, and finishes in roughly 200 ms.

```bash
dart tools/arch_check/check.dart          # exits 1 on any blocking violation
dart tools/arch_check/check.dart --help   # full rule descriptions
```

It takes no other argument: anything besides `--help` (a `--fix`, a typo of `--help`) exits `64` instead of passing for a clean run.

| Rule | What it checks |
|---|---|
| R1 | Dependency direction — no `platform/*` package may import or declare `feature_*` / `data_*` / `domain_*`, except the approved edges |
| R2 | Domain is pure Dart — no `flutter` / `dio` / `retrofit` import, no `flutter` under `dependencies:` |
| R3 | Feature boundaries — no feature imports another feature or a `data_*` package |
| R4 | Public `static const` live in a `utils/` directory (files under `styles/` — `core_base_ui`'s design tokens — are exempt). A package with no public constants needs no `utils/` |
| R5 | Every `package:` import used in `lib/` is declared under that package's `dependencies:` — a `dev_dependencies` entry does not count |
| R6 | Generated files still carry their generator header (advisory) |
| R7 | Responsive sizing goes through `BuildContext` — no bare `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm` receiver, in any file that mentions `core_responsive` |
| R8 | A `core_di` contract implemented under `modules/` — any layer — is resolved with `getItOrNull` / `getAllOrEmpty`, never a throwing `getIt` / `getAll`, outside the module that implements it |
| R9 | `platform_kernel` and every `*_contracts` package neither import nor **declare** a Flutter-bound package |
| R10 | Nothing in an app (`apps/<id>/`) imports a module — only `injection.dart`, the composition root, may name one. (`platform/shell/app_shell` is core, so R1 covers it) |

The three approved upward exceptions are hardcoded in the tool **and printed on every run**, with the reason for each — so they cannot quietly rot inside a comment. Adding a fourth means editing the allow-list in `check.dart` — without that the build fails — and recording the edge in `.agents/AGENTS.md` §2, which the tool does not read.

R7 exists because `flutter analyze` cannot see the difference. `core_responsive` ships no `num` extension, so `16.h` cannot resolve against it — but an extension declared in another package, or one someone adds locally, would type-check fine while reading a global that never notifies anyone. Only `context.h(16)` registers an `InheritedWidget` dependency on `ResponsiveScope` and therefore rebuilds when metrics change. The bare form is a silent stale-value bug, and a linter has no rule for it. The check only runs on files that reference `core_responsive`, and matches a numeric or closing-paren receiver followed by `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`.

R10 exists because removability is a promise the template makes in four documents and nothing was checking. `network_config_impl.dart` imported `data_auth` and `domain_auth` to read and refresh the session token, so deleting the auth module broke the app shell at compile time — the one place in the shell that undid what every other file was careful to preserve. `getItOrNull` cannot help: it guards a *lookup*, and the failure here is an *import*, which the compiler resolves long before any lookup runs. The fix is a contract (`IAuthSessionGateway` in `core_di`, implemented by `data_auth`), and the check is one line of policy — an app may import a module package in exactly one file, the composition root, because that file's job is to name what it composes.

R8 exists because removability is a property the app shell depends on, and nothing was holding it. The tool derives the set at run time: every type declared in `core_di`, narrowed to those with an `implements` / `extends` / `as:` binding in a package under `modules/` — any layer, so `IAuthSessionGateway`, implemented in `data_auth`, is in the set as surely as a feature's navigator — and keyed by the module that implements it. A throwing lookup against one of those compiles — the calling package depends on `core_di`, not on the module — and then crashes at runtime in any build without that module. Contracts implemented in the app shell (`IThemeStorage`, `ILanguageStorage`) are always registered, so they are deliberately outside the set. A module is removed whole, so every package of the implementing module may resolve its contracts eagerly: if one of its packages is in the build, so is the registration.

R5 is the mirror image of `unused_checker`: that tool finds dependencies *declared but unused*, this one finds them *used but undeclared*. Pub Workspaces hide the second kind entirely — everything resolves locally through the shared `package_config.json` and only breaks when a package is extracted or published.

---

## `composer`

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

Packages are resolved by **name**, discovered by scanning for `pubspec.yaml`. No directory is encoded anywhere, so moving packages needs no change to the tool or to any manifest. Module packages are matched under either naming convention — `domain_auth` and `auth_domain` both resolve.

`--strict` (implied by `verify`) turns "a manifest names a module that is not on disk" from a warning into an error. Without it, `sync` composes what it can find — which is what lets a developer work with only their own module checked out.

Both `sync` and `verify` also **refuse**, exit `1`, when a file they generate into — the root `pubspec.yaml`, an app's `pubspec.yaml` or `lib/di/injection.dart` — is missing, or has lost a region's `composer:managed:<region>` / `composer:end:<region>` marker. They name the file and the marker, and `sync` writes nothing. A missing marker used to be a warning followed by "up to date": deleting one and hand-editing what it had guarded passed Gate 0.

Both also **refuse** an app pubspec that declares a managed package by hand outside the markers. Pub rejects a duplicate key, so that one mistake stops the whole workspace resolving — and it is exactly the mistake composer itself once made.

A non-strict sync that skipped anything prints a **`PARTIAL COMPOSITION`** block: the committed files that run actually rewrote — only those; a file that already held this composition is not listed (the candidates are the root `pubspec.yaml`, plus the `pubspec.yaml` and `injection.dart` of each app it synced) — and the `git checkout --` line that restores them. The composition it wrote is correct locally and wrong to commit, and CI Gate 0 catches it either way, because `verify` regenerates from the manifest on a runner where every module is present. See [`12_module_isolation.md`](../guides/12_module_isolation.md).

### `bootstrap` — before composer can run

```bash
dart tools/composer/bootstrap.dart            # prune, from the managed regions, every member not on disk
dart tools/composer/bootstrap.dart --dry-run  # report only
```

`composer.dart` imports `package:path` and `package:yaml`, so it needs a resolved workspace — and a fresh **partial** checkout (a module submodule left uninitialised, i.e. an empty directory) does not resolve: the committed root `workspace:` list and each app's managed path dependencies still name it, and `flutter pub get` refuses the whole workspace. `tools/composer/bootstrap.dart` imports **no package** (only `dart:io` and the `dart:io`-only `OutputFormatter`), so it runs before pub has ever resolved. It removes, from the root `composer:managed:workspace` region and each app's `composer:managed:deps` region only, every entry whose directory has no `pubspec.yaml`, prints what it pruned and the `git checkout --` line that undoes it, and tells you to run `flutter pub get` → `composer.dart sync` → `workspace_setup/configure.dart`. `sync` then rewrites the regions from the manifests.

Exit `0` when it pruned or found nothing to prune (a full checkout — it writes nothing); `1`, writing nothing, when there is no `composer:managed:workspace` region (not run from the root) or when a present package has a **hand-written** path dependency on a missing directory (`modules/auth/data` without `modules/auth/domain`) — pruning cannot fix that, so it names the line and tells you to initialise that submodule too; `64` on an unknown argument. The full sequence: [`12_module_isolation.md` § 3](../guides/12_module_isolation.md#3-working-in-a-partial-checkout).

---

## `docs_check`

**Gate 5 of `pr_quality_check.yml`.** Resolves every repository path the documentation names, collects every one that is not there, prints them grouped by file, then exits 1. References into a sample bundle you removed with `remove_sample` are the one exception — summarised as INFO, never a failure (below).

```bash
dart tools/docs_check/check.dart            # exits 1 on any dead reference or en ↔ vi parity mismatch
dart tools/docs_check/check.dart --verbose  # plus a copy-paste allowlist block and every removed-sample reference
dart tools/docs_check/check.dart --help     # usage; any other argument exits 64
```

Two kinds of reference are checked in every Markdown file in the repository — only tool state, build output and fetched native dependencies (`.dart_tool`, `build`, `Pods`, …) are skipped. It used to cover just `docs/`, `.agents/`, `README.md` and `CLAUDE.md`; widening it found 11 dead links in the `.github` guides, a package README and the fastlane README:

| Kind | Example | How it is resolved |
|---|---|---|
| Backticked path | `` `platform/foundation/kernel/lib/platform_kernel.dart` `` | Repo-rooted, but only when the span starts with a real top-level directory |
| Markdown link | `[…](../../../tools/arch_check/check.dart)` | Relative to the **file containing the link**, not the working directory |

The top-level-directory test is what makes the check usable. A repository is full of backticked spans that look like paths and are not: `utils/` and `routing/` are conventions that exist in a dozen packages at once, `ViewState` is a type, `flutter pub get` is a command. Treating those as paths produced 817 "failures" on the first run and would have taught everyone to ignore the gate. Anchoring to `platform/`, `modules/`, `apps/`, `tools/`, `docs/`, `.agents/`, `.github/` leaves about 1 900 genuine references (at the time of writing) — and the spans that get skipped are exactly the ones a reviewer can verify by eye anyway.

Spans containing a space are skipped: they are shell lines. Spans containing a `*` or a `{` are globs, each describing a *set* rather than one file — they pass when at least one path fits. A span with a `<placeholder>` segment (`modules/<owner>/feature/lib/src/handlers`) is a **template** for the reader's own module, not a reference: only the literal part before the first placeholder must exist (`modules`), so a placeholder path never fails because no current module happens to have that folder. A placeholder path under the long-gone packages/domain directory still fails, because that literal part does not exist. The top-level list also keeps `packages/` and a bare `app/`, where nothing lives any more, so a document still pointing there fails instead of being skipped.

**Removed samples do not fail the gate.** `remove_sample.dart <bundle> --apply` deletes a bundle's packages but never edits `tools/sample_manifest.yaml`, and `docs_check` reads the bundle definitions there: a bundle whose packages are **all** absent from disk is "removed", and a dead reference inside it — a package path, the emptied `modules/<id>` directory, one of its `orphaned_contracts` — is reported as one summary line per bundle instead of a failure:

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

---

## `sample_cleanup`

Answers "which of this is example code, and how do I delete it without breaking the app?".

```bash
dart tools/sample_cleanup/remove_sample.dart --list    # classification table
dart tools/sample_cleanup/remove_sample.dart auth      # dry-run (default)
dart tools/sample_cleanup/remove_sample.dart auth --verbose  # dry-run, every doc reference listed
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

Its source of truth is [`tools/sample_manifest.yaml`](../../../tools/sample_manifest.yaml), which classifies every package as `framework`, `sample` or `shell`. No sample code lives inside a framework package: every sample is a package of its own, so removing one is always a whole-bundle operation.

The dry-run output is the part worth reading. Removing `auth` is not just three directories: it prints the exact lines to strip from the root `pubspec.yaml` and from every app's manifest, pubspec and `injection.dart`, the `core_di` contracts that become dead, **and which other samples break and how** (the `breaks` list in `tools/sample_manifest.yaml` — empty for every sample today) — as well as the couplings that degrade safely, such as `feature_settings` hiding its logout row when `getItOrNull<IAuthActionHandler>()` is null, or `feature_home` showing the signed-out state when the route's `getItOrNull<IAuthStatusStream>()` is null.

Both the dry-run and `--apply` also count the **Markdown references** to the paths the removal deletes — backticked paths and relative links in every `*.md` (`docs/`, `.agents/`, READMEs), matched the way `docs_check` matches them. They are informational: `dart tools/docs_check/check.dart` (CI Gate 5) recognises them as pointing into a removed sample bundle, prints one INFO summary for the bundle and still passes — update those docs at your leisure. That is also why the tool never edits `tools/sample_manifest.yaml`: the bundle definition staying there is how `docs_check` knows. The first 15 are printed; `--verbose` lists them all.

Bundles: `auth`, `home`, `settings`, `onboarding`, `dashboard`, `splash`, `cache` (`--list` prints them with the classification).

Writes are opt-in via `--apply`, and shared files are snapshotted first so a mid-run failure rolls back. Arguments are checked first: an unknown flag (`--aply`), flags without a bundle name, an unknown bundle name, or more than one bundle exits `64` (no arguments at all prints the usage and exits `0`) — a misspelt flag is never silently a dry run, nor ignored next to `--apply`.

---

## `module_generator`

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
| `--group` | types `4`/`5` only — the `platform/` group folder: `foundation` · `layers` · `infra` · `ui` · `state` · `shell` (`--group ui`, `--group=ui`). Default `infra`. What belongs in each group: [`02_core.md`](../architecture/02_core.md). An unknown group, or `--group` on types 1–3, exits 64 |
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

**What a new package declares.** Only the packages its templates import, so it passes `check_unused_packages` from the first run — add `core_network`, `core_storage` and the rest when the code needs them. A feature declares `core_di`, `core_common`, `core_base_ui` and `core_responsive` (every generated page lays out through `AdaptiveContent`, with `AppSpacing` / `AppTextStyles` sizing through context), plus `provider_state_management` + `domain_core` for Provider, or `bloc_state_management` + `core_ui_kit` for BLoC (its loading state is the kit's `LoadingWidget`); only a feature gets `flutter_localizations` and `intl`, which its generated `gen-l10n` output imports. A domain package gets `domain_core` and a repository contract `I<Name>Repository` (in `repositories/`, one placeholder `ping()` returning `Result<void>`). A data package gets `data_core` and a `<Name>RepositoryImpl extends IBaseRepository` (in `repositories_impl/`); when `domain_<name>` already exists it also declares `domain_core` + `domain_<name>`, implements that contract and registers as it (`@LazySingleton(as: I<Name>Repository)`) — so generate the domain first. Core and custom packages start with no workspace dependency.

**Generated tests.** A feature starts with tests that pass untouched, so CI Gate 3 has something to run from the first commit: `test/<name>_page_test.dart` pumps the page under `ResponsiveInit` and the feature's localizations — with its real controller provided above it exactly as the route provides it — and checks the localized title and that it lays out on a phone and a tablet window; `test/<name>_provider_test.dart` (Provider) waits for `initialize()` and expects success, `test/<name>_bloc_test.dart` (BLoC) expects `initial` and then `success` after the `started` event. SM `3` gets the page test only. `flutter_test` is in the feature pubspec's `dev_dependencies`. Replace the real controller with a fake once it takes use cases (see `modules/auth/feature/test/auth_provider_test.dart`).

**Build time.** Nearly all of a run is `build_runner` over the whole workspace (~76 s of ~92 s measured on a warm cache), and ~50 s of that is recompiling the AOT builder script, which a new workspace package forces. `--build-filter` limited to the new package and the apps' `di/` saved nothing (77 s) and left 21 outputs elsewhere unbuilt until the next full build, so the generator keeps the full `build_runner build --workspace`.

**Nav destination order.** A `<route>` `2` feature's `INavDestinationModule.order` is 10 above the highest `order` any existing destination under `modules/*/feature` returns (10 when there is none), so generated tabs never tie. Renumber freely; only the relative order matters.

> [!NOTE]
> Beyond those stubs, entities, use cases, models and data sources are written by hand. See [`../guides/02_new_domain_data.md`](../guides/02_new_domain_data.md).

---

## `barrel_generator`

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

---

## `dependency_sync`

`pubspec_dependencies.yaml` at the repo root is the single source of truth for versions.

```bash
dart tools/dependency_sync.dart          # write versions into every package
dart tools/dependency_sync.dart --check  # verify only; exits 1 on drift
dart tools/dependency_sync.dart --help   # usage; any other flag exits 64 without syncing
```

Also repairs broken local `path:` entries. Use `--check` in CI and pre-commit.

> [!NOTE]
> The catalog and every pubspec are read with a YAML parser, so a trailing comment on a header (`dependencies: # runtime`) is fine. The catalog must be a map of at most `dependencies:` and `dev_dependencies:`, each a map of package → **version-constraint string**; anything else — an unknown section, a nested `git:`/`path:` source, an unquoted number, an empty value, a package pinned in both sections, invalid YAML — is refused as `pubspec_dependencies.yaml: <section>.<package>: <problem>` (or `file:line` for invalid YAML), exit `1`, in `--check` too, and nothing is written. An unparsable workspace pubspec is refused the same way before any file is touched. Rewrites replace only the characters of the one value, so comments and formatting stay. `dependency_overrides` is deliberately left alone, and a dependency given as a map (`path:`/`git:`/`sdk:`/`hosted:`) is never overwritten — only a workspace package's `path:` is repaired. Native Gradle dependencies (e.g. `play-services-auth` in `apps/mobile/android/app/build.gradle.kts`) are outside its scope entirely — they have no single source of truth.

---

## `unused_checker`

```bash
dart tools/unused_checker/check_script.dart              # all four, with a summary
dart tools/unused_checker/check_unused_assets.dart       # assets not referenced
dart tools/unused_checker/check_unused_translate.dart    # .arb keys never used
dart tools/unused_checker/check_unused_file.dart         # orphaned Dart files
dart tools/unused_checker/check_unused_packages.dart     # declared but unused deps
```

Each check resolves the repository root from its own location, so it works from any working directory; a root holding no package is a failure (exit `1`), never a clean result — run from a subdirectory they used to find 0 packages and report success. Every script takes `--help`; any other argument exits `64`.

[Rule 2](01_rules.md#2-explicit-dependency-declaration) has two halves: `arch_check` R5 catches a package imported but not declared; `check_unused_packages.dart` catches one declared but never imported (it scans `lib/`, `bin/`, `test/` and `tool/` — a package with no `lib/`, like `core_tools`, is read whole — so a dependency used only by tests counts as used). Run both before every PR.

> [!WARNING]
> The asset / file / translation checkers work by textual reference and will report false positives for anything reached dynamically (a string-built asset path, a key looked up at runtime). Confirm before deleting.

---

## `check_outdated`

```bash
dart tools/check_outdated.dart
```

Reports packages in `pubspec_dependencies.yaml` with newer versions on pub.dev. In a terminal it then offers a checklist (all pre-selected); typing `a` writes the selected versions to the catalog and runs `dependency_sync` and `pub get`, `q` quits. Without a terminal (CI, a pipe) it only reports.

It exits `1` when resolving the catalog, `pub outdated`, reading its JSON, or applying an update (`dependency_sync`, `pub get`) fails, so a script can tell a failed check from an up-to-date one. It takes no arguments besides `--help`; anything else exits `64`.

---

## `workspace_setup`

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

---

## `firebase`

```bash
dart tools/firebase/firebase_config.dart              # the workspace's only app
dart tools/firebase/firebase_config.dart --app mobile # one of several
dart tools/firebase/firebase_config.dart --help       # usage
```

Runs `flutterfire configure` inside the chosen app for each flavour and build mode, producing the three `lib/firebase/firebase_options_*.dart` files that the app's own `lib/firebase/firebase_module.dart` imports (for the sample app, `apps/mobile/lib/firebase/firebase_module.dart`), plus the per-flavour `GoogleService-Info.plist` and `google-services.json`. With more than one app and no `--app`, it lists the apps and exits rather than configure an arbitrary one.

> [!WARNING]
> Those generated files are git-ignored, and `firebase_module.dart` imports **all three unconditionally**. A fresh clone therefore does not compile until this has been run — even for a dev-only build. See [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Must be run from the repository root; the script checks for `pubspec.yaml` and exits otherwise.

It needs the **Firebase CLI installed and logged in**: Node.js + npm, `npm install -g firebase-tools`, and an interactive `firebase login` with a Google account that can access your Firebase project. The script no longer installs the CLI for you: if `firebase` is not on `PATH` it prints the install instructions and exits `1`. When the session is missing or expired it runs `firebase login` **at most twice**, then exits `1` asking you to log in yourself (`firebase login` returns success without logging in when it cannot open a prompt, so an unbounded retry never ended). The FlutterFire CLI, by contrast, is activated through `dart pub global activate` when missing.

The script is interactive — there is no flag form for its answers — so it **refuses to run without a terminal** (exit `1`). An argument other than `--app <id>` / `--help` exits `64`. It prompts for one project ID, which it uses for **every** flavor. For one project per flavor, or for compile-only stubs when you have no Firebase project, see [`../getting-started/01_setup.md`](../getting-started/01_setup.md) § 3.

---

## `theme_generator`

```bash
dart tools/theme_generator/theme_setting.dart              # the workspace's only app
dart tools/theme_generator/theme_setting.dart --app mobile # one of several
dart tools/theme_generator/theme_setting.dart --help       # usage
```

Drives `flutter_native_splash` and `icons_launcher` from the per-flavour configs at the repo root (`flutter_native_splash-*.yaml`, `icons_launcher-*.yaml`).

Before writing anything it checks the app can take them: the app needs `android/` and `ios/` (the configs enable both platforms), must declare `flutter_native_splash` and `icons_launcher` in its `pubspec.yaml`, and the config files must be at the repo root. Any gap is listed and the tool exits `1`. **`--app admin` is refused today** — `apps/admin` has no platform directories and declares neither package. If a generator fails midway, every file it created or changed under the app's `android/`, `ios/` and `web/` is restored, and the tool exits `1`; the copied configs are removed either way. An argument other than `--app <id>` / `--help` exits `64`.

---

## `android_compliance`

```bash
# Build a release APK of one flavor first (cd apps/mobile && flutter build apk --flavor dev --release), then:
./tools/android_compliance/16kb_ckeck.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk     # macOS / Linux
.\tools\android_compliance\16kb_ckeck.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

Checks an APK (zip alignment, then the ELF alignment of its native `.so` libraries), an APEX, or a directory of native libraries for Android 15+ 16 KB page-size compliance. It takes exactly one path; with none it prints the usage and exits `1`, and `--help` prints it with exit `0`. A file must be an `.apk`, an `.apex` or a single `.so` — anything else (an `.aab` included) exits `1`. An APK that `unzip` cannot read (not a zip, truncated) exits `1`; only "no `lib/*` entry" (unzip exit `11`) is the no-native-libraries pass — every unzip failure used to be reported as that pass. The `.sh` is executable, so the `./` call works as written; the `.bat` is a thin wrapper that runs the `.sh` through Git Bash and returns its exit code. The only tools in the repo that are shell scripts rather than Dart.

> [!NOTE]
> The filename really is `16kb_ckeck` — a typo that is preserved because scripts and docs reference it.

---

## `code_review`

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
> The GitHub workflow runs this in **advisory mode** — its "fail on critical issues" step has `exit 1` commented out, so it never blocks a PR. See [`../operations/01_cicd.md`](../operations/01_cicd.md).

---

## `coverage_report`

```bash
flutter test --coverage                              # in each package: writes <pkg>/coverage/lcov.info (gitignored)
dart tools/coverage_report/report.dart               # every */coverage/lcov.info under the root
dart tools/coverage_report/report.dart --min 60      # exit 1 when the TOTAL is below 60 %
dart tools/coverage_report/report.dart --min-package 40   # exit 1 when ANY package is below 40 %
```

Prints per-package line coverage as a Markdown table — package, path, files, lines, covered, % and a total row — and appends it to `$GITHUB_STEP_SUMMARY` when that is set (`--no-summary` turns that off). CI Gate 3 runs every package's tests with `--coverage` and then this step, advisory: no threshold, `continue-on-error`, and it runs even when a test failed. Generated files — `*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gr.dart`, `*.mocks.dart`, anything under `gen/` — are excluded, and a line is counted once however many `DA:` records name it. Only files some test loaded appear in `lcov.info`, so an untested file nothing imports does not lower the number. With no `lcov.info` found it exits `1`; a bad argument exits `64`.

---

## Tests for the tools (`tools/test/`)

Every gate in `pr_quality_check.yml` is one of the scripts above, and a gate that has quietly stopped failing looks exactly like a clean PR. `tools/test/` is what stops that: it runs as the second half of CI Gate 1, right after `arch_check`.

```bash
cd tools && dart test                            # the whole suite, ~15 s
cd tools && dart test test/arch_check_test.dart  # one tool
```

Each test builds a throwaway workspace with `Directory.systemTemp.createTemp` — a few pubspecs, a manifest, a source file — runs the tool against it as a subprocess and asserts the exit code and the output. Nothing touches the real repository. `test/support/tool_harness.dart` compiles each tool to a kernel snapshot once per test file (a snapshot starts in ~0.5 s instead of ~1.7 s), and for `docs_check`, which finds the repository from its own script location, copies the snapshot into the temp workspace at `tools/docs_check/`.

| File | Covers |
|:---|:---|
| `arch_check_test.dart` | A clean and a violating fixture for every rule R1–R10 (R6 warns and still exits `0`); an empty workspace fails; an unknown flag exits `64` |
| `composer_test.dart` | `sync` then `verify` passes; a hand-edited region, a module missing from disk, `phase: befor`, an unknown layer and a duplicate module exit `1` naming the key path |
| `dependency_sync_test.dart` | `--check`: in step passes; a version mismatch, a malformed catalog and invalid YAML exit `1` |
| `docs_check_test.dart` | A dead path or link exits `1`; a `<placeholder>` span, an allowlisted path and a removed sample bundle (INFO) exit `0`; the root comes from the script, not the cwd; en ↔ vi parity: a missing heading, code block or table row exits `1` with both counts, fences are ignored, an allowlisted difference passes, a stale entry warns, an entry without a reason is refused |
| `module_generator_test.dart` | `--apps` with an unknown id, no value, an empty list or given twice exits `64` and writes nothing; `registerInAppManifests` touches every manifest by default and only the listed ones with `apps:` |
| `firebase_stubs_test.dart` | `--stub-firebase`'s stubs: one Dart file per imported flavor, one `google-services.json` per Gradle product flavor with the suffixed package name (not `signingConfigs`), real files kept, apps without Firebase or the plugin skipped; `configure.dart` reaches no `package:` import |
| `coverage_report_test.dart` | lcov parsing (generated files dropped, a line counted once), the table and total, the job summary, `--min` / `--min-package`, exit `1` with no `lcov.info`, `64` on bad arguments |
| `barrel_generator_test.dart` | A trailing slash on the path; a `web/` directory inside `lib/` is exported, the platform `web/` beside it is not; hand-written exports are replaced |
| `bootstrap_test.dart` | `--dry-run` reports a missing workspace member and app dependency and writes nothing; without it the managed regions are pruned |

When you change a gate, add the case that would have caught the bug. `package:test` is the only dev dependency (pinned in `pubspec_dependencies.yaml`); fakes are plain files on disk.

---

**Next:** [`04_review_checklist.md`](04_review_checklist.md) · [`01_rules.md`](01_rules.md) · [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md)
