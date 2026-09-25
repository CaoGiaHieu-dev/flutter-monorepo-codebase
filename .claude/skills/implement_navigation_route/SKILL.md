---
name: implement_navigation_route
description: Use when adding a screen or route, linking navigation between features, or adding a tab — "create a new page and navigate to it", "navigate from feature A to feature B", "add a bottom-nav tab", "add route parameters". Covers GoRouteDataCustom routes, path constants in utils/, navigator contracts in the owner's <id>_api, and IFeatureRouteModule / INavDestinationModule registration.
---

# 🚦 Skill: Implement Navigation & Routing (Implement Navigation Route)

Use this skill when requested to: "create a new screen/page and link navigation", "navigate from Feature A to Feature B", "add routing parameters", etc.

**Read first:** [`docs/en/guides/04_routing.md`](../../../docs/en/guides/04_routing.md) § Dashboard — when to use `INavDestinationModule` vs `IFeatureRouteModule`, and what `feature_dashboard` must not own.
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-04, RULE-09, RULE-12, RULE-20,
RULE-21, RULE-22, RULE-23, RULE-24, RULE-75, RULE-78.

---

## 📋 Detailed Steps

### Step 1: Declare the Navigator Interface in the module's API package
Navigation across features must not be performed directly via path strings. Declare a Navigator interface in the **owning module's API package**, `modules/<id>/api/lib/src/navigators/` (package `<id>_api`; create the package first if the module has none — `docs/en/guides/12_module_isolation.md` § 4). `core_di` holds no module navigator — only product-neutral contracts such as `ISignInLocation` / `IPostSignInLocation`, which the app shell uses instead:
```dart
import 'package:flutter/widgets.dart';

abstract class ProfileNavigator {
  void toProfile(BuildContext context);
  void toEditProfile(BuildContext context);
}
```
A navigator holds **only its own feature's routes** — `ProfileNavigator` never gets a
`toSettings`; a caller wanting Settings asks for `SettingsNavigator`. Real examples:
`modules/home/api/lib/src/navigators/home_navigator.dart` (`home_api`),
`modules/auth/api/lib/src/navigators/auth_navigator.dart` (`auth_api`). Regenerate the API
barrel after adding a file: `dart tools/barrel_generator/generate.dart modules/<id>/api/lib`.

Navigators are per owning feature (RULE-22, RULE-24): Settings routes live in `feature_settings`, and a `SettingsNavigator` contract goes into a `settings_api` package only once another module needs it. The caller lists `<id>_api` in its `dependencies:`, never the other feature (RULE-04).

### Step 2: Put the path constants in `utils/`

Route paths are constants, so they live in `lib/src/utils/`, not `routing/` (RULE-09).

`modules/home/feature/lib/src/utils/home_path.dart`:
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
getItOrNull<ProfileNavigator>()?.toEditProfile(context);
```
`getItOrNull`, not `getIt` (RULE-12); `context` straight from the widget (RULE-23).

### Step 4: Define Route Class using `GoRouteDataCustom`
Declare a type-safe route in the feature's `routing/*_route_module.dart` file (inherit `GoRouteDataCustom`), importing the path constant from `../utils/`.

Instantiate the controller **in the route's `build`**, never inside the `Page` (RULE-21):
```dart
@override
Widget build(BuildContext context, GoRouterState state) {
  return BlocProvider(
    // Auth is optional: an app composed without `feature_auth` registers
    // no ISessionStatusStream, and Home then shows the signed-out state.
    create: (_) => getIt<HomeProfileBloc>(
      param1: getItOrNull<ISessionStatusStream>(),
    ),
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
| Bottom-nav primary tab | `INavDestinationModule` | Requires `order`, `path`, `routes`, `destination`. `order` is an ascending sort key (not a branch index — `AppRouter` and the dashboard both sort by it); keep it unique so the order stays deterministic. |
| Stack / shell sibling (login, onboarding, …) | `IFeatureRouteModule` | **`routes` only — no `order`** (GoRouter matches by path). |
| First-launch path | `IAppEntryLocation` | Optional, and used only until `AppBootStorage.viewedOnboard` is set; after that, and when none is registered, the first destination's path, or the placeholder `/_empty_dashboard` when no destination is registered. |
| Dashboard scaffold chrome | `IDashboardRouteModule` | **Only** in `feature_dashboard`. |

1. Implement the chosen contract with `@LazySingleton(as: …)` (or `@Singleton` for chrome).
2. Compose the package: list its module in each `apps/<id>/app_manifest.yaml` (the generator does this) and run `dart tools/composer/composer.dart sync` — never hand-edit an app's `pubspec.yaml` or `injection.dart`.
3. **Never** append `$fooRoute` into `app_router.dart` (RULE-20) — the host collects contributions with `getAllOrEmpty` / `getItOrNull`.
4. Export the new navigator from its API package first (Step 1 added a file there; without this
   the impl reports `Undefined name 'ProfileNavigator'`), then codegen, then the feature's barrels
   (after `build_runner` — RULE-75), then a **full restart** (hot reload does not pick up new DI
   registrations):
   ```bash
   dart tools/barrel_generator/generate.dart modules/profile/api/lib
   dart run build_runner build --workspace
   dart tools/barrel_generator/generate.dart modules/profile/feature/lib
   ```

---

## 🔑 `NavigatorKeys`

Lives at `platform/foundation/contracts/lib/src/routing/navigator_keys.dart`. The whole API:

```dart
class NavigatorKeys {
  NavigatorKeys._();
  static final appKey = GlobalKey<NavigatorState>(debugLabel: 'app');   // the app ShellRoute
  static final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root'); // GoRouter's own navigator
  static GlobalKey<NavigatorState> nested(String id) => ...;            // same instance per id
}
```

The keys sit in the DI hub because both the shell (which builds the `ShellRoute`) and the
feature (which declares child routes) must hand GoRouter the *same instance*; putting them on
either side would create a cycle.

**Never add a key to this class.** A module that needs its own back stack asks for one by id —
`static final $navigatorKey = NavigatorKeys.nested('auth');` — and gets the same instance every
time. A dashboard tab inside the `StatefulShellRoute` gets a branch navigator from GoRouter and
needs no key at all.

---

## 🧩 App Shell notes — keep features removable

The shell must stay buildable when any feature package is deleted. It talks to contracts in
`core_di`, never to feature types:

| Shell need | Contract | Registered by |
| :--- | :--- | :--- |
| `GoRouter.refreshListenable` | `ISessionRefreshListenable` | `feature_auth` (`@module` binding `AuthProvider`) |
| Boot redirect / session + failures | `ISessionState` | `feature_auth` (same module) |
| Dart splash widget | `IAppSplashScreen` | `feature_splash` |
| Provider/Bloc scopes above the router | `IAppTreeWrapper` | any feature; shell folds them by `order` |

- `refreshListenable: getItOrNull<ISessionRefreshListenable>()` — **not** `AuthProvider`.
- `NavigatorWrapperWidget` drives the first-frame boot redirect through `ISessionState`.
- Splash is managed by `MainScope`, **not** a GoRouter route; absent `IAppSplashScreen` the
  app falls back to the native splash.
- Impl classes: `*NavigatorImpl` in `*_navigator_impl.dart` (RULE-78).
- Missing modules must not crash (`platform/shell/app_shell/lib/src/navigation/app_router.dart`):
  no route modules → empty lists; no destination → a placeholder branch at `/_empty_dashboard`;
  no `IAppEntryLocation` → the first destination's path (else `/_empty_dashboard`); no
  `IDashboardRouteModule` → the bare `navigationShell`, i.e. tabs without chrome.

---

## 🔗 Related

- `docs/{en,vi}/guides/04_routing.md` — full routing guide
- `docs/{en,vi}/architecture/06_app_shell.md` — how the shell assembles routes
- `implement_action_handler` — cross-feature UI actions that are not navigation
