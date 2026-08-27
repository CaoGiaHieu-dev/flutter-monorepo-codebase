---
name: implement_navigation_route
description: Guide for creating Routes, declaring local Navigator interfaces, and implementing navigation in the monorepo.
---

# 🚦 Skill: Implement Navigation & Routing (Implement Navigation Route)

Use this skill when requested to: "create a new screen/page and link navigation", "navigate from Feature A to Feature B", "add routing parameters", etc.

**Read first:** `docs/{en,vi}/guides/04_routing.md` § Dashboard — when to use `IDashboardTabModule` vs `IFeatureRouteModule`, and what `feature_dashboard` must not own.

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
**Clean Architecture / feature boundary:** Navigators are per owning feature. Do not put Settings routes inside `feature_home` — use `feature_settings` + `SettingsNavigator`. `feature_dashboard` supplies **chrome only** (`DashboardRouteModule`); tab branches come from each feature's `IDashboardTabModule`.

### Step 2: Put the path constants in `utils/`

Route paths are constants, so they follow the repo-wide rule: every package keeps its
constants in `lib/src/utils/`. **Not** in `routing/` — they were moved.

`packages/features/home/lib/src/utils/home_path.dart`:
```dart
class HomePath {
  HomePath._();
  static const String HOME = '/home';
}
```

Existing files: `auth_path.dart`, `home_path.dart`, `onboarding_path.dart`,
`settings_path.dart` — all under their feature's `src/utils/`.

### Step 3: Trigger Navigation inside Feature Page / Widget
Inject and call the Navigator interface from the UI layer, passing the local `BuildContext`:
```dart
getItOrNull<ProfileNavigator>()?.toSettings(context);
```
Use `getItOrNull` (not `getIt`) so the call degrades to a no-op when the owning feature has
been removed from the build.

### Step 4: Define Route Class using `GoRouteDataCustom`
Declare a type-safe route in the feature's `routing/*_route_module.dart` file (inherit `GoRouteDataCustom`), importing the path constant from `../utils/`.

Instantiate the controller **in the route's `build`**, never inside the `Page`:
```dart
@override
Widget build(BuildContext context, GoRouterState state) {
  return BlocProvider(
    create: (_) => getIt<HomeProfileBloc>(),
    child: const HomePage(),
  );
}
```

### Step 5: Implement the Navigator inside the Feature Package
Create `*_navigator_impl.dart` under the feature's `routing/` with `@Singleton(as: XxxNavigator)`.

### Step 6: Register via DI (do **not** hardcode lists in AppRouter) & Run Code Gen

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

---

## 🔑 `NavigatorKeys`

Lives at `packages/core/di/lib/src/routing/navigator_keys.dart` (moved out of
`routing_interfaces.dart`, which now holds only `IFeatureRouteModule`):

```dart
class NavigatorKeys {
  NavigatorKeys._();
  static final appKey = GlobalKey<NavigatorState>();
  static final rootKey = GlobalKey<NavigatorState>();
  static final authKey = GlobalKey<NavigatorState>();
}
```

There are **three** keys — `homeKey` was deleted as dead code. They sit in the DI hub because
both the shell (which builds the `ShellRoute`) and the feature (which declares child routes)
must hand GoRouter the *same instance*; putting them on either side would create a cycle.

Add a key only when a feature needs its own nested back stack — a dashboard tab inside
`StatefulShellRoute` does not.

---

## 🧩 App Shell notes — keep features removable

The shell must stay buildable when any feature package is deleted. It talks to contracts in
`core_di`, never to feature types:

| Shell need | Contract | Registered by |
| :--- | :--- | :--- |
| `GoRouter.refreshListenable` | `IAuthRefreshListenable` | `feature_auth` (`@module` binding `AuthProvider`) |
| Boot redirect / session + failures | `IAuthSessionState` | `feature_auth` (same module) |
| Dart splash widget | `IAppSplashScreen` | `feature_splash` |
| Provider/Bloc scopes above the router | `IAppTreeWrapper` | any feature; shell folds them by `order` |

- `refreshListenable: getItOrNull<IAuthRefreshListenable>()` — **not** `AuthProvider`.
- `NavigatorWrapperWidget` drives the first-frame boot redirect through `IAuthSessionState`.
- Splash is managed by `MainScope`, **not** a GoRouter route; absent `IAppSplashScreen` the
  app falls back to the native splash.
- Impl classes: `*NavigatorImpl` in `*_navigator_impl.dart` — never `I*Navigator`.
- Missing modules must not crash: empty routes / `SizedBox.shrink()` / `/`.

---

## 🔗 Related

- `docs/{en,vi}/guides/04_routing.md` — full routing guide
- `docs/{en,vi}/architecture/06_app_shell.md` — how the shell assembles routes
- `implement_action_handler` — cross-feature UI actions that are not navigation
