# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**IMPORTANT:** The authoritative, detailed rules live in [`.agents/AGENTS.md`](.agents/AGENTS.md). Read it before making changes — it covers layer isolation, DI lifecycle, naming conventions, routing, localization, Freezed/BLoC rules, and responsive UI rules in full. This file is a **comprehensive** summary plus commands.

---

## What This Repo Is

A Flutter **Pub Workspaces monorepo template** built on **Clean Architecture + SOLID + MVVM** with dual state management support (**Provider** and **BLoC**). The shipped feature/domain/data packages (auth, home, settings, onboarding, splash, dashboard, language) are **sample reference code** demonstrating the wiring — patterns to copy or delete, not production logic.

**Author:** CaoGiaHieu-dev. **Docs hub:** `docs/en/` (00–14) covers each layer in depth.

---

## Commands

FVM is used — prefix flutter/dart commands with `fvm` (e.g. `fvm flutter run`, `fvm dart run ...`).

```bash
# Install all workspace dependencies (single pubspec.lock at root)
flutter pub get

# Code generation across the whole workspace (injectable, freezed, retrofit, go_router_builder, l10n)
dart run build_runner build -d --workspace

# Run the app (flavors: dev / staging / prod)
flutter run -t app/lib/main.dart --flavor dev

# Static analysis
flutter analyze
dart fix --apply

# Full workspace setup (pub get + build_runner + l10n)
dart tools/workspace_setup/configure.dart
```

### Tests

Tests live per-package under `packages/<layer>/<pkg>/test/`. Run from the package directory:

```bash
cd packages/core/common
flutter test                           # all tests in the package
flutter test test/debounce_test.dart   # a single test file
```

### Repo Tooling (run from root)

```bash
# Generate a new module
# Syntax: dart tools/module_generator/generate.dart <type> <name> [<dir>] [<SM>] [<route>]
# <type>: 1=Feature, 2=Domain, 3=Data, 4=Core, 5=Custom
# <SM> (Feature only): 1=Provider, 2=BLoC, 3=None
# <route> (Feature only): 1=IFeatureRouteModule (stack), 2=IDashboardTabModule (bottom nav tab), 3=none
dart tools/module_generator/generate.dart 1 profile "" 1 1    # Feature+Provider+stack routes
dart tools/module_generator/generate.dart 1 chat "" 2 2       # Feature+BLoC+bottom nav tab
dart tools/module_generator/generate.dart 2 payment            # Domain micro-package
dart tools/module_generator/generate.dart 3 payment            # Data micro-package
dart tools/module_generator/generate.dart 4 analytics          # Core package

# Regenerate barrel files after adding/renaming/deleting files in a package's lib/
dart tools/barrel_generator/generate.dart packages/<layer>/<package_name>/lib

# Sync dependency versions from the version catalog (pubspec_dependencies.yaml)
dart tools/dependency_sync.dart          # --check for dry run (CI/pre-commit)

# Check for outdated packages on pub.dev
dart tools/check_outdated.dart

# Find unused files/assets/translations/packages
dart tools/unused_checker/check_script.dart             # all checks
dart tools/unused_checker/check_unused_assets.dart      # unused assets only
dart tools/unused_checker/check_unused_packages.dart    # unused packages only
dart tools/unused_checker/check_unused_translate.dart   # unused translation keys
dart tools/unused_checker/check_unused_file.dart        # orphaned files

# AI-powered code review (requires Gemini API key in code_review_config.json)
dart tools/code_review/code_review.dart --all
dart tools/code_review/code_review.dart --file lib/main.dart
dart tools/code_review/code_review.dart --changed
dart tools/code_review/code_review.dart --all --focus architecture,security

# Workspace setup scripts
# Windows:
.\tools\workspace_setup\configure.bat
# macOS/Linux:
./tools/workspace_setup/configure.sh

# Firebase multi-environment config
.\tools\firebase\firebase_config.bat

# Theme (splash screen + app icons)
.\tools\theme_generator\theme_setting.bat

# Android 15+ 16KB page size compliance check
.\tools\android_compliance\16kb_ckeck.bat   # Windows
./tools/android_compliance/16kb_ckeck.sh    # macOS/Linux
```

**Dependency versions** are centrally managed in `pubspec_dependencies.yaml` — never hardcode versions in a package's pubspec; edit the catalog and run `dart tools/dependency_sync.dart`.

---

## Architecture (Clean Architecture + Pub Workspaces Monorepo)

### Dependency Rule: Always Points Inward

```
Feature (UI) → Domain ← Data
     ↓              ↓
  core_di      core_network / core_storage / core_database
```

Each package is a workspace member listed in root `pubspec.yaml`.

### Layer Layout

| Layer | Path | Responsibility |
|:------|:-----|:---------------|
| **App Shell** | `app/` | Entrypoint, flavors, central DI assembly (`injection.dart`), **dynamic** router assembly (`app_router.dart` — collects route modules from DI, never hardcode feature routes) |
| **Core** | `packages/core/*` | Infrastructure shared across all layers |
| **Domain** | `packages/domain/*` | **Pure Dart** business logic — entities, use cases, repository interfaces |
| **Data** | `packages/data/*` | Repository implementations, DTOs/models, data sources (remote + local) |
| **Features** | `packages/features/*` | UI + state management — one bounded UI concern per package |

### Core Packages Detail

| Package | Purpose | Key Notes |
|:--------|:--------|:----------|
| `core_common` | Constants (`UPPER_SNAKE_CASE`), enums, `AppFailure`, `ErrorHandler`, mixins, utils | Host helpers: `getItOrNull`, `getAll`, `getAllOrEmpty` |
| `core_di` | DI Hub — Navigator interfaces, `I*ActionHandler`, routing contracts (`IFeatureRouteModule`, `IDashboardTabModule`, `IAppEntryLocation`, `DashboardRouteModule`), `NavigatorKeys`, agnostic stream interfaces | May import `domain_*` for entity types |
| `core_base_ui` | Design System — themes, color palette, typography, assets, L10n translations | **Contains zero Flutter widgets.** Feature-specific assets go in feature packages |
| `core_network` | `ApiClient` (Dio factory), Retrofit, interceptors (Auth/Retry/Logging), SSL pinning | `NetworkConfig` interface → `NetworkConfigImpl` in app shell |
| `core_storage` | Reactive `StorageValue<T>`, AES-256 encryption, dual-layer security (Keychain/KeyStore), `StorageValuePresets` | `@PostConstruct(preResolve: true)` hydrates at startup |
| `core_database` | Drift/SQLite on background isolate, tables, DAOs, migrations | `AppDatabase` via `@preResolve` DI. See sample `CacheEntries` / `CacheEntriesDao` |
| `core_notifications` | Push notification management | — |
| `provider_state_management` | `BaseProvider`, `executeOperation`, `ViewStateModel`, `ProviderStateListener`, `MultiProviderStateListener`, `BaseViewWidget`, `BaseProxyWidget` | See package README for full API |
| `bloc_state_management` | `BaseBloc`, `BaseCubit` (only when events unnecessary), `ViewState` (optional Freezed union) | See package README for full API |

### Domain Layer Rules (Pure Dart Mandate)

- **FORBIDDEN imports:** `package:flutter/...`, `package:dio/...`, `package:retrofit/...`
- **Allowed imports:** `dart:core`, `core_common`, `domain_core` (`Result<T>`, `BaseEntity<T>`), `freezed_annotation`, `json_annotation`, `injectable`
- Components: `entities/` (Freezed immutable), `params/`, `repositories/` (interfaces), `usecases/` (`@injectable`, returns `Result<T>`), `services/` (optional)
- `Result<T>` is a sealed Freezed class in `domain_core` with 4 variants: `Success<T>`, `Failure<T>` (containing `AppFailure`), `None<T>`, `Cancel<T>`

### Data Layer Rules

- Directory convention: `data_sources/remote/` (Retrofit) and `data_sources/local/` (Storage/DB). **NOT** `datasources/`
- Models use `freezed` + `json_serializable` with `.toEntity()` mapper
- `RepositoryImpl` extends `IBaseRepository` from `data_core` and uses `execute()` (async) / `executeSync()` (sync) wrappers
- Error handling: `ErrorHandler.handleError(e)` — **NEVER** use `AppFailure.fromException()`
- DataSources return Models only, never Entities. They let exceptions bubble up to RepositoryImpl

### Feature Layer Rules

- **Allowed deps:** `domain_*`, `core_di`, `core_common`, `core_base_ui`, `provider_state_management` or `bloc_state_management`, `feature_shared`
- **FORBIDDEN:** Direct deps on `data` layer or other feature packages (except `feature_shared`)
- **One bounded UI concern per package** — Home and Settings are separate packages; `feature_dashboard` is shell chrome only
- Feature-specific assets go in `<feature>/assets/` (images, SVGs, language ARBs)
- Structure: `pages/`, `widgets/`, `provider/` or `blocs/`, `routing/`, `handlers/` (optional), `di/module.dart`

---

## Dependency Injection (GetIt + Injectable)

### Micro-package DI Pattern

Each package declares `@InjectableInit.microPackage()` at `lib/di/module.dart`. The host app assembles all modules in `app/lib/di/injection.dart`:

```dart
@InjectableInit(
  externalPackageModulesBefore: [..._coreModules],  // core_common, network, notifications, storage, di
  externalPackageModulesAfter: [
    ..._uiModules,       // CoreBaseUiPackageModule (depends on app-local storage interfaces)
    ..._domainModules,   // domain_core, domain_auth, domain_language
    ..._dataModules,     // data_core, data_auth, data_language
    ..._featureModules,  // feature_auth, feature_dashboard, feature_home, etc.
    ..._otherModules,    // ProviderStateManagementPackageModule, BlocStateManagementPackageModule
  ],
)
```

### Registration Rules

| Scope | Annotation | Use For |
|:------|:-----------|:--------|
| **Feature controllers** | `@injectable` (factory) | ViewModels, Blocs — **NEVER** singleton (causes memory leaks) |
| **Global controllers** | `@lazySingleton` | `AuthProvider`, `ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider` |
| **Repository impls** | `@LazySingleton(as: IFooRepository)` or `@Injectable(as: IFooRepository)` | RepositoryImpls |
| **Third-party libs** | `@module` + `@preResolve` | `SharedPreferences`, `Dio`, `AppDatabase` |

### Critical DI Rules

1. **Constructor Injection only** — no `getIt<T>()` inside business logic (VMs, Repos, UseCases)
2. **CoreBaseUiPackageModule** must be in `externalPackageModulesAfter` (depends on app-local `ILanguageStorage`/`IThemeStorage`)
3. Never create monolithic `DomainPackageModule`/`DataPackageModule` — register each micro-package module separately
4. Categorize new modules into `_coreModules`, `_uiModules`, `_domainModules`, `_dataModules`, `_featureModules`, or `_otherModules`
5. When using `ignoreUnregisteredTypes`, use **relative imports** from the package's barrel file

### App-Shell Storage Adapters

`LanguageProvider`/`ThemeProvider` (in `core_base_ui`) inject `ILanguageStorage`/`IThemeStorage` from `core_di`. Concrete impls live in `app/lib/di/`:
- `language_storage_impl.dart` → `StorageValuePresets.locale`
- `theme_storage_impl.dart` → `StorageValuePresets.themeMode`

---

## Routing (go_router + go_router_builder, Decentralized)

### Routing Contracts (registered via DI, NOT hardcoded in app_router.dart)

| Contract | Purpose | Has Order? | Who Implements |
|:---------|:--------|:-----------|:---------------|
| `IFeatureRouteModule` | Stack/shell routes under app `ShellRoute` | **No** (path match) | auth, onboarding, … |
| `IDashboardTabModule` | One bottom-nav tab + one `StatefulShellBranch` | **Yes** (must match nav index) | home, settings, … |
| `IAppEntryLocation` | Cold-start `GoRouter.initialLocation` | n/a | usually onboarding |
| `DashboardRouteModule` | Dashboard **chrome** only (scaffold/bottom bar host) | n/a | `feature_dashboard` only |
| `IFeatureLocalization` | Feature ARB delegates | n/a | every feature with strings |

### Navigator Pattern

1. **Declare** Navigator interface in `core_di/lib/src/navigators/` (e.g., `AuthNavigator`)
2. **Implement** in the owning feature's `routing/` directory (e.g., `AuthNavigatorImpl` in `feature_auth`)
3. **Use** via `getIt<AuthNavigator>().toLogin(context)` — never hardcode paths or `GoRouter.of(context).go(...)`
4. **BuildContext MUST be passed directly** from UI caller — avoid using `NavigatorKeys.*.currentContext`

### Route-Level Instantiation (Critical)

Feature controllers are instantiated in the `build` method of `GoRouteDataCustom`:

```dart
// Provider:
@override
Widget build(BuildContext context, GoRouterState state) {
  return ChangeNotifierProvider(
    create: (context) => getIt<OnboardingProvider>(),
    child: const OnboardingPage(),
  );
}

// BLoC:
@override
Widget build(BuildContext context, GoRouterState state) {
  return BlocProvider(
    create: (context) => getIt<ProfileBloc>(),
    child: const ProfilePage(),
  );
}
```

> [!CAUTION]
> **NEVER DOUBLE-WRAP CONTROLLERS INSIDE PAGE WIDGETS!**
> Since `BlocProvider` or `ChangeNotifierProvider` is instantiated at the Route level in `*_route_module.dart`, the Page class (`*Page`) **MUST NOT** wrap itself in another `BlocProvider` or `ChangeNotifierProvider` inside its `build()` method. Double-wrapping creates duplicate controller instances, causing state desynchronization bugs and memory leaks.

### Dashboard Rules

**`feature_dashboard` is chrome only** — it implements `DashboardRouteModule` and builds the bottom bar from `getAllOrEmpty<IDashboardTabModule>()`.

**Dashboard MUST NOT:**
- Import `feature_home`/`feature_settings` or embed their pages
- Own `HomePage`/`SettingsPage` or business BLoCs for tabs
- Hardcode `BottomNavigationBarItem` list ignoring DI
- Register `IDashboardTabModule` itself for "fake" tabs

**Use `IDashboardTabModule`** ONLY when the screen is a primary bottom-nav destination needing a stable `StatefulShellBranch`.

### Key Router Components

- **`AppRouter`**: `@singleton`, uses `NavigatorKeys` (rootKey, appKey, authKey, homeKey)
- **`NavigatorWrapperWidget`**: App shell widget at `app/lib/presentation/widgets/` — handles auth boot redirect (via `endOfFrame.whenComplete`) and global auth side-effects
- **`UndefineRouteWidget`**: GoRouter's `errorPageBuilder` child — never use inline anonymous widgets
- **SplashPage**: Manually managed by `MainScope` (`AppMaterialWrapper`), NOT a GoRouter route

---

## Application Boot Lifecycle

1. `main.dart` → `runZonedGuarded` → `WidgetsFlutterBinding.ensureInitialized()`
2. `configureDependencies()` — initializes all DI modules (GetIt)
3. `MainScope.run()`:
   - Removes native splash (`FlutterNativeSplash.remove()`)
   - Launches `SplashPage` via `AppMaterialWrapper(home: splashScreen)` (no router)
   - Calls `AppInitializer.init()` (HttpOverrides, Logger, ScreenOrientation, SystemUIOverlay)
   - Updates widget to `RootApp` with `AppMaterialWrapper.router(...)` and GoRouter
4. `AppMaterialWrapper` wraps tree in `MultiProvider` with global singletons, `Consumer2<ThemeProvider, LanguageProvider>` for reactive theme/locale

---

## State Management

### Provider Pattern (`provider_state_management`)

- Inherit `BaseProvider<T>`
- Use `executeOperation(OperationConfig(...))` for automatic Loading/Error handling
- `ViewStateModel<T>` wraps UI state (sealed: `initial`/`loading`/`success`/`error`)
- `ProviderStateListener<P, T>` / `MultiProviderStateListener` for declarative side-effects
- `BaseViewWidget<P, T>` for exhaustive state rendering
- Custom `ErrorState` via polymorphic `ErrorStateRegistry`

### BLoC Pattern (`bloc_state_management`)

- **Prefer `BaseBloc`** — use `BaseCubit` only when events are unnecessary
- **`ViewState<T>`** is a shared optional helper (initial/loading/success/error) — not mandatory
- Complex features may define custom Freezed UI state (`BaseBloc<Event, CustomState>`)
- **Freezed Event Rules:**
  - All event subclasses must be **private** (`_HomeStarted`, not `HomeStarted`)
  - Use `part`/`part of` architecture: `_bloc.dart` ← `_event.dart`, `_state.dart`, `_bloc.freezed.dart`
- **Event handler signature must be async with `(event, emit)`** — never sync closure calling unawaited async

```dart
// CORRECT:
HomeBloc() : super(const ViewState.initial()) {
  on<_HomeStarted>(_fetchInitialData);
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

## Cross-Feature Communication (6 Models)

| # | Problem | Solution | Implementation |
|:--|:--------|:---------|:---------------|
| 1 | Business logic sharing | **Domain UseCase** | Both features inject same UseCase from `domain_*` |
| 2 | Infrastructure utils | **Core Service** | Import `core_storage`, `core_network`, etc. |
| 3 | Cross-feature state | **Agnostic Streams** | Neutral `Stream`/`ValueListenable` interface on `core_di`; dual-register owner impl |
| 4 | Pure UI prefs (theme/locale) | **Bypass Domain** | `ThemeProvider → IThemeStorage → StorageValuePresets` |
| 5 | Embed complex widgets | **Builder/Service Interface** | Interface in `core_di`, impl in owning feature, use via GetIt |
| 6 | Cross-feature UI actions | **Action Handler** | `I*ActionHandler` in `core_di/src/actions/`, `*ActionHandlerImpl` in owning feature's `handlers/` |

### Agnostic Streams (Dual Registration Pattern)

```dart
// 1. Interface in core_di:
abstract class IAuthStatusStream {
  Stream<UserEntity?> get authStatusStream;
}

// 2. Concrete @singleton in owning feature:
@singleton
class AuthStatusStreamImpl implements IAuthStatusStream { ... }

// 3. @module binding in owning feature DI:
@module
abstract class AuthModule {
  IAuthStatusStream bind(AuthStatusStreamImpl impl) => impl;
}

// 4. Consumer injects IAuthStatusStream (not AuthStatusStreamImpl)
```

---

## Naming Conventions (Strict)

| Component | File Suffix | Class Suffix | Example |
|:----------|:------------|:-------------|:--------|
| Main Screen | `_page.dart` / `_screen.dart` | `Page` / `Screen` | `LoginPage` |
| Sub Widget | `_widget.dart` / `_card.dart` | `Widget` / `Card` | `PrimaryButtonWidget` |
| UI Controller (Provider) | `_provider.dart` | `Provider` | `LoginProvider` |
| UI Controller (BLoC) | `_bloc.dart` | `Bloc` | `HomeProfileBloc` |
| UI Controller (Cubit) | `_cubit.dart` | `Cubit` | Only when events are unnecessary |
| Use Case | `_usecase.dart` | `UseCase` | `LoginUseCase` |
| Entity | `_entity.dart` | `Entity` | `UserEntity` |
| Repository Interface | `i_<name>_repository.dart` | Prefix `I` | `IAuthRepository` |
| Repository Impl | `_repository_impl.dart` | `RepositoryImpl` | `AuthRepositoryImpl` |
| API Response DTO | `_response.dart` / `_model.dart` | `Response` / `Model` | `UserResponse`, `UserModel` |
| API Request DTO | `_request.dart` | `Request` | `LoginRequest` |
| Navigator Impl | `_navigator_impl.dart` | `NavigatorImpl` | `AuthNavigatorImpl` |
| Action Handler Interface | `i_<name>_action_handler.dart` | Prefix `I` | `IAuthActionHandler` |
| Action Handler Impl | `_action_handler_impl.dart` | `ActionHandlerImpl` | `AuthActionHandlerImpl` |
| Dialog | `_dialog.dart` | `Dialog` | `ConfirmationDialog` |
| Bottom Sheet | `_bottom_sheet.dart` | `BottomSheet` | `HomeSettingsBottomSheet` |

- **Constants**: `UPPER_SNAKE_CASE` (e.g., `static const String BASE_URL = '...'`)
- **`I` prefix reserved for interfaces only** — never name an impl class with `I` prefix

---

## Localization (Decentralized)

- **ALL user-facing text MUST be translated** — hardcoded UI strings are FORBIDDEN
- **Feature-scoped:** Each feature owns `.arb` files in `assets/language/` and registers `IFeatureLocalization` via DI
- **Global strings only** in `core_base_ui`; `feature_shared` uses `core_base_ui` translations, does NOT define its own ARBs
- Access via feature extension: `context.l10nAuth.translationKey`
- Features **MUST NOT** edit `root_app.dart` to add delegates — root app collects via `getIt.getAll<IFeatureLocalization>()`

---

## Responsive UI (flutter_screenutil — Strict)

- **ALL sizing** (width, height, padding, margin, font size, border radius) MUST use ScreenUtil: `.w`, `.h`, `.sp`, `.r`
- **FORBIDDEN:** Raw doubles in layout (e.g., `SizedBox(height: 24)` → must be `SizedBox(height: 24.h)`)
- **Reusable widgets** in `feature_shared` take **unscaled** values — caller applies ScreenUtil

---

## Design System (core_base_ui)

- **Colors:** `context.colors.textPrimary`, `context.colors.surface`, `context.colors.primary` — auto-switch Light/Dark
- **Typography:** `AppTextStyles.bodyMediumStyle(context)`, auto-scaled with `.sp`
- **Spacing:** `AppSpacing.xs`, `.sm`, `.md`, `.lg`, `.xl` (scaled with `.w`)
- **Radius:** `AppRadius.sm`, `.md`, `.circular` (scaled with `.r`); `AppRadius.smRadius` for `BorderRadius` objects
- **Gradients/Shadows:** `AppGradients`, `AppShadows`
- **FORBIDDEN:** Hard-coding colors, font sizes, spacings, border radii directly in widgets

---

## Storage System (core_storage)

### Dual-Layer Security

1. **Layer 1 (Software):** AES-256-CBC with per-device Master Key + random IV per write
2. **Layer 2 (Hardware):** Apple Keychain / Android KeyStore via `flutter_secure_storage`

### Adding a New Storage Key

1. Declare key in `core_common/lib/src/constants/storage_key_constants.dart`
2. Define `late final` `StorageValue<T>` in `core_storage/lib/src/presets/storage_presets.dart`
3. Add to `initialize()` list for automatic hydration at startup
4. Use `reviver` callback for complex types (Enums, JSON objects, Lists)

### Usage

```dart
_storagePresets.isBioLocked.value = true;          // Write (auto-encrypted, async to disk)
final locked = _storagePresets.isBioLocked.value;   // Read (instant from RAM)
_storagePresets.isBioLocked.addListener(() { ... }); // Listen (ChangeNotifier)
_storagePresets.isBioLocked.listen((val) { ... });   // Stream
```

---

## Database System (core_database — Drift + SQLite)

- Background isolate via `NativeDatabase.createInBackground`
- `AppDatabase` registered via `@preResolve` DI — no manual `.open()` in `main.dart`
- Template ships a working sample: `CacheEntries` table + `CacheEntriesDao` + `CacheEntryLocalDataSource` + `CacheEntryRepositoryImpl` + Domain UseCases

### When to Use What

| Need | Package |
|:-----|:--------|
| Tokens, flags, theme, locale (key-value) | `core_storage` |
| Lists, relations, SQL queries, migrations | `core_database` |

### Adding a New Table

1. Create table class in `core_database/lib/src/database/tables/`
2. Create DAO with `part of '../app_database.dart'`
3. Register table + DAO in `AppDatabase` `@DriftDatabase` annotation
4. Bump `schemaVersion` and add migration in `MigrationStrategy`
5. Run `dart run build_runner build -d --workspace`
6. Add Local DataSource → Repository → UseCase following the cache sample

---

## Networking (core_network)

### ApiClient (Dynamic Factory)

```dart
@module
abstract class RegisterModule {
  @lazySingleton
  Dio dio(ApiClient apiClient) => apiClient.createClient();

  @Named('public_api')
  @lazySingleton
  Dio publicDio(ApiClient apiClient) => apiClient.createClient(
    useDefaultInterceptors: false,
    interceptors: [LoggingInterceptor(tag: 'PublicAPI')],
  );
}
```

### Interceptors Chain

1. **AuthInterceptor**: Auto-injects Bearer JWT Token from `core_storage`
2. **RetryInterceptor**: Auto-retry with Exponential Backoff, groups concurrent failures into single retry dialog
3. **LoggingInterceptor**: JSON-formatted HTTP logs via `dynamic_logger`, disabled in production

### SSL Certificate Pinning

- **Global:** `HttpOverrides.global` with `HttpSecurityPinningClient` (SPKI SHA-256)
- **Dev:** SSL bypass enabled for self-signed certs
- **Staging/Prod:** Strict SPKI hash matching — MANDATORY

### Data Standardization

- `BaseEntity<T>`: Standard server response wrapper
- `PaginatedEntity<T>`: Pagination (items, totalCount, currentPage, pageSize)
- `BaseRequest`: Pagination params builder

---

## Fastlane CI/CD

CWD-independent architecture — run from monorepo root, no `cd app/` needed:

```bash
# Android
fastlane android build flavor:dev build_type:apk distribute_firebase:true
fastlane android store version:1.2.0 build_number:45 track:internal

# iOS
fastlane ios build flavor:dev distribute_store:true
fastlane ios store version:1.2.0 build_number:45

# Cross-platform
fastlane flutter flavor:dev version:1.2.0 build_number:45
fastlane store version:1.2.0 build_number:45
```

Config: `app/fastlane/Config.yaml`. Modules: `app/fastlane/modules/` (helpers, android_lanes, ios_lanes, flutter_lanes).

---

## Shared Components Architecture

| Package | Contains | Key Rule |
|:--------|:---------|:---------|
| `core_base_ui` | Design tokens, themes, colors, fonts, images, icons, L10n | **Zero Flutter widgets.** Only global assets |
| `feature_shared` | All reusable widgets (atomic + business) | May depend on `domain_*`, `core_common`, `core_base_ui` |

### Sharing Across Features

- **Pure UI widgets** (buttons, inputs) → `feature_shared`
- **Widgets with Feature B logic** → Widget Builder Interface via DI (declare in `core_di`, implement in owning feature)
- **Dialogs/BottomSheets** → Always separate widget classes (`*_dialog.dart`/`*_bottom_sheet.dart`), never inline

---

## Frequently-Violated Rules (Full List in AGENTS.md)

1. **ScreenUtil:** All UI dimensions use `.w`/`.h`/`.sp`/`.r` — no raw doubles. Reusable widgets in `feature_shared` take unscaled values — caller scales.
2. **Freezed BLoC events:** Private subclasses (`_HomeStarted`) via `part`/`part of`. `on<Event>` handlers must be async `(event, emit)` — never sync closure calling unawaited async.
3. **Dialogs/BottomSheets:** Always separate widget classes, never inline in `showDialog`/`showModalBottomSheet` builders.
4. **Naming:** `I` prefix reserved for interfaces. Data source dirs are `data_sources/` (not `datasources/`). Suffixes: `_page`, `_provider`, `_bloc`, `_usecase`, `_entity`, `_repository_impl`, etc.
5. **CLI tools** in `tools/` use `stdout.writeln`/`stderr.writeln`, **never** `print()`.
6. **No lint suppressions** — research proper migration for deprecation warnings.
7. **No PowerShell scripts** (`.ps1`) — only `.sh`/`.bat` due to Windows execution policy restrictions.
8. **BuildContext** must be passed directly from UI caller — don't use `NavigatorKeys.*.currentContext`.
9. **Never edit `app_router.dart`** to hardcode routes — register via DI contracts.
10. **Features must not edit `root_app.dart`** for delegates — use `IFeatureLocalization` DI.
11. **Error handling:** Use `ErrorHandler.handleError(e)` — never `AppFailure.fromException()`.
12. **No `throw` from Data layer to UI** — wrap in `Result.failure(AppFailure)`.
13. **Module generator** auto-handles workspace + DI registration — verify before manual edits.
14. **Barrel files:** Run `dart tools/barrel_generator/generate.dart` after creating/renaming/deleting files.
15. **Build runner flag:** Use `-d` (replaces deprecated `--delete-conflicting-outputs`).
16. **Flat workspace:** `resolution: workspace` at root `pubspec.yaml` only — no intermediate workspace nodes.

---

## PR Review Checklist (from docs/en/10_review_checklist.md)

- [ ] New package has `resolution: workspace` in pubspec
- [ ] Barrel file exports all public APIs
- [ ] Domain files are 100% Pure Dart (no Flutter/Dio/Retrofit imports)
- [ ] Entities use `freezed` with `const Class._()` empty constructor
- [ ] Models have `.toEntity()` mapper
- [ ] RepositoryImpl uses `execute()`/`executeSync()` from `IBaseRepository`
- [ ] Feature controllers are `@injectable` (NOT singleton) with route-level instantiation
- [ ] One bounded UI concern per feature package
- [ ] Routes registered via DI contracts (NOT hardcoded in `app_router.dart`)
- [ ] Cross-feature navigation uses Navigator interfaces (NOT direct imports)
- [ ] Dashboard limited to chrome only (`DashboardRouteModule`)
- [ ] Action Handlers used for cross-feature UI actions
- [ ] Localization uses `IFeatureLocalization` (NOT editing `root_app.dart`)
- [ ] ScreenUtil applied to all sizing
- [ ] CLI tools use `stdout.writeln`/`stderr.writeln` (NOT `print()`)
- [ ] Missing modules handled with `getAllOrEmpty`/`getItOrNull` + fallbacks

---

## Workflow: Creating a New Module (Best Practice)

```bash
# 1. Create domain + data micro-packages:
dart tools/module_generator/generate.dart 2 payment
dart tools/module_generator/generate.dart 3 payment

# 2. Implement: Entities → Repository Interfaces → UseCases → Models → DataSources → RepositoryImpl

# 3. Generate barrel files:
dart tools/barrel_generator/generate.dart packages/domain/payment/lib
dart tools/barrel_generator/generate.dart packages/data/payment/lib

# 4. Generate DI code:
dart run build_runner build -d --workspace

# 5. Create feature if needed:
dart tools/module_generator/generate.dart 1 payment "" 2 1

# 6. Verify: flutter analyze
```

---

## Workflow: Periodic Cleanup

```bash
dart tools/unused_checker/check_script.dart    # Find unused resources
dart tools/check_outdated.dart                 # Find outdated packages
dart tools/dependency_sync.dart                # Sync version catalog
dart tools/code_review/code_review.dart --all  # AI code review
```
