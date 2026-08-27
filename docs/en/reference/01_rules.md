# Architecture Rules

**This file answers:** what is allowed, what is forbidden, and *why* — for every layer of the monorepo.

**After reading you can:** settle any "is this legal?" argument in review, and know which command proves the answer.

This is the **lookup** copy. For step-by-step instructions see [`../guides/`](../guides/); for the reasoning behind the layering see [`../architecture/01_overview.md`](../architecture/01_overview.md).

> [!NOTE]
> The authoritative source is [`.agents/AGENTS.md`](../../../.agents/AGENTS.md). This page mirrors it and adds the verification command for each rule.

---

## 1. Dependency direction

**Rule.** Dependencies point inward. `Feature → Domain ← Data`, with `core/*` as infrastructure underneath. **No `core/*` package may depend on `feature_*` or `data_*`** — neither by import nor by a `pubspec.yaml` entry.

**Why.** Core is the innermost infrastructure ring. If core reaches upward, the ring closes into a cycle and nothing above it can be removed or reused independently.

**Domain sits at the centre and depends on nothing.** Verified state:

| Package | Workspace dependencies | Flutter SDK |
|---|---|---|
| `domain_core` | **none** | no |
| `domain_auth` | `domain_core` | no |
| `domain_language` | `domain_core` | no |

### Approved upward exceptions

Only these four exist. Adding a fifth requires updating `AGENTS.md` and the allow-list in `tools/arch_check/check.dart` — the checker fails the build otherwise.

| Exception | Reason |
|---|---|
| `core_di → domain_auth` | Agnostic stream contracts expose concrete entity types (`UserEntity`); generics would erase type-safety. See [rule 15](#15-cross-feature-communication). |
| `provider_state_management → domain_core` | Needs `Result<T>` and `PaginatedEntity<T>` for `executeOperation` / `PaginatedViewWidget`. |
| `core_common → domain_core` | `ErrorHandler` produces `AppFailure`, which now lives in `domain_core`. Core→Domain is the *correct* Clean Architecture direction. |
| `bloc_state_management → domain_core` | `BlocViewState.error` carries `AppFailure` directly, so the base state type needs it. |

> [!NOTE]
> `core_ui_kit → provider_state_management` is correct. The reverse is forbidden — it previously created a cycle inside the core ring, which is why `provider_state_management` ships its own `DefaultLoadingWidget` / `DefaultEmptyWidget` in `lib/src/base_view/default_state_widgets.dart` instead of borrowing from `core_ui_kit`.

**Verify**

```bash
# core must never name a feature or data package
grep -rn "package:feature_\|package:data_" packages/core/*/lib
grep -l "feature_\|data_" packages/core/*/pubspec.yaml

# domain must never touch Flutter
grep -rn "package:flutter" packages/domain/*/lib
```

All four commands must return nothing.

❌ **Wrong** — a core package borrowing a feature widget:
```dart
// packages/core/provider_state_management/lib/src/base_view/base_view_widget.dart
import 'package:feature_auth/feature_auth.dart';   // core → feature
```

✅ **Right** — define the fallback inside the core package:
```dart
import 'default_state_widgets.dart';   // ships with the package
```

---

## 2. Explicit dependency declaration

**Rule.** Every `package:` import used under `lib/` must have a matching entry in that package's `pubspec.yaml`. Production imports go in `dependencies`, never `dev_dependencies`. Remove entries that are no longer used.

**Why.** Pub Workspaces share one `package_config.json`, so an undeclared import **still compiles locally**. The breakage only appears when the package is extracted or published — and stale entries create phantom coupling that hides real layering violations.

**Verify**

```bash
dart tools/unused_checker/check_unused_packages.dart
```

---

## 3. Mandatory `utils/` folder

**Rule.** Every package, at every layer, keeps its own constants in a `utils/` folder inside that package. A constant has exactly **one** owner. Creating a shared cross-domain constants file is forbidden.

**Why.** A shared constants file lets any package read — and typo — another domain's keys. Two such god-objects (`StorageKeyConstants`, `ApiConstants`) were deleted for this reason.

Applied conventions:

| Kind | Location | Real example |
|---|---|---|
| Route paths | `lib/src/utils/<feature>_path.dart` | `packages/features/home/lib/src/utils/home_path.dart` |
| Storage keys | `lib/src/utils/<owner>_storage_keys.dart` | `packages/data/auth/lib/src/utils/auth_storage_keys.dart` |
| API endpoints | `lib/src/utils/<owner>_api_constants.dart` | `packages/data/auth/lib/src/utils/auth_api_constants.dart` |

Constant classes use a private constructor and `UPPER_SNAKE_CASE` members:

```dart
// packages/data/auth/lib/src/utils/auth_storage_keys.dart
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

> [!NOTE]
> **Approved exception — design tokens.** `AppSpacing`, `AppRadius`, `AppTextStyles`, `AppGradients`, `AppShadows` stay in `packages/core/base_ui/lib/src/styles/`, *not* in `utils/`.
>
> They are the public API of the design system, and `styles/` carries that meaning where `utils/` reads as "miscellaneous". Moving them would break every doc reference for no gain. **Do not "fix" this in a future audit.**

`core_common` keeps only genuinely global values — currently `ApiStatusConstants` (HTTP status codes) and `EnvConstants` (`String.fromEnvironment` wiring), both under `lib/src/utils/`.

---

## 4. Package-owned storage

**Rule.** `core_storage` provides the **mechanism only** and defines zero keys. Each consumer injects `StorageManager`, declares its own `StorageValue<T>`, and keys it from its own `utils/` class.

**Why.** The deleted `StorageValuePresets` was a single `@Singleton` holding every domain's keys — anyone who injected it could read or clear another feature's data.

Registration is **mandatory as a singleton** plus `@PostConstruct(preResolve: true)`:

```dart
// packages/data/auth/lib/src/data_sources/local/auth_local_data_source.dart
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
| `LanguageRepositoryImpl` | `data_language` | `locale` | pref |
| `ThemeStorageImpl` | app shell | `themeMode` | pref |
| `LanguageStorageImpl` | app shell | `locale` | pref |
| `AppBootStorage` | app shell | `viewed_onboard` | pref |

Full walkthrough: [`../guides/06_storage.md`](../guides/06_storage.md).

---

## 5. DI registration order

**Rule.** An eager `@Singleton` must never depend on a type registered by a module that initialises **later** in `configureDependencies()`. Use `@LazySingleton` when the dependency comes from a later module.

**Why.** GetIt throws `"<Type> is not registered"` during boot. Modules initialise in the order declared in `app/lib/di/injection.dart`: `externalPackageModulesBefore` → app-local registrations → `externalPackageModulesAfter`.

Reference: `NetworkConfigImpl` is `@LazySingleton(as: NetworkConfig)` because it injects `AuthLocalDataSource` from `data_auth`, whose module runs after the app-local block. Its only consumer (`ApiClient`) is itself lazy, so deferring is safe.

> [!CAUTION]
> **`flutter analyze` cannot detect this class of bug.** It only appears at runtime, on a real boot.

**Verify** — after changing any DI annotation or constructor, read the generated file and confirm each eager registration's dependencies appear *earlier* in `init()`:

```bash
dart run build_runner build -d --workspace
grep -n "PackageModule().init\|gh.singleton<" app/lib/di/injection.config.dart
```

`@PostConstruct(preResolve: true)` on a `@lazySingleton` is awaited during module init and re-registered as a plain sync lazy singleton, so later `gh<T>()` sync lookups are safe.

---

## 6. Feature boundaries and removability

**Rule.** One feature = one bounded UI concern. Feature A must never import feature B — no exception; shared widgets come from `core_ui_kit`, which is core. **The app must still build and run when any feature package is removed.**

**Why.** A template whose features cannot be deleted is not a template. Removability is also the practical proof that the boundaries are real.

Everything the shell consumes at runtime resolves through a `core_di` contract with a fallback:

| Lookup | Behaviour when nothing is registered |
|---|---|
| `getAllOrEmpty<T>()` | empty list |
| `getItOrNull<T>()` | `null` |
| `getAll<T>()` | **throws** — do not use for optional contributions |

> [!WARNING]
> `getAll<T>()` and `getAllOrEmpty<T>()` differ exactly here. `getAll` throwing on an unregistered type once crashed the app during `MaterialApp` construction when no feature contributed an `IFeatureLocalization`.

**Removing a feature** — the four steps documented in `app/lib/di/injection.dart`:

1. its `ExternalModule(...)` entry and the matching import in `app/lib/di/injection.dart`;
2. its `feature_x:` entry in `app/pubspec.yaml`;
3. its path in the root `pubspec.yaml` `workspace:` list;
4. `flutter pub get` + `dart run build_runner build -d --workspace`.

The `injection.dart` imports are the shell's **only intentional hard reference** to features — as the composition root it must name what it composes. Every other consumer goes through `core_di`.

**Verify**

```bash
# after removing a feature
flutter pub get && dart analyze app
```

---

## 7. Domain is pure Dart

**Rule.** No `package:flutter/...`, `package:dio/...`, `package:retrofit/...`, or any UI/network library in `packages/domain/*`. UI concepts must be translated into primitives or enums.

**Why.** Domain is the one layer that should outlive framework choices. It is now enforced at the package-graph level too: no domain `pubspec.yaml` declares the Flutter SDK, and `domain_core` has zero workspace dependencies.

Components: `entities/` (Freezed, with `const Class._()`), `params/`, `repositories/` (interfaces), `usecases/` (`@injectable`, returning `Result<T>`), `utils/`.

---

## 8. Data layer

**Rule.**

- Directories are `data_sources/remote/` and `data_sources/local/` — **snake_case, plural `data_sources`**, never `datasources/`.
- `RepositoryImpl` extends `IBaseRepository` and wraps work in `execute()` (async) or `executeSync()`.
- Errors convert through `ErrorHandler.handleError(e)`. **Never** `AppFailure.fromException()`.
- **DataSources return Models, never Entities** — and never a class generated by Drift.
- Never `throw` from Data to UI; return `Result.failure(AppFailure)`.

**Why the Model rule.** Returning a Drift row class leaks the persistence library into every consumer of the package. `CacheEntryModel` (`packages/data/core/lib/src/models/cache_entry_model.dart`) exists purely as that boundary.

---

## 9. Freezed, BLoC and state

**Rule.**

- BLoC event subclasses are **private**: `const factory HomeEvent.started() = _HomeStarted;`
- Use `part` / `part of`: `_bloc.dart` declares `part '_event.dart';` and `part '_bloc.freezed.dart';`
- Event handlers take both parameters and are `async`: `Future<void> _onStarted(_HomeStarted event, Emitter<...> emit) async`

> [!CAUTION]
> A synchronous closure that calls async work without awaiting produces `emit was called after an event handler completed normally` — the handler returns immediately, then the async work emits into a closed sink.

**Two `ViewState` types exist and are different.** The BLoC one was renamed to avoid a name collision:

| | `ViewState` (Provider) | `BlocViewState<T>` (BLoC) |
|---|---|---|
| File | `provider_state_management/lib/src/base/view_state_model.dart` | `bloc_state_management/lib/src/bloc_view_state.dart` |
| Generic | no | yes |
| Variants | 5 (incl. `loadingMore`) | 4 |
| Error | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — required |
| Holds data | no (data lives in `ViewStateModel<T>`) | yes |

> [!WARNING]
> `BaseBloc` / `BaseCubit` are currently **empty extension points**. There is no BLoC equivalent of `executeOperation` — on the BLoC branch you unwrap `Result`, map `AppFailure`, and set loading yourself in every handler. The two branches are not at parity.

---

## 10. Controller lifetime

**Rule.** Screen-scoped controllers are `@injectable` (factory). Global controllers may be `@lazySingleton`. Controllers are instantiated **at the route**, in the `build` of `*_route_module.dart`.

**Why.** A `@singleton` ViewModel is held by GetIt forever, so popping the screen leaks it and the next visit reuses stale state.

> [!CAUTION]
> If the route already wraps the page in `BlocProvider` / `ChangeNotifierProvider`, the `Page` widget **must not** wrap itself again. Double-wrapping builds two controllers; the one the UI reads is not the one the route created.

---

## 11. Routing

**Rule.** Never edit `app/lib/presentation/navigation/app_router.dart` to add a route. Register a `core_di` contract from the feature instead:

| Contract | Purpose | Ordered? |
|---|---|---|
| `IFeatureRouteModule` | stack routes under the app `ShellRoute` | no (path match) |
| `IDashboardTabModule` | one bottom-nav tab + one `StatefulShellBranch` | **yes** — `order` must match nav index |
| `IAppEntryLocation` | cold-start `initialLocation` | n/a |
| `DashboardRouteModule` | dashboard chrome only | `feature_dashboard` only |

Cross-feature navigation goes through a Navigator interface declared in `core_di` and implemented in the owning feature's `routing/`. Hardcoding a path or calling `GoRouter.of(context).go(...)` into another feature is forbidden. **`BuildContext` is passed directly from the UI caller** — do not reach for `NavigatorKeys.*.currentContext`.

`feature_dashboard` is **chrome only**: it must not import tab features, own tab pages, hardcode a `BottomNavigationBarItem` list, or register `IDashboardTabModule` itself.

---

## 12. Responsive UI

**Rule.** Every dimension — width, height, padding, margin, font size, border radius — uses `flutter_screenutil`: `.w`, `.h`, `.sp`, `.r`. Raw doubles in layout are forbidden.

**Reusable widgets take raw, unscaled values and must not scale internally.** Scaling is the caller's job.

❌ **Wrong** — this shipped, and it silently discarded the caller's value:
```dart
// packages/core/ui_kit/lib/navigation/app_bar_custom.dart
@override
double? get leadingWidth => 64.w;   // overrides super.leadingWidth forever
```

✅ **Right** — accept the constructor parameter, let the caller scale it.

---

## 13. Localization

**Rule.** All user-facing text is translated — hardcoded UI strings are forbidden. Each feature owns its `.arb` files in `assets/language/` and registers `IFeatureLocalization` via DI. Access through the feature extension: `context.l10nAuth.someKey`.

Features **must not** edit `app/lib/presentation/root_app.dart` to add delegates; the shell collects them with `getAllOrEmpty<IFeatureLocalization>()`.

Global strings live in `core_base_ui`. `core_ui_kit` **must not** define its own `.arb` files — it uses `core_base_ui`'s.

---

## 14. Dialogs and bottom sheets

**Rule.** Every dialog and bottom sheet is its own widget class in its own file. Writing an inline widget tree inside `showDialog()` / `showModalBottomSheet()` is forbidden.

Suffixes: `_dialog.dart` → `Dialog`, `_bottom_sheet.dart` → `BottomSheet`. Real examples: `packages/core/ui_kit/lib/dialogs/error_dialog.dart`, `retry_dialog.dart`, `warning_dialog.dart`.

---

## 15. Cross-feature communication

**Rule.** Six sanctioned models; pick by what you are sharing.

| # | Need | Mechanism |
|---|---|---|
| 1 | Business logic | shared Domain UseCase |
| 2 | Infrastructure | core service (`core_storage`, `core_network`, …) |
| 3 | Cross-feature state | agnostic `Stream` / `ValueListenable` interface on `core_di`, dual-registered |
| 4 | Pure UI prefs (theme, locale) | bypass Domain → `core_di` storage interface → app-shell impl |
| 5 | Embedding another feature's widget | builder interface on `core_di` |
| 6 | Cross-feature UI action | `I*ActionHandler` in `core_di/src/actions/` |

**Dual registration** (model 3): the owning feature registers the concrete class as `@singleton`, then binds the interface via a DI `@module`:

```dart
@module
abstract class AuthModule {
  IAuthStatusStream bind(AuthStatusStreamImpl impl) => impl;
}
```

This lets the owner inject the concrete type through its constructor while every other feature sees only the interface.

> [!NOTE]
> GetIt resolves by **exact type**, never by supertype. Registering `Impl as InterfaceA` does *not* make `getIt<InterfaceB>()` work even when `InterfaceA implements InterfaceB` — bind each one explicitly. See `app/lib/di/network_binding_module.dart`, where `SslPinningConfig` needs its own binding despite `NetworkConfig implements SslPinningConfig`.

Do not use Action Handlers for plain navigation (use a Navigator) or for Domain-only logic (use a UseCase).

---

## 16. Tooling and code hygiene

| Rule | Detail |
|---|---|
| No `print()` in `tools/` | use `stdout.writeln()` / `stderr.writeln()` |
| No lint suppressions | `// ignore_for_file: ...` is forbidden; research the real migration |
| No PowerShell scripts | `.ps1` is forbidden (Windows execution policy); use `.dart` |
| Never hand-edit generated files | `.g.dart`, `.freezed.dart`, `.module.dart`, `.config.dart` |
| Versions come from the catalog | edit `pubspec_dependencies.yaml`, then run the sync tool |
| Re-run the barrel generator | after adding, renaming, or deleting any file under `lib/` |
| Handle deprecations properly | research the migration; quick-fixes and ignores are forbidden |

---

## Rule → command cheat sheet

| Check | Command |
|---|---|
| Unused / undeclared dependencies | `dart tools/unused_checker/check_unused_packages.dart` |
| Version catalog drift | `dart tools/dependency_sync.dart --check` |
| Unused assets, files, translations | `dart tools/unused_checker/check_script.dart` |
| Static analysis | `flutter analyze` |
| Codegen up to date | `dart run build_runner build -d --workspace` |
| DI order safety | read `app/lib/di/injection.config.dart` |
| core ⇏ feature | `grep -rn "package:feature_" packages/core/*/lib` |
| Domain purity | `grep -rn "package:flutter" packages/domain/*/lib` |

---

**Next:** [`02_naming.md`](02_naming.md) · [`03_tooling.md`](03_tooling.md) · [`04_review_checklist.md`](04_review_checklist.md)
