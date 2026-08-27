---
name: implement_dependency_injection
description: Declare, register, and wire Dependency Injection (DI) using the Injectable and GetIt libraries.
---

# 💉 Skill: Implement Dependency Injection (Implement Dependency Injection)

Use this skill when requested to: "register a new Service/Repository in DI", "inject a ViewModel/Provider", "fix a GetIt instance not found error", etc.

---

## 📋 Annotation Rules

1. **ViewModels / Feature Providers / Blocs**:
   - **Must use `@injectable`** (factory registration) to instantiate a new object every time it is requested (prevents memory leaks by disposing of resources when the screen is closed).
   - **DO NOT USE** `@singleton` or `@lazySingleton` for feature view models or UI controllers.
2. **Global app controllers** (e.g. `AuthProvider`, `ThemeProvider`, `LanguageProvider`, `DeeplinkProvider`):
   - Allowed to use `@lazySingleton` / `@singleton`.
3. **Repositories / Services / UseCases**:
   - Use `@lazySingleton` (lazily instantiated and cached) or `@singleton`.
   - If registering an implementation class for an interface: `@LazySingleton(as: IMyRepository)`.
4. **Storage owners** (a class holding `StorageValue` fields):
   - **Must** be a singleton + `@PostConstruct(preResolve: true)`. `@injectable` would hand
     out fresh instances with an empty RAM cache. See `implement_package_storage`.

---

## ⚠️ Trap 1 — eager `@Singleton` that depends on a later module

`@Singleton` is **eager**: GetIt constructs it while the owning module registers. If its
constructor needs a type registered by a module that runs *later* in
`configureDependencies()`, boot throws `... is not registered inside GetIt`.

Real case: `NetworkConfigImpl` needs `AuthLocalDataSource` (from `data_auth`, an
`externalPackageModulesAfter` module) while the app-local block runs earlier. The fix is to
defer construction:

```dart
// app/lib/di/network_config_impl.dart
@LazySingleton(as: NetworkConfig)   // NOT @Singleton
class NetworkConfigImpl implements NetworkConfig { ... }
```

Deferring is safe whenever every consumer is itself lazy — nothing resolves it during startup.

> [!CAUTION]
> **`flutter analyze` cannot catch this** — it is a runtime ordering fault, not a type error.
> Verify by reading the generated graph after `build_runner`:
> ```bash
> grep -n "YourType" app/lib/di/injection.config.dart
> ```
> Check that everything your eager singleton needs is registered on an *earlier* line.

## ⚠️ Trap 2 — GetIt does not resolve supertypes

GetIt looks up the **exact** type a binding was registered under; it never walks the
supertype chain. Registering `@LazySingleton(as: NetworkConfig)` therefore leaves
`getItOrNull<SslPinningConfig>()` returning `null` even though `NetworkConfig implements
SslPinningConfig` — which silently disabled certificate pinning until it was fixed.

Bind the second type explicitly with a `@module` (`app/lib/di/network_binding_module.dart`):

```dart
@module
abstract class NetworkBindingModule {
  @lazySingleton
  SslPinningConfig bindSslPinningConfig(NetworkConfig config) => config;
}
```

Typing the parameter as `NetworkConfig` makes the upcast compiler-checked — no `as` needed.
The same dual-registration pattern binds `IAuthStatusStream`, `IAuthSessionState` and
`IAuthRefreshListenable` in `packages/features/auth/lib/di/module.dart`.

### Third-party SDKs go through `@module` too

Never call `SomeSdk.instance` inside a repository — it hides the dependency from the
container and leaves no seam for a fake. Register it, then take it as a constructor
parameter. `packages/data/auth/lib/di/register_module.dart`:

```dart
@module
abstract class RegisterModule {
  @preResolve
  Future<GoogleSignIn> get googleSignIn async {
    final instance = GoogleSignIn.instance;
    await GoogleSignIn.instance.initialize();
    return instance;
  }

  @lazySingleton
  FirebaseAuth get firebaseAuth => FirebaseAuth.instance;

  @lazySingleton
  FirebaseFirestore get firestore => FirebaseFirestore.instance;

  @lazySingleton
  FacebookAuth get facebookAuth => FacebookAuth.instance;
}
```

Use `@preResolve` only for an SDK that needs async initialisation; the rest are plain
`@lazySingleton` getters.

## ⚠️ Trap 3 — `getAll` throws when nothing is registered

`core_common` exposes four lookups; picking the wrong one breaks feature removal:

| Function | Missing registration |
| :--- | :--- |
| `getIt<T>()` | **throws** |
| `getItOrNull<T>()` | returns `null` |
| `getAll<T>()` | **throws** |
| `getAllOrEmpty<T>()` | returns empty iterable |

Anything the **app shell** consumes from a feature must use the `…OrNull` / `…OrEmpty`
variants plus a fallback, so deleting that feature leaves the app bootable.

---

## 📋 Steps for setting up DI in a New Package

### Step 1: Initialize Micro-package DI Module
Inside the sub-package (`packages/<layer>/<package_name>`), create the file `lib/di/module.dart`:
```dart
import 'package:injectable/injectable.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}
```

### Step 2: Annotate Classes for Injection
```dart
@lazySingleton
class MyService { ... }

@injectable
class MyProvider extends BaseProvider<MyEntity> {
  final MyService _service;
  MyProvider(this._service); // Injected via constructor
}
```

Constructor injection only — **never** call `getIt<T>()` inside a ViewModel, Repository or
UseCase.

### Step 3: Register the Package Module in Host App (`app`)
*Note: The `module_generator` tool automates this step.*
1. Open `app/lib/di/injection.dart`.
2. Import the generated micro-package module (e.g., `import 'package:my_package/di/module.module.dart';`).
3. Add `ExternalModule(MyPackageModule)` into the **correct** constant list:

| List | Phase | When to use |
|------|-------|-------------|
| `_coreModules` | `externalPackageModulesBefore` | Core infra **without** app-local interface deps (`CoreCommon`, `CoreNetwork`, `CoreNotifications`, `CoreStorage`, `CoreDatabase`, `CoreDi`) |
| `_uiModules` | after | **`CoreBaseUiPackageModule` only** — depends on app-local `ILanguageStorage` / `IThemeStorage` |
| `_domainModules` | after | `domain_*` micro-packages |
| `_dataModules` | after | `data_*` micro-packages |
| `_featureModules` | after | `feature_*` packages |
| `_otherModules` | after | State-management cores (`ProviderStateManagement`, `BlocStateManagement`) |

```dart
@InjectableInit(
  externalPackageModulesBefore: [..._coreModules],
  externalPackageModulesAfter: [
    ..._uiModules,
    ..._domainModules,
    ..._dataModules,
    ..._featureModules,
    ..._otherModules,
  ],
)
```

**ABSOLUTELY FORBIDDEN:**
- Putting `CoreBaseUiPackageModule` in `_coreModules` / `externalPackageModulesBefore` (Language/Theme providers will fail to resolve storage interfaces).
- Inlining `ExternalModule(...)` directly inside `@InjectableInit` arrays — always use the named lists + spread.

App-shell adapters (`LanguageStorageImpl`, `ThemeStorageImpl`, `AppBootStorage`,
`NetworkConfigImpl`, `NetworkBindingModule`) are registered as local bindings in
`app/lib/di/` so they exist **before** `_uiModules` run.

### Step 3b: Ordering when a module opens a database

A module that opens a database with `@preResolve` runs its collected `IDatabaseMigration`
steps **during its own initialisation**, so any package contributing a step must be
registered before it. `data_core` opens `CacheDatabase` inside `_dataModules`, which means a
migration contributed by a *feature* would not be seen — features initialise afterwards.

Nothing in the template hits this yet. When it does: move that feature's module ahead of the
module owning the database, or give the feature its own database. `core_database` itself
registers nothing — it is mechanism only and owns no database.

### Step 4: Run Code Generation
Run the following command at the root of the monorepo to regenerate the DI graph:
```bash
dart run build_runner build -d --workspace
```
Then **hot restart** — new DI registrations are not applied by hot reload.

### Step 5: Declare the dependency explicitly

Pub Workspaces share one `package_config.json`, so a package you *use* but never *declare*
still compiles — and breaks the moment the package is extracted. Every import must have a
matching `pubspec.yaml` entry, in `dependencies` (not `dev_dependencies`) when production
code uses it. Verify with:

```bash
dart tools/unused_checker/check_unused_packages.dart
```

---

## 🔗 Related

- `docs/{en,vi}/guides/05_di.md` — the full DI guide
- `docs/{en,vi}/architecture/06_app_shell.md` — boot sequence and module assembly
- `implement_package_storage` — why storage owners must be singletons
