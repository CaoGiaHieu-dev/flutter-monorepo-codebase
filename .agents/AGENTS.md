# 🤖 Codebase Rules & Developer Agent Guidelines (AGENTS.md)

This file contains the rules for architectural design, naming conventions, dependency injection (DI) management, routing, and coding standards for this Monorepo template. Every AI Agent (Gemini, Copilot, Cursor, etc.) working on this codebase **MUST read and strictly comply 100%** with the rules below.

---

## 🏗️ 1. Monorepo Directory Layout

This monorepo uses **Pub Workspaces** and is divided into independent physical layers under the `packages/` directory:

- **`app/`**: Host App Shell. Contains startup (`main.dart`), **dynamic** router assembly (`app_router.dart` collects `IFeatureRouteModule` / `IDashboardTabModule` / `DashboardRouteModule` via DI — do not hardcode feature `$…Route` lists), and centralized DI (`injection.dart`).
- **`packages/core/`**: Infrastructure and utility packages shared across the project:
  - `core_common`: **Genuinely global** constants (`ApiStatusConstants`, `EnvConstants` — all under `lib/src/utils/`), enums, mixins, `ErrorHandler`, `AppConfig`, `AppInitializer`, extensions. **MUST NOT** hold constants owned by a single feature/domain (storage keys, route paths, API endpoints) — those live in the owning package's `utils/`. Note `AppFailure` now lives in `domain_core` (§ 2.1); `core_common` keeps a re-export shim at `lib/src/error/failures.dart` so existing imports keep resolving.
  - `core_di`: Navigation keys, routing contribution contracts (`IFeatureRouteModule`, `IDashboardTabModule`, `IAppEntryLocation`, `DashboardRouteModule`), and cross-package communication interfaces.
  - `core_base_ui`: Design system resources (typography, color palette, icons, assets, and L10n translations). **Contains zero Flutter widgets.**
  - `core_ui_kit`: Unified library for all reusable widgets (atomic components like buttons/inputs, plus dialogs, feedback, layout, media and navigation widgets). Depends only on `core_common`, `core_base_ui` and `provider_state_management` — never on a feature. It lives under `packages/core/` because it is a shared UI library every feature may consume, **not** a removable feature.
  - `core_network`: Pre-configured HTTP client (Dio, Retrofit) with interceptors (auth, retry, logging).
  - `core_storage`: **Storage mechanism only** — `StorageInterface`, `StorageManager`, reactive `StorageValue<T>`, `StorageType`, over two-tier storage (Secure Storage + SharedPreferences). **Defines zero keys or presets**; every consumer declares its own `StorageValue` (see § 17).
  - `core_database`: **Database mechanism only** — `IDatabaseHandle<TDb>`, `IDatabaseMigration`, `DatabaseMigrationRunner`, `DatabaseConnectionFactory`, `DriftDatabaseOpener`. **Owns no database, table or DAO** (its DI module registers nothing); each package declares its own database (see § 20).
  - `core_notifications`: Push notification management module. Owns its channel constants at `lib/src/utils/notification_constants.dart`.
  - `provider_state_management`: Provider state management base classes (`BaseProvider`, `executeOperation`, `BaseViewWidget`, `ViewStateModel`), plus the in-core `DefaultLoadingWidget` / `DefaultEmptyWidget` fallbacks.
  - `bloc_state_management`: BLoC state management base classes (`BaseBloc`, `BlocViewState<T>`; `BaseCubit` only when events are unnecessary). **`BaseBloc`/`BaseCubit` are extension points only** — there is no BLoC equivalent of `executeOperation`, so BLoC handlers unwrap `Result` / map `AppFailure` / set loading by hand.
- **`packages/domain/*` (Micro-packages)**: Business logic core. **MUST be pure Dart (100% decoupled from Flutter UI, Dio, Retrofit, or any platform-specific dependencies)**. Current micro-packages:
  - `domain_core`: Defines `Result<T>`, `BaseEntity<T>`, and shared primitive types.
  - `domain_auth`: Entities, use cases, and repository interfaces for authentication.
  - `domain_language`: Entities and use cases for multi-language localization.
- **`packages/data/*` (Micro-packages)**: Data access layer (remotes, local caching, models/DTOs). Depends on `domain` packages. Current micro-packages:
  - `data_core`: `IBaseRepository` with `execute()` and `executeSync()` wrappers to automatically handle error conversion.
  - `data_auth`: Models/DTOs, Remote DataSources (Retrofit), and RepositoryImpl for authentication.
  - `data_language`: RepositoryImpl for multi-language localization.
- **`packages/features/`**: Independent functional modules. Every package here is a removable product surface — the shared widget library is **not** one of them; it lives at `packages/core/ui_kit` as `core_ui_kit`.
  - Feature packages (e.g., `feature_onboarding`, `feature_auth`, `feature_dashboard`, `feature_home`, `feature_settings`, `feature_splash`):
    - Can only depend on `domain_*` and `core_*` packages — in practice `core_di`, `core_common`, `core_base_ui`, `core_ui_kit`, and `provider_state_management` or `bloc_state_management`.
    - **ABSOLUTELY FORBIDDEN** to directly depend on the `data` layer or on **any** other feature package. There is no exception: shared widgets come from `core_ui_kit`, which is core, not a feature.
    - **One bounded UI concern per feature package**: Do not co-locate unrelated product surfaces in the same feature (e.g. Home tab + Settings tab). `AppRouter` + `IDashboardTabModule` assemble shell branches; `feature_dashboard` supplies **chrome only** (`DashboardRouteModule`), not tab pages. Sample split: `feature_home` vs `feature_settings`.

---

## 🧱 2. Strict Layer Isolation

0. **Core Layer must never depend on Features (or Data)**:
   - **ABSOLUTELY FORBIDDEN** for any `packages/core/*` package to import `package:feature_*/...` or `package:data_*/...`, or to declare them in its `pubspec.yaml`. Core is the innermost infrastructure ring — nothing above it may own it.
   - **Core → Domain is not an upward edge.** Domain is the innermost ring: it depends on nothing, and every other layer may depend on it. The exceptions below are recorded so the graph stays auditable, not because they are violations. Verify the full list at any time with:
     ```bash
     grep -E "^  (domain_|data_|feature_)" packages/core/*/pubspec.yaml
     ```
   - Currently **four** core → domain edges exist, and no `core → data` or `core → feature` edge may ever be added:
     - `core_di → domain_auth` — needs concrete entity types (e.g. `UserEntity`) for agnostic stream interfaces (see § 8.4).
     - `provider_state_management → domain_core` — needs `Result<T>` / `PaginatedEntity<T>`.
     - `bloc_state_management → domain_core` — needs `AppFailure` for `BlocViewState.error`. It must import `domain_core` **directly**, not via `core_common`'s re-export shim: the shim's `show` clause cannot carry the Freezed-generated `$AppFailureCopyWith`, and the resulting breakage is invisible to `flutter analyze` (§ 21).
     - `core_common → domain_core` — `ErrorHandler` produces `AppFailure`, which now lives in Domain.
   - If a core package needs a fallback widget, **define it inside that core package**. Do not borrow one from `core_ui_kit`. Reference: `provider_state_management` ships `DefaultLoadingWidget` / `DefaultEmptyWidget` in `lib/src/base_view/default_state_widgets.dart` for exactly this reason.
   - Dependencies flow **one way**: `core_ui_kit → provider_state_management` is correct; the reverse is a genuine cycle **inside** the core ring and is forbidden. (This edge is why the two `Default*Widget` fallbacks exist: `provider_state_management` used to reach into the widget library for them, which closed the loop.)
1. **Domain Layer must be Pure Dart** — enforced by the package graph, not just by review:
   - Do not import: `package:flutter/...`, `package:dio/...`, `package:retrofit/...`, or any UI/Network framework library.
   - **`domain_core` has ZERO workspace dependencies** and no `flutter` entry in `dependencies`. `domain_auth` / `domain_language` depend only on `domain_core`. Keep it that way.
   - **ABSOLUTELY FORBIDDEN** for a domain package to depend on `core_common` (or any `core_*` package). That edge used to exist and was removed: `core_common` imports `flutter/material.dart`, so depending on it dragged Flutter into Domain. `AppFailure` was moved into `domain_core` precisely to break that edge — it is part of the `Result` contract and belongs at the centre.
   - Allowed to import: `dart:*`, `domain_core` (`Result<T>`, `AppFailure`, `BaseEntity<T>`, `PaginatedEntity<T>`), `freezed_annotation`, `json_annotation`, `injectable`, `get_it`.
   - Domain-owned constants live in that package's own `utils/` (§ 16) — e.g. `domain_core`'s `DomainConstants`. Never reach into `core_common` for them.
   - If UI-related classes (such as colors or image assets) are needed, translate them into primitive data types or enums declared **inside the domain package**.
   - Verify:
     ```bash
     grep -rn "package:flutter" packages/domain/*/lib   # must print nothing
     ```
2. **Data Layer**:
   - Data source directories must be named `data_sources/` (snake_case), NOT `datasources/`.
   - Categorize into `data_sources/remote/` (Retrofit) and `data_sources/local/` (Storage/DB).
   - RepositoryImpl classes should inherit from `BaseRepository` in `data_core` and use the helper methods `execute()` or `executeSync()` wrappers to automatically handle error conversion. API calls are no longer strictly forced to return `BaseEntity`, manual unwrapping/mapping via `mapper` parameter is advised if the payload is wrapped.
   - **DataSources return Models, never Entities**, and never leak a generated type. A Drift row class must be converted at the package boundary — see `CacheEntryModel.fromRow` in `packages/data/core/lib/src/models/cache_entry_model.dart`; `ICacheEntryLocalDataSource` speaks only in `CacheEntryModel`.
   - Error handling must use `ErrorHandler.handleError(e)` from `core_common`. **DO NOT** invent an `AppFailure.fromException()` — no such constructor exists.
   - ⚠️ Known gap: `ErrorHandler` has no `FirebaseException` / `FirebaseAuthException` / `PlatformException` branch, so every Firebase error collapses to `ServerFailure(code: 9999)` (`"Unknown error occurred"` in release). Add a branch before relying on Firebase error codes in UI.
3. **Feature Module Boundary**:
   - Feature package A must never import any file from Feature package B.
   - **One feature = one bounded UI concern.** Unrelated tabs/screens (e.g. Home vs Settings) MUST live in separate feature packages. `feature_dashboard` only provides shell chrome (`DashboardRouteModule`); tab routes register via `IDashboardTabModule` and are assembled by `AppRouter`.
   - **Forbidden:** editing `app_router.dart` to hardcode a new feature’s `$…Route` / `StatefulShellBranch`. Register `IFeatureRouteModule` or `IDashboardTabModule` in the feature DI instead. See [`docs/en/guides/04_routing.md`](../docs/en/guides/04_routing.md) § Dashboard for misuse rules.
   - Cross-feature communication (e.g., navigating from Feature A to Feature B) must be done through navigation interfaces (`Navigator`) defined in `core_di`.
   - **Navigation Rules (Decentralized Navigators)**:
     - Navigator interfaces (`AuthNavigator`, `HomeNavigator`, etc.) defined in `core_di` must only contain navigation methods to routes owned by that specific feature.
     - Implementation classes (`NavigatorImpl`) must reside locally under the `routing/` directory of the feature package that owns those routes (e.g., `AuthNavigatorImpl` resides in `feature_auth`).
     - **ABSOLUTELY FORBIDDEN** to hardcode route paths or call `GoRouter.of(context).go(...)` directly to navigate to another feature. Instead, fetch the target feature's Navigator from GetIt (e.g., `getIt<HomeNavigator>().toHome(context)`).
     - **BuildContext MUST be passed directly** as a parameter from the UI caller (Widget/Page/View). Minimize or avoid utilizing context from `NavigatorKeys` or `appRouter.currentContext` to prevent Widget Lifecycle issues.
   - Shared utilities and UI widgets used only across features should be placed in `packages/core/ui_kit`.
   - **Cross-Feature UI Actions (Action Handlers)**:
     - When Feature A must trigger a UI-bound action owned by Feature B (e.g., logout) without importing Feature B, declare an `I*ActionHandler` interface in `packages/core/di/lib/src/actions/`.
     - Implement `*ActionHandlerImpl` inside the owning feature under `handlers/` and register with `@Injectable(as: I*ActionHandler)` (or `@LazySingleton(as: ...)` when appropriate).
     - Consumers call `getIt<I*ActionHandler>().method(context)`. Do **not** use Action Handlers for pure route navigation (use Navigators) or Domain-only logic (use UseCases).
4. **UI vs. Business State Workflows (Bypassing Domain)**:
   - **Pure UI State (e.g., ThemeMode, Locale)**: Cannot pass through the Domain layer because Domain must be Pure Dart (cannot import `flutter/material.dart`). UI Providers bypass Domain and persist via a DI storage Interface implemented in the App Shell:
     - **Theme**: `ThemeProvider` → `IThemeStorage` → `ThemeStorageImpl` (`app/lib/di/theme_storage_impl.dart`), which owns its own `StorageValue<ThemeMode>` keyed by `ThemeStorageKeys.THEME_MODE` (`app/lib/di/utils/theme_storage_keys.dart`)
     - **Language**: `LanguageProvider` → `ILanguageStorage` → `LanguageStorageImpl` (`app/lib/di/language_storage_impl.dart`), which owns its own `StorageValue<String>` keyed by `LanguageStorageKeys.LOCALE` (`app/lib/di/utils/language_storage_keys.dart`)
   - **`domain_language`**: Retained for API/business locale needs if required later; the Settings UI currently uses `LanguageProvider`, not `SetLanguageUseCase`.

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
         create: (context) => getIt<OnboardingProvider>(),
         child: const OnboardingPage(),
       );
     }

     // Using BLoC in Route Module:
     @override
     Widget build(BuildContext context, GoRouterState state) {
       return BlocProvider(
         create: (context) => getIt<ProfileBloc>(),
         child: const ProfilePage(),
       );
     }
     ```
   - **ABSOLUTELY FORBIDDEN** to wrap `BlocProvider` or `ChangeNotifierProvider` inside the `Page` widget's `build()` method if it is already provided at the Route level. Double wrapping creates duplicate controller instances, causing state desynchronization bugs and memory leaks.
2. **Global Controllers**:
   - Allowed to use `@lazySingleton` or `@singleton` for application-wide global controllers (e.g., `ThemeProvider`, `LanguageProvider`, `AppProvider`, `AuthProvider`, `DeeplinkProvider`).
3. Constructor Injection:
   - Do not call `getIt<T>()` inside business logic (ViewModels, Repositories, UseCases).
   - Pass all dependencies through the constructor to enable easy unit testing and mocking.
4. **Micro-package DI & Relative Imports**:
   - When declaring `@InjectableInit.microPackage()` with `ignoreUnregisteredTypes`, always import the ignored type using a **relative import** from the package's public API barrel file (e.g. `import '../domain_auth.dart';` inside `lib/di/module.dart`) instead of a `package:` import. This ensures compatibility with the `prefer_relative_imports` lint rule.

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
| **Repository Interface** | `_repository.dart` | Prefix `I` | `IAuthRepository` |
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
   - Avoid using comments like `// ignore_for_file: avoid_print` unless absolutely necessary.
3. **FVM is optional — never hardcode the `fvm` prefix**:
   - The repo pins a version in `.fvmrc`, but that file does **not** guarantee `fvm` is installed on the current machine. Blindly prefixing `fvm` fails on a plain Flutter install.
   - Write commands **without** the prefix (`flutter pub get`, `dart run build_runner build -d --workspace`). Add `fvm ` yourself only if your own machine uses it.
   - A tool that shells out to the toolchain **MUST detect FVM at runtime**, not assume it. Reference implementation — `CommonHelpers.useFvm` in `tools/module_generator/src/common_helpers.dart` requires **both** a config file (`.fvmrc` or `.fvm/fvm_config.json`) **and** a successful `fvm --version`, then routes through `runDart()` / `runFlutter()`.
4. **No PowerShell scripts** (`.ps1`) — Windows execution policy blocks them. Prefer a cross-platform `.dart` script (as `tools/workspace_setup/configure.dart` does); use `.sh`/`.bat` pairs only when a Dart script cannot do the job.

---

## 📜 6. Updating Barrel Files

- When creating, renaming, or deleting Dart files under `lib/` in any sub-package, run the barrel generator script to update exports:
  ```bash
  dart tools/barrel_generator/generate.dart packages/<layer>/<package_name>/lib
  ```
- ⚠️ **The generator DELETES every hand-written `export '...';` line in a barrel.** It strips all lines starting with `export '` and re-emits its own sorted list (`tools/barrel_generator/generate.dart`, the `line.trim().startsWith("export '")` filter).
  - **ABSOLUTELY FORBIDDEN** to hand-add an `export` to a barrel file — it will silently vanish on the next run.
  - Need a deliberate re-export? Put it in a **normal source file**, which the generator then picks up. Reference: `packages/core/common/lib/src/error/failures.dart` is a plain file whose whole body is the `AppFailure` compatibility re-export.
- The generator also skips `part of` files and generated output (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*_test.dart`). Run it **before** `build_runner`, one package at a time.

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
   - Create a neutral communication interface containing pure Dart `Stream` or `ValueListenable` properties, register it in DI, and have Feature B retrieve and listen to it (`getIt<INeutralStreamService>()`).
3. **Dual Registration for Owner Feature**:
   - The feature that owns and writes to the neutral stream MUST register its implementation as a concrete `@singleton` (e.g., `AuthStatusStreamImpl`).
   - Use a DI `@module` to bind the pure interface to the concrete instance (e.g., `IAuthStatusStream bind(AuthStatusStreamImpl impl) => impl;`).
   - This allows the owner feature to inject the concrete class directly via constructor (avoiding manual `getIt` lookups and type casting `as`), while other features remain decoupled by only listening to the Interface.
4. **Domain Entity Sharing via DI Hub**:
   - When a Neutral Stream needs to expose a strictly typed Domain Entity (e.g., `UserEntity`), the interface in `core_di` MUST explicitly use that type without falling back to generics (`<T>`).
   - Consequently, `core_di` is **explicitly permitted** to declare dependencies on `domain_*` micro-packages (e.g., `domain_auth`) in its `pubspec.yaml` to access these entity models. 
   - This ensures UI-state-sharing streams remain centrally located in the DI Hub without falsely treating them as domain UseCases.

---

## 🚀 9. Creating New Modules (Quick Reference)

```bash
# Feature (Provider):
dart tools/module_generator/generate.dart 1 <name> "" 1

# Feature (BLoC):
dart tools/module_generator/generate.dart 1 <name> "" 2

# Domain micro-package:
dart tools/module_generator/generate.dart 2 <name>

# Data micro-package:
dart tools/module_generator/generate.dart 3 <name>

# Core package:
dart tools/module_generator/generate.dart 4 <name>
```

---

## 🔍 10. Deprecation Handling & Deep Research

- When encountering any `info` or `warning` from `flutter analyze` regarding deprecated members/APIs, AI Agents **MUST perform deep research** to find the correct, up-to-date migration path before writing code.
- Ignoring deprecations or applying temporary quick-fixes is **ABSOLUTELY FORBIDDEN**.

---

## 🌍 11. Strict Localization (Translation) Enforcement

- If the app supports localization, **ALL user-facing text** (including hardcoded UI text, toast messages, and server error messages) **MUST be translated** using the app's standard localization infrastructure.
- **Feature-Scoped Translations**: Each feature MUST define its own translation `.arb` files inside its `assets/language/` directory (e.g., `packages/features/auth/assets/language/en.arb`).
- **Global Assets & Shared UI Only**: The `core_base_ui` package is strictly reserved ONLY for globally shared assets and global fallback strings. Purely reusable UI packages (like `core_ui_kit`) **MUST NOT** define their own translation `.arb` files. They must use translations exported from `core_base_ui`.
- When calling translations, use the feature-specific extension (e.g., `context.l10nAuth.translationKey`) rather than a global delegate.
- Hardcoding raw strings in UI components is **ABSOLUTELY FORBIDDEN**.
- **Decentralized Delegation**: Feature packages MUST NOT modify `app/lib/presentation/root_app.dart` to add their LocalizationsDelegates. Instead, they must provide an implementation of `IFeatureLocalization` and register it in their local DI (`@LazySingleton(as: IFeatureLocalization)`). The root app dynamically collects all delegates using `getIt.getAll<IFeatureLocalization>()`. The same pattern applies to routing: register `IFeatureRouteModule` (top-level routes), `IDashboardTabModule` (shell tabs + bottom nav), and optionally `IAppEntryLocation` (cold start). The app shell uses `getAllOrEmpty` / `getItOrNull` with empty/`SizedBox` fallbacks so removing a feature package does not crash the host.

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
     // Include `_state.dart` when using a custom Freezed UI state (omit if using BlocViewState<T>).
     part '_state.dart';
     part '_bloc.freezed.dart';
     ```
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

- **Strict usage of `flutter_screenutil_plus`**: All UI sizing, including but not limited to width, height, padding, margins, font sizes, and border radii, **MUST** be scaled using the `flutter_screenutil_plus` extension methods.
- Specifically, you must use `.w` for widths, `.h` for heights, `.sp` for font sizes, and `.r` for border radii.
- **ABSOLUTELY FORBIDDEN** to use raw double values (e.g., `SizedBox(height: 24)`, `fontSize: 16`, `padding: EdgeInsets.all(16)`) in UI layout constraints. Always scale them (e.g., `SizedBox(height: 24.h)`, `fontSize: 16.sp`, `padding: EdgeInsets.all(16.r)`).
- **UI-Agnostic Reusable Components**: Reusable atomic UI components (e.g., those in `core_ui_kit` like `CustomButton`, `CustomCacheNetworkImage`) **MUST** remain strictly UI-agnostic. They should accept raw, unscaled numerical values in their constructors and **MUST NOT** scale incoming parameter values internally (e.g., no `widget.width.w` or `widget.radius.r`). It is the caller's responsibility to apply `flutter_screenutil_plus` to arguments *before* passing them to these reusable widgets.

---

## 🖼️ 15. Feature-Scoped Assets & Resources

- **Decentralized Assets**: All UI assets (images, svgs, animations, Lottie) that are specific to a feature MUST be placed in that feature's package (e.g., `packages/features/auth/assets/images`).
- **Global Assets Only**: The `core_base_ui` package is strictly reserved ONLY for globally shared assets (like the app logo, global icons, or global background patterns) and global fallback strings.
- **Do not** dump all images into `core_base_ui` as it creates massive coupling. Feature modules should be standalone and encapsulate their own assets.

---

## 🗂️ 16. Mandatory `utils/` Folder for Package Constants

- **EVERY package, at EVERY layer** (core / domain / data / features / app shell), MUST keep its own constants inside a `utils/` folder within that package — e.g. `packages/features/auth/lib/src/utils/`, `app/lib/di/utils/`.
- **ABSOLUTELY FORBIDDEN** to create a shared cross-domain constants file that many packages import. A constant belongs to exactly one owner.
- `core_common/lib/src/utils/` is reserved for constants that are **genuinely global** — today only `ApiStatusConstants` (HTTP status codes) and `EnvConstants` (`String.fromEnvironment` values). Feature/domain-owned values (storage keys, route paths, API endpoints) MUST NOT live there.
- **Precedent — constants that were evicted from `core_common`,** so nobody re-adds them:
  | Was | Now | Why |
  | :--- | :--- | :--- |
  | `StorageKeyConstants` | deleted → per-owner `utils/` keys (§ 17) | held every domain's storage keys |
  | `ApiConstants` | `AuthApiConstants` in `packages/data/auth/lib/src/utils/` | held only auth endpoints |
  | `NotificationConstants` | `packages/core/notifications/lib/src/utils/` | belongs to the notifications package |
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
4. Choose the backend explicitly: `StorageType.secure` for tokens/PII, `StorageType.pref` for settings and flags. Use the `reviver` callback for Enums, JSON objects, and Lists.

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

- `configureDependencies()` initializes modules **in the order declared** in `app/lib/di/injection.dart` (`externalPackageModulesBefore` → app-local registrations → `externalPackageModulesAfter`).
- **ABSOLUTELY FORBIDDEN** for an eager `@Singleton` to depend on a type registered by a module that runs **later** — GetIt throws `"<Type> is not registered"` during boot.
- Use `@LazySingleton` whenever a dependency comes from a later module. Reference: `NetworkConfigImpl` is `@LazySingleton(as: NetworkConfig)` because it injects `AuthLocalDataSource` from `data_auth`, whose module initializes after the app-local block. Its only consumer (`ApiClient`) is itself lazy, so deferring construction is safe.
- `flutter analyze` **cannot** detect this class of bug — it only appears at runtime. After changing any DI annotation or constructor, **verify the generated `app/lib/di/injection.config.dart`**: confirm each eager registration's dependencies appear earlier in `init()`.
- `@PostConstruct(preResolve: true)` on a `@lazySingleton` is awaited during module init and then re-registered as a plain sync lazy singleton, so downstream `gh<T>()` sync lookups are safe.

---

## 🔗 19. Explicit Dependency Declaration

- This monorepo uses **Pub Workspaces**, so all packages share a single `package_config.json`. A package that imports another package **without declaring it** still compiles locally — the breakage only surfaces when the package is extracted or published.
- **MANDATORY**: every `package:` import used under `lib/` must have a matching entry in that package's `pubspec.yaml`.
- Production-code imports belong in `dependencies`. **ABSOLUTELY FORBIDDEN** to satisfy a production import from `dev_dependencies`.
- Remove dependencies that are no longer used — stale entries create phantom coupling between layers.
- Verify before every PR:
  ```bash
  dart tools/unused_checker/check_unused_packages.dart
  ```

---

## 🧯 20. GetIt Resolution Traps

Three GetIt behaviours have each caused a real, silent production bug in this repo. Learn them before touching DI.

1. **`getAll<T>()` THROWS when `T` is unregistered — `getAllOrEmpty<T>()` does not.**
   - Both live in `packages/core/common/lib/di/module.dart`. `getAllOrEmpty` guards with `getIt.isRegistered<T>()` and returns `const []`.
   - **MANDATORY**: every optional multi-instance contribution (`IFeatureRouteModule`, `IDashboardTabModule`, `IFeatureLocalization`, `IAppTreeWrapper`, `IDatabaseMigration`) MUST be collected with `getAllOrEmpty`.
   - Real bug: `app_material_wrapper.dart` used `getIt.getAll<IFeatureLocalization>()`; with no feature contributing one, `MaterialApp` construction threw and the app died at boot.
   - Same rule for single instances: `getItOrNull<T>()` + a fallback, never bare `getIt<T>()`, whenever `T` is owned by a removable feature.

2. **GetIt does NOT resolve supertypes.** Registering `Impl as InterfaceA` leaves `getIt<InterfaceB>()` unresolvable even when `InterfaceA implements InterfaceB`.
   - Real bug: `NetworkConfigImpl` was registered only `as NetworkConfig`, so `getItOrNull<SslPinningConfig>()` in `AppInitializer._setupHttpOverrides` returned `null` and **certificate pinning was silently skipped on staging and production**.
   - Fix pattern — bind the second type through a `@module`, typed so the compiler checks the upcast (no `as`):
     ```dart
     // app/lib/di/network_binding_module.dart
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
- **Rule**: a package that needs relational storage declares **its own database** beside its own tables and DAO. Reference: `packages/data/core/lib/src/database/` holds `CacheDatabase`, `tables/cache_entries_table.dart` and `dao/cache_entries_dao.dart`.
- `core_database` supplies: `IDatabaseHandle<TDb extends GeneratedDatabase>` (hand a package only the accessor it asks for, plus `transaction`), `IDatabaseMigration` (a package contributes its own upgrade/downgrade steps), `DatabaseMigrationRunner`, `DatabaseConnectionFactory`, `DriftDatabaseOpener`.
- **Accepted trade-off**: SQL cannot join across package boundaries. That is deliberate — crossing a bounded context belongs at the repository layer, not in a query.
- **Removability**: deleting a package deletes its database with it. A database must open normally when **no** `IDatabaseMigration` is registered.
- Drift limits worth knowing: there is **no `onDowngrade` callback** (downgrade is routed through `onUpgrade` by comparing `from`/`to`), and **no runtime table registration** — a package cannot add a table to another package's database.

---

## 🔌 22. Any Feature Must Be Removable

Deleting any `packages/features/*` package must leave the app compiling and booting.

- **The app shell's only intentional hard reference to features is `app/lib/di/injection.dart`** — as the composition root it must name what it composes. Every *other* shell file resolves features through `core_di` contracts.
- To drop a feature (order matters — see the doc comment on `_featureModules`):
  1. its `ExternalModule(...)` entry and matching import in `app/lib/di/injection.dart`;
  2. its `feature_x:` entry in `app/pubspec.yaml`;
  3. its path in the root `pubspec.yaml` `workspace:` list;
  4. `flutter pub get` + `dart run build_runner build -d --workspace`.
- **A type import defeats `getItOrNull`.** Guarding the *lookup* is useless if the file still imports the feature for the *type* — it fails at compile time. When the shell needs something a feature owns, declare a contract in `core_di` and have the feature implement + register it:

  | Contract (`core_di`) | Replaces the shell's direct use of |
  | :--- | :--- |
  | `IAppSplashScreen` | `SplashPage` from `feature_splash` in `main.dart` |
  | `IAuthRefreshListenable` (`implements Listenable`) | `AuthProvider` as GoRouter's `refreshListenable` |
  | `IAuthSessionState` + `AuthSessionFailure` | `AuthProvider` / `AuthErrorState` / `context.l10nAuth` in `NavigatorWrapperWidget` |
  | `IAppTreeWrapper` | `ChangeNotifierProvider<AuthProvider>` in `app_material_wrapper.dart` |

- Contracts in `core_di` MUST stay state-management agnostic: `IAppTreeWrapper.wrap()` returns a plain `Widget`, so a Provider feature can return `ChangeNotifierProvider` and a BLoC feature `BlocProvider` without either forcing its package on the other.
- Prefer a plain Dart 3 `sealed class` over Freezed for `core_di` contracts (see `AuthSessionFailure`) — `core_di` runs no codegen, and adding a `part` would make every consumer wait on `build_runner`.
- The shared widget library is **not** a removable feature: it lives at `packages/core/ui_kit` as `core_ui_kit`, so `packages/features/` contains only genuinely removable product surfaces.

---

## 🔬 23. `flutter analyze` Cannot See Generated Code

`analysis_options.yaml` excludes `**.freezed.dart`, `**.g.dart`, `**.mocks.dart`, `**.config.dart`, `**.module.dart` from analysis.

- **A clean `flutter analyze` does NOT mean the app compiles.** Errors inside generated files are invisible to it and surface only in a real build.
- Real incident: moving `AppFailure` from `core_common` to `domain_core` broke `bloc_view_state.freezed.dart`, which needs the generated `$AppFailureCopyWith`. The `core_common` re-export shim lists concrete failure types in its `show` clause and cannot carry the generated companion. `flutter analyze` reported **No issues found**; the APK build failed with `Type '$AppFailureCopyWith' not found`. Fix was to depend on `domain_core` directly.
- **MANDATORY verification order** after any change to DI annotations, package dependencies, or the location of a Freezed/JSON type:
  ```bash
  dart run build_runner build -d --workspace
  flutter analyze
  cd packages/<layer>/<pkg> && flutter test      # per package
  cd app && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
  ```
  The build step is **not optional** — it is the only gate that sees generated code.
- Corollary: when a type consumed by generated code moves package, **import its new home directly**. Do not rely on a `show`-limited re-export.
