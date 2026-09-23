# Routing & Navigation

**This guide answers:** how do I add a screen, and how do I navigate to a screen owned by another feature?

**After reading you can:** register routes from inside a feature package without touching the app shell, build type-safe routes with `go_router_builder`, and navigate across features through interfaces instead of hardcoded paths.

---

## 1. The core idea: routing is decentralised

`platform/app_shell/lib/presentation/navigation/app_router.dart` is **assembly only**. It never names a feature's routes — it collects whatever features registered through DI:

```dart
List<INavDestinationModule> get _destinations {
  return getAllOrEmpty<INavDestinationModule>().toList()
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
        └── one StatefulShellBranch per INavDestinationModule (sorted by order)
```

---

## 2. The four routing contracts

All live in `platform/di/lib/src/routing/`.

| Contract | Use for | Ordered? | Implemented by |
|---|---|---|---|
| `IFeatureRouteModule` | Top-level / stack routes under the app shell | No — GoRouter matches by path | auth, onboarding, … |
| `INavDestinationModule` | One primary destination + its `StatefulShellBranch` | **Yes** — ascending `order` | home, settings, … |
| `IAppEntryLocation` | Cold-start location (`initialLocation`) | n/a | usually onboarding |
| `DashboardRouteModule` | Dashboard chrome (scaffold + bottom bar host) | n/a | **only** `feature_dashboard` |

### 2.1 `IFeatureRouteModule`

```dart
abstract class IFeatureRouteModule {
  List<RouteBase> get routes;
}
```

Registered in the owning feature — `modules/onboarding/feature/lib/src/routing/onboarding_feature_route_module.dart`:

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

### 2.2 `INavDestinationModule`

```dart
abstract class INavDestinationModule {
  int get order;                    // 0 = first tab
  String get path;                  // canonical path, used for fallbacks
  List<RouteBase> get routes;       // mounted in one StatefulShellBranch
  void onRestore();                 // re-tap on the active tab
  NavDestination destination(BuildContext context);
}
```

`modules/home/feature/lib/src/routing/home_nav_destination.dart`:

```dart
@LazySingleton(as: INavDestinationModule)
class HomeNavDestination extends INavDestinationModule {
  @override
  int get order => 0;

  @override
  String get path => HomePath.HOME;

  @override
  List<RouteBase> get routes => [$homeRoute];

  @override
  NavDestination destination(BuildContext context) => NavDestination(
    label: context.l10nHome.tabLabel,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  );
}
```

> [!NOTE]
> Use `INavDestinationModule` **only** for real bottom-nav destinations that need their own persistent back stack. A screen you merely push onto the stack belongs in `IFeatureRouteModule`.

### 2.3 Dashboard is chrome only

`feature_dashboard` depends on just `core_di` and `platform_kernel` — it physically **cannot** import another feature. Its page builds the bar from DI (`modules/dashboard/feature/lib/src/pages/dashboard_page.dart`):

```dart
final tabs = getAllOrEmpty<INavDestinationModule>().toList()
  ..sort((a, b) => a.order.compareTo(b.order));
return Scaffold(
  body: navigationShell,
  bottomNavigationBar: tabs.length < 2 ? null : BottomNavigationBar(...),
);
```

The dashboard **must not**:
- import `feature_home` / `feature_settings` or embed their pages
- own tab pages or business BLoCs
- hardcode a destination list instead of reading DI
- register `INavDestinationModule` itself for a "fake" tab

Note `tabs.length < 2` hides the bar entirely when fewer than two tabs are registered — part of the graceful-degradation story in §6.

---

## 3. Type-safe routes with `go_router_builder`

Routes are declared with annotations and generated into `*_route_module.g.dart`. **Run `dart run build_runner build -d --workspace` after any change.**

Path constants live in the feature's `src/utils/` folder, not in `routing/` — every package keeps its constants under `utils/`:

`modules/auth/feature/lib/src/utils/auth_path.dart`:

```dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
}
```

`modules/auth/feature/lib/src/routing/auth_route_module.dart`:

```dart
@TypedShellRoute<AuthShellRoute>(
  routes: [TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)],
)
class AuthShellRoute extends ShellRouteData {
  const AuthShellRoute();

  static final $navigatorKey = NavigatorKeys.nested('auth');
  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return navigator;
  }
}

class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.nested('auth');
  @override
  Widget build(BuildContext context, GoRouterState state) => const LoginPage();
}
```

Add sibling routes as further `TypedGoRoute` entries in `routes:` — they share the shell's nested Navigator, so they share one back stack. The generated `$authShellRoute` is what the feature hands back from `IFeatureRouteModule.routes`.

---

## 4. Instantiate controllers at the route

The route's `build()` is where a screen controller is created and bound to the tree.

**BLoC** — `modules/home/feature/lib/src/routing/home_route_module.dart`:

```dart
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      // Auth is optional: an app composed without `feature_auth` registers
      // no IAuthStatusStream, and Home then shows the signed-out state.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<IAuthStatusStream>(),
      ),
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
    create: (context) => getIt<ProfileProvider>(),
    child: const ProfilePage(),
  );
}
```

> [!CAUTION]
> The page itself must **not** wrap in a second provider. See [`03_state_management.md`](03_state_management.md) §4.

Routes for screens backed by a **global** controller (e.g. `LoginPage` with the `@lazySingleton` `AuthProvider`) build the page directly, with no wrapper.

---

## 5. Cross-feature navigation

Feature A must never import Feature B. Navigation crosses the boundary through an interface in `core_di`.

**1. Declare** — `platform/di/lib/src/navigators/auth_navigator.dart`:

```dart
abstract class AuthNavigator {
  void toLogin(BuildContext context);
}
```

One method per route the feature owns — and only routes it owns.

**2. Implement in the owning feature** — `modules/auth/feature/lib/src/routing/auth_navigator_impl.dart`:

```dart
@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) => const LoginRoute().go(context);
}
```

**3. Consume from anywhere:**

```dart
// From any package other than the owner — the owner is removable:
getItOrNull<AuthNavigator>()?.toLogin(context);

// Only inside feature_auth itself, which cannot be absent from its own code:
getIt<AuthNavigator>().toLogin(context);
```

### Rules

- A Navigator interface exposes **only** routes its own feature owns.
- **Never** hardcode a path string or call `GoRouter.of(context).go('/auth/login')` to reach another feature.
- **`BuildContext` must be passed in directly from the calling widget.** Do not reach for `NavigatorKeys.*.currentContext` or `appRouter.currentContext` — those bypass the widget lifecycle and produce "used after dispose" bugs.
- Use `getItOrNull` at call sites that must survive the target feature being removed.

---

## 6. `NavigatorKeys` — why they live in the DI Hub

`platform/di/lib/src/routing/navigator_keys.dart`:

```dart
class NavigatorKeys {
  NavigatorKeys._();

  static final appKey = GlobalKey<NavigatorState>(debugLabel: 'app');
  static final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  static final _nested = <String, GlobalKey<NavigatorState>>{};

  /// The nested navigator key registered under [id], created on first use.
  static GlobalKey<NavigatorState> nested(String id) => _nested.putIfAbsent(
    id,
    () => GlobalKey<NavigatorState>(debugLabel: 'nested:$id'),
  );
}
```

A `ShellRoute` and its child routes must reference the **same** `GlobalKey` instance. The shell is assembled by the app shell; the child routes are declared inside feature packages. Putting the keys on either side breaks a rule — the shell (`platform_app_shell`) is core and may not depend on a feature (R1), and a feature may not depend on the shell. `core_di`, which both sides already depend on, is the neutral home.

The DI Hub declares no feature-named key. `nested(id)` hands back the same instance for the same id, so a shell route and its children agree without anything central being declared — and `core_di`'s public surface never grows a product vocabulary.

Ask for a key **only** when a module genuinely needs its own nested navigator — its own back stack. Destinations inside `StatefulShellRoute` get a branch navigator from GoRouter and need none.

---

## 7. Graceful degradation

Every lookup in `app_router.dart` tolerates a missing contribution — this is what makes a feature removable:

```dart
String get fallbackLocation {
  final tabs = _destinations;
  if (tabs.isNotEmpty) return tabs.first.path;
  return _emptyDestinationPath;
}

String get entryLocation =>
    getItOrNull<IAppEntryLocation>()?.path ?? fallbackLocation;
```

```dart
builder: (context, state, navigationShell) {
  return getItOrNull<DashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      navigationShell;
},
```

| Missing | Result |
|---|---|
| All `IFeatureRouteModule` | No stack routes; app still builds |
| All `INavDestinationModule` | A placeholder `/_empty_dashboard` branch keeps `StatefulShellRoute` valid |
| `DashboardRouteModule` | The destinations render without chrome — `navigationShell` shows the current branch. (It used to be `SizedBox.shrink()`, a blank screen for any app with tabs but no dashboard) |
| `IAppEntryLocation` | Boot starts on `fallbackLocation` — the first tab, else the placeholder branch. With no entry location there is no onboarding to show, so boot goes on to the login check |
| `HomeNavigator` | After sign-in the app goes to `fallbackLocation` instead of staying on the login screen |

There are two locations, deliberately different. `entryLocation` is where a cold start lands — onboarding when it is composed. `fallbackLocation` is "home": `back()` with nothing to pop, `UndefineRouteWidget`'s go-home button, and after sign-in when no `HomeNavigator` is registered. It is always a registered route and never onboarding — a user who just signed in must not be sent back to it.

Unmatched paths land on `errorPageBuilder` → `UndefineRouteWidget` (a real widget class, never an inline anonymous one).

---

## 8. Add a screen — end to end

1. **Path constant** → `lib/src/utils/<feature>_path.dart`.
2. **Route class** → `lib/src/routing/<feature>_route_module.dart` with `@TypedGoRoute` / `@TypedShellRoute`; create the controller in `build()`.
3. **Register the contract** → `IFeatureRouteModule` for a stack route, or `INavDestinationModule` for a tab, annotated `@LazySingleton(as: ...)`.
4. **Cross-feature entry?** Add a method to that feature's Navigator interface in `core_di` and implement it in the feature's `*_navigator_impl.dart`.
5. **Generate** → `dart run build_runner build -d --workspace`.
6. **Barrels** → `dart tools/barrel_generator/generate.dart modules/<name>/feature/lib`.

## Checklist

- [ ] `app_router.dart` untouched
- [ ] Path constants under `src/utils/`, not `routing/`
- [ ] Controller created in the route's `build()`, page does not re-wrap
- [ ] `INavDestinationModule.order` matches the intended tab index
- [ ] Cross-feature navigation goes through a `core_di` Navigator interface
- [ ] `BuildContext` passed from the UI, never taken from `NavigatorKeys`
- [ ] `build_runner` re-run after touching route annotations

## Related

- [`03_state_management.md`](03_state_management.md) — controller lifecycle
- [`05_di.md`](05_di.md) — how contracts get registered and collected
- [`10_cross_feature.md`](10_cross_feature.md) — the other cross-feature models
- [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) — router assembly
