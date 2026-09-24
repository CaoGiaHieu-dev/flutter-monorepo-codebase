# 🤖 Codebase Rules & Developer Agent Guidelines (AGENTS.md)

This file contains the rules for architectural design, naming conventions, dependency injection (DI) management, routing, and coding standards for this Monorepo template. Every AI Agent (Gemini, Copilot, Cursor, etc.) working on this codebase **MUST read and strictly comply 100%** with the rules below.

---

## 🏗️ 1. Monorepo Directory Layout

This monorepo uses **Pub Workspaces** and is divided into three top-level territories — `apps/` (one composition root per app, owned by tech leads), `platform/` (infrastructure, owned by the infra team) and `modules/` (one vertical slice per bounded context, one owner each) — plus `tools/` for the repo's CLI tooling:

- **`apps/<id>/`**: an app — the composition root. Holds its `app_manifest.yaml`, the `injection.dart` generated from it, a one-line `main.dart` calling `runShellApp`, and what identifies the app (its `lib/firebase/`). Nothing else.
- **`platform/app_shell/`** (`platform_app_shell`): the shell every app shares — boot (`runShellApp`, `MainScope`), **dynamic** router assembly (`app_router.dart` collects `IFeatureRouteModule` / `INavDestinationModule` / `DashboardRouteModule` via DI — do not hardcode feature `$…Route` lists), the storage adapters and `NetworkConfigImpl`. Imports no module.
- **`platform/`**: Infrastructure and utility packages shared across the project:
  - `platform_kernel`: **Pure Dart, no `flutter` dependency.** Service locator (`getIt`, `getItOrNull`, `getAll`, `getAllOrEmpty`), `ErrorHandler`, `AppException`, primitive extensions, `TypeHelper`, `ValidationHelper`, and the two genuinely global constants classes, `EnvConstants` and `ErrorCodes`. This is the one package every other package may depend on, so its dependency list is everyone's — 7 entries, none Flutter-bound. Enforced by `arch_check` rule **R9**.
  - **Which of the two to depend on:** if a package uses only the service locator, `ErrorHandler`, a primitive extension or a global constant, depend on `platform_kernel` — `core_network`, `core_notifications`, `data_core` and `feature_dashboard` already do. Reach for `core_common` only when you need something Flutter-bound from it (`AppConfig`, `AppInitializer`, a mixin, `GoRouteDataCustom`, `AppUtils`, the dialog controller, a formatter).
  - `core_common`: The **Flutter side** of the old `core_common` — `AppConfig`, `AppInitializer`, mixins, `GoRouteDataCustom` and page transitions, `AppUtils`, the dialog controller, input formatters. Re-exports `platform_kernel` wholesale, so an existing `package:core_common/core_common.dart` import keeps resolving everything. **New code that needs only the pure-Dart foundation should import `platform_kernel` directly** rather than pulling Flutter and go_router in with it.

  - `core_di`: Navigation keys, routing contribution contracts (`IFeatureRouteModule`, `INavDestinationModule`, `IAppEntryLocation`, `DashboardRouteModule`), and cross-package communication interfaces.
  - `core_base_ui`: Design system resources (typography, color palette, icons, assets, and L10n translations). **Contains zero Flutter widgets.**
  - `core_ui_kit`: Unified library for all reusable widgets (atomic components like buttons/inputs, plus dialogs, feedback, layout, media and navigation widgets). Depends only on `core_common`, `core_base_ui`, `core_responsive` and `provider_state_management` — never on a feature. It lives under `platform/` because it is a shared UI library every feature may consume, **not** a removable feature.
  - `core_responsive`: Design-size scaling bound to `BuildContext` (`context.w/h/r/sp`), the scale policy (`ScaleBounds`, `ResponsiveProfile` — scales **down only** by default), window size classes (`WindowSizeClass`, `ResponsiveBreakpoints`) and the adaptive layout widgets (`context.adaptive`, `AdaptiveLayout`, `AdaptiveSplitView`, `AdaptiveContent`). Depends on nothing but `flutter`; ships no `num` extension (see § 14).
  - `core_network`: Pre-configured HTTP client (Dio, Retrofit) with interceptors (auth, retry, logging).
  - `core_storage`: **Storage mechanism only** — `StorageInterface`, `StorageManager`, reactive `StorageValue<T>`, `StorageType`, over two-tier storage (Secure Storage + SharedPreferences). **Defines zero keys or presets**; every consumer declares its own `StorageValue` (see § 17).
  - `core_database`: **Database mechanism only** — `IDatabaseHandle<TDb>`, `IDatabaseMigration`, `DatabaseMigrationRunner`, `DatabaseConnectionFactory`, `DriftDatabaseOpener`. **Owns no database, table or DAO** (its DI module registers nothing); each package declares its own database (see § 21).
  - `core_notifications`: Push notification management module. Owns its channel constants at `lib/src/utils/notification_constants.dart`.
  - `provider_state_management`: Provider state management base classes (`BaseProvider`, `executeOperation`, `BaseViewWidget`, `ViewStateModel`), plus the in-core `DefaultLoadingWidget` / `DefaultEmptyWidget` fallbacks.
  - `bloc_state_management`: BLoC state management base classes (`BaseBloc`, `BlocViewState<T>`; `BaseCubit` only when events are unnecessary). **`BaseBloc`/`BaseCubit` are extension points only** — there is no BLoC equivalent of `executeOperation`, so BLoC handlers unwrap `Result` / map `AppFailure` / set loading by hand.
- **Domain micro-packages** — the layer foundation `platform/domain_core` plus one `modules/<name>/domain` per module. Business logic core. **MUST be pure Dart (100% decoupled from Flutter UI, Dio, Retrofit, or any platform-specific dependencies)**. Current micro-packages:
  - `domain_core` (`platform/domain_core`): Defines `Result<T>`, `AppFailure`, `BaseEntity<T>`, and shared primitive types.
  - `domain_auth`: Entities, use cases, and repository interfaces for authentication.
  - `domain_cache`: The cache-entry entity, params, repository interface and use cases (sample, backing `data_cache`).
- **Data micro-packages** — the layer foundation `platform/data_core` plus one `modules/<name>/data` per module. Data access layer (remotes, local caching, models/DTOs). Depends on `domain` packages. Current micro-packages:
  - `data_core` (`platform/data_core`): `IBaseRepository` with `execute()` and `executeSync()` wrappers to automatically handle error conversion.
  - `data_auth`: Models/DTOs, Remote DataSources (Retrofit), and RepositoryImpl for authentication.
  - `data_cache`: A package-owned Drift database (`CacheDatabase`, table, DAO), its local data source and RepositoryImpl — the reference for § 21.
- **`modules/*/feature/`**: Independent functional modules. Every package here is a removable product surface — the shared widget library is **not** one of them; it lives at `platform/ui_kit` as `core_ui_kit`.
  - Feature packages (e.g., `feature_onboarding`, `feature_auth`, `feature_dashboard`, `feature_home`, `feature_settings`, `feature_splash`):
    - Can only depend on `domain_*` and `core_*` packages — in practice `core_di`, `core_common`, `core_base_ui`, `core_ui_kit`, `core_responsive`, and `provider_state_management` or `bloc_state_management`.
    - **ABSOLUTELY FORBIDDEN** to directly depend on the `data` layer or on **any** other feature package. There is no exception: shared widgets come from `core_ui_kit`, which is core, not a feature.
    - **One bounded UI concern per feature package**: Do not co-locate unrelated product surfaces in the same feature (e.g. Home tab + Settings tab). `AppRouter` + `INavDestinationModule` assemble shell branches; `feature_dashboard` supplies **chrome only** (`DashboardRouteModule`), not tab pages. Sample split: `feature_home` vs `feature_settings`.
---

## 🧱 2. Strict Layer Isolation

0. **Core Layer must never depend on Features, Data or product Domain packages**:
   - **ABSOLUTELY FORBIDDEN** for any `platform/*` package to import `package:feature_*/...`, `package:data_*/...` or `package:domain_*/...`, or to declare them in its `pubspec.yaml` — **except** the approved `→ domain_core` edges listed below. Core is the innermost infrastructure ring — nothing above it may own it.
   - **Enforced by machine.** `arch_check` rule **R1** blocks every core → `feature_*` / `data_*` / `domain_*` edge, by import and by pubspec, that is not in the `_approvedUpwardEdges` allow-list at the top of `tools/arch_check/check.dart`. Depending on `domain_core` is the correct Clean Architecture direction (it is the `Result` contract and depends on nothing), but each such edge is still allow-listed one by one; a core package may **never** depend on a product domain package (`domain_auth`, `domain_cache`, …) — that module is removable. Verify the full list at any time with:
     ```bash
     grep -E "^  (domain_|data_|feature_)" platform/*/pubspec.yaml
     ```
   - The grep also prints `platform/data_core → domain_core`; that is a data → domain edge (`data_core` is the data layer's foundation that happens to live under `platform/`, and R1 classifies it as data, not core). Among core packages, exactly **three** core → domain edges are approved; adding a fourth means updating this list and the allow-list in `check.dart` in the same PR, and no `core → data` or `core → feature` edge may ever be added:
     - `provider_state_management → domain_core` — needs `Result<T>` / `PaginatedEntity<T>`.
     - `bloc_state_management → domain_core` — needs `AppFailure` for `BlocViewState.error`. It must import `domain_core` **directly**, not via `core_common`'s re-export shim: the shim's `show` clause cannot carry the Freezed-generated `$AppFailureCopyWith`, and the resulting breakage is invisible to `flutter analyze` (§ 23).
     - `platform_kernel → domain_core` — `ErrorHandler` produces `AppFailure`, which now lives in Domain.
   - If a core package needs a fallback widget, **define it inside that core package**. Do not borrow one from `core_ui_kit`. Reference: `provider_state_management` ships `DefaultLoadingWidget` / `DefaultEmptyWidget` in `lib/src/base_view/default_state_widgets.dart` for exactly this reason.
   - Dependencies flow **one way**: `core_ui_kit → provider_state_management` is correct; the reverse is a genuine cycle **inside** the core ring and is forbidden. (This is why `provider_state_management` ships its own `DefaultLoadingWidget` / `DefaultEmptyWidget` instead of reaching into the widget library for them — that would close the loop.)
1. **Domain Layer must be Pure Dart** — enforced by the package graph, not just by review:
   - Do not import: `package:flutter/...`, `package:dio/...`, `package:retrofit/...`, or any UI/Network framework library.
   - **`domain_core` has ZERO workspace dependencies** and no `flutter` entry in `dependencies`. `domain_auth` and `domain_cache` depend only on `domain_core`. Keep it that way.
   - **ABSOLUTELY FORBIDDEN** for a domain package to depend on `core_common` (or any `core_*` package). `core_common` imports `flutter/material.dart`, so depending on it would drag Flutter into Domain. `AppFailure` lives in `domain_core` for exactly this reason — it is part of the `Result` contract and belongs at the centre.
   - Allowed to import: `dart:*`, `domain_core` (`Result<T>`, `AppFailure`, `BaseEntity<T>`, `PaginatedEntity<T>`), `freezed_annotation`, `json_annotation`, `injectable`, `get_it`.
   - Domain-owned constants live in that package's own `utils/` (§ 16) — e.g. `domain_core`'s `DomainConstants`. Never reach into `core_common` for them.
   - If UI-related classes (such as colors or image assets) are needed, translate them into primitive data types or enums declared **inside the domain package**.
   - Verify:
     ```bash
     grep -rn "package:flutter" modules/*/domain/lib   # must print nothing
     ```
2. **Data Layer**:
   - Data source directories must be named `data_sources/` (snake_case), NOT `datasources/`.
   - Categorize into `data_sources/remote/` (Retrofit) and `data_sources/local/` (Storage/DB).
   - RepositoryImpl classes should inherit from `IBaseRepository` in `data_core` and use the helper methods `execute()` or `executeSync()` wrappers to automatically handle error conversion. API calls are not required to return `BaseEntity`; when the payload is wrapped, unwrap and map it via the `mapper` parameter.
   - **DataSources return Models, never Entities**, and never leak a generated type. The one wrapper allowed around a Model is `domain_core`'s `BaseEntity<T>` response envelope — the reference `AuthRemoteDataSource` returns `Future<BaseEntity<UserModel>>`, and `AuthRepositoryImpl` unwraps it in `execute`'s `mapper`. A Drift row class must be converted at the package boundary — see `CacheEntryModel.fromRow` in `modules/cache/data/lib/src/models/cache_entry_model.dart`; `ICacheEntryLocalDataSource` speaks only in `CacheEntryModel`.
   - Error handling must use `ErrorHandler.handleError(e)` from `platform_kernel` (re-exported by `core_common`). **DO NOT** invent an `AppFailure.fromException()` — no such constructor exists.
   - ⚠️ Known gap: `ErrorHandler` has no `FirebaseException` / `FirebaseAuthException` / `PlatformException` branch, so every Firebase error collapses to `ServerFailure(code: 9999)` (`"Unknown error occurred"` in release). Add a branch before relying on Firebase error codes in UI.
3. **Feature Module Boundary**:
   - Feature package A must never import any file from Feature package B.
   - **One feature = one bounded UI concern.** Unrelated tabs/screens (e.g. Home vs Settings) MUST live in separate feature packages. `feature_dashboard` only provides shell chrome (`DashboardRouteModule`); tab routes register via `INavDestinationModule` and are assembled by `AppRouter`.
   - **Forbidden:** editing `app_router.dart` to hardcode a new feature’s `$…Route` / `StatefulShellBranch`. Register `IFeatureRouteModule` or `INavDestinationModule` in the feature DI instead. See [`docs/en/guides/04_routing.md`](../docs/en/guides/04_routing.md) § Dashboard for misuse rules.
   - Cross-feature communication (e.g., navigating from Feature A to Feature B) must be done through navigation interfaces (`Navigator`) defined in `core_di`.
   - **Navigation Rules (Decentralized Navigators)**:
     - Navigator interfaces (`AuthNavigator`, `HomeNavigator`, etc.) defined in `core_di` must only contain navigation methods to routes owned by that specific feature.
     - Implementation classes (`NavigatorImpl`) must reside locally under the `routing/` directory of the feature package that owns those routes (e.g., `AuthNavigatorImpl` resides in `feature_auth`).
     - **ABSOLUTELY FORBIDDEN** to hardcode route paths or call `GoRouter.of(context).go(...)` directly to navigate to another feature. Instead, fetch the target feature's Navigator from GetIt with `getItOrNull` — the owner is removable, and `arch_check` R8 blocks a throwing lookup (e.g., `getItOrNull<HomeNavigator>()?.toHome(context)`).
     - **BuildContext MUST be passed directly** as a parameter from the UI caller (Widget/Page/View). Minimize or avoid utilizing context from `NavigatorKeys` or `appRouter.currentContext` to prevent Widget Lifecycle issues.
   - Shared utilities and UI widgets used only across features should be placed in `platform/ui_kit`.
   - **Cross-Feature UI Actions (Action Handlers)**:
     - When Feature A must trigger a UI-bound action owned by Feature B (e.g., logout) without importing Feature B, declare an `I*ActionHandler` interface in `platform/di/lib/src/actions/`.
     - Implement `*ActionHandlerImpl` inside the owning feature under `handlers/` and register with `@Injectable(as: I*ActionHandler)` (or `@LazySingleton(as: ...)` when appropriate).
     - Consumers call `getItOrNull<I*ActionHandler>()?.method(context)` (R8). Do **not** use Action Handlers for pure route navigation (use Navigators) or Domain-only logic (use UseCases).
4. **UI vs. Business State Workflows (Bypassing Domain)**:
   - **Pure UI State (e.g., ThemeMode, Locale)**: Cannot pass through the Domain layer because Domain must be Pure Dart (cannot import `flutter/material.dart`). UI Providers bypass Domain and persist via a DI storage Interface implemented in the App Shell:
     - **Theme**: `ThemeProvider` → `IThemeStorage` → `ThemeStorageImpl` (`platform/app_shell/lib/di/theme_storage_impl.dart`), which owns its own `StorageValue<ThemeMode>` keyed by `ThemeStorageKeys.THEME_MODE` (`platform/app_shell/lib/di/utils/theme_storage_keys.dart`)
     - **Language**: `LanguageProvider` → `ILanguageStorage` → `LanguageStorageImpl` (`platform/app_shell/lib/di/language_storage_impl.dart`), which owns its own `StorageValue<String>` keyed by `LanguageStorageKeys.LOCALE` (`platform/app_shell/lib/di/utils/language_storage_keys.dart`)

---

## 🚥 3. Provider Lifecycle & Dependency Injection (DI) Management

1. **Feature UI Controllers (ViewModel / Bloc) Lifecycle**:
   - **MUST be annotated with `@injectable`** (or registered factory) to bind them to the screen's lifecycle.
   - **ABSOLUTELY FORBIDDEN** to register Feature Controllers as `@singleton` or `@lazySingleton` because GetIt will hold their instances indefinitely, causing memory leaks when screens are popped.
   - Prefer **`BaseBloc` + Freezed events** for BLoC features. Use **`BaseCubit` only when events are unnecessary**.
   - **Route-Level Instantiation**: UI Controllers must be instantiated and bound to the widget tree exclusively in the `build` method of the route (`*_route_module.dart` / `GoRouteData`):
     ```dart
     // Using Provider in Route Module:
     @override
     Widget build(BuildContext context, GoRouterState state) {
       return ChangeNotifierProvider(
         create: (context) => getIt<ProfileProvider>(),
         child: const ProfilePage(),
       );
     }

     // Using BLoC in Route Module:
     @override
     Widget build(BuildContext context, GoRouterState state) {
       return BlocProvider(
         // Auth is optional: an app composed without `feature_auth` registers
         // no IAuthStatusStream, and Home then shows the signed-out state.
         create: (_) => getIt<HomeProfileBloc>(
           param1: getItOrNull<IAuthStatusStream>(),
         ),
         child: const HomePage(),
       );
     }
     ```
   - **ABSOLUTELY FORBIDDEN** to wrap `BlocProvider` or `ChangeNotifierProvider` inside the `Page` widget's `build()` method if it is already provided at the Route level. Double wrapping creates duplicate controller instances, causing state desynchronization bugs and memory leaks.
2. **Global Controllers**:
   - Allowed to use `@lazySingleton` or `@singleton` for application-wide global controllers (e.g., `ThemeProvider`, `LanguageProvider`, `AppProvider`, `AuthProvider`, `DeeplinkProvider`).
3. Constructor Injection:
   - Do not call `getIt<T>()` inside business logic (ViewModels, Repositories, UseCases).
   - Pass all dependencies through the constructor to enable easy unit testing and mocking.
4. **Micro-package DI module**:
   - A package's DI module is `@InjectableInit.microPackage()` in `lib/di/module.dart`, with no arguments. The one exception is `core_notifications`, which passes `ignoreUnregisteredTypesInPackages: ['firebase_core']`: the `FirebaseOptions` it injects is registered by each app (`lib/firebase/firebase_module.dart`), never by a package module. Do not add such an argument to silence a genuinely missing registration.

---

## 🏷️ 4. Naming Conventions & File Suffixes

All files and class names must strictly adhere to the following naming conventions:

| Component Type | File Suffix (Snake Case) | Class Suffix (Pascal Case) | Example |
| :--- | :--- | :--- | :--- |
| **Main Screen** | `_page.dart` / `_screen.dart` | `Page` / `Screen` | `LoginPage`, `HomeScreen` |
| **Sub Widget** | `_widget.dart` / `_card.dart` | `Widget` / `Card` | `PrimaryButtonWidget` |
| **UI Controller (Provider)** | `_provider.dart` | `Provider` | `LoginProvider` |
| **UI Controller (BLoC)** | `_bloc.dart` | `Bloc` | `HomeProfileBloc` |
| **UI Controller (Cubit)** | `_cubit.dart` | `Cubit` | Only when events are unnecessary |
| **Use Case** | `_usecase.dart` | `UseCase` | `LoginUseCase` |
| **Entity** | `_entity.dart` | `Entity` | `UserEntity` |
| **Repository Interface** | `i_<name>_repository.dart` | Prefix `I` | `IAuthRepository` |
| **Repository Implementation** | `_repository_impl.dart` | `RepositoryImpl` | `AuthRepositoryImpl` |
| **API Response DTO** | `_response.dart` / `_model.dart` | `Response` / `Model` | `UserResponse`, `UserModel` |
| **API Request DTO** | `_request.dart` | `Request` | `LoginRequest` |
| **Navigator Implementation** | `_navigator_impl.dart` | `NavigatorImpl` | `AuthNavigatorImpl` |
| **Action Handler Interface** | `i_` + `_action_handler.dart` | Prefix `I` | `IAuthActionHandler` |
| **Action Handler Implementation** | `_action_handler_impl.dart` | `ActionHandlerImpl` | `AuthActionHandlerImpl` |

- **Constants**: All static constants must be in `UPPER_SNAKE_CASE` (e.g., `static const String BASE_URL = '...'`).
- **ABSOLUTELY FORBIDDEN** to name an implementation class with the `I` prefix (e.g., do not name a navigator impl `IAuthNavigator`). The `I` prefix is reserved for interfaces only.

---

## ⚙️ 5. Tooling Rules & Print Statements

1. **CLI Tools (`tools/`)**:
   - Do not use `print()` in CLI tools.
   - Use `stdout.writeln()` for standard messages and `stderr.writeln()` for errors.
2. **Lint Warning Annotations**:
   - **ABSOLUTELY FORBIDDEN** to add a lint suppression — `// ignore: ...`, `// ignore_for_file: ...` or a rule disabled in `analysis_options.yaml`. Fix the cause (for deprecations, see § 10). Generated files carry their generator's own `ignore_for_file` headers; that is not hand-written code.
3. **FVM is optional — never hardcode the `fvm` prefix**:
   - The repo pins a version in `.fvmrc`, but that file does **not** guarantee `fvm` is installed on the current machine. Blindly prefixing `fvm` fails on a plain Flutter install.
   - Write commands **without** the prefix (`flutter pub get`, `dart run build_runner build --workspace`). Add `fvm ` yourself only if your own machine uses it.
   - A tool that shells out to the toolchain **MUST detect FVM at runtime**, not assume it. Use the shared helper `tools/shared/toolchain.dart` (`useFvm`, `dartExecutable` + `dartArgs`, `flutterExecutable` + `flutterArgs`): it requires **both** a config file (`.fvmrc` or `.fvm/fvm_config.json`) **and** a successful `fvm --version`. Every tool that shells out goes through it.
4. **No PowerShell scripts** (`.ps1`) — Windows execution policy blocks them. Prefer a cross-platform `.dart` script (as `tools/workspace_setup/configure.dart` does); use `.sh`/`.bat` pairs only when a Dart script cannot do the job.
5. **Workspace setup is `dart tools/workspace_setup/configure.dart`**, never just `flutter pub get` + `build_runner`. It runs `flutter clean` → `pub get` → `gen-l10n` per package → `build_runner build --workspace` → the barrel generator per package. The gitignored `lib/src/gen/gen.dart` barrels only exist after that last step, and without them `flutter analyze` fails on `gen/gen.dart`, `AppLocalizations` and `Assets`.
6. **build_runner takes no `-d`.** Write `dart run build_runner build --workspace`. `--delete-conflicting-outputs` (short `-d`) was removed from build_runner and is ignored with a warning.
7. **Run and build the app from `apps/<id>/`**, for example `cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev`. The workspace root has no `android/` or `ios/`, so `flutter run -t apps/mobile/lib/main.dart` from the root cannot work.

---

## 📜 6. Updating Barrel Files

- When creating, renaming, or deleting Dart files under `lib/` in any sub-package, run the barrel generator script to update exports:
  ```bash
  dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib
  ```
- ⚠️ **The generator DELETES every hand-written `export '...';` line in a barrel.** It strips all lines starting with `export '` and re-emits its own sorted list (`tools/barrel_generator/generate.dart`, the `line.trim().startsWith("export '")` filter).
  - **ABSOLUTELY FORBIDDEN** to hand-add an `export` to a barrel file — it will silently vanish on the next run.
  - Need a deliberate re-export? Put it in a **normal source file**, which the generator then picks up. Reference: `platform/kernel/lib/src/error/failures.dart` is a plain file whose whole body is the `AppFailure` compatibility re-export.
- The generator skips `part of` files, `*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*_test.dart` and `firebase_options*`, but it **does export every other generated file present on disk**: `module.module.dart`, `injection.config.dart`, and the gen-l10n / flutter_gen output under `lib/src/gen/`. Some of those exports are load-bearing and committed although their targets are gitignored — `platform/base_ui/lib/src/src.dart` exports `gen/gen.dart`, which is how `core_ui_kit` reaches `Assets`.
- **Run it AFTER `gen-l10n` and `build_runner`**, one package at a time — the order `tools/workspace_setup/configure.dart` uses. It rewrites each barrel from what is on disk, so run before them on a clean checkout it drops the generated exports above. An extra run before codegen is harmless; the last run must come after.

---

## 📦 7. Dependency Version Catalog

- Dependency versions are centrally managed in `pubspec_dependencies.yaml` (single source of truth).
- To update package versions, edit `pubspec_dependencies.yaml` then run:
  ```bash
  dart tools/dependency_sync.dart
  ```
- Do NOT hardcode package versions when creating new modules. Run the sync tool instead.

---

## 🧩 8. Agnostic State Communication

The codebase supports multiple state management frameworks (Provider, BLoC). To maintain loose coupling:
1. **Global UI State**: Global app state (Theme, AppLanguage, DeepLink...) must be unified using a single state management utility (ChangeNotifier / ValueNotifier or pure Streams) so feature modules are not forced to import unwanted libraries.
2. **Neutral Streams on DI Hub**:
   - If Feature A (using BLoC) needs to share state with Feature B (using Provider), do NOT expose the BLoC/Provider instance directly.
   - Create a neutral communication interface containing pure Dart `Stream` or `ValueListenable` properties, register it in DI, and have Feature B inject it through its constructor and listen to it. Resolve it with `getItOrNull` wherever a lookup is unavoidable — the owner is removable (R8).
3. **Dual Registration for Owner Feature**:
   - The feature that owns and writes to the neutral stream MUST register its implementation as a concrete `@singleton` (e.g., `AuthStatusStreamImpl`).
   - Use a DI `@module` to bind the pure interface to the concrete instance (e.g., `IAuthStatusStream bind(AuthStatusStreamImpl impl) => impl;`).
   - This allows the owner feature to inject the concrete class directly via constructor (avoiding manual `getIt` lookups and type casting `as`), while other features remain decoupled by only listening to the Interface.
4. **A Neutral Stream MUST NOT carry a Domain Entity**:
   - **ABSOLUTELY FORBIDDEN** for a `core_di` contract to name a type from a `domain_*` package. Doing so makes the DI Hub — and therefore every consumer of it — depend on one feature's domain package for a *type*, which `getItOrNull` cannot soften: an unresolved import fails at compile time, not at lookup time.
   - Declare a **contract-owned** value type instead, and have the owning feature map to it at its boundary. Reference: `AuthPrincipal` (`core_di/lib/src/agnostic_streams/auth_principal.dart`), which `AuthStatusStreamImpl.toPrincipal` produces from `UserEntity`.
   - The contract is deliberately **smaller** than the entity: whatever field the owning module later adds to `UserEntity` stays invisible to a module that only needs to know who is signed in. Add a field to the contract only when a *second* module genuinely needs it.
   - `core_di` therefore declares **no** `domain_*` dependency.

---

## 🚀 9. Creating New Modules (Quick Reference)

```bash
# Feature (Provider), routes as IFeatureRouteModule:
dart tools/module_generator/generate.dart 1 <name> "" 1 1

# Feature (BLoC), routes as a bottom-nav INavDestinationModule:
dart tools/module_generator/generate.dart 1 <name> "" 2 2

# Domain micro-package:
dart tools/module_generator/generate.dart 2 <name>

# Data micro-package:
dart tools/module_generator/generate.dart 3 <name>

# Core package → core_<name> at platform/<name>:
dart tools/module_generator/generate.dart 4 <name>

# Custom package → <prefix>_<name> at platform/<name>:
dart tools/module_generator/generate.dart 5 <name> <prefix>
```

For a feature, **always pass all five arguments** (state management: `1` Provider · `2` BLoC · `3` none; route: `1` `IFeatureRouteModule` · `2` `INavDestinationModule` · `3` none). A feature missing `<SM>` or `<route>` prompts for it on a terminal, and without one exits `64` — always pass both. Arguments are validated before anything is written: `<name>` (and a type-5 prefix) must be a Dart package name — lowercase letters, digits, `_`, starting with a letter, not a Dart keyword — `<SM>` / `<route>` accept only `1`/`2`/`3`, a `<prefix>` / `<SM>` / `<route>` given to the wrong type and any unknown flag are refused; each refusal exits `64` with the usage (`--help` prints it). For types `1`–`4` the third argument must be empty (`""`). For type `5` it is a package-name prefix, not a directory — a layer word (`feature`, `domain`, `data`, `core`) is refused. If the module cannot be registered in an `app_manifest.yaml`, the generator rolls back and exits `1`.

---

## 🔍 10. Deprecation Handling & Deep Research

- When encountering any `info` or `warning` from `flutter analyze` regarding deprecated members/APIs, AI Agents **MUST perform deep research** to find the correct, up-to-date migration path before writing code.
- Ignoring deprecations or applying temporary quick-fixes is **ABSOLUTELY FORBIDDEN**.

---

## 🌍 11. Strict Localization (Translation) Enforcement

- If the app supports localization, **ALL user-facing text** (including hardcoded UI text, toast messages, and server error messages) **MUST be translated** using the app's standard localization infrastructure.
- **Feature-Scoped Translations**: Each feature MUST define its own translation `.arb` files inside its `assets/language/` directory (e.g., `modules/auth/feature/assets/language/en.arb`).
- **Global Assets & Shared UI Only**: The `core_base_ui` package is strictly reserved ONLY for globally shared assets and global fallback strings. Purely reusable UI packages (like `core_ui_kit`) **MUST NOT** define their own translation `.arb` files. They must use translations exported from `core_base_ui`.
- When calling translations, use the feature-specific extension (e.g., `context.l10nAuth.translationKey`) rather than a global delegate.
- Hardcoding raw strings in UI components is **ABSOLUTELY FORBIDDEN**.
- **ARB keys MUST be `lowerCamelCase`.** `flutter gen-l10n` copies each key straight through into a Dart getter, so `welcome_back` yields `context.l10nAuth.welcome_back` at every call site — an identifier that breaks Dart's naming convention. Generated files are excluded from `analysis_options.yaml`, so nothing will warn you; the `.arb` is the only place the casing is decided.
- **Decentralized Delegation**: Feature packages MUST NOT modify `platform/app_shell/lib/presentation/root_app.dart` to add their LocalizationsDelegates. Instead, they must provide an implementation of `IFeatureLocalization` and register it in their local DI (`@Injectable(as: IFeatureLocalization)`). The shell's `app_material_wrapper.dart` collects all delegates using `getAllOrEmpty<IFeatureLocalization>()`. The same pattern applies to routing: register `IFeatureRouteModule` (top-level routes), `INavDestinationModule` (shell tabs + bottom nav), and optionally `IAppEntryLocation` (cold start). The app shell uses `getAllOrEmpty` / `getItOrNull` with fallbacks so removing a feature package does not crash the host: no route modules → an empty list; no `IAppEntryLocation` → the first destination's path, or the placeholder branch `/_empty_dashboard` when no destination is registered either; no `DashboardRouteModule` → the bare `navigationShell`, tabs without chrome (`platform/app_shell/lib/presentation/navigation/app_router.dart`).

---

## 🎨 12. Dialog & Bottom Sheet Isolation

- **ALL dialogs and bottom sheets MUST be extracted into their own separate widget classes/files**.
- **ABSOLUTELY FORBIDDEN** to write inline widget structures directly inside `showDialog()` or `showModalBottomSheet()` builder functions.
- **Naming Suffixes**:
  - Dialog files must use the suffix `_dialog.dart` and class names must suffix with `Dialog` (e.g. `ConfirmationDialog` in `confirmation_dialog.dart`).
  - Bottom sheet files must use the suffix `_bottom_sheet.dart` and class names must suffix with `BottomSheet` (e.g. `HomeSettingsBottomSheet` in `home_settings_bottom_sheet.dart`).

---

## ⚡ 13. Freezed State & Event Rules

1. **Private Event Subclasses**: All subclasses (implementations) defined in a Freezed `Event` class of a BLoC **MUST be named private** (start with `_`, e.g., `const factory HomeEvent.started() = _HomeStarted;`).
2. **UI State is flexible**: Prefer shared `BlocViewState<T>` (from `bloc_state_management`) for simple screens. **It is not mandatory** — complex features may define a custom Freezed UI state (`BaseBloc<Event, CustomState>`). When using a custom state, keep its Freezed variants in `_state.dart` via `part` / `part of` (same privacy rules as events).
   - The BLoC state is named **`BlocViewState<T>`**, not `ViewState` — `provider_state_management` already exports a different `ViewState` (5 variants, no generic, nullable `ErrorState`). Both barrels are public, so the rename is what keeps a file that imports both from failing to compile.
3. **Part & Part Of Architecture**: So the BLoC can access private event (and custom state) subclasses without exporting them publicly, the BLoC file structure **MUST** use Dart `part` / `part of`:
   - The main BLoC file (`_bloc.dart`) declares:
     ```dart
     part '_event.dart';
     // The module generator always emits `_state.dart`: with BlocViewState it holds the
     // Freezed `…StateData` payload (`BlocViewState<…StateData>`); with a custom state, that state.
     part '_state.dart';
     part '_bloc.freezed.dart';
     ```
     Drop `_state.dart` only when the payload type lives elsewhere — `HomeProfileBloc` uses `BlocViewState<AuthPrincipal?>` and has no state file.
   - The corresponding event/state files (`_event.dart`, `_state.dart`) declare:
     ```dart
     part of '_bloc.dart';
     ```
4. **Strict Asynchronous Event Registration**: When registering an event handler with `on<SubEvent>(...)` in a BLoC, the handler signature **MUST** take both parameters `(event, emit)` per the `bloc` package contract.
   **ABSOLUTELY FORBIDDEN** to use a synchronous closure `on<Event>((event, emit) { event.when(...) })` that calls async functions without awaiting them, because the sync handler finishes immediately and later causes `emit was called after an event handler completed normally.` when the async work completes.
   ```dart
   // CORRECT: Register handlers that take both arguments directly
   // Example with BlocViewState — swap for CustomState when the screen needs richer UI state.
   HomeBloc(this._cryptoRepository) : super(const BlocViewState.initial()) {
     on<_HomeStarted>(_fetchInitialData);
     on<_HomeRefreshed>(_fetchInitialData);
     on<_HomeTradeUpdated>(_handleTradeUpdated);
   }

   Future<void> _fetchInitialData(
     HomeEvent event,
     Emitter<BlocViewState<HomeStateData>> emit,
   ) async {
     emit(const BlocViewState.loading());
     // ... async logic
   }
   ```

---

## 📏 14. Responsive UI & Screen Size Scaling

- **Strict usage of `core_responsive`**: All UI sizing — width, height, padding, margins, font sizes, border radii — **MUST** be scaled. `core_responsive` is a first-party package at `platform/responsive`; it replaced `flutter_screenutil_plus`, which is gone from the repo.
- **Scaling MUST go through `BuildContext`**: `context.w(x)`, `context.h(x)`, `context.sp(x)`, `context.r(x)` (plus `context.spMin`, `context.dg`, `context.dm`).

  **The bare receiver form (`16.h`) does not exist and does not compile.** `core_responsive` deliberately ships **no extension on `num`**. A number carries no context, so such an extension could only read a global — and a widget that reads a global never learns the metrics changed, computing once and never updating. That is a silent stale-value bug, invisible until a device rotates. Reading through `context` registers an **InheritedWidget dependency** (`ResponsiveScope`), so exactly the widgets that scale a value rebuild on rotation, split-screen, or a desktop resize, and the ones that do not are left alone. Requiring the context makes the correct thing the only writable thing.

- **ABSOLUTELY FORBIDDEN** to use raw double values (e.g., `SizedBox(height: 24)`, `fontSize: 16`, `padding: EdgeInsets.all(16)`) in UI layout constraints. Always scale them:
  ```dart
  SizedBox(height: context.h(24))
  TextStyle(fontSize: context.sp(16))
  Padding(padding: EdgeInsets.all(context.w(16)))   // or context.edgeInsets(all: 16)
  ```
- **No `BuildContext` in scope?** In an `async` method, read the value from context **before the first `await`** and pass it forward — never hold a context across an await. Read `context.w(96)` first, `await` second, and check `mounted` before touching state afterwards — see the snippet in `docs/en/reference/01_rules.md` §12.
- **Design tokens take context too.** `AppSpacing.lg(context)`, `AppRadius.xxlRadius(context)`, `AppTextStyles.bodyMediumStyle(context)` — never a bare getter. Their `raw*` constants are the single source of the numbers; edit `raw*`, not the accessors.
- **UI-Agnostic Reusable Components**: Reusable atomic UI components (e.g., those in `core_ui_kit` like `CustomButton`, `CustomCacheNetworkImage`) **MUST** remain strictly UI-agnostic. They **MUST NOT** scale incoming parameter values internally: it is the *caller's* responsibility to scale arguments *before* passing them in, so a parameter arrives already in device pixels and is used as-is. A widget's **own** constants — its padding, its default gap — it must still scale, or it is not responsive; `custom_input_field.dart` shows both in one line: `widget.paddingBottom ?? context.h(10)`.
- **`ResponsiveInit` is mounted once**, above `MaterialApp`, in `platform/app_shell/lib/main_scope.dart`. It is a `StatelessWidget` on purpose: it reads `MediaQuery.sizeOf(context)`, which registers a **size-only** dependency, so it rebuilds on resize and ignores brightness, text-scale and padding changes. Features never mount their own.
- **A widget test that scales must wrap the widget under test in `ResponsiveInit`.** Without it `ResponsiveScope.of` asserts — deliberately. A silent unscaled fallback would ship a layout that is wrong on every device except the design artboard, with nothing pointing at the cause.
- **Scale policy: down by default, up on opt-in, per window class.** Every scale factor is the window-to-artboard ratio clamped by a `ScaleBounds`. Layout (`scaleBounds` — `w`, `h`, and the `r` / `dg` / `dm` built from them) and text (`textScaleBounds` — `sp`) are clamped separately, both `ScaleBounds.downOnly()` by default: a window smaller than the artboard shrinks the design, a larger one draws it 1:1. **Do not expect sizes to grow on a tablet** — the extra room belongs to the layout. Growth is opt-in and capped, per `WindowSizeClass`, through a `ResponsiveProfile` (`designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt`; `null` inherits; the exact class applies, else the nearest smaller one). `ScaleBounds.fixed()` pins the design size; `ScaleBounds.unbounded()` is the old raw ratio. A `fontSizeResolver`'s result is never clamped; `spMin` is the explicit cap. The app's configuration (`_ResponsiveWrapper`): `AppConfig.design` (375×812), default bounds, an `expanded` profile at real logical pixels (`ScaleBounds.fixed()` for layout and text), `splitScreenMode: true`. The theme scales type with `context.sp`, so it follows `textScaleBounds`.
- **Choose a layout by window size class, never by device.** Use `context.windowSizeClass` (`compact` < 600, `medium` 600–839, `expanded` 840–1199, `large` 1200–1599, `extraLarge` ≥ 1600 — Material 3 `ResponsiveBreakpoints`, movable through `ResponsiveInit(breakpoints:)`), `context.adaptive(...)`, `AdaptiveLayout` / `AdaptiveBuilder`, `AdaptiveSplitView`, `AdaptiveContent`. **FORBIDDEN:** branching a layout on `Platform.isIOS`, a device model or an ad-hoc `shortestSide` check — one device shows many windows (Split View, a cover screen, a resized desktop window). These members work without a `ResponsiveInit` (Material 3 fallback). `AdaptiveSplitView` honours a fold or hinge only when it spans the window along it — in a dashboard tab the rail (`medium` and up) rules out book folds and the bottom bar (`compact`) tabletop ones. `AdaptiveContent.maxWidth` (640) is a window-space limit — never scale it. Reference: `feature_dashboard` — bottom bar on `compact`, `NavigationRail` from `medium`, extended from `large`. Full guide: `docs/en/guides/11_design_system.md` §6–§7.
- **Helper scaling axes:**

  | Helper | Scales by |
  |:--|:--|
  | `context.edgeInsets(all: x)` | `w` |
  | `context.edgeInsets(horizontal: x)` | `w` |
  | `context.edgeInsets(vertical: x)` | `h` |
  | `context.borderRadius(all: x)` | `r` |
  | `context.verticalSpace(x)` | `h` |
  | `context.horizontalSpace(x)` | `w` |

  Each axis is scaled by the axis it belongs to, so padding keeps its proportions rather than tracking one dimension. `context.edgeInsets(all: x)` is therefore a drop-in for `EdgeInsets.all(context.w(x))`.

**Enforced by machine.** `dart tools/arch_check/check.dart` (rule **R7**, Gate 1 of `pr_quality_check.yml`) scans every file importing `core_responsive` and **blocks the build** on any bare sizing extension, printing `file:line`. That half is not held by review; the raw-double, scale-policy and window-class points above are.

---

## 🖼️ 15. Feature-Scoped Assets & Resources

- **Decentralized Assets**: All UI assets (images, svgs, animations, Lottie) that are specific to a feature MUST be placed in that feature's own `assets/` folder — the shipped example is
  `modules/auth/feature/assets/language/`, and images belong beside it in an `assets/images/`
  folder the feature creates when it first needs one.
- **Global Assets Only**: The `core_base_ui` package is strictly reserved ONLY for globally shared assets (like the app logo, global icons, or global background patterns) and global fallback strings.
- **Do not** dump all images into `core_base_ui` as it creates massive coupling. Feature modules should be standalone and encapsulate their own assets.

---

## 🗂️ 16. Package Constants Live in `utils/`

- **Every package, at every layer** (core / domain / data / features / app shell), MUST keep its own public constants inside a `utils/` folder within that package — e.g. `modules/auth/feature/lib/src/utils/`, `platform/app_shell/lib/di/utils/`. A package with no constants needs no `utils/` folder: `arch_check` **R4** flags a public `static const` outside `utils/` (or `styles/`), and never asks for an empty folder.
- **ABSOLUTELY FORBIDDEN** to create a shared cross-domain constants file that many packages import. A constant belongs to exactly one owner.
- `platform_kernel`'s `lib/src/utils/` (re-exported through `core_common`) is reserved for constants that are **genuinely global** — today `EnvConstants` (`String.fromEnvironment` values) and `ErrorCodes` (the failure codes `ErrorHandler` and `IBaseRepository` assign when there is no HTTP status). Feature/domain-owned values (storage keys, route paths, API endpoints) MUST NOT live there.
- **Precedent — constants that were evicted from `core_common`,** so nobody re-adds them:
  | Was | Now | Why |
  | :--- | :--- | :--- |
  | `StorageKeyConstants` | deleted → per-owner `utils/` keys (§ 17) | held every domain's storage keys |
  | `ApiConstants` | `AuthApiConstants` in `modules/auth/data/lib/src/utils/` | held only auth endpoints |
  | `NotificationConstants` | `platform/notifications/lib/src/utils/` | belongs to the notifications package |
  | `AnalyticsConstants`, `SocketConstants`, `FirebaseRemoteConfigConstants` | deleted | zero references; dead scaffolding |
- **Approved exception — design tokens.** `core_base_ui/lib/src/styles/` (`AppSpacing`, `AppRadius`, `AppTextStyles`, `AppGradients`, `AppShadows`) stays in `styles/`, **not** `utils/`. It is the design system's public API; `styles/` names that intent, while `utils/` reads as miscellany. **Do not "fix" this in a future audit.**
- Applied conventions:
  - **Route paths**: `lib/src/utils/<feature>_path.dart` (moved out of `routing/`). E.g. `AuthPath`, `HomePath`, `OnboardingPath`, `SettingsPath`.
  - **Storage keys**: `lib/src/utils/<owner>_storage_keys.dart`. E.g. `AuthStorageKeys`, `LanguageStorageKeys`, `ThemeStorageKeys`, `AppBootStorageKeys`.
  - **API endpoints**: `lib/src/utils/<owner>_api_constants.dart`. E.g. `AuthApiConstants`.
- Constant classes use a private constructor and `UPPER_SNAKE_CASE` members:
  ```dart
  class AuthStorageKeys {
    AuthStorageKeys._();
    static const String TOKEN = 'token';
    static const String AUTH_USER = 'auth_user';
  }
  ```
- After adding/moving files, re-run the barrel generator (§ 6).

---

## 💾 17. Package-Owned Storage Values

`core_storage` provides the **mechanism only**. The former `StorageValuePresets` (a single `@Singleton` holding every domain's keys) and `core_common`'s `StorageKeyConstants` have been **deleted** — a shared object let any injector read and write another feature's data.

1. **Each consumer owns its own `StorageValue`.** Inject `StorageManager`, declare `late final StorageValue<T>` locally, and key it from that package's `utils/` keys class (§ 16).
2. **Register the owner as a singleton** — `@singleton`, `@lazySingleton`, or `@Singleton(as: IFoo)` — combined with `@PostConstruct(preResolve: true)` so the in-memory cache is hydrated from disk before first use.
   **ABSOLUTELY FORBIDDEN** to register a storage owner as `@injectable` (factory): every injection would produce a new instance with an empty cache, so synchronous getters would silently return `null`.
3. **Never expose one package's `StorageValue` to another package.** If another layer needs the value, publish an interface on `core_di` (as done for `IThemeStorage` / `ILanguageStorage`) instead of sharing the storage object.
4. Choose the backend explicitly: `StorageType.secure` for tokens/PII, `StorageType.pref` for settings and flags. Use the `reviver` callback for Enums and custom types (stored through their `toJson()`); primitives, `Map<String, dynamic>` and typed lists read back without one.

```dart
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }
}
```

---

## 🧨 18. DI Registration Order & Eager Singletons

- `configureDependencies()` initializes modules **in the order declared** in `apps/mobile/lib/di/injection.dart`: `externalPackageModulesBefore` (the `core` group) → `externalPackageModulesAfter` (`notifications`, `shell`, `ui`, `domain`, `data`, `feature`, `other`, in that order). That order comes from the manifest's `di_groups`. The app package's own registrations run *between* the two phases, and it keeps that slot for what identifies it: `FirebaseModule` (`apps/mobile/lib/firebase/firebase_module.dart`), which is why `core_notifications` — whose eager `PushNotificationService` injects `FirebaseOptions` — sits in `after`, not `core`.
- **ABSOLUTELY FORBIDDEN** for an eager `@Singleton` to depend on a type registered by a module that runs **later** — GetIt throws `"<Type> is not registered"` during boot.
- Use `@LazySingleton` whenever a dependency comes from a later module. One live constraint in this template is `shell` before `ui` (the other: `notifications` after the app's own `FirebaseModule`, see above): `ThemeProvider` / `LanguageProvider` in `core_base_ui` inject the storage adapters `platform_app_shell` registers, so the `shell` group must come first — the manifest's `di_groups` order is what guarantees it. (`NetworkConfigImpl` used to be the textbook example, injecting `AuthLocalDataSource` from `data_auth`; it now reads the session through `IAuthSessionGateway` at call time and has no cross-module constructor dependency at all.)
- `flutter analyze` **cannot** detect this class of bug — it only appears at runtime. After changing any DI annotation or constructor, read two generated files:
  - `apps/mobile/lib/di/injection.config.dart` holds only the **module order** — one `…PackageModule().init(gh)` call per package, plus the app's own `FirebaseModule` registrations between the phases.
  - Each package's `lib/di/module.module.dart` holds the **per-type registrations**: find your type's `gh.singleton<…>` / `gh.lazySingleton<…>` / `gh.factory<…>` and the `gh<Dep>()` calls in its constructor.
  An eager `gh.singleton` is safe only if every `gh<Dep>()` it makes is registered earlier in its own `module.module.dart` or by a package module whose `init` comes earlier in `injection.config.dart`.
- `@PostConstruct(preResolve: true)` on a `@lazySingleton` is awaited during module init and then re-registered as a plain sync lazy singleton, so downstream `gh<T>()` sync lookups are safe.

---

## 🔗 19. Explicit Dependency Declaration

- This monorepo uses **Pub Workspaces**, so all packages share a single `package_config.json`. A package that imports another package **without declaring it** still compiles locally — the breakage only surfaces when the package is extracted or published.
- **MANDATORY**: every `package:` import used under `lib/` must have a matching entry in that package's `pubspec.yaml`.
- Production-code imports belong in `dependencies`. **ABSOLUTELY FORBIDDEN** to satisfy a production import from `dev_dependencies`.
- Remove dependencies that are no longer used — stale entries create phantom coupling between layers.
- Verify before every PR — the two halves are checked by two different tools:
  ```bash
  dart tools/arch_check/check.dart                      # R5: imported under lib/ but not in `dependencies:` (dev_dependencies does not count) — blocking, Gate 1
  dart tools/unused_checker/check_unused_packages.dart  # declared in `dependencies:` but never imported — advisory
  ```

---

## 🧯 20. GetIt Resolution Traps

Three GetIt behaviours have each caused a real, silent production bug in this repo. Learn them before touching DI.

1. **`getAll<T>()` THROWS when `T` is unregistered — `getAllOrEmpty<T>()` does not.**
   - Both live in `platform/kernel/lib/src/di/service_locator.dart`; `platform/common/lib/di/module.dart` re-exports them. `getAllOrEmpty` guards with `getIt.isRegistered<T>()` and returns `const []`.
   - **MANDATORY**: every optional multi-instance contribution (`IFeatureRouteModule`, `INavDestinationModule`, `IFeatureLocalization`, `IAppTreeWrapper`) MUST be collected with `getAllOrEmpty`. `IDatabaseMigration<TDb>` is collected with the same guard written out: the database's own DI module checks `GetIt.instance.isRegistered<IDatabaseMigration<CacheDatabase>>()` and calls `getAll` only when it is true (`modules/cache/data/lib/di/module.dart`). Either form is fine; a bare `getAll` is not.
   - Real bug: `app_material_wrapper.dart` used `getIt.getAll<IFeatureLocalization>()`; with no feature contributing one, `MaterialApp` construction threw and the app died at boot.
   - Same rule for single instances: `getItOrNull<T>()` + a fallback, never bare `getIt<T>()`, whenever `T` is owned by a removable feature.
   - **Enforced by machine.** `dart tools/arch_check/check.dart` rule **R8** derives every `core_di`
     contract implemented under `modules/` — in **any** layer: a data package's gateway
     (`IAuthSessionGateway` in `data_auth`) as much as a feature's navigator — keyed by the module
     that implements it, then blocks a throwing `getIt<T>()` / `getAll<T>()` against one.
     Contracts implemented in the app shell (`IThemeStorage`, `ILanguageStorage`) are always
     registered and stay outside the set. A module is removed whole, so any package of the
     implementing module (e.g. `feature_auth` for `data_auth`'s gateway) may still resolve its
     contracts eagerly. `flutter analyze` cannot see this class of bug — the lookup type-checks
     against `core_di` and only crashes at runtime.

2. **GetIt does NOT resolve supertypes.** Registering `Impl as InterfaceA` leaves `getIt<InterfaceB>()` unresolvable even when `InterfaceA implements InterfaceB`.
   - Real bug: `NetworkConfigImpl` was registered only `as NetworkConfig`, so `getItOrNull<SslPinningConfig>()` in `AppInitializer._setupHttpOverrides` returned `null` and **certificate pinning was silently skipped on staging and production**.
   - Fix pattern — bind the second type through a `@module`, typed so the compiler checks the upcast (no `as`):
     ```dart
     // platform/app_shell/lib/di/network_binding_module.dart
     @module
     abstract class NetworkBindingModule {
       @lazySingleton
       SslPinningConfig bindSslPinningConfig(NetworkConfig config) => config;
     }
     ```
   - This is the same dual-registration idea as § 8.3, applied to a supertype instead of an interface.

3. **`@PostConstruct(preResolve: true)` on a `@lazySingleton`** is awaited during module init and then re-registered as a plain sync lazy singleton, so later `gh<T>()` sync lookups are safe (see § 17).

---

## 🗄️ 21. Package-Owned Databases

`core_database` provides the **mechanism only** and owns no database, table or DAO — its generated module body is literally `init(gh) {}`.

- **Why**: Drift resolves `@DriftDatabase(tables: [...], daos: [...])` at compile time and a DAO must be `part of` its database library. A single shared `AppDatabase` therefore forces whichever package declares it to own **every** table — reproducing the god-object that § 16/§ 17 exist to prevent.
- **Rule**: a package that needs relational storage declares **its own database** beside its own tables and DAO. Reference: `modules/cache/data/lib/src/database/` holds `CacheDatabase`, `tables/cache_entries_table.dart` and `dao/cache_entries_dao.dart`.
- `core_database` supplies: `IDatabaseHandle<TDb extends GeneratedDatabase>` (hand a package only the accessor it asks for, plus `transaction`), `IDatabaseMigration<TDb>` (a package contributes its own upgrade/downgrade steps), `DatabaseMigrationRunner`, `DatabaseConnectionFactory`, `DriftDatabaseOpener`.
- **Register a migration typed to its database**: `@LazySingleton(as: IDatabaseMigration<YourDatabase>)`. GetIt keys a registration by its exact type and the database's module collects only `IDatabaseMigration<YourDatabase>`, so an untyped `as: IDatabaseMigration` registration is never collected and the step silently never runs (`docs/en/guides/07_database.md` § 4). The step must also be registered **before** the database opens, which runs its migrations inside its `@preResolve` factory: a step in the owning package is, as long as the open carries `@Order(1)` (injectable registers a package's entries in ascending order; the step has the default 0 — `modules/cache/data/lib/di/module.dart`), so put `@Order(1)` on your own database's open too; a step from another package must sit in an earlier DI group.
- **Accepted trade-off**: SQL cannot join across package boundaries. That is deliberate — crossing a bounded context belongs at the repository layer, not in a query.
- **Removability**: deleting a package deletes its database with it. A database must open normally when **no** `IDatabaseMigration` is registered.
- Drift limits worth knowing: there is **no `onDowngrade` callback** (downgrade is routed through `onUpgrade` by comparing `from`/`to`; `DatabaseMigrationRunner` throws on a downgrade unless a step is registered for the version being left — downgrades need explicit steps), and **no runtime table registration** — a package cannot add a table to another package's database.

---

## 🔌 22. Any Feature Must Be Removable

Deleting any `modules/*/feature` package must leave the app compiling and booting.

- **An app's only intentional hard reference to features is its generated `apps/<id>/lib/di/injection.dart`** — as the composition root it must name what it composes. Every *other* shell file resolves features through `core_di` contracts.
- To drop a feature, delete its entry from **every** `apps/<id>/app_manifest.yaml` that composes it (`auth` and `settings` appear in both `mobile` and `admin`) and run:
  ```bash
  dart tools/composer/composer.dart sync
  flutter pub get && dart run build_runner build --workspace
  ```
  `composer` regenerates three artifacts — each app's `lib/di/injection.dart`, each app's `pubspec.yaml` path dependencies, and the root `workspace:` list — each between `composer:managed` markers. `composer verify` is Gate 0 of `pr_quality_check.yml`, so drift between the manifest and those files fails CI.
  **Only the manifest is edited by hand.**
- **A type import defeats `getItOrNull`.** Guarding the *lookup* is useless if the file still imports the feature for the *type* — an unresolved import fails at compile time, before any lookup runs. When the shell needs something a module owns, declare a contract in `core_di` and have the module implement + register it:

  **Enforced by machine.** `dart tools/arch_check/check.dart` rule **R10** fails the build when any file in an app imports a `feature_*`, `data_*` or product `domain_*` package, with `injection.dart` as the single exception; the shared shell, `platform_app_shell`, is a `platform/*` package, so **R1** holds it to the same rule. R10 was added after `network_config_impl.dart` (then an app file, now in `platform_app_shell`) was found importing `data_auth` and `domain_auth` to read and refresh the session token — this section promised removability while the composition root broke it. Review had not caught it in the entire life of the file.

  | Contract (`core_di`) | Replaces the shell's direct use of |
  | :--- | :--- |
  | `IAppSplashScreen` | `SplashPage` from `feature_splash` in `main.dart` |
  | `IAuthRefreshListenable` (`implements Listenable`) | `AuthProvider` as GoRouter's `refreshListenable` |
  | `IAuthSessionState` + `AuthSessionFailure` | `AuthProvider` / `AuthErrorState` / `context.l10nAuth` in `NavigatorWrapperWidget` |
  | `IAppTreeWrapper` | `ChangeNotifierProvider<AuthProvider>` in `app_material_wrapper.dart` |
  | `IAuthSessionGateway` | `AuthLocalDataSource` + `RefreshTokenUseCase` in `network_config_impl.dart` |

- Contracts in `core_di` MUST stay state-management agnostic: `IAppTreeWrapper.wrap()` returns a plain `Widget`, so a Provider feature can return `ChangeNotifierProvider` and a BLoC feature `BlocProvider` without either forcing its package on the other.
- Prefer a plain Dart 3 `sealed class` over Freezed for `core_di` contracts (see `AuthSessionFailure`) — `core_di` runs only injectable's codegen (its `lib/di/module.module.dart`), no Freezed or other `part`-file codegen, and adding a `part` to a contract would make every consumer wait on `build_runner`.
- The shared widget library is **not** a removable feature: it lives at `platform/ui_kit` as `core_ui_kit`, so `modules/*/feature/` contains only genuinely removable product surfaces.

---

## 🔬 23. `flutter analyze` Cannot See Generated Code

`analysis_options.yaml` excludes `**.freezed.dart`, `**.g.dart`, `**.mocks.dart`, `**.config.dart`, `**.module.dart` from analysis.

- **A clean `flutter analyze` does NOT mean the app compiles.** Errors inside generated files are invisible to it and surface only in a real build.
- Real incident: moving `AppFailure` from `core_common` to `domain_core` broke `bloc_view_state.freezed.dart`, which needs the generated `$AppFailureCopyWith`. The `core_common` re-export shim lists concrete failure types in its `show` clause and cannot carry the generated companion. `flutter analyze` reported **No issues found**; the APK build failed with `Type '$AppFailureCopyWith' not found`. Fix was to depend on `domain_core` directly.
- **MANDATORY verification order** after any change to DI annotations, package dependencies, or the location of a Freezed/JSON type:
  ```bash
  dart run build_runner build --workspace
  flutter analyze
  (cd modules/<module>/<layer> && flutter test)    # per package that has a test/ directory
  cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
  ```
  The build step is **not optional** — it is the only gate that sees generated code. Run `flutter test` only in a package that has a `test/` directory (CI Gate 3 does the same). The APK build needs two gitignored inputs a fresh clone lacks: the `firebase_options_<flavor>.dart` files in `apps/mobile/lib/firebase/` and `apps/mobile/android/app/src/<flavor>/google-services.json` — create them as described in `docs/en/getting-started/01_setup.md` § 3 before building.
- Corollary: when a type consumed by generated code moves package, **import its new home directly**. Do not rely on a `show`-limited re-export.
