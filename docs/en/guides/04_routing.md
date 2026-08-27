# Routing & Navigation

**This guide answers:** how do I add a screen, and how do I navigate to a screen owned by another feature?

**After reading you can:** register routes from inside a feature package without touching the app shell, build type-safe routes with `go_router_builder`, and navigate across features through interfaces instead of hardcoded paths.

---

## 1. The core idea: routing is decentralised

`app/lib/presentation/navigation/app_router.dart` is **assembly only**. It never names a feature's routes — it collects whatever features registered through DI:

```dart
List<IDashboardTabModule> get _dashboardTabs {
  return getAllOrEmpty<IDashboardTabModule>().toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

List<RouteBase> get _featureRoutes {
  return [
    for (final module in getAllOrEmpty<IFeatureRouteModule>())
      ...module.routes,
  ];
}
```

> [!CAUTION]
> **Never edit `app_router.dart` to add a route.** Adding `$myFeatureRoute` there couples the shell to your feature and breaks the "remove a feature and the app still runs" guarantee. Register a contract in your feature's DI module instead.

The shell tree it builds:

```
GoRouter (navigatorKey: NavigatorKeys.rootKey)
└── ShellRoute (navigatorKey: appKey)  →  NavigatorWrapperWidget
    ├── ...IFeatureRouteModule routes        ← auth, onboarding, …
    └── StatefulShellRoute.indexedStack      →  DashboardRouteModule.builder
        └── one StatefulShellBranch per IDashboardTabModule (sorted by order)
```

---

## 2. The four routing contracts

All live in `packages/core/di/lib/src/routing/`.

| Contract | Use for | Ordered? | Implemented by |
|---|---|---|---|
| `IFeatureRouteModule` | Top-level / stack routes under the app shell | No — GoRouter matches by path | auth, onboarding, … |
| `IDashboardTabModule` | One bottom-nav tab + its `StatefulShellBranch` | **Yes** — `order` must match nav index | home, settings, … |
| `IAppEntryLocation` | Cold-start location (`initialLocation`) | n/a | usually onboarding |
| `DashboardRouteModule` | Dashboard chrome (scaffold + bottom bar host) | n/a | **only** `feature_dashboard` |

### 2.1 `IFeatureRouteModule`

```dart
abstract class IFeatureRouteModule {
  List<RouteBase> get routes;
}
```

Registered in the owning feature — `packages/features/onboarding/lib/src/routing/onboarding_feature_route_module.dart`:

```dart
@LazySingleton(as: IFeatureRouteModule)
class OnboardingFeatureRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [$onboardingRoute];
}

@LazySingleton(as: IAppEntryLocation)
class OnboardingAppEntryLocation implements IAppEntryLocation {
  @override
  String get path => OnboardingPath.ONBOARDING;
}
```

Use unique paths and avoid overlapping catch-alls — sibling order between modules is not guaranteed.

### 2.2 `IDashboardTabModule`

```dart
abstract class IDashboardTabModule {
  int get order;                    // 0 = first tab
  String get path;                  // canonical path, used for fallbacks
  List<RouteBase> get routes;       // mounted in one StatefulShellBranch
  void onRestore();                 // re-tap on the active tab
  BottomNavigationBarItem navigationBarItem(BuildContext context);
}
```

`packages/features/home/lib/src/routing/home_dashboard_tab_module.dart`:

```dart
@LazySingleton(as: IDashboardTabModule)
class HomeDashboardTabModule extends IDashboardTabModule {
  @override
  int get order => 0;

  @override
  String get path => HomePath.HOME;

  @override
  List<RouteBase> get routes => [$homeShellRoute];

  @override
  BottomNavigationBarItem navigationBarItem(BuildContext context) {
    return BottomNavigationBarItem(
      icon: const Icon(Icons.home),
      label: context.l10nHome.tabLabel,
    );
  }
}
```

> [!NOTE]
> Use `IDashboardTabModule` **only** for real bottom-nav destinations that need their own persistent back stack. A screen you merely push onto the stack belongs in `IFeatureRouteModule`.

### 2.3 Dashboard is chrome only

`feature_dashboard` depends on just `core_di` and `core_common` — it physically **cannot** import another feature. Its page builds the bar from DI (`packages/features/dashboard/lib/src/pages/dashboard_page.dart`):

```dart
final tabs = getAllOrEmpty<IDashboardTabModule>().toList()
  ..sort((a, b) => a.order.compareTo(b.order));
return Scaffold(
  body: navigationShell,
  bottomNavigationBar: tabs.length < 2 ? null : BottomNavigationBar(...),
);
```

The dashboard **must not**:
- import `feature_home` / `feature_settings` or embed their pages
- own tab pages or business BLoCs
- hardcode a `BottomNavigationBarItem` list instead of reading DI
- register `IDashboardTabModule` itself for a "fake" tab

Note `tabs.length < 2` hides the bar entirely when fewer than two tabs are registered — part of the graceful-degradation story in §6.

---

## 3. Type-safe routes with `go_router_builder`

Routes are declared with annotations and generated into `*_route_module.g.dart`. **Run `dart run build_runner build -d --workspace` after any change.**

Path constants live in the feature's `src/utils/` folder (they moved out of `routing/` — every package keeps its constants under `utils/`):

`packages/features/auth/lib/src/utils/auth_path.dart`:

```dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
  static const String REGISTER = '/auth/register';
  static const String FORGOT_PASSWORD = '/auth/forgot-password';
}
```

`packages/features/auth/lib/src/routing/auth_route_module.dart`:

```dart
@TypedShellRoute<AuthShellRoute>(
  routes: [
    TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN),
    TypedGoRoute<RegisterRoute>(path: AuthPath.REGISTER),
    TypedGoRoute<ForgotPasswordRoute>(path: AuthPath.FORGOT_PASSWORD),
  ],
)
class AuthShellRoute extends ShellRouteData {
  const AuthShellRoute();

  static final $navigatorKey = NavigatorKeys.authKey;
  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return navigator;
  }
}

class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.authKey;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const LoginPage();
  }
}
```

The generated `$authShellRoute` is what the feature hands back from `IFeatureRouteModule.routes`.

---

## 4. Instantiate controllers at the route

The route's `build()` is where a screen controller is created and bound to the tree.

**BLoC** — `packages/features/home/lib/src/routing/home_route_module.dart`:

```dart
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      create: (_) => getIt<HomeProfileBloc>(),
      child: const HomePage(),
    );
  }
}
```

**Provider** — same shape:

```dart
@override
Widget build(BuildContext context, GoRouterState state) {
  return ChangeNotifierProvider(
    create: (context) => getIt<OnboardingProvider>(),
    child: const OnboardingPage(),
  );
}
```

> [!CAUTION]
> The page itself must **not** wrap in a second provider. See [`03_state_management.md`](03_state_management.md) §4.

Routes for screens backed by a **global** controller (e.g. `LoginPage` with the `@lazySingleton` `AuthProvider`) build the page directly, with no wrapper.

---

## 5. Cross-feature navigation

Feature A must never import Feature B. Navigation crosses the boundary through an interface in `core_di`.

**1. Declare** — `packages/core/di/lib/src/navigators/auth_navigator.dart`:

```dart
abstract class AuthNavigator {
  void toLogin(BuildContext context);
  void toRegister(BuildContext context);
  void toForgotPassword(BuildContext context);
}
```

**2. Implement in the owning feature** — `packages/features/auth/lib/src/routing/auth_navigator_impl.dart`:

```dart
@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) {
    const LoginRoute().go(context);
  }

  @override
  void toRegister(BuildContext context) => const RegisterRoute().go(context);

  @override
  void toForgotPassword(BuildContext context) =>
      const ForgotPasswordRoute().go(context);
}
```

**3. Consume from anywhere:**

```dart
getIt<AuthNavigator>().toLogin(context);
// or, when the feature may be absent:
getItOrNull<AuthNavigator>()?.toLogin(context);
```

### Rules

- A Navigator interface exposes **only** routes its own feature owns.
- **Never** hardcode a path string or call `GoRouter.of(context).go('/auth/login')` to reach another feature.
- **`BuildContext` must be passed in directly from the calling widget.** Do not reach for `NavigatorKeys.*.currentContext` or `appRouter.currentContext` — those bypass the widget lifecycle and produce "used after dispose" bugs.
- Use `getItOrNull` at call sites that must survive the target feature being removed.

---

## 6. `NavigatorKeys` — why they live in the DI Hub

`packages/core/di/lib/src/routing/navigator_keys.dart`:

```dart
class NavigatorKeys {
  NavigatorKeys._();

  static final appKey = GlobalKey<NavigatorState>();
  static final rootKey = GlobalKey<NavigatorState>();
  static final authKey = GlobalKey<NavigatorState>();
}
```

A `ShellRoute` and its child routes must reference the **same** `GlobalKey` instance. The shell is assembled by the app shell; the child routes are declared inside feature packages. Putting the keys on either side creates a cycle — the app shell already depends on every feature, so a feature cannot depend back on the shell. `core_di`, which both sides already depend on, is the neutral home.

`authKey` names a feature, which would normally be a layering smell. It is allowed because this is **routing plumbing, not business logic**: the key is only an identity token handed to GoRouter, and `core_di` never imports `feature_auth`.

Add a key **only** when a feature genuinely needs its own nested navigator (its own back stack). Dashboard tabs get their branch navigator from GoRouter's `StatefulShellRoute` and need no entry.

---

## 7. Graceful degradation

Every lookup in `app_router.dart` tolerates a missing contribution — this is what makes a feature removable:

```dart
String get _fallbackLocation {
  final entry = getItOrNull<IAppEntryLocation>()?.path;
  if (entry != null) return entry;
  final tabs = _dashboardTabs;
  if (tabs.isNotEmpty) return tabs.first.path;
  return '/';
}
```

```dart
builder: (context, state, navigationShell) {
  return getItOrNull<DashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      const SizedBox.shrink();
},
```

| Missing | Result |
|---|---|
| All `IFeatureRouteModule` | No stack routes; app still builds |
| All `IDashboardTabModule` | A placeholder `/_empty_dashboard` branch keeps `StatefulShellRoute` valid |
| `DashboardRouteModule` | Dashboard renders `SizedBox.shrink()` |
| `IAppEntryLocation` | Falls back to the first tab's path, then `/` |

Unmatched paths land on `errorPageBuilder` → `UndefineRouteWidget` (a real widget class, never an inline anonymous one).

---

## 8. Add a screen — end to end

1. **Path constant** → `lib/src/utils/<feature>_path.dart`.
2. **Route class** → `lib/src/routing/<feature>_route_module.dart` with `@TypedGoRoute` / `@TypedShellRoute`; create the controller in `build()`.
3. **Register the contract** → `IFeatureRouteModule` for a stack route, or `IDashboardTabModule` for a tab, annotated `@LazySingleton(as: ...)`.
4. **Cross-feature entry?** Add a method to that feature's Navigator interface in `core_di` and implement it in the feature's `*_navigator_impl.dart`.
5. **Generate** → `dart run build_runner build -d --workspace`.
6. **Barrels** → `dart tools/barrel_generator/generate.dart packages/features/<name>/lib`.

## Checklist

- [ ] `app_router.dart` untouched
- [ ] Path constants under `src/utils/`, not `routing/`
- [ ] Controller created in the route's `build()`, page does not re-wrap
- [ ] `IDashboardTabModule.order` matches the intended tab index
- [ ] Cross-feature navigation goes through a `core_di` Navigator interface
- [ ] `BuildContext` passed from the UI, never taken from `NavigatorKeys`
- [ ] `build_runner` re-run after touching route annotations

## Related

- [`03_state_management.md`](03_state_management.md) — controller lifecycle
- [`05_di.md`](05_di.md) — how contracts get registered and collected
- [`10_cross_feature.md`](10_cross_feature.md) — the other cross-feature models
- [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) — router assembly
