---
name: implement_action_handler
description: Guide for declaring cross-feature UI Action Handler interfaces in core_di and implementing them in the owning feature.
---

# 🎛️ Skill: Implement Cross-Feature Action Handler

Use this skill when requested to: "call logout from settings without importing auth", "trigger Feature B UI action from Feature A", "add an Action Handler", etc.

---

## 📋 When to Use

| Need | Prefer |
| :--- | :--- |
| Navigate to another feature's screen | **Navigator** (`AuthNavigator`, `HomeNavigator`) |
| Shared business logic without UI | **Domain UseCase** |
| Observe another feature's state | **Agnostic stream** (`IAuthStatusStream`, `IAuthSessionState`) |
| Inject a widget/scope from another feature | **`IAppTreeWrapper`** or a widget-builder interface in `core_di` |
| Trigger Feature B Provider / dialog / UI method from Feature A (e.g. Settings → logout in Auth) | **Action Handler** (`I*ActionHandler`) |

**Sample in this template:** `feature_settings` calls `getItOrNull<IAuthActionHandler>()?.logout(context)` — Settings and Auth remain separate packages, and with no auth feature the logout row is simply not offered.

---

## 📋 Detailed Steps

### Step 1: Declare the Interface in `core_di`
Create `platform/di/lib/src/actions/i_<feature>_action_handler.dart`:
```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  void logout(BuildContext context);
}
```
Do **not** hand-edit `platform/di/lib/src/actions/actions.dart` — it is a generated barrel, and the generator deletes hand-written `export` lines. Running the barrel generator (Step 4) adds the new file.

### Step 2: Implement in the Owning Feature
Create `modules/<owner>/feature/lib/src/handlers/<feature>_action_handler_impl.dart`:
```dart
import 'package:core_di/core_di.dart';
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
The consumer MUST NOT import the owning feature package.

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
dart tools/barrel_generator/generate.dart platform/di/lib            # so the feature can import the new interface
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart platform/di/lib            # final pass, after codegen
dart tools/barrel_generator/generate.dart modules/<owner>/feature/lib
```
The final barrel pass must come **after** `build_runner`, because barrels also export
generated files present on disk. The extra pass on `platform/di/lib` beforehand is harmless and
lets the owning feature's `@Injectable(as: I…ActionHandler)` resolve the new interface through
`core_di`'s barrel during codegen.

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
