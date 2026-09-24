# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**IMPORTANT:** The authoritative, detailed rules live in [`.agents/AGENTS.md`](.agents/AGENTS.md). Read it before making changes — it covers layer isolation, DI lifecycle, naming conventions, routing, localization, Freezed/BLoC rules, and responsive UI rules in full. This file is a **comprehensive** summary plus commands.

---

## What This Repo Is

A Flutter **Pub Workspaces monorepo template** built on **Clean Architecture + SOLID + MVVM** with dual state management support (**Provider** and **BLoC**). The shipped feature/domain/data packages (auth, cache, home, settings, onboarding, splash, dashboard) are **sample reference code** demonstrating the wiring — patterns to copy or delete, not production logic.

**Author:** CaoGiaHieu-dev. **Docs hub:** `docs/en/` (and `docs/vi/`), grouped by purpose:

| Folder | For |
|:-------|:----|
| `getting-started/` | First run, project tour, daily workflow |
| `architecture/` | Overview + one file per layer (core, domain, data, features, app shell) |
| `guides/` | How-to: new feature, domain/data, state management, routing, DI, storage, database, networking, localization/theming, cross-feature |
| `reference/` | Rules, naming, tooling, PR checklist |
| `operations/` | CI/CD, Fastlane & release |

---

## Commands

**FVM is optional — do not hardcode an `fvm` prefix.** `.fvmrc` pins a version, but that does not mean `fvm` is installed on the current machine. Write commands bare (`flutter pub get`); add `fvm ` yourself only if your machine uses it. Tools that shell out must **detect** FVM through `tools/shared/toolchain.dart` (`useFvm`, `dartExecutable`/`dartArgs`, `flutterExecutable`/`flutterArgs`).

```bash
# Full workspace setup — THE setup step on a fresh clone. Runs, in order:
# activate flutterfire_cli → flutter clean → flutter pub get → gen-l10n in every
# package with an l10n.yaml → build_runner build --workspace → barrel generator
# for every package with a lib/ (apps skipped). pub get + build_runner alone is
# NOT enough: the gitignored lib/src/gen/gen.dart barrels only exist after the
# barrel pass, and without them `flutter analyze` fails on `gen/gen.dart`,
# `AppLocalizations` and `Assets`.
dart tools/workspace_setup/configure.dart

# Install all workspace dependencies (single pubspec.lock at root, committed)
flutter pub get

# Code generation across the whole workspace (injectable, freezed, json_serializable, retrofit, go_router_builder, drift)
dart run build_runner build --workspace

# Run the app (flavors: dev / staging / prod) — from apps/mobile, the root has no android/ or ios/
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev

# Static analysis
flutter analyze
dart fix --apply
```

### Tests

Tests live per-package in a `test/` directory — sixteen packages today: `platform/{app_shell,base_ui,common,data_core,database,network,notifications,provider_state_management,responsive,storage,ui_kit}/test/` and `modules/{auth/data,auth/feature,cache/data,dashboard/feature,onboarding/feature}/test/` (CI Gate 3 finds every `test/` directory itself). Run from the package directory:

```bash
cd platform/common
flutter test                           # all tests in the package
flutter test test/debounce_test.dart   # a single test file
```

### Repo Tooling (run from root)

```bash
# Enforce the layering rules — Gate 1 of pr_quality_check.yml, exits 1 on violation.
# The only check that can see layering; analysis_options.yaml knows nothing about it.
dart tools/arch_check/check.dart
dart tools/arch_check/check.dart --help   # full rule descriptions (R1-R10)

# Verify every repo path the docs name actually exists — Gate 5 of
# pr_quality_check.yml. Known-absent paths (generated / secret / "create this
# file yourself") live in tools/docs_check/allowlist.txt with their reason.
# A `<placeholder>` span only needs its part before the first placeholder to
# exist. References into a sample bundle removed with remove_sample (all its
# packages gone; bundles read from tools/sample_manifest.yaml, which
# remove_sample never edits) print one INFO line per bundle and do not fail.
dart tools/docs_check/check.dart
dart tools/docs_check/check.dart --verbose   # + copy-paste allowlist block, removed-sample refs

# Which packages are sample code, and how to delete one safely.
# Source of truth: tools/sample_manifest.yaml
# Bundles: auth, home, settings, onboarding, dashboard, splash, cache
dart tools/sample_cleanup/remove_sample.dart --list
dart tools/sample_cleanup/remove_sample.dart auth           # dry-run (default)
dart tools/sample_cleanup/remove_sample.dart auth --apply   # actually remove

# Generate a new module
# Syntax: dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<SM>] [<route>]
# <type>: 1=Feature, 2=Domain, 3=Data, 4=Core (core_<name>), 5=Custom
# <prefix> (Custom only; pass "" otherwise): package-name prefix → <prefix>_<name> at platform/<name>
# <SM> (Feature only): 1=Provider, 2=BLoC, 3=None
# <route> (Feature only): 1=IFeatureRouteModule (stack), 2=INavDestinationModule (bottom nav tab), 3=none
# A feature missing <SM> or <route> prompts for it on a terminal, and exits 64 without one —
# always pass both. Invalid names (must be Dart package names), a package name any pubspec
# already declares (`2 core` = domain_core), or bad values are rejected up front (exit 64,
# nothing written); --help prints usage. A nav tab gets order = highest existing + 10.
dart tools/module_generator/generate.dart 1 profile "" 1 1    # Feature+Provider+stack routes
dart tools/module_generator/generate.dart 1 chat "" 2 2       # Feature+BLoC+bottom nav tab
dart tools/module_generator/generate.dart 2 payment            # Domain micro-package
dart tools/module_generator/generate.dart 3 payment            # Data micro-package
dart tools/module_generator/generate.dart 4 analytics          # Core package (core_analytics)
dart tools/module_generator/generate.dart 5 billing acme       # Custom package (acme_billing at platform/billing)

# Regenerate barrel files after adding/renaming/deleting files in a package's lib/ —
# AFTER gen-l10n / build_runner: barrels also export generated files present on disk
dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib

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

# AI-powered code review (Gemini API key via GEMINI_API_KEY, --api-key, or the gitignored tools/code_review/.gemini_api_key)
dart tools/code_review/code_review.dart --all
dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart
dart tools/code_review/code_review.dart --changed
dart tools/code_review/code_review.dart --all --focus architecture,security

# Workspace setup (cross-platform — there is no .bat/.sh wrapper)
dart tools/workspace_setup/configure.dart
dart tools/workspace_setup/configure.dart --help   # prints the steps, runs nothing; other args exit 64

# Firebase multi-environment config
dart tools/firebase/firebase_config.dart --app mobile   # --app is required once there are 2+ apps

# Theme (splash screen + app icons)
dart tools/theme_generator/theme_setting.dart --app mobile   # needs the app's android/ + ios/ — `--app admin` is refused

# Android 15+ 16KB page size compliance check
# Pass the APK to check — a Flutter release build lands at the path below
.\tools\android_compliance\16kb_ckeck.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
./tools/android_compliance/16kb_ckeck.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk    # macOS/Linux
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
| **Apps** | `apps/<id>/` | What genuinely differs per app: `app_manifest.yaml`, the `injection.dart` generated from it, a one-line `main.dart` (`runShellApp`), flavors, and what identifies it (`lib/firebase/`). Two today: `apps/mobile` (every sample module) and `apps/admin` (auth + settings) |
| **App Shell** | `platform/app_shell/` | Shared by every app: boot (`runShellApp`, `MainScope`), **dynamic** router assembly (`app_router.dart` — collects route modules from DI, never hardcode feature routes), material wrapper, storage adapters, `NetworkConfigImpl` |
| **Core** | `platform/*` | Infrastructure shared across all layers |
| **Domain** | `modules/*/domain` | **Pure Dart** business logic — entities, use cases, repository interfaces |
| **Data** | `modules/*/data` | Repository implementations, DTOs/models, data sources (remote + local) |
| **Features** | `modules/*/feature` | UI + state management — one bounded UI concern per package |

### Core Packages Detail

| Package | Purpose | Key Notes |
|:--------|:--------|:----------|
| `platform_kernel` | **Depend on this, not `core_common`, unless you need something Flutter-bound.** Pure Dart, zero Flutter. `getIt`/`getItOrNull`/`getAll`/`getAllOrEmpty`, `ErrorHandler`, `AppException`, primitive extensions, `TypeHelper`, `ValidationHelper`, `EnvConstants` | 7 dependencies, none Flutter-bound — enforced by arch_check **R9**. Everything else may depend on it |
| `platform_app_shell` | The reusable app shell — `MainScope`, `AppRouter`, `AppMaterialWrapper`, `NavigatorWrapperWidget`, the `ILanguageStorage`/`IThemeStorage` adapters, `AppBootStorage`, `NetworkConfigImpl` | Every app composes it instead of copying it. Its DI group runs **after `core`, before `ui`**. Imports no module — arch_check R1 holds that |
| `core_common` | The Flutter-bound half: `AppConfig`, `AppInitializer`, mixins, `GoRouteDataCustom` + page transitions, `AppUtils`, `Debounce`, formatters, dialog helpers | Re-exports `platform_kernel` wholesale, so `getItOrNull`, `ErrorHandler`, `EnvConstants` etc. still resolve through it — but they live in the kernel (`platform/kernel/lib/src/`), as does the `AppFailure` re-export shim at `src/error/failures.dart` (`AppFailure` itself lives in `domain_core`) |
| `core_di` | DI Hub — Navigator interfaces, `I*ActionHandler`, routing contracts (`IFeatureRouteModule`, `INavDestinationModule`, `IAppEntryLocation`, `DashboardRouteModule`), `NavigatorKeys`, agnostic stream interfaces | Declares **no** `domain_*` dependency — a contract carries its own value type (`AuthPrincipal`), never a domain entity |
| `core_base_ui` | Design System — themes, color palette, typography, assets, L10n translations | **Contains zero Flutter widgets.** Feature-specific assets go in feature packages |
| `core_network` | `ApiClient` (Dio factory), Retrofit, interceptors (Auth/Retry/Logging), SSL pinning | `NetworkConfig` interface → `NetworkConfigImpl` in `platform_app_shell` |
| `core_storage` | **Mechanism only** — `StorageInterface`, `StorageManager`, reactive `StorageValue<T>`, `StorageType`, AES-256 + RAM obfuscation, dual-layer security (Keychain/KeyStore) | **Defines zero keys/presets.** Each consumer declares its own `StorageValue` — see [Storage System](#storage-system-core_storage) |
| `core_database` | **Mechanism only** — `IDatabaseHandle<TDb>`, `IDatabaseMigration`, `DatabaseMigrationRunner`, `DatabaseConnectionFactory`, `DriftDatabaseOpener` | **Owns no database/table/DAO**; its DI module registers nothing. Each package declares its own database — see [Database System](#database-system-package-owned-drift--sqlite) |
| `core_notifications` | Push notification management | Owns `NotificationConstants` at `lib/src/utils/` |
| `core_responsive` | **Mechanism only** — `ResponsiveInit`, `ResponsiveScope` (InheritedWidget), `ResponsiveMetrics`, the `BuildContext` scaling extension (`context.w/h/r/sp/spMin/dg/dm`); scale policy (`ScaleBounds`, `ResponsiveProfile`); window classes (`WindowSizeClass`, `WindowHeightClass`, `ResponsiveBreakpoints`); adaptive layout (`context.adaptive`, `AdaptiveLayout`, `AdaptiveSplitView`, `AdaptiveContent`, `FoldPosture`) | **Ships no `num` extension** — `16.w` does not compile, on purpose. Scales **down only** by default. Zero workspace deps. See [Responsive UI](#responsive-ui-core_responsive--strict) |
| `provider_state_management` | `BaseProvider`, `executeOperation`, `ViewStateModel`, `ProviderStateListener`, `MultiProviderStateListener`, `BaseViewWidget`, `BaseProxyWidget` | Also ships `DefaultLoadingWidget`/`DefaultEmptyWidget` so core never borrows from `core_ui_kit` |
| `bloc_state_management` | `BaseBloc`, `BaseCubit` (only when events unnecessary), `BlocViewState<T>` (optional Freezed union) | **`BaseBloc`/`BaseCubit` are empty extension points** — no `executeOperation` equivalent; handlers unwrap `Result` by hand |

### Domain Layer Rules (Pure Dart Mandate)

- **FORBIDDEN imports:** `package:flutter/...`, `package:dio/...`, `package:retrofit/...`, **and any `core_*` package**
- **Allowed imports:** `dart:*`, `domain_core` (`Result<T>`, `AppFailure`, `BaseEntity<T>`, `PaginatedEntity<T>`), `freezed_annotation`, `json_annotation`, `injectable`, `get_it`
- **`domain_core` has ZERO workspace dependencies** and no `flutter` in `dependencies` — purity is enforced by the package graph, not just review. `domain_auth` and `domain_cache` depend only on `domain_core`. Verify: `grep -rn "package:flutter" modules/*/domain/lib` must print nothing
- `AppFailure` lives in `domain_core` (`lib/src/failures/`) — it is part of the `Result` contract. Moving it there is what let Domain drop `core_common`
- Domain constants live in the domain package's own `utils/` (e.g. `DomainConstants`) — never in `core_common`
- Components: `entities/` (Freezed immutable), `params/`, `repositories/` (interfaces), `usecases/` (`@injectable`, returns `Result<T>`), `utils/`, `services/` (optional)
- `Result<T>` is a sealed Freezed class in `domain_core` with 4 variants: `Success<T>`, `Failure<T>` (containing `AppFailure`), `None<T>`, `Cancel<T>`. Note `None`/`Cancel` are never returned by production code today

### Data Layer Rules

- Directory convention: `data_sources/remote/` (Retrofit) and `data_sources/local/` (Storage/DB). **NOT** `datasources/`
- Models use `freezed` + `json_serializable` with `.toEntity()` mapper
- `RepositoryImpl` extends `IBaseRepository` from `data_core` and uses `execute()` (async) / `executeSync()` (sync) wrappers
- Error handling: `ErrorHandler.handleError(e)` — there is **no** `AppFailure.fromException()`, do not invent one
- ⚠️ `ErrorHandler` has **no Firebase branch** — `FirebaseException`/`FirebaseAuthException`/`PlatformException` all collapse to `ServerFailure(code: 9999)` → *"Unknown error occurred"* in release. Add a branch before relying on Firebase error codes in UI
- DataSources return Models only, never Entities — the one allowed wrapper is `domain_core`'s `BaseEntity<T>` response envelope (`AuthRemoteDataSource` returns `Future<BaseEntity<UserModel>>`; the repository unwraps it in `execute`'s `mapper`) — and **never leak a generated type** (a Drift row must be converted at the boundary — see `CacheEntryModel.fromRow`). They let exceptions bubble up to RepositoryImpl

### Feature Layer Rules

- **Allowed deps:** `domain_*` and `core_*` — in practice `core_di`, `core_common`, `core_base_ui`, `core_ui_kit`, `core_responsive`, and `provider_state_management` **or** `bloc_state_management`
- **FORBIDDEN:** Direct deps on the `data` layer or on **any** other feature package — no exception. Shared widgets come from `core_ui_kit`, which is core
- **One bounded UI concern per package** — Home and Settings are separate packages; `feature_dashboard` is shell chrome only
- Feature-specific assets go in `<feature>/assets/` (images, SVGs, language ARBs)
- Structure: `pages/`, `widgets/`, `provider/` **or** `bloc/` (both **singular**), `routing/`, `utils/` (constants — route paths live here, not in `routing/`), `extensions/`, `handlers/` (optional), `di/module.dart`
- **Any feature must be removable** — see [Feature Removability](#feature-removability)

---

## Dependency Injection (GetIt + Injectable)

### Micro-package DI Pattern

Each package declares `@InjectableInit.microPackage()` at `lib/di/module.dart`. The host app assembles all modules in `apps/mobile/lib/di/injection.dart`:

```dart
@InjectableInit(
  externalPackageModulesBefore: [..._coreModules],  // core_common, network, storage, database, di
  // (the app's own lib/ registers here, between the phases: FirebaseModule)
  externalPackageModulesAfter: [
    ..._notificationsModules, // CoreNotificationsPackageModule — injects the app's FirebaseOptions
    ..._shellModules,    // PlatformAppShellPackageModule — storage adapters, NetworkConfig, router
    ..._uiModules,       // CoreBaseUiPackageModule (injects the shell's storage adapters)
    ..._domainModules,   // domain_core, domain_auth, domain_cache
    ..._dataModules,     // data_core, data_auth, data_cache
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
| **Third-party libs, async construction** | `@module` + `@preResolve` | `SharedPreferences`, a package's own Drift database |
| **Third-party libs, sync construction** | `@module` + `@lazySingleton` | `Dio` (`platform/network/lib/di/register_module.dart`), a Retrofit data source |
| **Supertype binding** | `@module` returning the supertype | `SslPinningConfig` ← `NetworkConfig` (GetIt does not walk supertypes) |

### Critical DI Rules

1. **Constructor Injection only** — no `getIt<T>()` inside business logic (VMs, Repos, UseCases)
2. **`CoreBaseUiPackageModule` must run after the `shell` group** — it injects `ILanguageStorage`/`IThemeStorage`, which `platform_app_shell` registers. The manifest's `di_groups` order is what enforces this
3. Never create monolithic `DomainPackageModule`/`DataPackageModule` — register each micro-package module separately
4. Compose a package through each `apps/<id>/app_manifest.yaml`, then run `composer sync` — the `_<group>Modules` lists in `injection.dart` are generated from it. A **module** (`domain_*`/`data_*`/`feature_*`) is listed under `modules:` as `- { id: <name>, layers: [domain, data, feature] }` and gets its group from the `from_modules:` of the `domain`/`data`/`feature` groups; only **platform** packages are named in a `di_groups` entry (`core`, `notifications`, `shell`, `ui`, `domain`, `data`, `other`)
5. `@InjectableInit.microPackage()` takes no arguments — the one exception is `core_notifications`' `ignoreUnregisteredTypesInPackages: ['firebase_core']`, because the app, not a package, registers `FirebaseOptions`
6. **Eager `@Singleton` must not depend on a later-registered type** — GetIt throws `"<Type> is not registered"` at boot. Use `@LazySingleton`. `flutter analyze` cannot catch this — check the module **order** in generated `apps/mobile/lib/di/injection.config.dart` and the type's own registration and its `gh<Dep>()` calls in the package's generated `lib/di/module.module.dart`
7. **`getAll<T>()` THROWS when `T` is unregistered** — use `getAllOrEmpty<T>()` for optional contributions, and `getItOrNull<T>()` + fallback for single ones
8. **GetIt does not resolve supertypes.** `Impl as InterfaceA` leaves `getIt<InterfaceB>()` unresolvable even if `InterfaceA implements InterfaceB`. Bind the second type via `@module`:
   ```dart
   // platform/app_shell/lib/di/network_binding_module.dart
   @module
   abstract class NetworkBindingModule {
     @lazySingleton
     SslPinningConfig bindSslPinningConfig(NetworkConfig config) => config;
   }
   ```
   Miss it and SSL pinning silently no-ops on staging/prod — the app still builds and still makes requests.

### App-Shell Storage Adapters (`platform_app_shell`)

`LanguageProvider`/`ThemeProvider` (in `core_base_ui`) inject `ILanguageStorage`/`IThemeStorage` from `core_di`. Concrete impls live in `platform/app_shell/lib/di/` — shared by every app — and each owns its **own** `StorageValue` (no shared preset object); their keys live in `platform/app_shell/lib/di/utils/`:
- `language_storage_impl.dart` → own `StorageValue<String>` @ `LanguageStorageKeys.LOCALE`
- `theme_storage_impl.dart` → own `StorageValue<ThemeMode>` @ `ThemeStorageKeys.THEME_MODE`
- `app_boot_storage.dart` → own `StorageValue<bool>` @ `AppBootStorageKeys.VIEWED_ONBOARD`

---

## Routing (go_router + go_router_builder, Decentralized)

### Routing Contracts (registered via DI, NOT hardcoded in app_router.dart)

| Contract | Purpose | Has Order? | Who Implements |
|:---------|:--------|:-----------|:---------------|
| `IFeatureRouteModule` | Stack/shell routes under app `ShellRoute` | **No** (path match) | auth, onboarding, … |
| `INavDestinationModule` | One primary nav destination (bottom-bar / rail item) + one `StatefulShellBranch` | **Yes** (ascending sort key — keep unique) | home, settings, … |
| `IAppEntryLocation` | First-launch `GoRouter.initialLocation` (once `AppBootStorage.viewedOnboard` is set, cold starts use `AppRouter.fallbackLocation`) | n/a | usually onboarding |
| `DashboardRouteModule` | Dashboard **chrome** only (scaffold + bottom bar / rail host) | n/a | `feature_dashboard` only |
| `IFeatureLocalization` | Feature ARB delegates | n/a | every feature with strings |

### Navigator Pattern

1. **Declare** Navigator interface in `core_di/lib/src/navigators/` (e.g., `AuthNavigator`)
2. **Implement** in the owning feature's `routing/` directory (e.g., `AuthNavigatorImpl` in `feature_auth`)
3. **Use** via `getItOrNull<AuthNavigator>()?.toLogin(context)` (a throwing `getIt` is allowed only inside the owning module's own packages — arch_check R8) — never hardcode paths or `GoRouter.of(context).go(...)`
4. **BuildContext MUST be passed directly** from UI caller — avoid using `NavigatorKeys.*.currentContext`

### Route-Level Instantiation (Critical)

Feature controllers are instantiated in the `build` method of `GoRouteDataCustom`:

```dart
// Provider (what `generate.dart 1 profile "" 1 1` scaffolds):
@override
Widget build(BuildContext context, GoRouterState state) {
  return ChangeNotifierProvider(
    create: (context) => getIt<ProfileProvider>(),
    child: const ProfilePage(),
  );
}

// BLoC (modules/home/feature/lib/src/routing/home_route_module.dart):
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

> [!CAUTION]
> **NEVER DOUBLE-WRAP CONTROLLERS INSIDE PAGE WIDGETS!**
> Since `BlocProvider` or `ChangeNotifierProvider` is instantiated at the Route level in `*_route_module.dart`, the Page class (`*Page`) **MUST NOT** wrap itself in another `BlocProvider` or `ChangeNotifierProvider` inside its `build()` method. Double-wrapping creates duplicate controller instances, causing state desynchronization bugs and memory leaks.

### Dashboard Rules

**`feature_dashboard` is chrome only** — it implements `DashboardRouteModule` and builds its navigation from `getAllOrEmpty<INavDestinationModule>()`: a bottom bar on a `compact` window, a `NavigationRail` from `medium` up (extended from `large`).

**Dashboard MUST NOT:**
- Import `feature_home`/`feature_settings` or embed their pages
- Own `HomePage`/`SettingsPage` or business BLoCs for tabs
- Hardcode a destination list ignoring DI
- Register `INavDestinationModule` itself for "fake" tabs

**Use `INavDestinationModule`** ONLY when the screen is a primary bottom-nav destination needing a stable `StatefulShellBranch`.

### Key Router Components

- **`AppRouter`**: `@singleton`, uses `NavigatorKeys` (`rootKey`, `appKey`, plus `nested(id)` for a module's own back stack) from `core_di/lib/src/routing/navigator_keys.dart`. `refreshListenable` resolves `IAuthRefreshListenable`, not `AuthProvider`
- **`NavigatorWrapperWidget`**: App shell widget at `platform/app_shell/lib/presentation/widgets/` — handles auth boot redirect (via `endOfFrame.whenComplete`) and global auth side-effects
- **`UndefineRouteWidget`**: GoRouter's `errorPageBuilder` child — never use inline anonymous widgets
- **SplashPage**: Manually managed by `MainScope` (`AppMaterialWrapper`), NOT a GoRouter route

---

## Application Boot Lifecycle

1. `main.dart` → `runShellApp(configureDependencies: …)` (`platform/app_shell/lib/bootstrap.dart`) → `runZonedGuarded` → `WidgetsFlutterBinding.ensureInitialized()`
2. `configureDependencies()` — the app's generated DI graph (GetIt)
   - then `AppInitializer.initBeforeRunApp()` — synchronous: Logger + `HttpOverrides.global` (SSL pinning / dev bypass), installed **before any widget is built**, so the first Dio client (the splash's session restore) is already pinned
3. `MainScope.run()`:
   - Removes native splash (`FlutterNativeSplash.remove()`)
   - Shows the splash from `getItOrNull<IAppSplashScreen>()` via `AppMaterialWrapper(home: splashScreen)` (no router); none registered, or iOS → native splash kept
   - Calls `AppInitializer.init()` (ScreenOrientation — portrait lock only when the display's shortest side is < 600, SystemUIOverlay; it re-runs `initBeforeRunApp()`, which is then a no-op)
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
- ⚠️ **`BaseBloc`/`BaseCubit` are empty extension points.** There is no BLoC equivalent of Provider's `executeOperation`: each handler must unwrap `Result`, map `AppFailure`, and set loading by hand. The two branches are **not** at parity
- **`BlocViewState<T>`** (renamed from `ViewState` to avoid colliding with Provider's `ViewState`) is a shared optional helper (initial/loading/success/error) — not mandatory. It carries data and takes a required `AppFailure` in `error`; Provider's `ViewState` has 5 variants, no generic, and a nullable `ErrorState`
- Complex features may define custom Freezed UI state (`BaseBloc<Event, CustomState>`)
- **Freezed Event Rules:**
  - All event subclasses must be **private** (`_HomeStarted`, not `HomeStarted`)
  - Use `part`/`part of` architecture: `_bloc.dart` ← `_event.dart`, `_state.dart`, `_bloc.freezed.dart`
- **Event handler signature must be async with `(event, emit)`** — never sync closure calling unawaited async

```dart
// CORRECT:
HomeBloc() : super(const BlocViewState.initial()) {
  on<_HomeStarted>(_fetchInitialData);
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

## Cross-Feature Communication (6 Models)

| # | Problem | Solution | Implementation |
|:--|:--------|:---------|:---------------|
| 1 | Business logic sharing | **Domain UseCase** | Both features inject same UseCase from `domain_*` |
| 2 | Infrastructure utils | **Core Service** | Import `core_storage`, `core_network`, etc. |
| 3 | Cross-feature state | **Agnostic Streams** | Neutral `Stream`/`ValueListenable` interface on `core_di`; dual-register owner impl |
| 4 | Pure UI prefs (theme/locale) | **Bypass Domain** | `ThemeProvider → IThemeStorage → ThemeStorageImpl` (owns its own `StorageValue`) |
| 5 | Embed complex widgets | **Builder/Service Interface** | Interface in `core_di`, impl in owning feature, use via GetIt |
| 6 | Cross-feature UI actions | **Action Handler** | `I*ActionHandler` in `core_di/src/actions/`, `*ActionHandlerImpl` in owning feature's `handlers/` |

### Agnostic Streams (Dual Registration Pattern)

```dart
// 1. Interface in core_di — carries a contract-owned type, never a domain entity:
abstract class IAuthStatusStream {
  Stream<AuthPrincipal?> get authStatusStream;
  AuthPrincipal? get currentUser; // broadcast streams do not replay
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
- **ARB keys are `lowerCamelCase`** — `gen-l10n` copies the key into the getter name, so `welcome_back` becomes `context.l10nAuth.welcome_back`. Generated files are excluded from analysis; no linter catches it
- **Feature-scoped:** Each feature owns `.arb` files in `assets/language/` and registers `IFeatureLocalization` via DI
- **Global strings only** in `core_base_ui`; `core_ui_kit` uses `core_base_ui` translations, does NOT define its own ARBs
- Access via feature extension: `context.l10nAuth.translationKey`
- Features **MUST NOT** edit `root_app.dart` to add delegates — the shell's `app_material_wrapper.dart` collects them via `getAllOrEmpty<IFeatureLocalization>()`

---

## Responsive UI (core_responsive — Strict)

- **ALL sizing** (width, height, padding, margin, font size, border radius) MUST be scaled **through `BuildContext`**: `context.w(x)`, `context.h(x)`, `context.sp(x)`, `context.r(x)` (also `context.spMin`, `context.dg`, `context.dm`)
- **There is no `num` extension.** `16.h` does not compile — `core_responsive` ships none, on purpose
  - **Why:** a number carries no context, so such an extension could only read a global, and a widget reading a global never learns the metrics changed — it computes once and never updates (silent stale value). `context.h(16)` registers a `ResponsiveScope` (InheritedWidget) dependency, so exactly the widgets that scale rebuild on rotation / split-screen / resize
- **FORBIDDEN:** Raw doubles in layout — `SizedBox(height: 24)` → `SizedBox(height: context.h(24))`
- **No context in an async method?** Read the value *before the first `await`*, then pass it on. Then check `mounted` after the `await`, before touching state
- **Reusable widgets** in `core_ui_kit` receive **already-scaled** values and use them as-is (the caller scales); they scale only their *own* constants. `context.w(widget.width)` double-scales
- **Helper axes:** `edgeInsets(all:)` → `w` · `edgeInsets(horizontal:)` → `w` · `edgeInsets(vertical:)` → `h` · `borderRadius(all:)` → `r` · `verticalSpace` → `h` · `horizontalSpace` → `w`. Each axis scales by the axis it belongs to, so `edgeInsets(all: 16)` is a drop-in for `EdgeInsets.all(context.w(16))`
- **`ResponsiveInit` is mounted once**, above `MaterialApp`, in `platform/app_shell/lib/main_scope.dart` — a `StatelessWidget` reading `MediaQuery.sizeOf(context)` (size-only dependency). Features never mount their own
- **Widget tests that scale must wrap the subject in `ResponsiveInit`** — otherwise `ResponsiveScope.of` asserts, deliberately, rather than silently falling back to unscaled values
- **Scale policy — down by default, up on opt-in, per window class.** Every factor is clamped by a `ScaleBounds`, layout (`scaleBounds`: `w/h/r/dg/dm`) and text (`textScaleBounds`: `sp`) separately, both `ScaleBounds.downOnly()` by default — shrink below the artboard, 1:1 above it
  - **Do not expect sizes to grow on a tablet** — the extra room is for layout. Growth is opt-in and capped per `WindowSizeClass` through a `ResponsiveProfile` (`ScaleBounds(max: 1.2)`); `.fixed()` pins the design size; `.unbounded()` is the old raw ratio. A profile covers its class and every wider class without its own
  - `fontSizeResolver` is **never clamped**; `spMin` is the explicit cap (equal to `sp` under the default bounds)
  - **This app** (`_ResponsiveWrapper`): `AppConfig.design` (375×812), default bounds, `profiles: {WindowSizeClass.expanded: ResponsiveProfile(scaleBounds: ScaleBounds.fixed(), textScaleBounds: ScaleBounds.fixed())}`, `splitScreenMode: true`
- **Choose a layout by window size class, never by device** — no `Platform.isIOS`, device model or ad-hoc `shortestSide` check. `context.windowSizeClass`: `compact` <600 · `medium` 600–839 · `expanded` 840–1199 · `large` 1200–1599 · `extraLarge` ≥1600 (Material 3; move with `ResponsiveInit(breakpoints:)`). These and every adaptive member work without a `ResponsiveInit`
  - `context.adaptive(compact:, medium:, …)` (a missing class takes the nearest smaller one) · `AdaptiveLayout` / `AdaptiveBuilder` · `AdaptiveSplitView` (master–detail; splits at a fold/hinge or from `splitAt`, else one pane — `AdaptiveSplitView.isSplit(context)` picks select vs push) · `AdaptiveContent` (640 px readable width, **not** scaled)
  - `AdaptiveSplitView` honours a fold only when it spans the window along it — in a dashboard tab the rail (`medium`+) rules out book folds and the bottom bar (`compact`) tabletop ones
  - Reference: `modules/dashboard/feature/lib/src/pages/dashboard_page.dart`. Full guide: `docs/en/guides/11_design_system.md` §6–§7
- **Enforced by machine:** `dart tools/arch_check/check.dart` rule **R7** blocks the build on any bare sizing extension in a file importing `core_responsive` (Gate 1 of `pr_quality_check.yml`). The scale-policy and window-class rules are review-held

---

## Design System (core_base_ui)

- **Colors:** `context.colors.textPrimary`, `context.colors.surface`, `context.colors.primary` — auto-switch Light/Dark
- **Typography:** `AppTextStyles.bodyMediumStyle(context)` — already scaled (`context.sp`, following `textScaleBounds`: down-only by default, so it shrinks below the design width and never grows past it); do **not** re-apply `context.sp()` at the call site
- **Spacing:** `AppSpacing.xs(context)`, `.sm(context)`, `.md(context)`, `.lg(context)`, `.xl(context)` (scaled with `w`); `H` variants (`lgH`) scale with `h`
- **Radius:** `AppRadius.sm(context)`, `.md(context)`, `.circular(context)` (scaled with `r`); `AppRadius.smRadius(context)` for `BorderRadius` objects
- **All three take `BuildContext`** — they are methods, not getters. Numbers live in their `raw*` constants: edit `raw*`, never the accessor
- **Never double-scale:** `AppSpacing.lg(context)` is final. `context.w(AppSpacing.lg(context))` scales twice
- Full configuration guide (change palette, font, spacing scale, design size, scale policy, adaptive layouts): `docs/en/guides/11_design_system.md`
- **Gradients/Shadows:** `AppGradients`, `AppShadows`
- **FORBIDDEN:** Hard-coding colors, font sizes, spacings, border radii directly in widgets

---

## Storage System (core_storage)

### Dual-Layer Security

1. **Layer 1 (Software):** AES-256-CBC with per-device Master Key + random IV per write
2. **Layer 2 (Hardware):** Apple Keychain / Android KeyStore via `flutter_secure_storage`

### Ownership Rule (CRITICAL)

`core_storage` ships the **mechanism only**. It defines **no keys and no presets** — there is no
`StorageValuePresets`, and `core_common` has no `StorageKeyConstants`. A single shared object
holding every domain's keys would let any injector read and write another feature's data.

**Every consumer declares and owns its own `StorageValue`**, keyed by constants living in that
package's `utils/` folder. Isolation is enforced by the dependency graph — a package that does not
declare `data_auth` in its pubspec simply cannot reach `AuthStorageKeys`.

### Adding a New Storage Key

1. Add the key to the **owning package's** `utils/` keys class (create it if absent), e.g.
   `modules/auth/data/lib/src/utils/auth_storage_keys.dart`. Never put it in `core_common`.
2. In the owning class, inject `StorageManager` and declare a `late final StorageValue<T>`.
3. Register the owner as a **singleton** (`@singleton` / `@lazySingleton` / `@Singleton(as: IFoo)`)
   with `@PostConstruct(preResolve: true)` to hydrate at startup.
   **Never `@injectable` (factory)** — each injection would get an empty cache.
4. Use a `reviver` callback for an enum or a custom type (stored through its `toJson()`); primitives, `Map<String, dynamic>` and typed lists read back without one.
5. Run `dart run build_runner build --workspace`.

```dart
// modules/auth/data/lib/src/utils/auth_storage_keys.dart
class AuthStorageKeys {
  AuthStorageKeys._();
  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}

// modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);
  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );
  // … _authUser: StorageValue<Map<String, dynamic>> @ AuthStorageKeys.AUTH_USER, declared the same way

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }
}
```

**Storage types:** `StorageType.pref` (SharedPreferences — settings, flags) ·
`StorageType.secure` (encrypted — tokens, sensitive data).

### Usage

```dart
_token.value = 'abc';                  // Write (auto-encrypted, async to disk)
final t = _token.value;                // Read (instant from RAM, de-obfuscated)
_token.addListener(() { ... });        // Listen (ChangeNotifier)
_token.listen((val) { ... });          // Stream
await _token.readFromStorage();        // Hydrate cache from disk
```

---

## Database System (Package-Owned Drift + SQLite)

### Ownership Rule (CRITICAL)

`core_database` ships the **mechanism only** — it owns **no database, table or DAO**, and its DI module body is literally `init(gh) {}`. There is no `AppDatabase`.

**Why:** Drift resolves `@DriftDatabase(tables:, daos:)` at compile time, and a DAO must be `part of` its database library. One shared database therefore forces whichever package declares it to own *every* table — the same god-object coupling the storage rules forbid.

**Rule:** a package needing relational storage declares **its own database** next to its own tables and DAO. Reference: `modules/cache/data/lib/src/database/` → `cache_database.dart`, `tables/cache_entries_table.dart`, `dao/cache_entries_dao.dart`.

`core_database` supplies:

| Piece | Purpose |
|:------|:--------|
| `IDatabaseHandle<TDb extends GeneratedDatabase>` | Hands a package only the accessor it asks for, plus `transaction` |
| `IDatabaseMigration` | A package contributes its own upgrade/downgrade steps |
| `DatabaseMigrationRunner` | Sorts + replays contributed steps (ascending up, descending down) |
| `DatabaseConnectionFactory` / `DriftDatabaseOpener` | Background-isolate opening, corruption quarantine, `beforeOpen` pragmas |

**Accepted trade-off:** SQL cannot join across package boundaries — deliberate; crossing a bounded context belongs at the repository layer.

**Drift limits:** no `onDowngrade` callback (downgrade rides `onUpgrade` via `from`/`to`) — and a downgrade with no registered step for the version being left **throws** rather than silently stamping a lower `user_version`; no runtime table registration (a package cannot add a table to another package's database).

### When to Use What

| Need | Package |
|:-----|:--------|
| Tokens, flags, theme, locale (key-value) | `core_storage` mechanism, key owned by the consumer |
| Lists, relations, SQL queries, migrations | Your **own** Drift database, opened via `core_database` |

### Adding a New Table

1. Create the table class in **your package**, e.g. `modules/<module>/<layer>/lib/src/database/tables/`
2. Create the DAO as `part of` **your** database library (not someone else's)
3. Register table + DAO in **your** `@DriftDatabase` annotation
4. Bump your `schemaVersion` and contribute an `IDatabaseMigration` implementation registered **typed to your database**: `@LazySingleton(as: IDatabaseMigration<YourDatabase>)`. An untyped `as: IDatabaseMigration` registration is never collected — the database's module looks up exactly `IDatabaseMigration<YourDatabase>` (see `docs/en/guides/07_database.md` § 4). Your `@preResolve` open needs `@Order(1)`, as `modules/cache/data/lib/di/module.dart` has, so a step in your own package registers before the open runs; a step from another package must sit in an earlier DI group
5. Run `dart run build_runner build --workspace`
6. Add Local DataSource → Repository → UseCase following the cache sample. **DataSource returns a Model** (`CacheEntryModel`), never the Drift row type

> [!NOTE]
> The cache chain (`CacheEntries` → DAO → DataSource → Repository → 2 UseCases) is the **`cache` sample module** (`modules/cache/{domain,data}`) with no runtime consumer — it also serves as the database tests' fixture. `apps/mobile` composes it, `apps/admin` does not. Remove it with `dart tools/sample_cleanup/remove_sample.dart cache --apply`, not on the word of `unused_checker`.

---

## Networking (core_network)

### ApiClient (Dynamic Factory)

What ships — `platform/network/lib/di/register_module.dart` registers one client:

```dart
@module
abstract class RegisterModule {
  @lazySingleton
  Dio dio(ApiClient apiClient) => apiClient.createClient();
}
```

A second client is added the same way. **Example only — nothing in the repo registers it:**

```dart
@Named('public_api')
@lazySingleton
Dio publicDio(ApiClient apiClient) => apiClient.createClient(
  useDefaultInterceptors: false,
  interceptors: [LoggingInterceptor(tag: 'PublicAPI')],
);
```

### Interceptors Chain

Registration order in `ApiClient.createClient()` (`platform/network/lib/src/api_client.dart`):

1. **AuthInterceptor**: injects the Bearer token via `NetworkConfig.getToken` (the config reads it through `IAuthSessionGateway`, resolved with `getItOrNull` — `core_network` never touches storage, and a build with no auth module simply sends no token). Also sends the locale under the non-standard header key `language`
2. **RefreshTokenInterceptor**: added **only when `NetworkConfig.onRefreshToken != null`**; catches 401 and replays. Sits **before** Retry so a 401 is never retried with a dead token. `RefreshTokenHandler` serialises concurrent 401s behind one `Completer`, and marks a replayed request so `dio.fetch` re-entering the same interceptor cannot recurse. `login` and `refreshToken` carry `@Extra({NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false})` — a `401` from the refresh call would otherwise wait on its own refresh forever
3. **RetryInterceptor**: retries timeout/connection errors only (not HTTP status codes); honours the per-request `canRetry` extra; groups concurrent failures into a single retry dialog
4. **LoggingInterceptor**: JSON-formatted logs via `dynamic_logger`, `kDebugMode`-gated on **all three** hooks (including `onError`), with `Authorization`/`Cookie` headers and credential body fields (`password`, `token`, `access_token`, …) redacted

### SSL Certificate Pinning

- **Global:** `HttpOverrides.global` with `HttpSecurityPinningClient` (SPKI SHA-256), installed by `AppInitializer._setupHttpOverrides`
- **Dev:** SSL bypass for self-signed certs — **only in a debug build that explicitly declared `--flavor dev`** (`AppConfig.bypassesCertificateValidation`). A missing/unknown flavor is treated as prod (validation on, ERROR logged); `appFlavor` falls back to `dev` in debug, `prod` otherwise
- **Staging/Prod:** strict SPKI hash matching
- > [!CAUTION]
  > Pinning needs **two** things or it silently no-ops (the initializer logs an ERROR in each case):
  > 1. `SslPinningConfig` must be **registered in its own right** — GetIt does not resolve supertypes, so registering `NetworkConfigImpl as NetworkConfig` is not enough. `platform/app_shell/lib/di/network_binding_module.dart` binds it.
  > 2. `sslPinningHashes` must be **non-empty**. It currently returns `const []`, i.e. **pinning is off** until you fill it in. See the `openssl` recipe in `network_config_impl.dart`; pin at least two keys (leaf + backup) so cert rotation cannot lock every client out.

### Data Standardization

- `BaseEntity<T>`: Standard server response wrapper
- `PaginatedEntity<T>`: Pagination — items in `data` (JSON key `items`), page info in `meta: MetaPaginate` (`totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`)
- `BaseRequest`: Pagination params builder

---

## Fastlane CI/CD

CWD-independent — every lane resolves its paths from `apps/mobile/fastlane/`, so the repo root and `apps/mobile/` work alike. Run through Bundler, which loads the `firebase_app_distribution` plugin:

```bash
bundle install                       # once
# Android
bundle exec fastlane android build flavor:dev build_type:apk distribute_firebase:true
bundle exec fastlane android store version:1.2.0 build_number:45 track:internal

# iOS
bundle exec fastlane ios build flavor:dev distribute_store:true
bundle exec fastlane ios store version:1.2.0 build_number:45

# Cross-platform
bundle exec fastlane flutter flavor:dev version:1.2.0 build_number:45
bundle exec fastlane store version:1.2.0 build_number:45
```

`build_number:` empty or `auto` = automatic; otherwise a positive integer. CI secrets for release builds: `docs/en/operations/01_cicd.md` § 7.

Config: copy `apps/mobile/fastlane/Config.example.yaml` → `apps/mobile/fastlane/Config.yaml` (gitignored, not in the repo). Modules: `apps/mobile/fastlane/modules/` (helpers, android_lanes, ios_lanes, flutter_lanes).

---

## Shared Components Architecture

| Package | Contains | Key Rule |
|:--------|:---------|:---------|
| `core_base_ui` | Design tokens, themes, colors, fonts, images, icons, L10n | **Zero Flutter widgets.** Only global assets |
| `core_ui_kit` | All reusable widgets (atomic + business) | Lives in `platform/ui_kit`. Depends on `core_common`, `core_base_ui`, `core_responsive`, `provider_state_management` — never on a feature |

### Sharing Across Features

- **Pure UI widgets** (buttons, inputs) → `core_ui_kit`
- **Widgets with Feature B logic** → Widget Builder Interface via DI (declare in `core_di`, implement in owning feature)
- **Dialogs/BottomSheets** → Always separate widget classes (`*_dialog.dart`/`*_bottom_sheet.dart`), never inline

---

## Feature Removability

Deleting any `modules/*/feature` package must leave the app compiling and booting.

**`apps/mobile/lib/di/injection.dart` is the app shell's only intentional hard reference to features** — as the composition root it must name what it composes. Every other shell file resolves features through `core_di` contracts with `getAllOrEmpty` / `getItOrNull` fallbacks.

**To drop a feature**: remove it from every `apps/<id>/app_manifest.yaml` that composes it, then

```bash
dart tools/composer/composer.dart sync
flutter pub get && dart run build_runner build --workspace
```

`injection.dart`, `apps/mobile/pubspec.yaml`'s path deps and the root `workspace:` list are generated between `composer:managed` markers — never edit them by hand. `composer verify` is Gate 0 in CI.

**A type import defeats `getItOrNull`** — guarding the lookup is useless if the file still imports the feature for the type. When the shell needs something a feature owns, declare a contract in `core_di`:

| Contract | Replaces the shell's direct use of |
|:---------|:-----------------------------------|
| `IAppSplashScreen` | `SplashPage` from `feature_splash` in `main.dart` |
| `IAuthRefreshListenable` (`implements Listenable`) | `AuthProvider` as GoRouter's `refreshListenable` |
| `IAuthSessionState` + `AuthSessionFailure` | `AuthProvider`/`AuthErrorState`/`context.l10nAuth` in `NavigatorWrapperWidget` |
| `IAppTreeWrapper` | `ChangeNotifierProvider<AuthProvider>` in `app_material_wrapper.dart` |
| `IAuthSessionGateway` | `AuthLocalDataSource` + `RefreshTokenUseCase` in `network_config_impl.dart` |

Contracts in `core_di` stay state-management agnostic — `IAppTreeWrapper.wrap()` returns a plain `Widget`, so a Provider feature returns `ChangeNotifierProvider` and a BLoC feature `BlocProvider` without either forcing its package on the other. Prefer a plain Dart 3 `sealed class` over Freezed in `core_di` (see `AuthSessionFailure`) — `core_di` runs only injectable's codegen (its `module.module.dart`), no Freezed/`part`-file codegen, and a `part` on a contract would make every consumer wait on `build_runner`.

> [!NOTE]
> The shared widget library is **not** a removable feature, which is why it lives at `platform/ui_kit` as `core_ui_kit` rather than under `modules/*/feature/`. Everything remaining in `modules/*/feature/` is a genuinely removable product surface.

---

## Frequently-Violated Rules (Full List in AGENTS.md)

1. **Responsive sizing:** All UI dimensions go through `context.w/h/sp/r` from `core_responsive` — no raw doubles, and no bare `16.w` (no `num` extension exists). Reusable widgets in `core_ui_kit` use parameters as received (the caller scaled them) and scale only their own constants. R7 holds the bare-extension half only.
2. **Freezed BLoC events:** Private subclasses (`_HomeStarted`) via `part`/`part of`. `on<Event>` handlers must be async `(event, emit)` — never sync closure calling unawaited async.
3. **Dialogs/BottomSheets:** Always separate widget classes, never inline in `showDialog`/`showModalBottomSheet` builders.
4. **Naming:** `I` prefix reserved for interfaces. Data source dirs are `data_sources/` (not `datasources/`). Suffixes: `_page`, `_provider`, `_bloc`, `_usecase`, `_entity`, `_repository_impl`, etc.
5. **CLI tools** in `tools/` use `stdout.writeln`/`stderr.writeln`, **never** `print()`.
6. **No lint suppressions** — research proper migration for deprecation warnings.
7. **No PowerShell scripts** (`.ps1`) — Windows execution policy blocks them. Prefer a cross-platform `.dart` script (as `tools/workspace_setup/configure.dart` does); `.sh`/`.bat` only when Dart cannot do the job.
8. **BuildContext** must be passed directly from UI caller — don't use `NavigatorKeys.*.currentContext`.
9. **Never edit `app_router.dart`** to hardcode routes — register via DI contracts.
10. **Features must not edit `root_app.dart`** for delegates — use `IFeatureLocalization` DI.
11. **Error handling:** Use `ErrorHandler.handleError(e)` — never `AppFailure.fromException()`.
12. **No `throw` from Data layer to UI** — wrap in `Result.failure(AppFailure)`.
13. **Module generator** adds the new module to every `app_manifest.yaml` and then runs `dart tools/composer/composer.dart sync` itself, which regenerates the workspace list, each app's dependencies and `injection.dart`. Never hand-edit those three — they sit between `composer:managed` markers and CI Gate 0 fails on drift.
14. **Barrel files:** Run `dart tools/barrel_generator/generate.dart` after creating/renaming/deleting files — and **after** `gen-l10n` / `build_runner`, because it also exports generated files present on disk (`module.module.dart`, `lib/src/gen/**`; `core_base_ui`'s `src.dart` exports `gen/gen.dart`). An extra run before codegen is harmless; the last run must come after.
15. **Build runner flags:** plain `dart run build_runner build --workspace`. `--delete-conflicting-outputs` (short form `-d`) was removed from build_runner and is ignored with a warning — do not pass it.
16. **Flat workspace:** `resolution: workspace` at root `pubspec.yaml` only — no intermediate workspace nodes.
17. **Core never depends on features, data or product domain packages.** No `platform/*` may import or declare `feature_*`, `data_*` or `domain_*` — except the three approved `→ domain_core` edges: `provider_state_management → domain_core`, `bloc_state_management → domain_core`, `platform_kernel → domain_core`. `arch_check` R1 blocks any other edge (allow-list `_approvedUpwardEdges` in `tools/arch_check/check.dart`); a fourth needs that list and AGENTS.md updated together. Audit with `grep -E "^  (domain_|data_|feature_)" platform/*/pubspec.yaml` — it also prints `data_core → domain_core`, a data → domain edge from the data layer's foundation, which lives under `platform/`. Need a fallback widget in core? Define it in core (see `DefaultLoadingWidget`/`DefaultEmptyWidget`), never borrow from `core_ui_kit`.
18. **A package's constants live in its own `utils/` folder** — a package with no constants needs none (`arch_check` R4 flags a public `static const` outside `utils/`/`styles/`, and never asks for an empty folder). No shared cross-domain constants file. Route paths live in `lib/src/utils/*_path.dart` (not `routing/`); storage keys in `utils/*_storage_keys.dart`.
19. **Eager `@Singleton` must not depend on a later-registered type.** Modules initialize in the order listed in `injection.dart`; an eager singleton resolving a type from a module that runs later throws "not registered" at boot. Use `@LazySingleton` instead. Two live ordering constraints in this template: `shell` before `ui` (`ThemeProvider` injects `IThemeStorage`, which the shell registers), and `notifications` after the app's own registrations (`PushNotificationService` injects the app's `FirebaseOptions`). `flutter analyze` cannot catch this; verify in the generated files — `injection.config.dart` for the module order, the package's `lib/di/module.module.dart` for the type's registration and its `gh<Dep>()` calls.
20. **Declare every dependency explicitly.** Pub Workspaces share one `package_config.json`, so an undeclared package still compiles — until the package is extracted. Production imports belong in `dependencies`, never `dev_dependencies`. `dart tools/arch_check/check.dart` rule **R5** catches an import missing from `dependencies:` (a `dev_dependencies` entry does not count); `dart tools/unused_checker/check_unused_packages.dart` catches the reverse — declared but never imported.
21. **`getAll<T>()` throws when `T` is unregistered.** Use `getAllOrEmpty<T>()` for optional multi-instance contributions and `getItOrNull<T>()` + fallback for single ones — otherwise removing a feature crashes the app at boot — `IFeatureLocalization` is the usual casualty, and it takes `MaterialApp` construction down with it.
22. **GetIt does not resolve supertypes.** `Impl as InterfaceA` leaves `getIt<InterfaceB>()` unresolvable. Bind the second type through a `@module` — miss it and SSL pinning silently no-ops.
23. **Barrel generator deletes hand-written `export` lines.** Never hand-add an export to a barrel; put deliberate re-exports in a normal source file (see `platform/kernel/lib/src/error/failures.dart`).
24. **`flutter analyze` cannot see generated code** — `analysis_options.yaml` excludes `**.freezed.dart`, `**.g.dart`, `**.config.dart`, `**.module.dart`. A clean analyze does **not** mean the app builds. Always finish with a real `flutter build apk`. Moving `AppFailure` between packages broke `bloc_view_state.freezed.dart` while analyze stayed green.
25. **When a type used by generated code moves package, import its new home directly.** A `show`-limited re-export cannot carry Freezed companions like `$AppFailureCopyWith`.
26. **Domain depends on nothing.** `domain_core` has zero workspace deps and no `flutter`. Never re-add `core_common` to a domain package.
27. **Every package owns its own database** if it needs one; `core_database` is mechanism only. Never create a shared `AppDatabase`.
28. **Any feature must be removable.** `injection.dart` is the shell's only intentional hard reference to modules; everything else goes through `core_di` contracts. A type-level import defeats `getItOrNull` — an unresolved import fails at compile time, before any lookup runs — so declare a contract instead. **Enforced by arch_check R10** in `apps/*` (only `injection.dart` may import a module) and **R1** in `platform_app_shell`. R10 was added after `network_config_impl.dart` — then an app file, now in `platform_app_shell` — was found importing `data_auth` and `domain_auth`, which made the auth module unremovable while every document said otherwise.

---

## PR Review Checklist (full version: `docs/en/reference/04_review_checklist.md`)

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
- [ ] All sizing goes through `context.w/h/sp/r` (`core_responsive`) — `dart tools/arch_check/check.dart` R7 is clean
- [ ] Layout choices use the window size class (`context.adaptive` / `AdaptiveLayout`), not `Platform.is*` or a device check
- [ ] `core_di` contracts implemented under `modules/` (any layer) resolve with `getItOrNull` / `getAllOrEmpty` outside their own module — arch_check R8 is clean
- [ ] No app-shell file outside `injection.dart` imports a module package — arch_check R1 (`platform_app_shell`) and R10 (`apps/*`) are clean
- [ ] CLI tools use `stdout.writeln`/`stderr.writeln` (NOT `print()`)
- [ ] Missing modules handled with `getAllOrEmpty`/`getItOrNull` + fallbacks
- [ ] No `platform/*` imports or declares `feature_*`, `data_*` or `domain_*` outside the three approved `→ domain_core` edges — `arch_check` R1 is clean
- [ ] Package constants live in that package's `utils/` folder — no shared cross-domain constants file
- [ ] New `StorageValue` is owned by its consumer (keys in `utils/`), registered as a singleton with `@PostConstruct(preResolve: true)` — never `@injectable`
- [ ] No eager `@Singleton` depends on a type registered by a later module (module order in generated `injection.config.dart`; the type's `gh<Dep>()` calls in its package's `lib/di/module.module.dart`)
- [ ] Every used package is declared in `pubspec.yaml`, production deps in `dependencies` — `arch_check` R5 is clean; `dart tools/unused_checker/check_unused_packages.dart` shows no stale entry
- [ ] Optional contributions use `getAllOrEmpty` / `getItOrNull` — no bare `getAll`/`getIt` for a removable feature's type
- [ ] A second interface on the same impl is bound via `@module` (GetIt does not resolve supertypes)
- [ ] No hand-written `export` added to a barrel file
- [ ] Domain packages still declare zero `core_*` deps and no `flutter` — `grep -rn "package:flutter" modules/*/domain/lib` is empty
- [ ] New tables/DAOs live in the **owning package's** database, not a shared one; DataSource returns a Model, not a Drift row
- [ ] The feature is still removable — shell touches it only via `core_di` contracts
- [ ] **`flutter build apk --flavor dev --debug` passes** — a clean `flutter analyze` does not cover generated code (needs the gitignored Firebase files; see `docs/en/getting-started/01_setup.md` § 3)

---

## Workflow: Creating a New Module (Best Practice)

```bash
# 1. Create domain + data micro-packages:
dart tools/module_generator/generate.dart 2 payment
dart tools/module_generator/generate.dart 3 payment

# 2. Implement: Entities → Repository Interfaces → UseCases → Models → DataSources → RepositoryImpl

# 3. Generate DI / Freezed / JSON code:
dart run build_runner build --workspace

# 4. Generate barrel files — after build_runner, since barrels export generated files too:
dart tools/barrel_generator/generate.dart modules/payment/domain/lib
dart tools/barrel_generator/generate.dart modules/payment/data/lib

# 5. Create feature if needed:
dart tools/module_generator/generate.dart 1 payment "" 2 1

# 6. Verify — all four steps; analyze alone does not cover generated code:
dart run build_runner build --workspace
flutter analyze
cd modules/payment/data && flutter test && cd -   # only if the package has a test/ directory
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

The APK build needs the gitignored `firebase_options_<flavor>.dart` files in `apps/mobile/lib/firebase/` and `apps/mobile/android/app/src/<flavor>/google-services.json`; a fresh clone has neither — create them per `docs/en/getting-started/01_setup.md` § 3 (which also gives compile-only stubs for when you have no Firebase project).

---

## Workflow: Periodic Cleanup

```bash
dart tools/unused_checker/check_script.dart    # Find unused resources
dart tools/check_outdated.dart                 # Find outdated packages
dart tools/dependency_sync.dart                # Sync version catalog
dart tools/code_review/code_review.dart --all  # AI code review
```
