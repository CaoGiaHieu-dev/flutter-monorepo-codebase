# 🤖 Codebase Rules & Developer Agent Guidelines (AGENTS.md)

This file contains the rules for architectural design, naming conventions, dependency injection (DI) management, routing, and coding standards for this Monorepo template. Every AI Agent (Gemini, Copilot, Cursor, etc.) working on this codebase **MUST read and strictly comply 100%** with the rules below.

---

## 🏗️ 1. Monorepo Directory Layout

This monorepo uses **Pub Workspaces** and is divided into independent physical layers under the `packages/` directory:

- **`app/`**: Host App Shell. Contains startup (`main.dart`), **dynamic** router assembly (`app_router.dart` collects `IFeatureRouteModule` / `IDashboardTabModule` / `DashboardRouteModule` via DI — do not hardcode feature `$…Route` lists), and centralized DI (`injection.dart`).
- **`packages/core/`**: Infrastructure and utility packages shared across the project:
  - `core_common`: Pure Dart constants (`StorageKeyConstants`, `ApiConstants`), enums, mixins, `AppFailure`, and `ErrorHandler`.
  - `core_di`: Navigation keys, routing contribution contracts (`IFeatureRouteModule`, `IDashboardTabModule`, `IAppEntryLocation`, `DashboardRouteModule`), and cross-package communication interfaces.
  - `core_base_ui`: Design system resources (typography, color palette, icons, assets, and L10n translations). **Contains zero Flutter widgets.**
  - `core_network`: Pre-configured HTTP client (Dio, Retrofit) with interceptors (auth, retry, logging).
  - `core_storage`: Reactive cache with two-tier storage (Secure Storage + SharedPreferences) and `StorageValuePresets`.
  - `core_database`: Drift/SQLite relational database on a background isolate.
  - `core_notifications`: Push notification management module.
  - `provider_state_management`: Provider state management base classes (`BaseProvider`, `executeOperation`, `BaseViewWidget`).
  - `bloc_state_management`: BLoC state management base classes (`BaseBloc`, `ViewState`; `BaseCubit` only when events are unnecessary).
- **`packages/domain/*` (Micro-packages)**: Business logic core. **MUST be pure Dart (100% decoupled from Flutter UI, Dio, Retrofit, or any platform-specific dependencies)**. Current micro-packages:
  - `domain_core`: Defines `Result<T>`, `BaseEntity<T>`, and shared primitive types.
  - `domain_auth`: Entities, use cases, and repository interfaces for authentication.
  - `domain_language`: Entities and use cases for multi-language localization.
- **`packages/data/*` (Micro-packages)**: Data access layer (remotes, local caching, models/DTOs). Depends on `domain` packages. Current micro-packages:
  - `data_core`: `IBaseRepository` with `execute()` and `executeSync()` wrappers to automatically handle error conversion.
  - `data_auth`: Models/DTOs, Remote DataSources (Retrofit), and RepositoryImpl for authentication.
  - `data_language`: RepositoryImpl for multi-language localization.
- **`packages/features/`**: Independent functional modules:
  - `feature_shared`: Unified library for all reusable widgets (both atomic components like buttons/inputs and complex business cards/dialogs).
  - Feature packages (e.g., `feature_onboarding`, `feature_auth`, `feature_dashboard`, `feature_home`, `feature_settings`, `feature_splash`):
    - Can only depend on `domain_*`, `core_di`, `core_common`, `core_base_ui`, `provider_state_management` or `bloc_state_management`, and `feature_shared`.
    - **ABSOLUTELY FORBIDDEN** to directly depend on the `data` layer or other feature packages (except `feature_shared`).
    - **One bounded UI concern per feature package**: Do not co-locate unrelated product surfaces in the same feature (e.g. Home tab + Settings tab). `AppRouter` + `IDashboardTabModule` assemble shell branches; `feature_dashboard` supplies **chrome only** (`DashboardRouteModule`), not tab pages. Sample split: `feature_home` vs `feature_settings`.

---

## 🧱 2. Strict Layer Isolation

1. **Domain Layer must be Pure Dart**:
   - Do not import: `package:flutter/...`, `package:dio/...`, `package:retrofit/...`, or any UI/Network framework library.
   - Allowed to import: `core_common` (constants, enums, `AppFailure`), `domain_core` (`Result<T>`, `BaseEntity<T>`), `freezed_annotation`, `json_annotation`, `injectable`.
   - If UI-related classes (such as colors or image assets) are needed, translate them into primitive data types or enums defined in `core_common`.
2. **Data Layer**:
   - Data source directories must be named `data_sources/` (snake_case), NOT `datasources/`.
   - Categorize into `data_sources/remote/` (Retrofit) and `data_sources/local/` (Storage/DB).
   - RepositoryImpl classes should inherit from `BaseRepository` in `data_core` and use the helper methods `execute()` or `executeSync()` wrappers to automatically handle error conversion. API calls are no longer strictly forced to return `BaseEntity`, manual unwrapping/mapping via `mapper` parameter is advised if the payload is wrapped.
   - Error handling must use `ErrorHandler.handleError(e)` from `core_common`. **DO NOT** use `AppFailure.fromException()`.
3. **Feature Module Boundary**:
   - Feature package A must never import any file from Feature package B.
   - **One feature = one bounded UI concern.** Unrelated tabs/screens (e.g. Home vs Settings) MUST live in separate feature packages. `feature_dashboard` only provides shell chrome (`DashboardRouteModule`); tab routes register via `IDashboardTabModule` and are assembled by `AppRouter`.
   - **Forbidden:** editing `app_router.dart` to hardcode a new feature’s `$…Route` / `StatefulShellBranch`. Register `IFeatureRouteModule` or `IDashboardTabModule` in the feature DI instead. See `docs/en/08_routing.md` § Dashboard for misuse rules.
   - Cross-feature communication (e.g., navigating from Feature A to Feature B) must be done through navigation interfaces (`Navigator`) defined in `core_di`.
   - **Navigation Rules (Decentralized Navigators)**:
     - Navigator interfaces (`AuthNavigator`, `HomeNavigator`, etc.) defined in `core_di` must only contain navigation methods to routes owned by that specific feature.
     - Implementation classes (`NavigatorImpl`) must reside locally under the `routing/` directory of the feature package that owns those routes (e.g., `AuthNavigatorImpl` resides in `feature_auth`).
     - **ABSOLUTELY FORBIDDEN** to hardcode route paths or call `GoRouter.of(context).go(...)` directly to navigate to another feature. Instead, fetch the target feature's Navigator from GetIt (e.g., `getIt<HomeNavigator>().toHome(context)`).
     - **BuildContext MUST be passed directly** as a parameter from the UI caller (Widget/Page/View). Minimize or avoid utilizing context from `NavigatorKeys` or `appRouter.currentContext` to prevent Widget Lifecycle issues.
   - Shared utilities and UI widgets used only across features should be placed in `packages/features/shared`.
   - **Cross-Feature UI Actions (Action Handlers)**:
     - When Feature A must trigger a UI-bound action owned by Feature B (e.g., logout) without importing Feature B, declare an `I*ActionHandler` interface in `packages/core/di/lib/src/actions/`.
     - Implement `*ActionHandlerImpl` inside the owning feature under `handlers/` and register with `@Injectable(as: I*ActionHandler)` (or `@LazySingleton(as: ...)` when appropriate).
     - Consumers call `getIt<I*ActionHandler>().method(context)`. Do **not** use Action Handlers for pure route navigation (use Navigators) or Domain-only logic (use UseCases).
4. **UI vs. Business State Workflows (Bypassing Domain)**:
   - **Pure UI State (e.g., ThemeMode, Locale)**: Cannot pass through the Domain layer because Domain must be Pure Dart (cannot import `flutter/material.dart`). UI Providers bypass Domain and persist via a DI storage Interface implemented in the App Shell:
     - **Theme**: `ThemeProvider` → `IThemeStorage` → `ThemeStorageImpl` (`app/lib/di/theme_storage_impl.dart`) → `StorageValuePresets.themeMode`
     - **Language**: `LanguageProvider` → `ILanguageStorage` → `LanguageStorageImpl` (`app/lib/di/language_storage_impl.dart`) → `StorageValuePresets.locale`
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
3. **FVM Usage**: Always prefix flutter/dart CLI operations with `fvm` (e.g. `flutter run`, `dart run build_runner`).

---

## 📜 6. Updating Barrel Files

- When creating, renaming, or deleting Dart files under `lib/` in any sub-package, run the barrel generator script to update exports:
  ```bash
  dart tools/barrel_generator/generate.dart packages/<layer>/<package_name>/lib
  ```

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
- **Global Assets & Shared UI Only**: The `core_base_ui` package is strictly reserved ONLY for globally shared assets and global fallback strings. Purely reusable UI packages (like `feature_shared`) **MUST NOT** define their own translation `.arb` files. They must use translations exported from `core_base_ui`.
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
2. **UI State is flexible**: Prefer shared `ViewState<T>` for simple screens. **It is not mandatory** — complex features may define a custom Freezed UI state (`BaseBloc<Event, CustomState>`). When using a custom state, keep its Freezed variants in `_state.dart` via `part` / `part of` (same privacy rules as events).
3. **Part & Part Of Architecture**: So the BLoC can access private event (and custom state) subclasses without exporting them publicly, the BLoC file structure **MUST** use Dart `part` / `part of`:
   - The main BLoC file (`_bloc.dart`) declares:
     ```dart
     part '_event.dart';
     // Include `_state.dart` when using a custom Freezed UI state (omit if using ViewState<T>).
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
   // Example with ViewState — swap for CustomState when the screen needs richer UI state.
   HomeBloc(this._cryptoRepository) : super(const ViewState.initial()) {
     on<_HomeStarted>(_fetchInitialData);
     on<_HomeRefreshed>(_fetchInitialData);
     on<_HomeTradeUpdated>(_handleTradeUpdated);
   }

   Future<void> _fetchInitialData(
     HomeEvent event,
     Emitter<ViewState<HomeStateData>> emit,
   ) async {
     emit(const ViewState.loading());
     // ... async logic
   }
   ```

---

## 📏 14. Responsive UI & Screen Size Scaling

- **Strict usage of `flutter_screenutil`**: All UI sizing, including but not limited to width, height, padding, margins, font sizes, and border radii, **MUST** be scaled using the `flutter_screenutil` extension methods.
- Specifically, you must use `.w` for widths, `.h` for heights, `.sp` for font sizes, and `.r` for border radii.
- **ABSOLUTELY FORBIDDEN** to use raw double values (e.g., `SizedBox(height: 24)`, `fontSize: 16`, `padding: EdgeInsets.all(16)`) in UI layout constraints. Always scale them (e.g., `SizedBox(height: 24.h)`, `fontSize: 16.sp`, `padding: EdgeInsets.all(16.r)`).
- **UI-Agnostic Reusable Components**: Reusable atomic UI components (e.g., those in `feature_shared` like `CustomButton`, `CustomCacheNetworkImage`) **MUST** remain strictly UI-agnostic. They should accept raw, unscaled numerical values in their constructors and **MUST NOT** scale incoming parameter values internally (e.g., no `widget.width.w` or `widget.radius.r`). It is the caller's responsibility to apply `flutter_screenutil` to arguments *before* passing them to these reusable widgets.

---

## 🖼️ 15. Feature-Scoped Assets & Resources

- **Decentralized Assets**: All UI assets (images, svgs, animations, Lottie) that are specific to a feature MUST be placed in that feature's package (e.g., `packages/features/auth/assets/images`).
- **Global Assets Only**: The `core_base_ui` package is strictly reserved ONLY for globally shared assets (like the app logo, global icons, or global background patterns) and global fallback strings.
- **Do not** dump all images into `core_base_ui` as it creates massive coupling. Feature modules should be standalone and encapsulate their own assets.
