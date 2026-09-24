---
name: implement_action_handler
description: Guide for declaring cross-feature UI Action Handler interfaces in the owning module's API package (<id>_api) and implementing them in the owning feature.
---

# 🎛️ Skill: Implement Cross-Feature Action Handler

Use this skill when requested to: "call logout from settings without importing auth", "trigger Feature B UI action from Feature A", "add an Action Handler", etc.

---

## 📋 When to Use

| Need | Prefer |
| :--- | :--- |
| Navigate to another feature's screen | **Navigator** (`AuthNavigator` in `auth_api`, `HomeNavigator` in `home_api`) |
| Shared business logic without UI | **Domain UseCase** |
| Observe the session | **Agnostic stream** (`ISessionStatusStream`, `ISessionState` in `core_di`) |
| Inject a widget/scope from another feature | **`IAppTreeWrapper`** (`core_di`) or a widget-builder interface in the owner's `<id>_api` |
| Trigger Feature B Provider / dialog / UI method from Feature A (e.g. Settings → logout in Auth) | **Action Handler** (`I*ActionHandler`) |

**Sample in this template:** `feature_settings` depends on `auth_api` and calls `getItOrNull<IAuthActionHandler>()?.logout(context)` — Settings and Auth remain separate packages, and with no auth feature the logout row is simply not offered (`remove_sample auth` keeps `auth_api` while Settings imports it).

---

## 📋 Detailed Steps

### Step 1: Declare the Interface in the owning module's API package
Create `modules/<owner>/api/lib/src/actions/i_<feature>_action_handler.dart` (package `<owner>_api`, foundation + Flutter dependencies only — `arch_check` R3; create the package first if the module has none: `docs/en/guides/12_module_isolation.md` § 7). `core_di` is for product-neutral contracts only:
```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  void logout(BuildContext context);
}
```
Do **not** hand-edit `modules/<owner>/api/lib/src/actions/actions.dart` — it is a generated barrel, and the generator deletes hand-written `export` lines. Running the barrel generator (Step 4) adds the new file.

### Step 2: Implement in the Owning Feature
Create `modules/<owner>/feature/lib/src/handlers/<feature>_action_handler_impl.dart`:
```dart
import 'package:auth_api/auth_api.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';

@Injectable(as: IAuthActionHandler)
class AuthActionHandlerImpl implements IAuthActionHandler {
  @override
  void logout(BuildContext context) {
    context.read<AuthProvider>().logout();
  }
}
```

### Step 3: Call from the Consuming Feature
```dart
getItOrNull<IAuthActionHandler>()?.logout(context);
```
The consumer lists `<owner>_api` in its `dependencies:` and MUST NOT import the owning feature package.

> [!CAUTION]
> **Prefer `getItOrNull` over `getIt` for cross-feature calls.** The app must still run when
> any feature package is deleted, and the handler's implementation lives in the *owning*
> feature. `getIt<T>()` throws when that feature is gone; `getItOrNull<T>()?` degrades to a
> no-op.
>
> If the action must visibly do *something* when the owner is absent, branch on the null and
> show a fallback rather than letting the widget throw.

### Step 4: Barrels + Code Gen
```bash
dart tools/barrel_generator/generate.dart modules/<owner>/api/lib     # so the feature can import the new interface
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<owner>/feature/lib
```
The final barrel pass must come **after** `build_runner`, because barrels also export
generated files present on disk. The API package has no generated files, so its one pass
before codegen is enough — it lets the owning feature's `@Injectable(as: I…ActionHandler)`
resolve the new interface through the `<owner>_api` barrel.

---

## 🏷️ Naming Rules

| Kind | File | Class |
| :--- | :--- | :--- |
| Interface | `i_<name>_action_handler.dart` | `I*ActionHandler` |
| Implementation | `<name>_action_handler_impl.dart` | `*ActionHandlerImpl` |

**ABSOLUTELY FORBIDDEN**: Naming an implementation with the `I` prefix (e.g., `IAuthActionHandlerImpl` as a class name for the interface, or renaming navigator impls to `IAuthNavigator`).

---

## 🔗 Related

- `docs/{en,vi}/guides/10_cross_feature.md` — all six cross-feature communication models
- `implement_navigation_route` — use a Navigator when the action is pure navigation
- `implement_dependency_injection` — `getIt` vs `getItOrNull` vs `getAllOrEmpty`
