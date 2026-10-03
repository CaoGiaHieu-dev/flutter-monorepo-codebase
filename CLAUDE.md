# CLAUDE.md

Agent brief for Claude Code. **Every rule lives once, in the registry** —
[`docs/en/reference/01_rules.md`](docs/en/reference/01_rules.md), ids `RULE-NN`. This file cites
ids and never restates a rule; if it disagrees with the registry, the registry wins.

## What this repo is

A Flutter **Pub Workspaces monorepo template**: Clean Architecture + SOLID + MVVM, Provider **and**
BLoC, GetIt/injectable DI, go_router. Apps are composed from `apps/<id>/app_manifest.yaml`; layering
is enforced by CI (`arch_check`, `composer verify`, a DI smoke test), not by review alone. The
modules shipped (auth, cache, home, settings, onboarding, splash, dashboard) are **sample reference
code** — patterns to copy or delete (`remove_sample`), not product logic. Docs are bilingual:
`docs/en/` and `docs/vi/`. Author: CaoGiaHieu-dev.

## Top rules — the ones that get violated

Read the registry row before touching the area. Enforcement first: a gate will catch you anyway.

| Rule | One line | Enforced by |
|:--|:--|:--|
| RULE-30 | All sizing through `context.w/h/sp/r` — no raw doubles, no `16.w` | arch_check R7, R20, review |
| RULE-05 | Only `apps/<id>/lib/di/injection.dart` imports a module; the shell imports none | arch_check R10, R1 |
| RULE-12 | Module-owned contracts: `getItOrNull` / `getAllOrEmpty` + fallback, never `getIt` / `getAll` | arch_check R8 |
| RULE-01 | `platform/*` never depends on `feature_*` / `data_*` / product `domain_*` / `<id>_api` | arch_check R1 |
| RULE-04 | A feature never imports another feature or `data_*`; reach a module via its `<id>_api` | arch_check R3, R2 |
| RULE-03 | Domain is pure Dart — no Flutter, no transport or persistence package, no workspace package but `domain_core` and its own module's domain | arch_check R2 |
| RULE-13 | No eager `@Singleton` on a later-registered type — use `@LazySingleton` | test (`apps/*/test/di_smoke_test.dart`), CI gate 3 |
| RULE-10 | Screen controllers are `@injectable` factories, never singletons | review |
| RULE-21 | Controllers are created at the route; a `Page` never double-wraps its provider | review |
| RULE-51 | Freezed BLoC events are private subclasses, via `part` / `part of` | review |
| RULE-52 | `on<Event>` handlers are `async (event, emit)` — no sync closure calling async | arch_check R18, review |
| RULE-34 | Every user-facing string translated via the feature's ARB + `IFeatureLocalization` | review |
| RULE-35 | ARB keys are `lowerCamelCase` | review |
| RULE-36 | Dialogs / bottom sheets are their own widget classes, never inline builders | review |
| RULE-80 | Everything per-app lives in `apps/<id>/` (manifest, `lib/app/app_profile.dart`, `app_hooks.dart`) — never a constant in `platform/` | composer verify, test, analyzer, review |
| RULE-81 | Every optional shell contract is `provided` or `absent` + reason in the app's `capabilities:` | composer verify, arch_check R16, test (`di_smoke_test`) |
| RULE-82 | A platform difference is read from `PlatformFacts`; no new `Platform.is*` / `kIsWeb` fork | arch_check R17 |
| RULE-16 | Never hand-edit a `composer:managed` region — edit the manifest, run `composer sync` | composer verify (Gate 0) |
| RULE-75 | One barrel per package, regenerated after codegen; never hand-add an `export` | CI barrel gate, review |
| RULE-71 | No `// ignore:` / `// ignore_for_file:` — fix the cause | arch_check R13, review |
| RULE-72 | No `.ps1` scripts | arch_check R12 |
| RULE-40 | `data_sources/`, never `datasources/` | arch_check R14 |
| RULE-78 | The `I` prefix marks interfaces only — never a concrete class | arch_check R15, R3, review |
| RULE-43 | `ErrorHandler.handleError(e)`; data returns `Result.failure`, never throws to UI (RULE-42) | review |
| RULE-77 | A clean analyze is not a build — finish DI/dependency changes with a debug APK | CI gate build |

All 68 rules, grouped 01–09 layering · 10–19 DI · 20–29 routing · 30–39 UI/l10n/a11y ·
40–49 data/storage/db/network · 50–59 state · 60–69 testing/logging/errors · 70–79 tooling/docs ·
80–89 apps/composition: [registry](docs/en/reference/01_rules.md#rule-registry).

## Layout

```text
apps/<id>/                 composition roots — mobile, admin; `composer new` makes a third:
  app_manifest.yaml        what the app is (flavors, env, platforms, capabilities) + what it composes
  README.md                reading path + a GENERATED report (`composer describe --app <id>`)
  lib/app/                 app_profile.dart (generated `facts` + typed tuning), app_hooks.dart (ShellHooks)
  lib/main.dart            runShellApp(profile:, hooks:, configureDependencies:)
  lib/di/injection.dart    100 % generated; lib/firebase/ (mobile only); test/ smoke + profile tests
modules/<id>/
  api/                     <id>_api — contracts other features use (navigator, action handlers)
  domain/                  domain_<id> — pure Dart: entities, use cases, repository interfaces
  data/                    data_<id> — models, data_sources/{remote,local}, repository impls
  feature/                 feature_<id> — pages, widgets, provider/ or bloc/, routing/, utils/
platform/<group>/<pkg>     infrastructure, six groups, dependency direction = arch_check R11:
  layers/domain            domain_core (Result, AppFailure) — the leaf
  foundation/              platform_kernel (getIt helpers, ErrorHandler), core_di (contracts), core_common
  layers/data              data_core (BaseRepository)
  infra/                   core_network, core_storage, core_database, core_notifications — mechanism only
  ui/                      core_responsive, core_base_ui (tokens, global l10n), core_ui_kit (widgets)
  state/                   provider_state_management, bloc_state_management
  shell/                   platform_shell_adapters, platform_app_shell (boot, router, material wrapper)
tools/                     CLI gates and generators (tools/test/ = their tests)
pubspec_dependencies.yaml  the version catalog — the only place versions live (RULE-74)
```

Direction: `Feature → Domain ← Data`; platform never points at `modules/`. Boot, DI group order
(`core` → the app's own `lib/` → `notifications` → `shell` → `ui` → `domain` → `data` → `feature` → `other`) and
router assembly: [`docs/en/architecture/06_app_shell.md`](docs/en/architecture/06_app_shell.md).

## Commands

FVM is optional — write commands bare (RULE-73). Run from the repository root unless shown.

```bash
# Setup on a fresh clone — pub get, gen-l10n, build_runner, then the barrel pass (needed only
# after you add, rename or delete a lib/ file; it is harmless on a fresh clone).
dart tools/workspace_setup/configure.dart
dart tools/workspace_setup/configure.dart --stub-firebase   # + compile-only Firebase stubs (what CI runs)

dart run build_runner build --workspace                      # codegen — no -d flag (RULE-76)
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev   # the root has no android/ios

# The gates, in CI order (.github/workflows/pr_quality_check.yml)
dart tools/composer/composer.dart verify   # Gate 0 — composition matches the manifests
dart tools/arch_check/check.dart           # Gate 1 — R1–R20; --help describes each
cd tools && dart test                      # Gate 1 — the gate tools' own tests
flutter analyze                            # Gate 2 — 0 issues, infos included
cd <package> && flutter test               # Gate 3 — every package with a test/ except tools/ (incl. apps/*: DI smoke test)
dart tools/dependency_sync.dart --check    # Gate 4 — catalog in sync (drop --check to apply)
dart tools/docs_check/check.dart           # Gate 5 — doc paths, en↔vi parity, RULE-ID citations
dart tools/docs_check/check.dart --stale-translations                   # vi files behind their en source
dart tools/docs_check/check.dart --stamp-translations docs/vi/<f>.md    # after syncing one (commit en first)
dart tools/unused_checker/check_unused_packages.dart   # CI's last quality step — declared but never imported (exit 2 = findings)
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # build job

# Generate — always pass every argument; see docs/en/reference/03_tooling.md
dart tools/module_generator/generate.dart 1 <name> "" <SM 1=Provider|2=BLoC|3=none> <route 1=stack|2=nav tab|3=none>
dart tools/module_generator/generate.dart 2 <name>          # domain   (3 = data, 4 = core_<name>, 5 = custom, 6 = api)
dart tools/barrel_generator/generate.dart <package>/lib     # after adding/renaming/deleting a lib/ file
dart tools/composer/composer.dart sync                      # after editing an app_manifest.yaml
dart tools/composer/composer.dart describe --app <id>       # what an app declares + what the shell resolves; --catalog = every key
dart tools/composer/composer.dart new <id> --platforms <a,b> [--modules <x,y>]   # a whole app; never runs flutter create
dart tools/sample_cleanup/remove_sample.dart <bundle>       # dry run; --apply removes; --list lists
```

CI also fails on barrel drift: after `configure.dart --stub-firebase`, `git diff` over `*.dart` must be empty
and no untracked `.dart` file may appear (RULE-75).

Everything else in `tools/` (unused checker, outdated check, AI code review, coverage report,
Firebase config, theme generator, 16 KB page check, `bootstrap` for partial checkouts):
[`docs/en/reference/03_tooling.md`](docs/en/reference/03_tooling.md).

## Workflows

**New module.** `generate.dart 2 <name>` → `generate.dart 3 <name>` → implement entities → repository
interface → use cases → models → data sources → repository impl → `build_runner` → barrels →
`generate.dart 1 <name> "" <SM> <route>` if it has UI. The generator adds it to every
`app_manifest.yaml` (or `--apps <id,id>`) and runs `composer sync`. Guides:
[`01_new_feature`](docs/en/guides/01_new_feature.md), [`02_new_domain_data`](docs/en/guides/02_new_domain_data.md).

**New app.** `composer new <id> --platforms <a,b> --modules <x,y>` → `flutter pub get` → `build_runner` →
`cd apps/<id> && flutter test`; then edit only `app_manifest.yaml` and `lib/app/app_profile.dart`.
Guide: [`13_app_composition`](docs/en/guides/13_app_composition.md).

**Drop a module.** Delete its line from every `apps/<id>/app_manifest.yaml`, then
`composer sync` → **delete the leftover `modules/<id>/` directory** (`composer verify` fails on a package
no app composes) → `flutter pub get` → `build_runner`. Or `remove_sample <bundle> --apply`, which
deletes the directories itself (skill `remove_module`).

**Before you say "done".** The Gate 0–5 commands above for what you touched, plus the debug APK
build after any DI, dependency or type-location change (RULE-77). A DI change is proven by the
smoke test (`cd apps/mobile && flutter test test/di_smoke_test.dart`), not by reading generated files.

## Task → start here

| Task | Skill (`.claude/skills/`) | Guide (`docs/en/guides/`) |
|:--|:--|:--|
| New feature / domain / data / core package | `create_feature_module` | `01_new_feature`, `02_new_domain_data` |
| New API call, use case, repository, model | `implement_domain_data_flow` | `02_new_domain_data`, `08_networking` |
| Screen logic with Provider / with BLoC | `implement_provider_ui` / `implement_bloc_ui` | `03_state_management` |
| New screen, route, nav tab, cross-feature navigation | `implement_navigation_route` | `04_routing` |
| Register something in DI, fix "not registered" | `implement_dependency_injection` | `05_di` |
| Configure an app: platform, flavor, pin, language, palette, hook, capability; a third app | `configure_app` | `13_app_composition` |
| Persist a key-value setting or token | `implement_package_storage` | `06_storage` |
| Tables, offline lists, migrations | `implement_package_database` | `07_database` |
| Let one feature reach another module: an `<id>_api` package (navigator, contracts) | `create_api_package` | `10_cross_feature`, `12_module_isolation` |
| Trigger another feature's UI action | `implement_action_handler` | `10_cross_feature` |
| Remove a module or the shipped samples | `remove_module` | `01_new_feature` § 9 |
| Barrels, version sync, unused code, AI review, `composer describe` / `new` | `run_repo_tooling` | `../reference/03_tooling` |
| Translated string, ARB key, new locale | `localize_feature` | `09_localization_theming` |
| Theme, palette, tokens | — | `09_localization_theming`, `11_design_system` |
| Tablet / foldable / split-screen layout | — | `11_design_system` § 7 |
| Docs, a rule, the changelog, a vi translation | `update_docs` | `CONTRIBUTING` § 5 |
| Crash reporting, analytics | — | `../architecture/06_app_shell` § 2 |
| Work in a partial checkout (one module) | — | `12_module_isolation` § 2 |

## Contracts the shell resolves from modules

All in `core_di` (`platform/foundation/contracts`), all optional — resolved with `getItOrNull` /
`getAllOrEmpty`, so an app composed without the contributing module still boots (RULE-05, RULE-12).

```text
routing     IFeatureRouteModule (stack routes) · INavDestinationModule (nav tab, unique order)
            IAppEntryLocation (first launch) · IDashboardRouteModule (dashboard chrome only)
            IPostSignInLocation (where the shell sends a signed-in user)
session     ISessionState · ISessionRefreshListenable · ISessionGateway · ISignInLocation (where it sends
            a signed-out user) — one bundle, declared together as `session`
app         IAppSplashScreen · IAppTreeWrapper · IFeatureLocalization
observe     IErrorReporter · IAnalytics                      (register one in the app — RULE-67)
```

What an app does with each row is declared in its manifest `capabilities:` (RULE-81); the table of rows is
`SHELL_CONTRACTS` (21 rows: 7 required, 14 optional) — `composer describe --catalog` prints it.
`ISessionStatusStream` (features listening to the session) is for modules only and has no row.

A module's contracts *for other features* (its navigator, action handlers) live in its own
`modules/<id>/api` package (`auth_api`, `home_api`) — RULE-04, RULE-22, RULE-25.

## Where to look

| Need | Go to |
|:--|:--|
| Is this allowed? Why? What enforces it? | [`docs/en/reference/01_rules.md`](docs/en/reference/01_rules.md) — the registry |
| How the system fits together | [`docs/en/architecture/`](docs/en/architecture/01_overview.md) — overview, core, domain, data, features, app shell |
| How to do X (feature, DI, routing, storage, database, networking, l10n, design system, cross-feature, module isolation) | [`docs/en/guides/`](docs/en/guides/) |
| Names, tools, PR checklist | [`02_naming`](docs/en/reference/02_naming.md) · [`03_tooling`](docs/en/reference/03_tooling.md) · [`04_review_checklist`](docs/en/reference/04_review_checklist.md) |
| First run, project tour, daily loop | [`docs/en/getting-started/`](docs/en/getting-started/01_setup.md) |
| A first module end to end (generate, code, test, gates, remove) — verified | [`04_first_feature_tutorial`](docs/en/getting-started/04_first_feature_tutorial.md) |
| CI/CD, Fastlane, release, secrets | [`docs/en/operations/`](docs/en/operations/01_cicd.md) |
| Task recipes for agents | [`.claude/skills/`](.claude/skills/) — configure app, create module, create API package, remove module, localize feature, DI, BLoC/Provider UI, navigation, action handler, domain/data flow, storage, database, repo tooling, update docs |
| Docs contract, commits, PR process | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Other AI tools' entry point | [`.agents/AGENTS.md`](.agents/AGENTS.md) |
| How the repo got here | [`docs/history/restructure-log.md`](docs/history/restructure-log.md) |

## Conventions for your changes

- **Docs ship with the code**, in `docs/en/` **and** `docs/vi/` (same headings, code blocks and
  table rows — `docs_check` fails otherwise; `README.md` ↔ `README.vi.md` likewise). After syncing
  a vi file, stamp it (`--stamp-translations`). State a rule only in the registry; everywhere else
  cite `RULE-NN` and link. Contract: [`CONTRIBUTING.md` § 5](CONTRIBUTING.md#5-documentation-contract).
- **Commits:** Conventional Commits — `<type>(<scope>): <summary>`, lowercase, no trailing period;
  body says why. User-visible changes get a line under `Unreleased` in `CHANGELOG.md`.
- **Generated regions are off-limits:** `composer:managed` blocks (root `workspace:`, app path deps,
  `injection.dart`, the `facts` region of `lib/app/app_profile.dart`, the README `report` region), `*.g.dart`, `*.freezed.dart`, `*.module.dart`, `*.config.dart`, barrel exports.
- **Versions** only in `pubspec_dependencies.yaml`, then `dart tools/dependency_sync.dart`.
- **Tools** in `tools/` print with `stdout.writeln` / `stderr.writeln` (RULE-65) and shell out
  through `tools/shared/toolchain.dart` (RULE-73).
