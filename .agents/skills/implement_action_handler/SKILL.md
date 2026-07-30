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
| Navigate to another feature's screen | **Navigator** (`AuthNavigator`, `HomeNavigator`, `SettingsNavigator`) |
| Shared business logic without UI | **Domain UseCase** |
| Trigger Feature B Provider / dialog / UI method from Feature A (e.g. Settings → logout in Auth) | **Action Handler** (`I*ActionHandler`) |

**Sample in this template:** `feature_settings` calls `getIt<IAuthActionHandler>().logout(context)` — Settings and Auth remain separate packages.

---

## 📋 Detailed Steps

### Step 1: Declare the Interface in `core_di`
Create `packages/core/di/lib/src/actions/i_<feature>_action_handler.dart`:
```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  void logout(BuildContext context);
}
```
Export it from `packages/core/di/lib/src/actions/actions.dart` (barrel will pick it up via generator).

### Step 2: Implement in the Owning Feature
Create `packages/features/<owner>/lib/src/handlers/<feature>_action_handler_impl.dart`:
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
getIt<IAuthActionHandler>().logout(context);
```
The consumer MUST NOT import the owning feature package.

### Step 4: Barrel + Code Gen
```bash
dart tools/barrel_generator/generate.dart packages/core/di/lib
dart tools/barrel_generator/generate.dart packages/features/<owner>/lib
dart run build_runner build -d --workspace
```

---

## 🏷️ Naming Rules

| Kind | File | Class |
| :--- | :--- | :--- |
| Interface | `i_<name>_action_handler.dart` | `I*ActionHandler` |
| Implementation | `<name>_action_handler_impl.dart` | `*ActionHandlerImpl` |

**ABSOLUTELY FORBIDDEN**: Naming an implementation with the `I` prefix (e.g., `IAuthActionHandlerImpl` as a class name for the interface, or renaming navigator impls to `IAuthNavigator`).
