# 08. Decentralized Scoped Routing (Decentralized Scoped Routing)

The routing system of the **Codebase Provider Monorepo** uses the `go_router` library combined with the type-safe code generator **`go_router_builder`**. To completely resolve the problem of source code conflicts (Merge Conflicts) and ensure the **Encapsulation** of each Feature Package, the project applies the **Decentralized Scoped Navigators** model.

---

## 🏛️ 1. Zero-Conflict Routing Design Philosophy

In a large Monorepo model:
- If a single routing interface file (like `AppNavigator`) at `core_common` is shared, every change from any feature team must modify this file ➔ Causes severe **Merge Conflicts** when merging code.
- At the same time, `core_common` should not depend on child Features because it will cause a **Circular Dependency Error**.

### 🛠️ Ultimate Solution: Decoupled Navigation Contracts via `core_di`
We decouple routing contracts and converge them at the `core_di` "Hub":
1. **Converge Interfaces at `core_di` (DI Hub)**: Instead of each Feature defining its own, all **Interface Navigators** (e.g., `AuthNavigator`) and Routing Modules sharing interfaces are centrally declared at `packages/core/di`.
2. **Features communicate via `core_di`**: When Features want to navigate or call each other's Widgets, they simply `import 'package:core_di/core_di.dart';` and use `getIt<T>()` without cross-importing each other. This completely puts an end to Circular Dependency errors.
3. **Decentralized implementation at the local Feature package**: Instead of centralized implementation in the App Shell, each Feature package writes its own actual implementation code for its own Interface Navigator in the `routing/` directory (e.g., `auth_navigator_impl.dart` in `feature_auth`).

---

## 🚥 2. Decentralized Architecture Grid Diagram

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                        FEATURE LAYER (PACKAGES)                            │
│  feature_auth / onboarding     feature_home / settings      feature_dashboard│
│  IFeatureRouteModule           IDashboardTabModule          DashboardRouteModule│
│  (+ AuthNavigator, …)          (order, path, routes, nav)   (chrome / shell UI)│
└───────────────┬──────────────────────────┬───────────────────────┬───────────┘
                │                          │                       │
                └──────────────────────────┼───────────────────────┘
                                           │ package:core_di
                                           ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  core_di: Navigators + IFeatureRouteModule + IDashboardTabModule +         │
│           IAppEntryLocation + DashboardRouteModule + NavigatorKeys         │
└────────────────────────────────────────────────────────────────────────────┘
                                           ▲
                                           │ getAllOrEmpty / getItOrNull
┌────────────────────────────────────────────────────────────────────────────┐
│  app AppRouter — assembles routes dynamically (no hardcoded $fooRoute list)│
└────────────────────────────────────────────────────────────────────────────┘
```

### Contract cheat-sheet

| Contract | Purpose | Has `order`? | Who implements |
| :--- | :--- | :--- | :--- |
| `IFeatureRouteModule` | Sibling stack/shell routes under the app `ShellRoute` | **No** (path match) | auth, onboarding, … |
| `IDashboardTabModule` | One bottom-nav tab + one `StatefulShellBranch` | **Yes** (must match nav index) | home, settings, … |
| `IAppEntryLocation` | Cold-start `GoRouter.initialLocation` | n/a | usually onboarding |
| `DashboardRouteModule` | Dashboard **chrome** only (scaffold / bottom bar host) | n/a | `feature_dashboard` only |
| `IFeatureLocalization` | Feature ARB delegates | n/a | every feature with strings |

---

## 🧭 2.1. `feature_dashboard` — why it exists and how not to misuse it

### Why Dashboard exists

`feature_dashboard` is **not** a place to dump Home/Settings/Chat/Profile page code. It exists to own the **authenticated main shell chrome**:

1. **`DashboardRouteModule`** — wires `StatefulNavigationShell` into a `Scaffold` (see `DashboardPage`).
2. **Bottom navigation host** — reads `getAllOrEmpty<IDashboardTabModule>()`, sorts by `order`, builds `BottomNavigationBar` items. Tab **content** still lives in other feature packages.
3. **Optional package** — `AppRouter` uses `getItOrNull<DashboardRouteModule>()`; if dashboard is removed, chrome falls back to `SizedBox.shrink()` and the app still boots.

This keeps **shell layout** separate from **tab product features**, so teams can add/remove tabs without editing `app_router.dart` or importing sibling features.

### What Dashboard MUST do

- Implement `@Singleton(as: DashboardRouteModule)`.
- In `DashboardPage`, build nav items **only** from `IDashboardTabModule` (same sort key as `AppRouter` branches).
- Keep feature-local strings for tab labels inside each tab feature (`tabLabel`), not hardcode Home/Settings inside dashboard.

### What Dashboard MUST NOT do

| Anti-pattern | Why it is wrong |
| :--- | :--- |
| Import `feature_home` / `feature_settings` and embed their pages | Breaks feature isolation; circular-dep risk; defeats DI tabs |
| Own `HomePage` / `SettingsPage` / business BLoCs for those tabs | Dashboard is chrome, not a kitchen-sink feature |
| Hardcode `BottomNavigationBarItem` list that ignores DI | Removing a tab package then crashes or shows dead tabs |
| Register `IDashboardTabModule` itself for “fake” tabs | Tabs belong to the owning feature package |
| Use Dashboard for login, onboarding, or push-only screens | Those use `IFeatureRouteModule` + Navigator, not bottom nav |
| Put unrelated tabs in one feature “because Dashboard needs them” | One bounded UI concern per feature; Dashboard only hosts |

### When to use `IDashboardTabModule` vs `IFeatureRouteModule`

Use **`IDashboardTabModule`** only if **all** are true:

- The screen is a **primary destination** in the main authenticated shell (a bottom-nav / rail destination).
- It needs a stable branch in `StatefulShellRoute` (state preserved when switching tabs).
- Its `order` must stay unique and aligned with other tabs.

Use **`IFeatureRouteModule`** when:

- The screen is reached by **push / go** (login, register, detail, wizard, onboarding).
- It is **not** a bottom-nav destination.
- Sibling path order does not matter (GoRouter matches by path).

**Wrong:** implementing `IDashboardTabModule` for “Forgot password” or “Edit profile” just to avoid writing a Navigator.  
**Right:** `IFeatureRouteModule` (if top-level under shell) or nested routes under a tab’s own route tree + `XxxNavigator`.

### Removing a tab or the whole dashboard

1. Remove the feature from root `workspace`, `app/pubspec.yaml`, and `ExternalModule(...)` in `injection.dart`.
2. Do **not** edit route arrays in `app_router.dart`.
3. Hot **restart** (DI graph changes are not applied by hot reload).
4. If fewer than 2 tabs remain, `DashboardPage` hides the bottom bar; with zero tabs, `AppRouter` mounts an empty placeholder branch.

---

## 💻 3. Detailed Practical Guide

Below is the standard for implementing decentralized routing by Feature:

### Step 1: Declare local Interface inside `core_di`
Create the file `packages/core/di/lib/src/navigators/auth_navigator.dart`:
```dart
import 'package:flutter/widgets.dart';

abstract class AuthNavigator {
  void toLogin(BuildContext context);
  void toRegister(BuildContext context);
  void toForgotPassword(BuildContext context);
}
```
*Note: The Interface Navigator only contains navigation methods to routes managed by that Feature itself. For example, `toHome()` does not belong to Auth so it is put into `HomeNavigator`.*

And don't forget to export it in the package's main barrel file (`packages/core/di/lib/core_di.dart`):
```dart
export 'src/navigators/auth_navigator.dart';
```

### Step 2: Call navigation via shell listener (preferred for global AuthProvider)
Global `AuthProvider` does **not** take `BuildContext` on `login` / `logout`. Update stream/state in the provider; navigate from `NavigatorWrapperWidget`'s `ProviderStateListener`:

```dart
import 'package:core_di/core_di.dart';

class AuthProvider extends BaseProvider<UserEntity> {
  // ...
  Future<void> login(String email, String password) async {
    await executeOperation(
      OperationConfig(
        operation: () => _loginUseCase(...),
        // Do NOT navigate here — shell ProviderStateListener handles login ↔ home.
      ),
    );
  }

  Future<void> logout() async {
    await executeOperation(
      OperationConfig(
        operation: () => _logoutUseCase(const NoParams()),
        showLoading: false,
        onSuccess: (_) async {
          // Clear retained user (Result<void> alone keeps old data).
          updateState(
            state: const ViewState.success(),
            data: null,
            retainOldData: false,
          );
        },
      ),
    );
  }
}
```

For **screen-scoped** feature navigators (non-global), you may still pass `BuildContext` into the method and call `getIt<HomeNavigator>().toHome(context)` from `onSuccess` when appropriate.

### Step 3: Actual implementation at the local Feature package
Create the implementation file inside the `routing/` directory of the corresponding Feature package, e.g.: `packages/features/auth/lib/src/routing/auth_navigator_impl.dart`:
```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'auth_route_module.dart';

@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) => const LoginRoute().go(context);

  @override
  void toRegister(BuildContext context) => const RegisterRoute().go(context);

  @override
  void toForgotPassword(BuildContext context) => const ForgotPasswordRoute().go(context);
}
```

Register to export the implementation file at the feature's routing barrel file (`packages/features/auth/lib/src/routing/routing.dart`). This helps GetIt automatically recognize it via micro-package DI and load it into the Host App at startup.

---

## 🏛️ 4. Declaring & Hierarchizing Navigator Keys (Global Keys)

To strongly support nested routing structures (`Nested Shells`, `Tab Bar navigation`), prevent conflicts and cross-references between child packages, the monorepo centrally declares `GlobalKey<NavigatorState>`s at [routing_interfaces.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/di/lib/src/routing/routing_interfaces.dart):

```dart
class NavigatorKeys {
  NavigatorKeys._();
  static final appKey = GlobalKey<NavigatorState>();
  static final rootKey = GlobalKey<NavigatorState>();
  static final authKey = GlobalKey<NavigatorState>();
  static final homeKey = GlobalKey<NavigatorState>();
}
```

### Hierarchy & Scopes Rules:
1. **`rootKey`**: 
   - Root Navigator of the entire application (`GoRouter(navigatorKey: NavigatorKeys.rootKey)`).
   - Used to display screens overlaying the entire UI (like global Dialogs, BottomSheets, or the `UndefineRouteWidget` error screen).
2. **`appKey`**:
   - Used for the application's main Shell (`ShellRoute(navigatorKey: NavigatorKeys.appKey)`).
   - Wraps shared components via `NavigatorWrapperWidget` (auth boot redirect, global auth side-effects, and deep link listener via `DeeplinkProvider`).
3. **`authKey`**:
   - Local nested Navigator of `feature_auth` (`AuthShellRoute(navigatorKey: NavigatorKeys.authKey)`).
   - Ensures child routes like `LoginRoute`, `RegisterRoute` are pushed within the auth view frame: `static final $parentNavigatorKey = NavigatorKeys.authKey;`.
4. **`homeKey`**:
   - Local nested Navigator for pages belonging to the main tab (`feature_home`).

---

## 🚦 5. Managing AppRouter via Dependency Injection (GetIt)

The `AppRouter` class is configured as a GetIt `@singleton` to support mock tests and strictly adhere to the Dependency Injection Graph (DI Graph):

```dart
@singleton
class AppRouter {
  final routeObserver = RouteObserver<ModalRoute>();

  BuildContext get currentContext {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context?.mounted ?? false) {
      return router.routerDelegate.navigatorKey.currentContext!;
    }
    throw FlutterError('AppRouter [currentContext] cannot be null');
  }

  String get currentRouterName {
    final route = router.routerDelegate.currentConfiguration.last.route;
    return route.name ?? route.path;
  }

  late final GoRouter router = GoRouter(
    debugLogDiagnostics: kDebugMode,
    navigatorKey: NavigatorKeys.rootKey,
    refreshListenable: getItOrNull<AuthProvider>(),
    errorPageBuilder: (context, state) {
      return NoTransitionPage(child: UndefineRouteWidget(state: state));
    },
    // IAppEntryLocation → else first IDashboardTabModule.path → else '/'
    initialLocation: fallbackLocation,
    routes: [
      ShellRoute(
        navigatorKey: NavigatorKeys.appKey,
        parentNavigatorKey: NavigatorKeys.rootKey,
        builder: (context, state, child) =>
            NavigatorWrapperWidget(child: child),
        routes: [
          // ...getAllOrEmpty<IFeatureRouteModule>().expand((m) => m.routes)
          StatefulShellRoute(
            parentNavigatorKey: NavigatorKeys.appKey,
            // branches from getAllOrEmpty<IDashboardTabModule>() sorted by order
            branches: dashboardBranches,
            navigatorContainerBuilder: (context, navigationShell, children) {
              return getItOrNull<DashboardRouteModule>()
                      ?.navigatorContainerBuilder(
                        context,
                        navigationShell,
                        children,
                      ) ??
                  const SizedBox.shrink();
            },
            builder: (context, state, navigationShell) {
              return getItOrNull<DashboardRouteModule>()?.builder(
                    context,
                    state,
                    navigationShell,
                  ) ??
                  const SizedBox.shrink();
            },
          ),
        ],
      ),
    ],
  );
}
```

### 💡 Special note on the Splash Page:
- `SplashPage` is completely manually managed by the `MainScope` class (`AppMaterialWrapper(home: splashScreen)` does not use the router) to serve temporary display during configuration initialization at startup. 
- Because it doesn't use the router, **`SplashPage` is not declared a route path in GoRouter**. The `initialLocation` property of GoRouter comes from `getItOrNull<IAppEntryLocation>()?.path` (onboarding sample), then the first `IDashboardTabModule.path`, else `/`.

### 🧩 `NavigatorWrapperWidget` (App Shell)
- Lives at `app/lib/presentation/widgets/navigator_wrapper_widget.dart` (not inline inside `AppRouter`).
- Responsibilities:
  1. After the first frame (`WidgetsBinding.instance.endOfFrame.whenComplete`), await `AuthProvider.ensureInitialized()` (waits until `initialize()` — including session restore — finishes) then perform the **initial** auth-aware redirect / deep-link boot. Boot owns this first navigation.
  2. Wrap the shell child with `ProviderStateListener<AuthProvider, UserEntity>` for global auth toasts and **post-boot** login ↔ home navigation. Use `listenWhen` to ignore session-restore success so boot and the listener do not double-redirect.
- **`UndefineRouteWidget`** lives at `app/lib/presentation/widgets/undefine_route_widget.dart` and is used exclusively as GoRouter's `errorPageBuilder` child.

---

## 🚥 6. Route-Level Instantiation of Scoped UI Controllers

To ensure absolute independence between modules and optimal memory lifecycle management (Auto-dispose local state managers when leaving the screen), the monorepo applies the rule: **Every local Feature Controller (ViewModel, Bloc, Cubit) MUST be instantiated directly at the routing layer in the `build` method of the corresponding Route class.**

### ❌ WRONG Case (Anti-pattern):
1. Registering `@lazySingleton` or `@singleton` for a Feature Controller (like `OnboardingProvider` or `LoginBloc`). This wastes system RAM because its state will be permanently retained by GetIt even when the user has transitioned to another screen.
2. Instantiating a Widget Provider (ChangeNotifierProvider, BlocProvider) at the App Shell layer, leaking the Feature's internal implementation details to the Host App.

### ✅ CORRECT Case (Standard Pattern):
Declare the Controller with the `@injectable` annotation (so GetIt auto-maps dependent classes but generates a **new instance** each time it is retrieved). Then, provide this Controller right inside the Feature's `GoRouteDataCustom` class in the `route_module.dart` file:

**Example with Provider:**
```dart
@TypedGoRoute<OnboardingRoute>(path: OnboardingPath.ONBOARDING)
class OnboardingRoute extends GoRouteDataCustom with $OnboardingRoute {
  const OnboardingRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ChangeNotifierProvider(
      // Use getIt to auto-resolve UseCases/Services, significantly shortening code.
      // Because it's @injectable, it creates a brand new instance specifically for this Route.
      create: (context) => getIt<OnboardingProvider>(),
      child: const OnboardingPage(),
    );
  }
}
```

**Example with BLoC:**
```dart
@TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      create: (context) => getIt<LoginCubit>(),
      child: const LoginPage(),
    );
  }
}
```

### 💡 Benefits:
1. **Auto-dispose**: When the user transitions to another screen, the management framework (Provider / Bloc) will automatically call the `dispose()` or `close()` function to free the Controller from RAM.
2. **Encapsulation**: The Host App (`app`) package doesn't need to care at all about what state management tool that Feature uses. All logic setup lies entirely and safely inside the Feature Package.

---

## 💎 7. Absolute Benefits of the Fully Decentralized Model
1. **Completely eliminate Merge Conflicts**: Developers working on `feature_auth` only edit their local `AuthNavigator` and `auth_navigator_impl.dart` inside `feature_auth/routing/`. They never touch files of other features.
2. **100% compliant with ISP principle (Interface Segregation)**: Modules do not need to see each other's routing methods. They only need to declare and exactly use the methods they truly need.
3. **Independent and Isolated (Encapsulation)**: There are no reverse dependencies from core back to feature, completely eliminating circular dependencies. Easy to write independent Unit Tests by mocking each module's local Navigator.

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
