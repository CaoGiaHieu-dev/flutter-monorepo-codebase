# Architecture Rules

**This file answers:** what is allowed, what is forbidden, *why*, and what enforces it — for every layer of the monorepo.

**After reading you can:** settle any "is this legal?" argument in review by citing one `RULE-NN`, and know which command proves the answer.

For step-by-step instructions see [`../guides/`](../guides/); for the reasoning behind the layering see [`../architecture/01_overview.md`](../architecture/01_overview.md).

> [!IMPORTANT]
> **This page is the single source of truth for every rule in the repository.** The registry below states each rule once, with a stable `RULE-NN` id. Every other document — `CLAUDE.md`, `.agents/AGENTS.md`, the guides, the skills in `.claude/skills/`, the review checklist, `tools/code_review/review_prompt.md` — cites the id and links here instead of restating the rule. If another page disagrees with this one, this one wins and the other page is the one to fix.

---

## Rule registry

### How to read the registry

- **ID** — `RULE-NN`, stable forever. Ranges group topics; a gap is room to grow. An id is never renumbered or reused.
- **Enforced by** — what stops a violation from merging:

  | Value | Meaning |
  |---|---|
  | `arch_check Rn` | `dart tools/arch_check/check.dart` rule *n* — CI Gate 1, blocks the merge |
  | `analyzer (<lint>)` | `flutter analyze` with that setting or lint — CI Gate 2, 0 issues including infos |
  | `test (<file>)` | a test that fails on a violation — CI Gate 3 |
  | `CI gate N` | a step of `.github/workflows/pr_quality_check.yml`: 0 composer verify · 1 arch_check + `tools/test` · 2 analyze · 3 per-package tests · 4 catalog sync · 5 docs_check · `build` the debug APK job |
  | `composer verify` | Gate 0 — generated composition matches `apps/<id>/app_manifest.yaml` |
  | `docs_check` | Gate 5 — documented paths exist, `docs/en` ↔ `docs/vi` parity |
  | `review` | nothing mechanical — a reviewer holds it, using [`04_review_checklist.md`](04_review_checklist.md) |

- **Verify** — a command you can run from the repository root, or `review`.
- **Details** — the section below (or the guide) that explains the rule, its exceptions and its history.

### 01–09 · Layering and dependencies

| ID | Rule | Why | Enforced by | Verify | Details |
|---|---|---|---|---|---|
| RULE-01 | No `platform/*` package imports or declares a `feature_*`, `data_*`, product `domain_*` or `<id>_api` package — only the three approved `→ domain_core` edges | Core is the innermost ring; an upward edge makes modules unremovable | arch_check R1 | `dart tools/arch_check/check.dart` | [§1](#1-dependency-direction) |
| RULE-02 | Every platform package sits at `platform/<group>/<package>` and its `dependencies:` follow the group DAG (no infra → infra, ui never → state) | Each group stays ownable and replaceable on its own | arch_check R11 | `dart tools/arch_check/check.dart` | [§1 R11](#platform-group-direction-r11) |
| RULE-03 | Domain is pure Dart: no `flutter` / `dio` / `retrofit` / `core_*` import or dependency; `domain_core` has zero workspace dependencies | Domain outlives framework choices | arch_check R2 | `grep -rn "package:flutter" modules/*/domain/lib` (empty) | [§7](#7-domain-is-pure-dart) |
| RULE-04 | A feature never imports another feature or any `data_*` package; it reaches another module only through that module's `<id>_api`, which depends on `platform/foundation/*` and Flutter only | Modules stay independently ownable and removable | arch_check R3 | `dart tools/arch_check/check.dart` | [§6](#module-api-packages) |
| RULE-05 | Every module is removable: in `apps/*` only `lib/di/injection.dart` imports a module package; the shell packages import none | A type import defeats `getItOrNull` — it fails at compile time | arch_check R10, arch_check R1 | remove it from the manifest, `composer sync`, build | [§6](#6-feature-boundaries-and-removability) |
| RULE-06 | Every `package:` import under `lib/` is declared in that package's `dependencies:` (never only `dev_dependencies`); unused entries are removed | One shared `package_config.json` hides an undeclared import until extraction | arch_check R5 | `dart tools/arch_check/check.dart` · `dart tools/unused_checker/check_unused_packages.dart` | [§2](#2-explicit-dependency-declaration) |
| RULE-07 | `platform_kernel` stays pure Dart — no Flutter-bound import or dependency, no transport type | It is every package's dependency list | arch_check R9 | `dart tools/arch_check/check.dart` | [architecture/02_core §1](../architecture/02_core.md) |
| RULE-08 | `core_di` holds product-neutral contracts only: no `domain_*` dependency, a contract carries its own value type (`SessionPrincipal`), returns plain `Widget`s, and prefers a Dart 3 `sealed class` over Freezed | A domain type in the hub makes every consumer depend on one module | arch_check R1 (dependency half), review | `dart tools/arch_check/check.dart` | [§15](#15-cross-feature-communication) |
| RULE-09 | A package's public constants live in its own `utils/` (routes `*_path.dart`, keys `*_storage_keys.dart`, endpoints `*_api_constants.dart`) as `UPPER_SNAKE_CASE`; design tokens stay in `styles/`; no shared cross-domain constants file | A constant has exactly one owner | arch_check R4 | `dart tools/arch_check/check.dart` | [§3](#3-constants-live-in-utils) |

### 10–19 · Dependency injection

| ID | Rule | Why | Enforced by | Verify | Details |
|---|---|---|---|---|---|
| RULE-10 | Screen controllers (Provider, Bloc, Cubit) are `@injectable` factories; only app-wide controllers (`ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider`, `AuthProvider`) are `@lazySingleton` | GetIt never frees a singleton — the next visit reuses stale state | review | review | [§10](#10-controller-lifetime) |
| RULE-11 | Constructor injection only — no `getIt<T>()` inside a ViewModel, Bloc, Repository or UseCase | Dependencies stay visible and replaceable by a hand-written fake | review | review | [guides/05_di §7](../guides/05_di.md) |
| RULE-12 | A contract implemented only under `modules/` is resolved with `getItOrNull` / `getAllOrEmpty` + a fallback outside its own module — never `getIt` / `getAll` | `getAll<T>()` throws when nothing is registered; removing the module crashes boot | arch_check R8 | `dart tools/arch_check/check.dart` | [§6](#6-feature-boundaries-and-removability) |
| RULE-13 | An eager `@Singleton` never depends on a type a later DI group registers — use `@LazySingleton`; `shell` runs before `ui`, `notifications` after the app's own registrations | GetIt throws `"<Type> is not registered"` at boot, and `flutter analyze` cannot see it | test (`apps/*/test/di_smoke_test.dart`), CI gate 3 | `cd apps/mobile && flutter test test/di_smoke_test.dart` | [§5](#5-di-registration-order) |
| RULE-14 | A second interface on one implementation is bound through a `@module` (`SslPinningConfig ← NetworkConfig`) | GetIt resolves the exact type, never a supertype — pinning silently no-ops | test (`apps/*/test/di_smoke_test.dart`), review | `cd apps/mobile && flutter test test/di_smoke_test.dart` | [§15](#15-cross-feature-communication) |
| RULE-15 | Each package declares `@InjectableInit.microPackage()` at `lib/di/module.dart` with no arguments (sole exception: `core_notifications`' `ignoreUnregisteredTypesInPackages`); no monolithic domain/data module | A per-package module is what composer composes and removal deletes | review | review | [guides/05_di §8](../guides/05_di.md) |
| RULE-16 | Composition comes from `apps/<id>/app_manifest.yaml` through `composer sync`: never hand-edit a `composer:managed` region (root `workspace:`, app path dependencies, `injection.dart`); every member declares `resolution: workspace` and the root is the only workspace node | Generated composition cannot drift from the manifest | composer verify (CI gate 0) | `dart tools/composer/composer.dart verify` | [§20](#20-workspace-codegen-and-barrels) |

### 20–29 · Routing, navigation and feature boundaries

| ID | Rule | Why | Enforced by | Verify | Details |
|---|---|---|---|---|---|
| RULE-20 | Never edit `app_router.dart` to add a route: contribute `IFeatureRouteModule` / `INavDestinationModule` / `IAppEntryLocation` through DI | The router is assembled from DI, so a feature stays removable | review | review | [§11](#11-routing) |
| RULE-21 | Controllers are created at the route (`*_route_module.dart` `build`); the `Page` never wraps itself in another `BlocProvider` / `ChangeNotifierProvider` | Double-wrapping builds two controllers; the UI reads the wrong one | review | review | [§10](#10-controller-lifetime) |
| RULE-22 | Cross-feature navigation goes through the owning module's navigator in `<id>_api` (implemented in its feature's `routing/`), resolved with `getItOrNull`; never a hardcoded path or `GoRouter.of(context).go(...)` into another feature; the shell uses `ISignInLocation` / `IPostSignInLocation` | A route path is its owner's private detail | review, arch_check R8 (the lookup) | review | [§11](#11-routing) |
| RULE-23 | `BuildContext` is passed directly from the UI caller — never `NavigatorKeys.*.currentContext` | A global context outlives the widget it belonged to | review | review | [§11](#11-routing) |
| RULE-24 | One bounded UI concern per feature package; `feature_dashboard` is chrome only; `INavDestinationModule` is for primary destinations only, with a unique `order` | A package bundling unrelated screens cannot be removed alone | review, test (`apps/*/test/di_smoke_test.dart` — unique `order`) | review | [§11](#11-routing) |
| RULE-25 | A cross-feature need uses one of the six sanctioned models; a UI action goes through an `I*ActionHandler` in the owner's `<id>_api` (implemented in its `handlers/`) — never for plain navigation or domain logic | Coupling stays explicit and one-directional | review | review | [§15](#15-cross-feature-communication) |

### 30–39 · UI, responsive layout, localization and accessibility

| ID | Rule | Why | Enforced by | Verify | Details |
|---|---|---|---|---|---|
| RULE-30 | Every dimension is scaled through `BuildContext` (`context.w/h/sp/r`, `context.edgeInsets`, tokens): no raw doubles in layout, no bare `16.w`; in an async method read the value before the first `await` | Only a context read rebuilds on rotation, split screen and resize | arch_check R7 (bare extension), review (raw doubles) | `dart tools/arch_check/check.dart` | [§12](#12-responsive-ui) |
| RULE-31 | Reusable `core_ui_kit` widgets use their parameters as received and scale only their own constants; an already-scaled token is never re-scaled | Scaling twice — or never — is a silent layout bug | review | review | [§12](#12-responsive-ui) |
| RULE-32 | A layout is chosen by window size class (`context.windowSizeClass`, `context.adaptive`, `AdaptiveLayout`) — never `Platform.is*`, a device model or an ad-hoc `shortestSide` | One device shows many windows | review | review | [§12](#12-responsive-ui) |
| RULE-33 | Colours, typography, spacing and radii come from the design tokens (`context.colors`, `AppTextStyles.*(context)`, `AppSpacing` / `AppRadius`); numbers change in their `raw*` constants, never hardcoded in a widget | One place to rebrand; light/dark for free | review | review | [guides/11_design_system](../guides/11_design_system.md) |
| RULE-34 | All user-facing text is translated: feature ARBs in `assets/language/`, registered through `IFeatureLocalization` — never by editing `root_app.dart`; global strings only in `core_base_ui`; `core_ui_kit` has no ARB | Delegates collected from DI keep a feature removable | review | `dart tools/unused_checker/check_unused_translate.dart` | [§13](#13-localization-and-assets) |
| RULE-35 | ARB keys are `lowerCamelCase` | `gen-l10n` copies the key into a getter, and generated code is not analysed | review | review | [§13](#13-localization-and-assets) |
| RULE-36 | Every dialog and bottom sheet is its own widget class (`*_dialog.dart` → `…Dialog`, `*_bottom_sheet.dart` → `…BottomSheet`), never an inline tree in a `showDialog` / `showModalBottomSheet` builder | Reusable, testable, reviewable | review | review | [§14](#14-dialogs-and-bottom-sheets) |
| RULE-37 | Feature-specific assets live in the feature's `assets/`; `core_base_ui` holds only global assets and strings, and no widget | A global asset dump couples every feature | review | `dart tools/unused_checker/check_unused_assets.dart` | [§13](#13-localization-and-assets) |
| RULE-38 | Text follows the OS font size: never `withNoTextScaling` or `TooltipVisibility(visible: false)` (the shell caps it at 2.0), never a fixed-height text container; an icon-only button carries a `tooltip`, a meaningful image a `semanticLabel` | Low-vision and screen-reader users | test (`platform/shell/app_shell/test/accessibility_test.dart`), review | `cd platform/shell/app_shell && flutter test test/accessibility_test.dart` | [§19](#19-accessibility) |
| RULE-39 | Tap targets are at least 48 × 48 dp (`kMinInteractiveDimension`); a start/end side uses `edgeInsetsDirectional`, not physical `left` / `right` | Motor accessibility; right-to-left locales | review | review | [§19](#19-accessibility) |

### 40–49 · Domain, data, storage, database and network

| ID | Rule | Why | Enforced by | Verify | Details |
|---|---|---|---|---|---|
| RULE-40 | Data sources live in `data_sources/remote/` and `data_sources/local/` — never `datasources/` | One convention in every module | arch_check R14 | `dart tools/arch_check/check.dart` | [§8](#8-data-layer) |
| RULE-41 | A data source returns Models (the one wrapper: `BaseEntity<T>`), never Entities or a generated type (a Drift row converts at the boundary); Models implement `BaseModel<E>` with `.toEntity()` | Transport and persistence types stay inside the data package | review | review | [§8](#8-data-layer) |
| RULE-42 | `RepositoryImpl` extends `IBaseRepository` and wraps work in `execute()` / `executeSync()`; the data layer never throws to UI — it returns `Result.failure(AppFailure)` | Failures cross the boundary as values | review | review | [§8](#8-data-layer) |
| RULE-43 | Errors are classified with `ErrorHandler.handleError(e)` — never an invented `AppFailure.fromException()`; a new exception family (Firebase, platform) registers an `ErrorClassifier` | An unclassified error collapses to code 9999, "Unknown error occurred" | review | review | [§8](#8-data-layer) |
| RULE-44 | `core_storage` defines no keys: each consumer declares its own `StorageValue<T>`, keyed from its own `utils/*_storage_keys.dart`, never hands it to another package (publish a `core_di` interface instead), and chooses `secure` for tokens/PII, `pref` for settings | A shared key object lets any package read another's data | review | review | [§4](#4-package-owned-storage) |
| RULE-45 | A storage owner is a singleton (`@singleton` / `@lazySingleton` / `@Singleton(as:)`) with `@PostConstruct(preResolve: true)` — never `@injectable` | A factory hands out empty caches, and getters return `null` silently | review | review | [§4](#4-package-owned-storage) |
| RULE-46 | A package that needs SQL declares its own Drift database (tables, DAO as `part of` it) on top of `core_database`; there is no shared `AppDatabase` | Drift binds tables at compile time — a shared database owns every table | review | review | [guides/07_database](../guides/07_database.md) |
| RULE-47 | A migration is registered typed to its database — `@LazySingleton(as: IDatabaseMigration<YourDatabase>)` — and the database's `@preResolve` open carries `@Order(1)` | An untyped registration is never collected; the step silently never runs | review | review | [guides/07_database §4](../guides/07_database.md) |
| RULE-48 | SSL pinning needs `SslPinningConfig` bound in its own right (RULE-14) **and** non-empty `sslPinningHashes` (leaf + backup); the certificate bypass exists only in a debug `--flavor dev` build | Either gap silently disables pinning | test (`apps/*/test/di_smoke_test.dart` — binding), review (hashes) | `cd apps/mobile && flutter test test/di_smoke_test.dart` | [guides/08_networking §5](../guides/08_networking.md) |
| RULE-49 | Entities are Freezed with `const Class._()`; a use case is `@injectable`, does one thing and returns `Result<T>` | One immutable, uniform domain surface | review | review | [§7](#7-domain-is-pure-dart) |

### 50–59 · State management

| ID | Rule | Why | Enforced by | Verify | Details |
|---|---|---|---|---|---|
| RULE-50 | A BLoC feature uses `BaseBloc` + Freezed events (`BaseCubit` only when events are unnecessary); a Provider feature extends `BaseProvider<T>` and uses `executeOperation` | One pattern per state library | review | review | [§9](#9-freezed-bloc-and-state) |
| RULE-51 | Freezed event subclasses are private (`= _HomeStarted`), and the Bloc uses `part` / `part of` for `_event.dart`, `_state.dart` and `_bloc.freezed.dart` | Events are the Bloc's private API | review | review | [§9](#9-freezed-bloc-and-state) |
| RULE-52 | Every `on<Event>` handler is `async` and takes `(event, emit)` — never a sync closure calling unawaited async work | Otherwise: "emit was called after an event handler completed normally" | review, analyzer (unawaited_futures) | `flutter analyze` | [§9](#9-freezed-bloc-and-state) |
| RULE-53 | A `BlocViewState<T>` state settles through `emitResult` (`BlocResultMixin` / `CubitResultMixin`); a custom state ends every branch in a terminal state; generic code writes the type argument (`BlocViewState<T>.loading()`, never `const BlocViewState.loading()`) | A `const` state inside a `<T>` helper is `BlocViewState<Never>` and never compares equal | review | review | [§9](#9-freezed-bloc-and-state) |
| RULE-54 | Cross-feature state is shared through a neutral `Stream` / `ValueListenable` interface, never a Bloc or Provider instance; the owner registers the concrete `@singleton` and binds the interface in a `@module` | Features on different state libraries stay decoupled | review | review | [§15](#15-cross-feature-communication) |

### 60–69 · Testing, logging and error reporting

| ID | Rule | Why | Enforced by | Verify | Details |
|---|---|---|---|---|---|
| RULE-60 | Tests live in the package's own `test/`; Flutter packages use `flutter_test`, pure-Dart ones (`domain_core`, `tools`) `package:test` | CI Gate 3 discovers every `test/` directory by itself | CI gate 3 | `cd <package> && flutter test` | [§17](#17-testing) |
| RULE-61 | Fakes are hand-written — no mockito, no mocktail | No test codegen; a fake documents the contract it fakes | review | `grep -rnE "mockito\|mocktail" --include=pubspec.yaml .` (empty) | [§17](#17-testing) |
| RULE-62 | A widget test that scales wraps the widget under test in `ResponsiveInit` | `ResponsiveScope.of` asserts instead of silently falling back to unscaled values | test (the widget test fails on the assert) | `cd <package> && flutter test` | [§17](#17-testing) |
| RULE-63 | Each app keeps `test/di_smoke_test.dart`, which boots its real DI graph for every flavor; a plugin touched during DI (`@preResolve`, `@PostConstruct(preResolve: true)`) gets its test double there | It catches DI ordering and missing registrations before a device does | test (`apps/*/test/di_smoke_test.dart`), CI gate 3 | `cd apps/mobile && flutter test` | [§17](#17-testing) |
| RULE-64 | A change to a gate tool (`arch_check`, `composer`, `docs_check`, `dependency_sync`, the barrel generator, …) adds the case that would have caught the bug to `tools/test/` | An untested gate rots silently | CI gate 1 (`tools/test`) | `cd tools && dart test` | [§17](#17-testing) |
| RULE-65 | Runtime diagnostics go through `dynamic_logger` (`DynamicLogger.log`), never `print`; CLI tools write with `stdout.writeln` / `stderr.writeln` | `print` reaches release logs and cannot be filtered | analyzer (avoid_print) | `flutter analyze` | [§18](#18-logging-error-reporting-and-secrets) |
| RULE-66 | Secrets are never committed (prod env, keystores, API keys stay gitignored) and never logged (`Authorization` / `Cookie` headers and credential fields are redacted; network logging is `kDebugMode`-gated) | Git history and device logs leak | review | review | [§18](#18-logging-error-reporting-and-secrets) |
| RULE-67 | Crash and error reporting plugs in by registering an `IErrorReporter` (and optionally `IAnalytics`) in the app — never by setting `FlutterError.onError` / `PlatformDispatcher.instance.onError` yourself | The shell's hooks chain every handler; overwriting one drops the rest | review | review | [§18](#18-logging-error-reporting-and-secrets) |

### 70–79 · Tooling, repository hygiene and documentation

| ID | Rule | Why | Enforced by | Verify | Details |
|---|---|---|---|---|---|
| RULE-70 | `flutter analyze` reports 0 issues — infos included — under `strict-casts`, `strict-inference`, `strict-raw-types` and the extra lints | Strict typing catches what review misses | analyzer, CI gate 2 | `flutter analyze` | [§16](#analyzer-strictness) |
| RULE-71 | No lint suppression in hand-written Dart (`// ignore:`, `// ignore_for_file:`, a rule turned off in `analysis_options.yaml`); a deprecation is migrated after researching the replacement | A suppression hides the next real bug | arch_check R13 | `dart tools/arch_check/check.dart` | [§16](#16-tooling-and-code-hygiene) |
| RULE-72 | No PowerShell (`.ps1`) scripts: prefer a cross-platform `.dart` tool; `.sh` / `.bat` only when Dart cannot do the job | Windows execution policy blocks `.ps1` | arch_check R12 | `dart tools/arch_check/check.dart` | [§16](#16-tooling-and-code-hygiene) |
| RULE-73 | Commands are written without an `fvm` prefix; a tool that shells out detects FVM through `tools/shared/toolchain.dart` | `.fvmrc` does not mean `fvm` is installed | review | review | [§16](#16-tooling-and-code-hygiene) |
| RULE-74 | Dependency versions live only in `pubspec_dependencies.yaml` and reach members through `dart tools/dependency_sync.dart` | One catalog, no per-package drift | CI gate 4 | `dart tools/dependency_sync.dart --check` | [§16](#16-tooling-and-code-hygiene) |
| RULE-75 | The barrel generator re-runs after a `lib/` file is added, renamed or deleted — after gen-l10n / build_runner — and nobody hand-adds an `export` to a barrel | The generator deletes hand-written exports and exports the generated files on disk | review | `dart tools/barrel_generator/generate.dart <package>/lib` | [§20](#20-workspace-codegen-and-barrels) |
| RULE-76 | Generated files (`*.g.dart`, `*.freezed.dart`, `*.module.dart`, `*.config.dart`) are never hand-edited; codegen is `dart run build_runner build --workspace`, without `-d` | The next run destroys the edit | arch_check R6 (warning), review | `dart run build_runner build --workspace` | [§20](#20-workspace-codegen-and-barrels) |
| RULE-77 | A clean analyze is not a build: a DI, dependency or type-move change ends with a debug APK build, and a type used by generated code is imported from its real home, never through a `show`-limited re-export | Analysis excludes generated code | CI gate build | `cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev` | [§20](#20-workspace-codegen-and-barrels) |
| RULE-78 | Files, classes and packages follow the naming table (`_page`, `_provider`, `_bloc`, `_usecase`, `_entity`, `i_<name>_repository`, `_repository_impl`, layer prefixes `core_` / `domain_` / `data_` / `feature_`); the `I` prefix marks an interface, never a concrete class | A name says what a file is | arch_check R15 (`I` prefix), review | `dart tools/arch_check/check.dart` | [02_naming](02_naming.md) |
| RULE-79 | Docs change in the same PR as the code, in `docs/en` **and** `docs/vi` with the same shape; every repo path they name exists; a rule is stated once — here — and cited elsewhere as `RULE-NN` | Drifting docs teach the wrong pattern | docs_check (CI gate 5), review | `dart tools/docs_check/check.dart` | [CONTRIBUTING § 5](../../../CONTRIBUTING.md#5-documentation-contract) |

### Adding or changing a rule

1. Add a row in the matching range with the next free id — never renumber, never reuse. A retired rule keeps its row, marked **retired**, with where it went.
2. Name what enforces it. If nothing mechanical does, write `review` — do not imply a gate that does not exist. When a rule becomes machine-checked, update its **Enforced by** in the same PR.
3. Put the explanation (why, exceptions, history) in the section below or in the right guide, and link it from **Details**.
4. Mirror the row in [`docs/vi/reference/01_rules.md`](../../vi/reference/01_rules.md). If the rule is among the most violated, add its one-liner to the top-rules list in `CLAUDE.md` and `.agents/AGENTS.md` — as an id and one line, not a paraphrase.

---

## 1. Dependency direction

Registry: RULE-01 · RULE-02 · RULE-03.

**Rule.** Dependencies point inward. `Feature → Domain ← Data`, with `core/*` as infrastructure underneath. **No `core/*` package may depend on `feature_*`, `data_*` or `domain_*`** — neither by import nor by a `pubspec.yaml` entry — except the approved `→ domain_core` edges below. `arch_check` rule **R1** blocks every other edge.

**Why.** Core is the innermost infrastructure ring. If core reaches upward, the ring closes into a cycle and nothing above it can be removed or reused independently.

**Domain sits at the centre and depends on nothing.** Verified state:

| Package | Workspace dependencies | Flutter SDK |
|---|---|---|
| `domain_core` | **none** | no |
| `domain_auth` | `domain_core` | no |

### Approved upward exceptions

Only these three exist. Adding a fourth requires updating this page (RULE-01, both locales) and the allow-list in `tools/arch_check/check.dart` — the checker fails the build otherwise.

| Exception | Reason |
|---|---|
| `provider_state_management → domain_core` | Needs `Result<T>` and `PaginatedEntity<T>` for `executeOperation` / `PaginatedViewWidget`. |
| `platform_kernel → domain_core` | `ErrorHandler` produces `AppFailure`, which lives in `domain_core` as part of the `Result` contract. Core→Domain is the *correct* Clean Architecture direction. |
| `bloc_state_management → domain_core` | `BlocViewState.error` carries `AppFailure` directly, so the base state type needs it. |

> [!NOTE]
> These three are the only `platform → domain_core` edges. Every other platform edge follows the group direction (`docs/en/architecture/02_core.md` § 0): `ui` never depends on `state`, `infra` never on another infra package, and the foundation never on `ui` or a transport. `core_ui_kit` declares no state-management package — `LoadMoreListView` lives in `provider_state_management` (`state → ui` is the allowed direction) — and `provider_state_management` still ships its own `DefaultLoadingWidget` / `DefaultEmptyWidget` in `lib/src/base_view/default_state_widgets.dart` instead of borrowing from `core_ui_kit`. The kernel names no Dio type: `core_network` contributes `DioFailureClassifier` through `ErrorHandler.registerClassifier`.

### Platform group direction (R11)

Inside `platform/`, `arch_check` rule **R11** holds the group DAG. The group is the folder — `platform/<group>/<package>` — and a package outside a known group folder is itself a violation. Only `dependencies:` are checked: a dev dependency never ships (`platform_app_shell`'s tests use `core_storage` for fakes).

| Group (folder) | May declare platform packages of |
|---|---|
| `layers/domain` (`domain_core`) | nothing — the leaf |
| `foundation` | foundation, `layers/domain` |
| `layers/data` (`data_core`, any other `layers/*`) | foundation, `layers/domain` |
| `infra` | foundation, layers — never another infra package |
| `ui` | foundation, ui |
| `state` | foundation, layers, ui |
| `shell` | every group |

R11 allows an edge by group; R1 still demands its approved list for any edge into `domain_core` / `data_core` from a core package.

**Verify**

```bash
# R1 + R11 — the authoritative check; prints the approved edges on every run
dart tools/arch_check/check.dart

# core must never name a feature, data or product domain package
grep -rn "package:feature_\|package:data_" platform/*/*/lib
grep -lE "^  (feature_|data_)" platform/*/*/pubspec.yaml
grep -rn "package:domain_" platform/*/*/lib | grep -v "package:domain_core"

# domain must never touch Flutter
grep -rn "package:flutter" modules/*/domain/lib
```

`arch_check` must pass, and the four greps must return nothing.

❌ **Wrong** — a core package borrowing a feature widget:
```dart
// platform/state/provider/lib/src/base_view/base_view_widget.dart
import 'package:feature_auth/feature_auth.dart';   // core → feature
```

✅ **Right** — define the fallback inside the core package:
```dart
import 'default_state_widgets.dart';   // ships with the package
```

---

## 2. Explicit dependency declaration

Registry: RULE-06.

**Rule.** Every `package:` import used under `lib/` must have a matching entry in that package's `pubspec.yaml`. Production imports go in `dependencies`, never `dev_dependencies`. Remove entries that are no longer used.

**Why.** Pub Workspaces share one `package_config.json`, so an undeclared import **still compiles locally**. The breakage only appears when the package is extracted or published — and stale entries create phantom coupling that hides real layering violations.

**Verify** — the two halves are checked by two tools:

```bash
dart tools/arch_check/check.dart                      # R5: imported under lib/ but missing from `dependencies:` (dev_dependencies does not count)
dart tools/unused_checker/check_unused_packages.dart  # declared in `dependencies:` but never imported
```

---

## 3. Constants live in `utils/`

Registry: RULE-09.

**Rule.** Every package, at every layer, keeps its own public constants in a `utils/` folder inside that package. A package with no constants needs no `utils/` folder — `arch_check` rule **R4** flags a public `static const` outside `utils/` (or `styles/`) and never asks for an empty folder. A constant has exactly **one** owner. Creating a shared cross-domain constants file is forbidden.

**Why.** A shared constants file lets any package read — and typo — another domain's keys. Storage keys and API endpoints are the two that most invite such a god-object; both belong to the package that owns the data.

Applied conventions:

| Kind | Location | Real example |
|---|---|---|
| Route paths | `lib/src/utils/<feature>_path.dart` | `modules/home/feature/lib/src/utils/home_path.dart` |
| Storage keys | `lib/src/utils/<owner>_storage_keys.dart` | `modules/auth/data/lib/src/utils/auth_storage_keys.dart` |
| API endpoints | `lib/src/utils/<owner>_api_constants.dart` | `modules/auth/data/lib/src/utils/auth_api_constants.dart` |

Constant classes use a private constructor and `UPPER_SNAKE_CASE` members:

```dart
// modules/auth/data/lib/src/utils/auth_storage_keys.dart
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

> [!NOTE]
> **Approved exception — design tokens.** `AppSpacing`, `AppRadius`, `AppTextStyles`, `AppGradients`, `AppShadows` stay in `platform/ui/design_system/lib/src/styles/`, *not* in `utils/`.
>
> They are the public API of the design system, and `styles/` carries that meaning where `utils/` reads as "miscellaneous". Moving them would break every doc reference for no gain. **Do not "fix" this in a future audit.**

Constants evicted from `core_common`, recorded so nobody re-adds them:

| Was | Now | Why |
|---|---|---|
| `StorageKeyConstants` | deleted → per-owner `utils/` keys (§ 4) | held every domain's storage keys |
| `ApiConstants` | `AuthApiConstants` in `modules/auth/data/lib/src/utils/` | held only auth endpoints |
| `NotificationConstants` | `platform/infra/notifications/lib/src/utils/` | belongs to the notifications package |
| `AnalyticsConstants`, `SocketConstants`, `FirebaseRemoteConfigConstants` | deleted | zero references; dead scaffolding |

The bottom of the stack keeps only genuinely global values. Today that is `EnvConstants` (`String.fromEnvironment` wiring) and `ErrorCodes` (the failure codes `ErrorHandler` assigns when there is no HTTP status). Both live under `platform_kernel`'s `lib/src/utils/` and are re-exported by `core_common`.

---

## 4. Package-owned storage

Registry: RULE-44 · RULE-45.

**Rule.** `core_storage` provides the **mechanism only** and defines zero keys. Each consumer injects `StorageManager`, declares its own `StorageValue<T>`, and keys it from its own `utils/` class.

**Why.** A single shared object holding every domain's `StorageValue`s would let anyone who injected it read or clear another feature's data. Isolation is enforced by the dependency graph instead: a package that does not declare `data_auth` cannot reach `AuthStorageKeys`.

Registration is **mandatory as a singleton** plus `@PostConstruct(preResolve: true)`:

```dart
// modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );
```

> [!CAUTION]
> Registering a storage owner as `@injectable` (factory) is **forbidden**. Every injection would build a new instance with an empty in-memory cache, so synchronous getters silently return `null` — no error, just wrong data.

Backend choice is explicit: `StorageType.secure` for tokens and PII, `StorageType.pref` for settings and flags. Never hand one package's `StorageValue` to another — publish an interface on `core_di` instead (as `IThemeStorage` / `ILanguageStorage` do).

Current owners:

| Owner | Package | Keys | Backend |
|---|---|---|---|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | secure |
| `ThemeStorageImpl` | app shell (`platform_shell_adapters`) | `themeMode` | pref |
| `LanguageStorageImpl` | app shell (`platform_shell_adapters`) | `locale` | pref |
| `AppBootStorage` | app shell (`platform_shell_adapters`) | `viewed_onboard` | pref |

Full walkthrough: [`../guides/06_storage.md`](../guides/06_storage.md).

---

## 5. DI registration order

Registry: RULE-13 · RULE-63.

**Rule.** An eager `@Singleton` must never depend on a type registered by a module that initialises **later** in `configureDependencies()`. Use `@LazySingleton` when the dependency comes from a later module.

**Why.** GetIt throws `"<Type> is not registered"` during boot. Modules initialise in the order declared in `apps/mobile/lib/di/injection.dart`, which is generated from the manifest's `di_groups`: `core` (before), then — after the app's own registrations — `notifications`, `shell`, `ui`, `domain`, `data`, `feature`, `other` (after). `apps/admin` has no `notifications` group.

Two constraints are live here. `shell` before `ui`: `ThemeProvider` in `core_base_ui` injects `IThemeStorage`, which `platform_shell_adapters` registers (first in the `shell` group) — swap the two groups and boot throws. And `notifications` after the app's own registrations: `PushNotificationService` is eager and injects the `FirebaseOptions` the app registers, so `core_notifications` cannot sit in `core`. (`NetworkConfigImpl` used to be the example, injecting `AuthLocalDataSource` from a later module; it now reads the session through `ISessionGateway` at call time and has no such dependency.)

> [!CAUTION]
> **`flutter analyze` cannot detect this class of bug** — it only appears at runtime, on a boot. That boot is what each app's `test/di_smoke_test.dart` performs (RULE-63): every flavor, plugins replaced by test doubles, every lazy singleton built. CI Gate 3 runs it, so an ordering fault fails the PR, not the first launch.

**Verify**

```bash
cd apps/mobile && flutter test test/di_smoke_test.dart
cd apps/admin && flutter test test/di_smoke_test.dart
```

**Diagnose** — when the smoke test reports `"<Type> is not registered"`, read two generated files. `apps/mobile/lib/di/injection.config.dart` holds only the **module order** (one `…PackageModule().init(gh)` per package, plus the app's own `FirebaseOptions`); the per-type registrations — and the `gh<Dep>()` calls each constructor makes — are in each package's own `lib/di/module.module.dart`. An eager `gh.singleton…` (including `singletonAsync`) is safe only when every `gh<Dep>()` it makes is registered above it in that file or by a module whose `init` runs earlier:

```bash
dart run build_runner build --workspace
grep -n "PackageModule().init" apps/mobile/lib/di/injection.config.dart       # module order
grep -rn -A4 "gh.singleton" platform/*/*/lib/di/module.module.dart modules/*/*/lib/di/module.module.dart   # eager registrations and their gh<Dep>() calls
```

`@PostConstruct(preResolve: true)` on a `@lazySingleton` is awaited during module init and re-registered as a plain sync lazy singleton, so later `gh<T>()` sync lookups are safe.

---

## 6. Feature boundaries and removability

Registry: RULE-04 · RULE-05 · RULE-12 · RULE-24.

**Rule.** One feature = one bounded UI concern. Feature A must never import feature B — no exception; shared widgets come from `core_ui_kit`, which is core. **The app must still build and run when any feature package is removed.**

**Why.** A template whose features cannot be deleted is not a template. Removability is also the practical proof that the boundaries are real.

**Enforced by machine.** `arch_check` **R3** blocks a feature importing another feature (or any data package). **R8** blocks a throwing `getIt` / `getAll` on a contract only a module implements. **R10** blocks a module *import* — its API package included — anywhere in an app except `injection.dart`. R10 exists because R8 alone was not enough: `getItOrNull` guards a lookup, while an unresolved import fails at compile time, before any lookup runs. `network_config_impl.dart` imported `data_auth` and `domain_auth` for exactly that reason, and made the auth module unremovable while this section said otherwise.

Everything the shell consumes at runtime resolves through a `core_di` contract with a fallback:

| Lookup | Behaviour when nothing is registered |
|---|---|
| `getAllOrEmpty<T>()` | empty list |
| `getItOrNull<T>()` | `null` |
| `getAll<T>()` | **throws** — do not use for optional contributions |

> [!WARNING]
> `getAll<T>()` and `getAllOrEmpty<T>()` differ exactly here. `getAll` throws on an unregistered type, so a bare `getAll<IFeatureLocalization>()` crashes during `MaterialApp` construction in any build where no feature contributes one.

**Enforced by machine.** `arch_check` rule **R8** derives every `core_di` contract implemented by a package under `modules/`, keyed by the implementing module. Any layer counts: `ISessionGateway` in `data_auth` counts as much as a feature's navigator. R8 then blocks a throwing `getIt<T>()` / `getAll<T>()` against one:

```bash
dart tools/arch_check/check.dart      # rule R8 — Gate 1 of pr_quality_check.yml
```

This is not a style rule. The throwing lookup **compiles**: the calling package depends on `core_di`, not on the feature that implements the contract, so `flutter analyze` sees nothing wrong. It fails at runtime, in a build without that feature, on whichever screen happens to call it. Contracts implemented in the app shell (`IThemeStorage`, `ILanguageStorage`) are always registered and stay outside the set. A module is removed whole, so every package of the implementing module may resolve its own contracts eagerly.

**Removing a feature** — the manifest is the only hand-edited file:

1. its line under `modules:` in every `apps/<id>/app_manifest.yaml` that composes it;
2. `dart tools/composer/composer.dart sync`, which regenerates `injection.dart`, the app's path dependencies and the root `workspace:` list;
3. `flutter pub get` + `dart run build_runner build --workspace`.

The `injection.dart` imports are the shell's **only intentional hard reference** to features — as the composition root it must name what it composes. Every other consumer goes through `core_di` (product-neutral contracts) or the owning module's API package.

### Module API packages

A contract that exists so one feature can reach **another module** — its navigator, its action handlers — lives in that module's API package, `modules/<id>/api`, named `<id>_api` (`auth_api`, `home_api`). `core_di` keeps only product-neutral contracts, named for what the platform needs: the session (`ISessionState`, `ISessionStatusStream`, …) and where the shell sends a signed-out / signed-in user (`ISignInLocation`, `IPostSignInLocation`).

| Rule | Enforced by |
|---|---|
| An API package depends on `platform/foundation/*` and Flutter/pub packages only — not its own module's domain/data/feature, not another module or its API, not another platform group | `arch_check` R3 (imports and pubspec) |
| A feature may import another module's API package, never its feature or data package | `arch_check` R3 |
| A type declared in an API package and implemented only under `modules/` is resolved with `getItOrNull` / `getAllOrEmpty` outside its module | `arch_check` R8 |
| No platform package and no app file (bar `injection.dart`) imports an API package | `arch_check` R1, R10 |

An API package is composed as the `api` layer (`- { id: auth, layers: [api, domain, data, feature] }`): a workspace member, never an app dependency or an `injection.dart` entry. `remove_sample <id>` removes it with its module — unless a package outside the bundle still imports it. Then it is **kept**, the importers are named, and the manifests keep `{ id: <id>, layers: [api] }`. The build still compiles, and the consumers' lookups return null.

**Verify**

```bash
# after removing a feature
dart tools/composer/composer.dart sync
flutter pub get && dart run build_runner build --workspace
dart tools/arch_check/check.dart
flutter analyze
```

---

## 7. Domain is pure Dart

Registry: RULE-03 · RULE-49.

**Rule.** No `package:flutter/...`, `package:dio/...`, `package:retrofit/...`, or any UI/network library in `modules/*/domain`. UI concepts must be translated into primitives or enums.

**Why.** Domain is the one layer that should outlive framework choices. It is enforced at the package-graph level too: no domain `pubspec.yaml` declares the Flutter SDK, and `domain_core` has zero workspace dependencies.

Components: `entities/` (Freezed, with `const Class._()`), `params/`, `repositories/` (interfaces), `usecases/` (`@injectable`, returning `Result<T>`), `utils/`.

---

## 8. Data layer

Registry: RULE-40 · RULE-41 · RULE-42 · RULE-43.

**Rule.**

- Directories are `data_sources/remote/` and `data_sources/local/` — **snake_case, plural `data_sources`**, never `datasources/`.
- `RepositoryImpl` extends `IBaseRepository` and wraps work in `execute()` (async) or `executeSync()`.
- Errors convert through `ErrorHandler.handleError(e)`. **Never** `AppFailure.fromException()`.
- **DataSources return Models, never Entities** — and never a class generated by Drift. The one allowed wrapper is `domain_core`'s `BaseEntity<T>` response envelope: `AuthRemoteDataSource` returns `Future<BaseEntity<UserModel>>`, and the repository unwraps it in `execute`'s `mapper`.
- Never `throw` from Data to UI; return `Result.failure(AppFailure)`.

**Why the Model rule.** Returning a Drift row class leaks the persistence library into every consumer of the package. `CacheEntryModel` (`modules/cache/data/lib/src/models/cache_entry_model.dart`) exists purely as that boundary.

---

## 9. Freezed, BLoC and state

Registry: RULE-50 · RULE-51 · RULE-52 · RULE-53.

**Rule.**

- BLoC event subclasses are **private**: `const factory HomeEvent.started() = _HomeStarted;`
- Use `part` / `part of`: `_bloc.dart` declares `part '_event.dart';` and `part '_bloc.freezed.dart';`
- Event handlers take both parameters and are `async`: `Future<void> _onStarted(_HomeStarted event, Emitter<...> emit) async`

> [!CAUTION]
> A synchronous closure that calls async work without awaiting produces `emit was called after an event handler completed normally` — the handler returns immediately, then the async work emits into a closed sink.

**Two state types exist and are different.** The BLoC one is named `BlocViewState<T>` so that a file importing both public barrels never meets two types called `ViewState`:

| | `ViewState` (Provider) | `BlocViewState<T>` (BLoC) |
|---|---|---|
| File | `provider_state_management/lib/src/base/view_state_model.dart` | `bloc_state_management/lib/src/bloc_view_state.dart` |
| Generic | no | yes |
| Variants | 5 (incl. `loadingMore`) | 4 |
| Error | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — required |
| Holds data | no (data lives in `ViewStateModel<T>`) | yes |

> [!WARNING]
> `BaseBloc` / `BaseCubit` are **empty extension points**. The BLoC counterpart of `executeOperation` is opt-in: mix in `BlocResultMixin<T>` / `CubitResultMixin<T>` (`bloc_state_management`) and call `emitResult` — loading, success, failure, none/cancel and thrown exceptions are then handled for you. A handler that does not use it unwraps `Result` by hand.

---

## 10. Controller lifetime

Registry: RULE-10 · RULE-21.

**Rule.** Screen-scoped controllers are `@injectable` (factory). Global controllers may be `@lazySingleton`. Controllers are instantiated **at the route**, in the `build` of `*_route_module.dart`.

**Why.** A `@singleton` ViewModel is held by GetIt forever, so popping the screen leaks it and the next visit reuses stale state.

> [!CAUTION]
> If the route already wraps the page in `BlocProvider` / `ChangeNotifierProvider`, the `Page` widget **must not** wrap itself again. Double-wrapping builds two controllers; the one the UI reads is not the one the route created.

---

## 11. Routing

Registry: RULE-20 · RULE-22 · RULE-23 · RULE-24.

**Rule.** Never edit `platform/shell/app_shell/lib/presentation/navigation/app_router.dart` to add a route. Register a `core_di` contract from the feature instead:

| Contract | Purpose | Ordered? |
|---|---|---|
| `IFeatureRouteModule` | stack routes under the app `ShellRoute` | no (path match) |
| `INavDestinationModule` | one primary destination + one `StatefulShellBranch` | **yes** — ascending `order` |
| `IAppEntryLocation` | first-launch `initialLocation` (later cold starts use the fallback) | n/a |
| `DashboardRouteModule` | dashboard chrome only | `feature_dashboard` only |

Cross-feature navigation goes through a Navigator interface declared in the owning module's API package (`modules/<id>/api`, e.g. `AuthNavigator` in `auth_api`), implemented in that module's feature under `routing/`, and resolved with `getItOrNull`. The app shell uses no module navigator: it sends users to `ISignInLocation` / `IPostSignInLocation` (`core_di`), falling back to `AppRouter.fallbackLocation`. Hardcoding a path or calling `GoRouter.of(context).go(...)` into another feature is forbidden. **`BuildContext` is passed directly from the UI caller** — do not reach for `NavigatorKeys.*.currentContext`.

`feature_dashboard` is **chrome only**: it must not import tab features, own tab pages, hardcode a destination list, or register `INavDestinationModule` itself. Use `INavDestinationModule` only for a primary destination that needs a stable `StatefulShellBranch`, and keep its `order` unique — the DI smoke test asserts it.

---

## 12. Responsive UI

Registry: RULE-30 · RULE-31 · RULE-32.

**Rule.** Every dimension — width, height, padding, margin, font size, border radius — is scaled **through `BuildContext`**, using `core_responsive`: `context.w(x)`, `context.h(x)`, `context.sp(x)`, `context.r(x)` (also `context.spMin`, `context.dg`, `context.dm`). Raw doubles in layout are forbidden, and so is the bare receiver form `16.h`.

**Why the bare form is not even available.** `core_responsive` ships **no `num` extension**, so `16.h` does not compile. That is deliberate: a number carries no context, so such an extension could only read a global singleton, and a widget reading a global never learns the metrics changed. `context.h(16)` instead registers an **InheritedWidget dependency** on `ResponsiveScope`, so it rebuilds when screen metrics change: rotation, split-screen, a resized desktop window. Requiring the context makes the correct thing the only writable thing. And `arch_check` rule R7 rejects the bare form in any file importing `core_responsive`, so an extension declared elsewhere cannot smuggle it back in.

❌ **Wrong** — does not compile, and would go stale if it did:
```dart
SizedBox(height: 16.h)
```

✅ **Right** — subscribes to metric changes:
```dart
SizedBox(height: context.h(16))
```

**Design tokens take context too:** `AppSpacing.lg(context)`, `AppRadius.xxlRadius(context)`, `AppTextStyles.bodyMediumStyle(context)`. Their numbers live in `raw*` constants — edit `raw*`, never the accessor. Never re-scale an already-scaled token.

**No context in scope?** Inside an `async` method, read from context **before the first `await`** and pass the value forward. Never hold a `BuildContext` across an await. The pattern — illustrative, since no screen in the template needs it today:

```dart
Future<void> _loadAvatar() async {
  final side = context.w(96).toInt();   // read while the context is valid
  final bytes = await _repository.fetchAvatar(size: side);
  if (!mounted) return;                 // the widget may be gone by now
  setState(() => _avatar = bytes);
}
```

**Helper scaling axes** — defined in `platform/ui/responsive/lib/src/context_extension.dart`:

| Helper | Scales by |
|:--|:--|
| `context.edgeInsets(all: x)` | `w` |
| `context.edgeInsets(horizontal: x)` | `w` |
| `context.edgeInsets(vertical: x)` | `h` |
| `context.edgeInsetsDirectional(start: x)` / `(end: x)` | `w` — flips with the text direction |
| `context.borderRadius(all: x)` | `r` |
| `context.verticalSpace(x)` | `h` |
| `context.horizontalSpace(x)` | `w` |

> [!WARNING]
> `context.edgeInsets` scales each axis by the axis it belongs to — horizontal by `w`, vertical by `h`, and `all:` by `w`, which makes it a drop-in for `EdgeInsets.all(context.w(16))`. `borderRadius` is the exception: it uses `r`, because a radius scaled on one axis alone turns a circle into an ellipse. When in doubt, write the explicit form; it names the axis.

**Reusable widgets use their parameters exactly as received and must not scale them.** Scaling is the caller's job, so the value arrives already in device pixels. A widget's *own* constants it does scale — `widget.paddingBottom ?? context.h(10)` is correct on both counts.

❌ **Wrong** — an internal override silently discards the caller's value:
```dart
// what platform/ui/ui_kit/lib/navigation/app_bar_custom.dart once did
@override
double? get leadingWidth => context.w(64);   // overrides super.leadingWidth forever
```

✅ **Right** — accept the constructor parameter, let the caller scale it.

**Sizes do not grow on a tablet.** Every factor is clamped by a `ScaleBounds`. The default, `ScaleBounds.downOnly()`, stops at 1:1: a window smaller than the artboard shrinks the design, and a larger one draws it at design size. Do not tune a screen expecting `context.w(16)` to come out bigger on an iPad — spend the extra room on layout. Where a window class genuinely should grow, opt in for that class with a capped bound (`ResponsiveProfile(scaleBounds: ScaleBounds(max: 1.2))` in `_ResponsiveWrapper`'s `profiles`). See [design system §6](../guides/11_design_system.md#6-set-the-scale-policy-per-window-class).

**Choose a layout by window size class, never by device.** Use `context.windowSizeClass`, `context.adaptive(...)`, `AdaptiveLayout` or `AdaptiveSplitView` — never a device model, `Platform.isIOS`, or an ad-hoc `shortestSide` check. One device shows many windows — an iPad in Split View, a foldable's cover screen, a desktop window dragged narrow — and only the window class sees them. The dashboard's bottom bar / rail switch is the reference; see [design system §7](../guides/11_design_system.md#7-lay-out-for-tablets-foldables-and-split-screen).

❌ **Wrong** — an ad-hoc tablet test: its own threshold, blind to the app's breakpoints, and it asks "is this a tablet?" instead of "is this window wide enough for two panes?":
```dart
final twoPane = MediaQuery.sizeOf(context).shortestSide >= 600;
```

✅ **Right** — the window's width class, on the app's breakpoints:
```dart
final twoPane = context.isExpandedOrWider;
```

**Verify**

```bash
dart tools/arch_check/check.dart      # rule R7 — blocks on any bare sizing extension
```

The bare-extension half of this rule is **enforced by machine**, not by review: R7 runs as Gate 1 of `pr_quality_check.yml` on every PR and prints `file:line` for each violation. The raw-double, scale-policy and window-class points are review-held.

---

## 13. Localization and assets

Registry: RULE-34 · RULE-35 · RULE-37.

**Rule.** All user-facing text is translated — hardcoded UI strings are forbidden. Each feature owns its `.arb` files in `assets/language/` and registers `IFeatureLocalization` via DI. Access through the feature extension: `context.l10nAuth.someKey`.

Features **must not** edit `platform/shell/app_shell/lib/presentation/root_app.dart` to add delegates; the shell collects them with `getAllOrEmpty<IFeatureLocalization>()`.

Global strings live in `core_base_ui`. `core_ui_kit` **must not** define its own `.arb` files — it uses `core_base_ui`'s.

**Assets are feature-scoped too.** Images, SVGs and animations specific to a feature live in that feature's own `assets/` (the shipped example is `modules/auth/feature/assets/language/`; images go beside it in an `assets/images/` the feature creates). `core_base_ui` is reserved for global assets — the app logo, global icons — and global fallback strings, and contains zero widgets.

**ARB keys are `lowerCamelCase`.** `flutter gen-l10n` turns each key into a Dart getter verbatim, so a `snake_case` key produces `context.l10nAuth.welcome_back` — an identifier that breaks Dart's own naming convention at every call site. The generated file is excluded from analysis, so no linter will ever tell you. Pick the casing in the `.arb`; it is the only place you can.

---

## 14. Dialogs and bottom sheets

Registry: RULE-36.

**Rule.** Every dialog and bottom sheet is its own widget class in its own file. Writing an inline widget tree inside `showDialog()` / `showModalBottomSheet()` is forbidden.

Suffixes: `_dialog.dart` → `Dialog`, `_bottom_sheet.dart` → `BottomSheet`. Real examples: `platform/ui/ui_kit/lib/dialogs/error_dialog.dart`, `retry_dialog.dart`, `warning_dialog.dart`.

---

## 15. Cross-feature communication

Registry: RULE-08 · RULE-14 · RULE-25 · RULE-54.

**Rule.** Six sanctioned models; pick by what you are sharing.

| # | Need | Mechanism |
|---|---|---|
| 1 | Business logic | shared Domain UseCase |
| 2 | Infrastructure | core service (`core_storage`, `core_network`, …) |
| 3 | Cross-feature state | agnostic `Stream` / `ValueListenable` interface on `core_di`, dual-registered |
| 4 | Pure UI prefs (theme, locale) | bypass Domain → `core_di` storage interface → app-shell impl |
| 5 | Embedding another feature's widget | builder interface in the owning module's `<id>_api` |
| 6 | Cross-feature UI action | `I*ActionHandler` in the owning module's `modules/<id>/api/lib/src/actions/` |

**Dual registration** (model 3): the owning feature registers the concrete class as `@singleton`, then binds the interface via a DI `@module`:

```dart
@module
abstract class AuthModule {
  ISessionStatusStream bind(AuthStatusStreamImpl impl) => impl;
}
```

This lets the owner inject the concrete type through its constructor while every other feature sees only the interface.

> [!NOTE]
> GetIt resolves by **exact type**, never by supertype. Registering `Impl as InterfaceA` does *not* make `getIt<InterfaceB>()` work even when `InterfaceA implements InterfaceB` — bind each one explicitly. See `platform/shell/adapters/lib/di/network_binding_module.dart`, where `SslPinningConfig` needs its own binding despite `NetworkConfig implements SslPinningConfig`.

Do not use Action Handlers for plain navigation (use a Navigator) or for Domain-only logic (use a UseCase).

**`core_di` contracts stay neutral** (RULE-08). A contract never names a `domain_*` type — it declares a smaller, contract-owned value type (`SessionPrincipal`), which the owner maps to at its boundary (`AuthStatusStreamImpl.toPrincipal`). It returns plain Flutter types (`IAppTreeWrapper.wrap()` returns a `Widget`), so neither state library is forced on the other. It prefers a Dart 3 `sealed class` to Freezed (`SessionFailure`): `core_di` runs only injectable's codegen, and a `part` file on a contract would make every consumer wait on `build_runner`. Global UI state (theme, language, deep links) uses one neutral utility: `ChangeNotifier` / `ValueNotifier` or a plain `Stream`. So no feature is forced to import a state library it does not use.

---

## 16. Tooling and code hygiene

Registry: RULE-70 · RULE-71 · RULE-72 · RULE-73 · RULE-74.

| Rule | Detail |
|---|---|
| No `print()` in `tools/` | use `stdout.writeln()` / `stderr.writeln()` |
| No lint suppressions | `// ignore_for_file: ...` is forbidden; research the real migration |
| No PowerShell scripts | `.ps1` is forbidden (Windows execution policy); use `.dart` |
| Never hand-edit generated files | `.g.dart`, `.freezed.dart`, `.module.dart`, `.config.dart` |
| Versions come from the catalog | edit `pubspec_dependencies.yaml`, then run the sync tool |
| Re-run the barrel generator | after adding, renaming, or deleting any file under `lib/` |
| Handle deprecations properly | research the migration; quick-fixes and ignores are forbidden |

**FVM is optional.** `.fvmrc` pins a version, but does not mean `fvm` is installed: write commands bare (`flutter pub get`) and add `fvm ` yourself if your machine uses it. A tool that shells out detects it at runtime through `tools/shared/toolchain.dart` (`useFvm`, `dartExecutable` / `dartArgs`, `flutterExecutable` / `flutterArgs`), which requires both a config file and a working `fvm --version`.

### Analyzer strictness

The single root `analysis_options.yaml` applies to every package. On top of `flutter_lints` it turns on the three strict language modes and a handful of rules; its header explains each one and how to add a rule. `flutter analyze` must report **0 issues** — CI Gate 2 fails on infos too.

| Setting | What it asks of your code |
|---|---|
| `strict-casts` | cast a `dynamic` value before using it as a typed one — `jsonDecode(body) as Map<String, dynamic>` |
| `strict-inference` | give the type argument inference cannot find — `Future<void>.delayed(...)`, `catchError((Object e, StackTrace s) {...})` |
| `strict-raw-types` | never drop a generic's arguments — `StreamSubscription<User>`, `AppFailure<dynamic>` (keep `<dynamic>` for `AppFailure`: its Freezed `==` compares `runtimeType`) |
| `unawaited_futures` | in an async body, `await` a Future or wrap it in `unawaited(...)` from `dart:async` with a comment saying why |
| `cancel_subscriptions` / `close_sinks` | a `StreamSubscription` field is cancelled, a `StreamController` field closed, in the class that owns it |
| `avoid_dynamic_calls` | no method call or property access on `dynamic` — cast first |
| `empty_catches` | an empty `catch` holds a comment saying why dropping the error is safe; prefer narrowing it (`on FileSystemException`) |

`discarded_futures` is **not** enabled: in Flutter it mostly flags `subscription.cancel()` / `controller.close()` in a synchronous `dispose()` and dialogs opened from `void` callbacks. Adding a rule means fixing every hit it reports — never `// ignore:` — and regenerating a module (`generate.dart 1 smoke "" 2 2`) to prove the generator templates still pass.

---

## 17. Testing

Registry: RULE-60 · RULE-61 · RULE-62 · RULE-63 · RULE-64.

**Rule.** Tests live beside the code they test, in each package's own `test/` directory. Flutter packages use `flutter_test`; pure-Dart packages (`domain_core`, `tools`) use `package:test`, pinned in the catalog. Fakes are hand-written — the repository declares no mockito and no mocktail.

**Why.** CI Gate 3 does not keep a list: it finds every directory holding both a `pubspec.yaml` and a `test/` and runs `flutter test --coverage` there, and it fails if it finds none. A new package with tests is covered the moment it exists. Hand-written fakes need no codegen and read as a statement of the contract they stand in for.

Three tests are load-bearing for rules elsewhere in this file:

| Test | Holds |
|---|---|
| `apps/mobile/test/di_smoke_test.dart`, `apps/admin/test/di_smoke_test.dart` | Boots the app's real generated DI graph for `dev`, `staging` and `prod` with every plugin replaced by a test double, builds every lazy singleton, and resolves every shell contract and `AppRouter.router` — the runtime proof for RULE-13, RULE-14, RULE-24 (unique `order`) and RULE-48 (the binding half) |
| `platform/shell/app_shell/test/accessibility_test.dart` | Icon-only buttons keep their tooltip as a semantic label; the OS text scale passes through up to `MAX_TEXT_SCALE_FACTOR` (RULE-38) |
| `tools/test/` | Every gate tool, each case in a throwaway workspace in a temp dir (RULE-64); CI runs it right after Gate 1, and Gate 3 skips `tools/` |

A plugin that the DI graph touches while it initialises — a `@preResolve` factory, a `@PostConstruct(preResolve: true)` — needs its test double added to the smoke tests, or they fail with the plugin's `MissingPluginException`.

**Scaled widgets need `ResponsiveInit`.** A widget test whose subject reads `context.w` / `context.sp` wraps it in `ResponsiveInit`; without it `ResponsiveScope.of` asserts, deliberately, rather than lay out at unscaled values nobody would notice.

**Verify**

```bash
cd platform/foundation/common && flutter test          # one package
cd apps/mobile && flutter test test/di_smoke_test.dart # the DI boot, every flavor
cd tools && dart test                                  # the gate tools (~15 s)
dart tools/coverage_report/report.dart                 # per-package coverage after --coverage (advisory)
```

---

## 18. Logging, error reporting and secrets

Registry: RULE-43 · RULE-65 · RULE-66 · RULE-67.

**Rule.** Runtime diagnostics go through `dynamic_logger` (`DynamicLogger.log`), never `print` — the analyzer's `avoid_print` rejects it. CLI tools under `tools/` write with `stdout.writeln` / `stderr.writeln`. Nothing secret is logged or committed.

**Why.** `print` output reaches release device logs and cannot be filtered by level or tag. The network stack shows the redaction standard. `LoggingInterceptor` is `kDebugMode`-gated on all three hooks, including `onError`, and redacts `Authorization` / `Cookie` headers and credential body fields (`password`, `token`, `access_token`, …) — see [`../architecture/02_core.md`](../architecture/02_core.md#the-interceptor-chain) § 6. Production env files, keystores, `key.properties` and API keys (`tools/code_review/.gemini_api_key`, `apps/mobile/fastlane/Config.yaml`) are gitignored; CI materialises them from secrets ([`../operations/01_cicd.md`](../operations/01_cicd.md) § 7).

**Error reporting.** `runShellApp` installs one hook behind the zone handler, `FlutterError.onError` and `PlatformDispatcher.instance.onError`. It keeps the previous handler, calls the app's optional `onError`, then `getItOrNull<IErrorReporter>()` with `fatal: true`; `ErrorHandler.onUnclassifiedError` sends exceptions `ErrorHandler` could not classify to the same reporter with `fatal: false`. To plug in Crashlytics or Sentry, register an `IErrorReporter` implementation in the app (`@LazySingleton(as: IErrorReporter)` in its own `lib/`); `IAnalytics` likewise, and every `GoRouteDataCustom` page reports its screen through it. Setting `FlutterError.onError` yourself replaces the chain instead of joining it. Details: [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) § "Errors and crash reporting".

**Classifying errors.** A failure reaches the UI as an `AppFailure` produced by `ErrorHandler.handleError(e)`. `ErrorHandler` names no transport type; a family of exceptions it should understand registers an `ErrorClassifier` through `ErrorHandler.registerClassifier` — the way `core_network` contributes `DioFailureClassifier`. There is no Firebase classifier today: `FirebaseException`, `FirebaseAuthException` and `PlatformException` all collapse to `ServerFailure(code: 9999)`, "Unknown error occurred" in release. Register one before a screen relies on a Firebase error code.

---

## 19. Accessibility

Registry: RULE-38 · RULE-39 · RULE-30 (directional insets).

**Rule.**

- **Text follows the OS font size.** The shell wraps every `builder` in `MediaQuery.withClampedTextScaling(maxScaleFactor: AppShellUiConstants.MAX_TEXT_SCALE_FACTOR)` (2.0). Never `MediaQuery.withNoTextScaling`, never `TooltipVisibility(visible: false)` — it strips icon-button labels from semantics; the theme's `tooltipTheme` (`triggerMode: manual`) already suppresses the long-press popup.
- **Text containers grow with their text.** Do not give a container of text a fixed `context.h(...)` height; let it size to its content, or scale it down with `TextScaleDown`.
- **Everything interactive has a name.** An icon-only `IconButton` carries a `tooltip` (it becomes the semantic label); a meaningful image passes `semanticLabel` (`CustomCacheNetworkImage` does); a decorative one leaves it `null`.
- **Tap targets are at least 48 × 48 dp** (`kMinInteractiveDimension`) — shrink the visual, not the hit area.
- **Right-to-left.** A padding that means start/end of the line uses `context.edgeInsetsDirectional(start:, end:)`, which flips in RTL; `edgeInsets(left:/right:)` is physical.

**Why.** Each of these was a real defect here. `RootApp` once ended in `withNoTextScaling`, pinning every text at 100 % whatever the user chose. And a global `TooltipVisibility(visible: false)` silenced every icon button for screen readers. Details: [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) § 7.

**Verify**

```bash
cd platform/shell/app_shell && flutter test test/accessibility_test.dart
cd modules/auth/feature && flutter test test/login_page_text_scale_test.dart
```

---

## 20. Workspace, codegen and barrels

Registry: RULE-16 · RULE-75 · RULE-76 · RULE-77.

**Composition is generated.** Each `apps/<id>/app_manifest.yaml` is the only hand-edited description of an app. `dart tools/composer/composer.dart sync` writes three things from it, each between `composer:managed` markers: the root `workspace:` list, the app's path dependencies in its `pubspec.yaml`, and its `lib/di/injection.dart`. `composer verify` is Gate 0 and fails on any drift. The module generator adds the new module to every manifest (or only the apps named with `--apps`) and runs `sync` itself. The workspace is flat: `resolution: workspace` in every member, no intermediate workspace node.

**Barrels.** `dart tools/barrel_generator/generate.dart <package>/lib` rewrites a package's barrel from what is on disk. It **deletes** every line starting with `export '` and re-emits its own sorted list, so a hand-added export silently vanishes — put a deliberate re-export in a normal source file (`platform/foundation/kernel/lib/src/error/failures.dart` is exactly that). It also exports the generated files present on disk (`module.module.dart`, `lib/src/gen/**`; `core_base_ui`'s `src.dart` exports `gen/gen.dart`), so the last run must come **after** gen-l10n and build_runner — the order `tools/workspace_setup/configure.dart` uses.

**Generated code is invisible to analysis.** `analysis_options.yaml` excludes `**.freezed.dart`, `**.g.dart`, `**.mocks.dart`, `**.config.dart` and `**.module.dart`, so a clean `flutter analyze` does not mean the app compiles. Real incident: moving `AppFailure` from `core_common` to `domain_core` broke `bloc_view_state.freezed.dart`, which needs the generated `$AppFailureCopyWith`; `core_common`'s re-export shim lists types in a `show` clause and cannot carry it. Analyze said *No issues found*; the APK build failed with `Type '$AppFailureCopyWith' not found`. The fix — and the rule — is to import a type used by generated code from its real home.

`build_runner` takes no `-d`: `--delete-conflicting-outputs` was removed and is ignored with a warning.

**Verify** — after a change to DI annotations, package dependencies or the home of a Freezed/JSON type:

```bash
dart run build_runner build --workspace
flutter analyze
(cd modules/<module>/<layer> && flutter test)    # per package that has a test/ directory
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

The APK build needs the gitignored `firebase_options_<flavor>.dart` files and `google-services.json`; `dart tools/workspace_setup/configure.dart --stub-firebase` writes compile-only stubs ([`../getting-started/01_setup.md`](../getting-started/01_setup.md) § 3).

---

## Rule → command cheat sheet

| Check | Command |
|---|---|
| Undeclared dependencies (imported, not in `dependencies:`) | `dart tools/arch_check/check.dart` (R5) |
| Unused dependencies (declared, never imported) | `dart tools/unused_checker/check_unused_packages.dart` |
| Version catalog drift | `dart tools/dependency_sync.dart --check` |
| Unused assets, files, translations | `dart tools/unused_checker/check_script.dart` |
| Static analysis | `flutter analyze` |
| Codegen up to date | `dart run build_runner build --workspace` |
| DI order safety | `cd apps/mobile && flutter test test/di_smoke_test.dart` (and `apps/admin`) |
| core ⇏ feature / data / product domain | `dart tools/arch_check/check.dart` (R1) |
| Removable contracts resolved optionally | `dart tools/arch_check/check.dart` (R8) |
| The app shell imports no module | `dart tools/arch_check/check.dart` (R1 for `platform_app_shell` / `platform_shell_adapters`, R10 for `apps/*`) |
| Platform group direction | `dart tools/arch_check/check.dart` (R11) |
| Module API packages depend on the foundation only; features import other modules' APIs, never their features | `dart tools/arch_check/check.dart` (R3) |
| No `.ps1`, no lint suppression, no `datasources/`, no concrete `I*` class | `dart tools/arch_check/check.dart` (R12–R15) |
| Domain purity | `grep -rn "package:flutter" modules/*/domain/lib` |
| Composition matches the manifests | `dart tools/composer/composer.dart verify` |
| Docs paths and en ↔ vi parity | `dart tools/docs_check/check.dart` |
| Generated code compiles | `cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev` |

---

**Next:** [`02_naming.md`](02_naming.md) · [`03_tooling.md`](03_tooling.md) · [`04_review_checklist.md`](04_review_checklist.md)
