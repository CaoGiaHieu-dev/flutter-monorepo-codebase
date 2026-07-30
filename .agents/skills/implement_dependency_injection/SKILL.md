---
name: implement_dependency_injection
description: Declare, register, and wire Dependency Injection (DI) using the Injectable and GetIt libraries.
---

# 💉 Skill: Implement Dependency Injection (Implement Dependency Injection)

Use this skill when requested to: "register a new Service/Repository in DI", "inject a ViewModel/Provider", "fix a GetIt instance not found error", etc.

---

## 📋 Annotation Rules

1. **ViewModels / Feature Providers**:
   - **Must use `@injectable`** (factory registration) to instantiate a new object every time it is requested (prevents memory leaks by disposing of resources when the screen is closed).
   - **DO NOT USE** `@singleton` or `@lazySingleton` for feature view models or UI controllers.
2. **Global app controllers** (e.g. `AuthProvider`, `ThemeProvider`, `LanguageProvider`, `DeeplinkProvider`):
   - Allowed to use `@lazySingleton` / `@singleton`.
3. **Repositories / Services / UseCases**:
   - Use `@lazySingleton` (lazily instantiated and cached) or `@singleton`.
   - If registering an implementation class for an interface: `@LazySingleton(as: IMyRepository)`.

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

### Step 3: Register the Package Module in Host App (`app`)
*Note: The `module_generator` tool automates this step.*
1. Open `app/lib/di/injection.dart`.
2. Import the generated micro-package module (e.g., `import 'package:my_package/di/module.module.dart';`).
3. Add `ExternalModule(MyPackageModule)` into the **correct** constant list:

| List | When to use |
|------|-------------|
| `_coreModules` | Core infra **without** app-local interface deps (`CoreStorage`, `CoreNetwork`, `CoreDi`, …). Goes to `externalPackageModulesBefore`. |
| `_uiModules` | **`CoreBaseUiPackageModule` only** — depends on app-local `ILanguageStorage` / `IThemeStorage`. Goes to `externalPackageModulesAfter`. |
| `_domainModules` | `domain_*` micro-packages |
| `_dataModules` | `data_*` micro-packages |
| `_featureModules` | `feature_*` packages |
| `_otherModules` | State-management cores (`ProviderStateManagement`, `BlocStateManagement`) |

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

App-shell adapters (`LanguageStorageImpl`, `ThemeStorageImpl`, `NetworkConfigImpl`) are registered as local `@Singleton(as: …)` in `app/lib/di/` so they exist **before** `_uiModules` run.

### Step 4: Run Code Generation
Run the following command at the root of the monorepo to regenerate the DI graph:
```bash
dart run build_runner build -d --workspace
```
