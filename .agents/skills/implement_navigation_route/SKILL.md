---
name: implement_navigation_route
description: Guide for creating Routes, declaring local Navigator interfaces, and implementing navigation in the monorepo.
---

# 🚦 Skill: Implement Navigation & Routing (Implement Navigation Route)

Use this skill when requested to: "create a new screen/page and link navigation", "navigate from Feature A to Feature B", "add routing parameters", etc.

**Read first:** `docs/en/08_routing.md` § Dashboard — when to use `IDashboardTabModule` vs `IFeatureRouteModule`, and what `feature_dashboard` must not own.

---

## 📋 Detailed Steps

### Step 1: Declare Navigator Interface in `core_di`
Navigation across features must not be performed directly via path strings. Declare a Navigator interface under `packages/core/di/lib/src/navigators/`:
```dart
import 'package:flutter/widgets.dart';

abstract class ProfileNavigator {
  void toEditProfile(BuildContext context);
  void toSettings(BuildContext context);
}
```
**Clean Architecture / feature boundary:** Navigators are per owning feature. Do not put Settings routes inside `feature_home` — use `feature_settings` + `SettingsNavigator`. `feature_dashboard` supplies **chrome only** (`DashboardRouteModule`); tab branches come from each feature’s `IDashboardTabModule`.

### Step 2: Trigger Navigation inside Feature Page / Widget
Inject and call the Navigator interface from the UI layer, passing the local `BuildContext`:
```dart
getItOrNull<ProfileNavigator>()?.toSettings(context);
```

### Step 3: Define Route Class using `GoRouteDataCustom`
Declare a type-safe route in the feature's `routing/*_route_module.dart` file (inherit `GoRouteDataCustom`).

### Step 4: Implement the Navigator inside the Feature Package
Create `*_navigator_impl.dart` under the feature’s `routing/` with `@Singleton(as: XxxNavigator)`.

### Step 5: Register via DI (do **not** hardcode lists in AppRouter) & Run Code Gen

Pick **one** contribution type:

| Need | Contract | Notes |
| :--- | :--- | :--- |
| Bottom-nav primary tab | `IDashboardTabModule` | Requires `order`, `path`, `routes`, `navigationBarItem`. `order` **must** stay unique and match shell branch index. |
| Stack / shell sibling (login, onboarding, …) | `IFeatureRouteModule` | **`routes` only — no `order`** (GoRouter matches by path). |
| Cold-start path | `IAppEntryLocation` | Optional; else first tab path / `/`. |
| Dashboard scaffold chrome | `DashboardRouteModule` | **Only** in `feature_dashboard`. |

1. Implement the chosen contract with `@LazySingleton(as: …)` (or `@Singleton` for chrome).
2. Wire package in `app/pubspec.yaml` + `ExternalModule` in `injection.dart` (generator usually does this).
3. **Never** append `$fooRoute` into `app_router.dart` manually — host already uses `getAllOrEmpty` / `getItOrNull`.
4. Codegen + **hot restart**:
   ```bash
   dart tools/barrel_generator/generate.dart packages/features/profile/lib
   dart run build_runner build -d --workspace
   ```

### Notes (App Shell)
- `NavigatorWrapperWidget` owns first-frame auth boot / deep-link init and global `ProviderStateListener<AuthProvider, …>`.
- Splash is managed by `MainScope`, **not** a GoRouter route.
- `refreshListenable: getItOrNull<AuthProvider>()`.
- Impl classes: `*NavigatorImpl` in `*_navigator_impl.dart` — never `I*Navigator`.
- Missing modules must not crash: empty routes / `SizedBox.shrink()` / `/`.
