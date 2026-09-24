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
| RULE-30 | All sizing through `context.w/h/sp/r` — no raw doubles, no `16.w` | arch_check R7, review |
| RULE-05 | Only `apps/<id>/lib/di/injection.dart` imports a module; the shell imports none | arch_check R10, R1 |
| RULE-12 | Module-owned contracts: `getItOrNull` / `getAllOrEmpty` + fallback, never `getIt` / `getAll` | arch_check R8 |
| RULE-01 | `platform/*` never depends on `feature_*` / `data_*` / product `domain_*` / `<id>_api` | arch_check R1 |
| RULE-04 | A feature never imports another feature or `data_*`; reach a module via its `<id>_api` | arch_check R3 |
| RULE-03 | Domain is pure Dart — no Flutter, Dio, Retrofit, `core_*` | arch_check R2 |
| RULE-13 | No eager `@Singleton` on a later-registered type — use `@LazySingleton` | test (`apps/*/test/di_smoke_test.dart`) |
| RULE-10 | Screen controllers are `@injectable` factories, never singletons | review |
| RULE-21 | Controllers are created at the route; a `Page` never double-wraps its provider | review |
| RULE-51 | Freezed BLoC events are private subclasses, via `part` / `part of` | review |
| RULE-52 | `on<Event>` handlers are `async (event, emit)` — no sync closure calling async | review |
| RULE-34 | Every user-facing string translated via the feature's ARB + `IFeatureLocalization` | review |
| RULE-35 | ARB keys are `lowerCamelCase` | review |
| RULE-36 | Dialogs / bottom sheets are their own widget classes, never inline builders | review |
| RULE-16 | Never hand-edit a `composer:managed` region — edit the manifest, run `composer sync` | composer verify |
| RULE-75 | Barrels regenerate after codegen; never hand-add an `export` | review |
| RULE-71 | No `// ignore:` / `// ignore_for_file:` — fix the cause | arch_check R13 |
| RULE-72 | No `.ps1` scripts | arch_check R12 |
| RULE-40 | `data_sources/`, never `datasources/` | arch_check R14 |
| RULE-78 | The `I` prefix marks interfaces only — never a concrete class | arch_check R15 |
| RULE-43 | `ErrorHandler.handleError(e)`; data returns `Result.failure`, never throws to UI (RULE-42) | review |
| RULE-77 | A clean analyze is not a build — finish DI/dependency changes with a debug APK | CI gate build |

All 65 rules, grouped 01–09 layering · 10–19 DI · 20–29 routing · 30–39 UI/l10n/a11y ·
40–49 data/storage/db/network · 50–59 state · 60–69 testing/logging/errors · 70–79 tooling/docs:
[registry](docs/en/reference/01_rules.md#rule-registry).

## Layout

```text
apps/<id>/                 composition roots: app_manifest.yaml, generated lib/di/injection.dart,
                           one-line main.dart (runShellApp), flavors, lib/firebase/ — mobile, admin
modules/<id>/
  api/                     <id>_api — contracts other features use (navigator, action handlers)
  domain/                  domain_<id> — pure Dart: entities, use cases, repository interfaces
  data/                    data_<id> — models, data_sources/{remote,local}, repository impls
  feature/                 feature_<id> — pages, widgets, provider/ or bloc/, routing/, utils/
platform/<group>/<pkg>     infrastructure, six groups, dependency direction = arch_check R11:
  layers/domain            domain_core (Result, AppFailure) — the leaf
  foundation/              platform_kernel (getIt helpers, ErrorHandler), core_di (contracts), core_common
  layers/data              data_core (IBaseRepository)
  infra/                   core_network, core_storage, core_database, core_notifications — mechanism only
  ui/                      core_responsive, core_base_ui (tokens, global l10n), core_ui_kit (widgets)
  state/                   provider_state_management, bloc_state_management
  shell/                   platform_shell_adapters, platform_app_shell (boot, router, material wrapper)
tools/                     CLI gates and generators (tools/test/ = their tests)
pubspec_dependencies.yaml  the version catalog — the only place versions live (RULE-74)
```

Direction: `Feature → Domain ← Data`; platform never points at `modules/`. Boot, DI group order
(`core` → app → `notifications` → `shell` → `ui` → `domain` → `data` → `feature` → `other`) and
router assembly: [`docs/en/architecture/06_app_shell.md`](docs/en/architecture/06_app_shell.md).

## Commands

FVM is optional — write commands bare (RULE-73). Run from the repository root unless shown.

```bash
# Setup on a fresh clone — pub get, gen-l10n, build_runner, barrels. `pub get` + build_runner
# alone is NOT enough (the gitignored lib/src/gen/gen.dart barrels come from the barrel pass).
dart tools/workspace_setup/configure.dart
dart tools/workspace_setup/configure.dart --stub-firebase   # + compile-only Firebase stubs (what CI runs)

dart run build_runner build --workspace                      # codegen — no -d flag (RULE-76)
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev   # the root has no android/ios

# The gates, in CI order (.github/workflows/pr_quality_check.yml)
dart tools/composer/composer.dart verify   # Gate 0 — composition matches the manifests
dart tools/arch_check/check.dart           # Gate 1 — R1–R15; --help describes each
cd tools && dart test                      # Gate 1 — the gate tools' own tests (~15 s)
flutter analyze                            # Gate 2 — 0 issues, infos included
cd <package> && flutter test               # Gate 3 — every package with a test/ (incl. apps/*: DI smoke test)
dart tools/dependency_sync.dart --check    # Gate 4 — catalog in sync (drop --check to apply)
dart tools/docs_check/check.dart           # Gate 5 — doc paths, en↔vi parity, RULE-ID citations
dart tools/docs_check/check.dart --stale-translations                   # vi files behind their en source
dart tools/docs_check/check.dart --stamp-translations docs/vi/<f>.md    # after syncing one (commit en first)
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # build job

# Generate — always pass every argument; see docs/en/reference/03_tooling.md
dart tools/module_generator/generate.dart 1 <name> "" <SM 1=Provider|2=BLoC|3=none> <route 1=stack|2=nav tab|3=none>
dart tools/module_generator/generate.dart 2 <name>          # domain   (3 = data, 4 = core_<name>, 5 = custom)
dart tools/barrel_generator/generate.dart <package>/lib     # after adding/renaming/deleting a lib/ file
dart tools/composer/composer.dart sync                      # after editing an app_manifest.yaml
dart tools/sample_cleanup/remove_sample.dart <bundle>       # dry run; --apply removes; --list lists
```

Everything else in `tools/` (unused checker, outdated check, AI code review, coverage report,
Firebase config, theme generator, 16 KB page check, `bootstrap` for partial checkouts):
[`docs/en/reference/03_tooling.md`](docs/en/reference/03_tooling.md).

## Workflows

**New module.** `generate.dart 2 <name>` → `generate.dart 3 <name>` → implement entities → repository
interface → use cases → models → data sources → repository impl → `build_runner` → barrels →
`generate.dart 1 <name> "" <SM> <route>` if it has UI. The generator adds it to every
`app_manifest.yaml` (or `--apps <id,id>`) and runs `composer sync`. Guides:
[`01_new_feature`](docs/en/guides/01_new_feature.md), [`02_new_domain_data`](docs/en/guides/02_new_domain_data.md).

**Drop a module.** Delete its line from every `apps/<id>/app_manifest.yaml`, then
`composer sync` → `flutter pub get` → `build_runner`. Or `remove_sample <bundle> --apply`.

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
| Persist a key-value setting or token | `implement_package_storage` | `06_storage` |
| Tables, offline lists, migrations | `implement_package_database` | `07_database` |
| Trigger another feature's UI action | `implement_action_handler` | `10_cross_feature` |
| Barrels, version sync, unused code, AI review | `run_repo_tooling` | `../reference/03_tooling` |
| Translated string, new locale, theme | — | `09_localization_theming`, `11_design_system` |
| Tablet / foldable / split-screen layout | — | `11_design_system` § 7 |
| Crash reporting, analytics | — | `../architecture/06_app_shell` § 2 |
| Work in a partial checkout (one module) | — | `12_module_isolation` § 2 |

## Contracts the shell resolves from modules

All in `core_di` (`platform/foundation/contracts`), all optional — resolved with `getItOrNull` /
`getAllOrEmpty`, so an app composed without the contributing module still boots (RULE-05, RULE-12).

```text
routing     IFeatureRouteModule (stack routes) · INavDestinationModule (nav tab, unique order)
            IAppEntryLocation (first launch) · DashboardRouteModule (dashboard chrome only)
            ISignInLocation / IPostSignInLocation (where the shell sends signed-out / signed-in users)
session     ISessionState · ISessionStatusStream · ISessionRefreshListenable · ISessionGateway
app         IAppSplashScreen · IAppTreeWrapper · IFeatureLocalization
observe     IErrorReporter · IAnalytics                      (register one in the app — RULE-67)
```

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
| Task recipes for agents | [`.claude/skills/`](.claude/skills/) — create module, DI, BLoC/Provider UI, navigation, action handler, domain/data flow, storage, database, repo tooling |
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
  `injection.dart`), `*.g.dart`, `*.freezed.dart`, `*.module.dart`, `*.config.dart`, barrel exports.
- **Versions** only in `pubspec_dependencies.yaml`, then `dart tools/dependency_sync.dart`.
- **Tools** in `tools/` print with `stdout.writeln` / `stderr.writeln` (RULE-65) and shell out
  through `tools/shared/toolchain.dart` (RULE-73).
