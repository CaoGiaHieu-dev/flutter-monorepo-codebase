---
name: implement_navigation_route
description: Use when adding a screen or route, linking navigation between features, or adding a tab — "create a new page and navigate to it", "navigate from feature A to feature B", "add a bottom-nav tab", "add route parameters". Covers GoRouteDataCustom typed routes (path and query parameters), path constants in utils/, the navigator contract in the owner's <id>_api (generator type 6), the controller created at the route, and IFeatureRouteModule / INavDestinationModule registration.
---

# Skill: Implement navigation and routes

Use this skill to add a screen inside a feature, link navigation between features, add a bottom-nav tab,
or pass route parameters.

**Guide:** [`docs/en/guides/04_routing.md`](../../../docs/en/guides/04_routing.md) — read § 1
(Pick the routing contract) first: when `INavDestinationModule` and when `IFeatureRouteModule`; what
`feature_dashboard` must not own is [`architecture/05_features.md` § 4](../../../docs/en/architecture/05_features.md#4-feature_dashboard-is-chrome-only).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-04, RULE-09, RULE-12, RULE-20,
RULE-21, RULE-22, RULE-23, RULE-24, RULE-78. Cite them; do not restate them.

## Pick the contract (one)

| Need | Contract | Notes |
| :--- | :--- | :--- |
| Bottom-nav primary tab | `INavDestinationModule` | `order`, `path`, `routes`, `destination(context)`. `order` is an ascending sort key, unique across tabs (check C06); two or more tabs need `feature_dashboard` composed and `dashboard: provided` (check C12) |
| Stack / pushed screen (login, detail, onboarding) | `IFeatureRouteModule` | `routes` only, no `order` — GoRouter matches by path |
| First-launch path | `IAppEntryLocation` | Optional; used only until the onboarding-seen flag is set |
| Dashboard chrome | `IDashboardRouteModule` | **Only** `feature_dashboard` |

The generator writes the stub for the choice you passed as `<route>` (`generate.dart 1 <name> "" <SM> <route>`).
A route you add later is a further `@TypedGoRoute` in the same `routing/*_route_module.dart`, listed in the
feature's contract implementation. Never append a route to `app_router.dart` (RULE-20).

## Steps

### Step 1: Path constants in `utils/`

Route paths are constants, so they live in `lib/src/utils/`, not `routing/` (RULE-09). Edit the
generated `utils/<name>_path.dart` (shape of `modules/home/feature/lib/src/utils/home_path.dart`):

```dart
class ProfilePath {
  ProfilePath._();

  static const String PROFILE = '/profile';
  static const String DETAIL = '/profile/:id';
}
```

### Step 2: The typed route

In the feature's `routing/<name>_route_module.dart`, extend `GoRouteDataCustom` (`core_common`). A stack route
sits on the app navigator, above the dashboard's tabs, so it names `NavigatorKeys.appKey` as its parent; a
tab's route names none (`modules/auth/feature/lib/src/routing/auth_route_module.dart` is the stack
example, `modules/home/feature/lib/src/routing/home_route_module.dart` the tab).

```dart
@TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();

  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget build(BuildContext context, GoRouterState state) => const LoginPage();
}
```

**Route parameters.** A path parameter is a `:name` segment in the path constant; a query parameter is any
other constructor field. `go_router_builder` matches both to the constructor fields by name:

```dart
@TypedGoRoute<ProfileDetailRoute>(path: ProfilePath.DETAIL)
class ProfileDetailRoute extends GoRouteDataCustom with $ProfileDetailRoute {
  const ProfileDetailRoute({required this.id, this.tab});

  final String id; // path parameter  — /profile/42
  final int? tab;  // query parameter — /profile/42?tab=2

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ChangeNotifierProvider(
      create: (_) => getIt<ProfileDetailProvider>(param1: id),
      child: ProfileDetailPage(initialTab: tab ?? 0),
    );
  }
}
```

Navigate with the typed class — `const ProfileDetailRoute(id: '42', tab: 2).go(context)` — never by
building the string. The controller takes the id as `ProfileDetailProvider(@factoryParam this._id)`. A factory
with a **non-nullable** `@factoryParam` cannot be built by the DI smoke test without its screen: list its type
in `_factoriesNeedingArguments` in `apps/<id>/test/di_smoke_test.dart`, with the reason (check F01,
[`05_di.md`](../../../docs/en/guides/05_di.md)).

### Step 3: Create the controller at the route, never in the `Page` (RULE-21)

```dart
@override
Widget build(BuildContext context, GoRouterState state) {
  return BlocProvider(
    // Auth is optional: an app composed without `feature_auth` registers
    // no ISessionStatusStream, and Home then shows the signed-out state.
    create: (_) => getIt<HomeProfileBloc>(param1: getItOrNull<ISessionStatusStream>()),
    child: const HomePage(),
  );
}
```

A Provider feature wraps the page in `ChangeNotifierProvider(create: (context) => getIt<ProfileProvider>(), …)`
the same way; a BLoC route adds `..add(const XEvent.started())`. The page must **not** wrap itself again. A
screen backed by a global controller (`LoginPage` with the `@lazySingleton` `AuthProvider`) builds the page
directly. The controller kinds are in [`implement_provider_ui`](../implement_provider_ui/SKILL.md) and
[`implement_bloc_ui`](../implement_bloc_ui/SKILL.md).

### Step 4: Register the contract

Implement the chosen contract with `@LazySingleton(as: …)` in the feature (the generator wrote the stub:
`*_feature_route_module.dart` or `*_nav_destination.dart`):

```dart
@LazySingleton(as: IFeatureRouteModule)
class ProfileFeatureRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [$profileRoute, $profileDetailRoute];
}
```

The package is composed by its module line in each `apps/<id>/app_manifest.yaml` (the generator adds it) and
`dart tools/composer/composer.dart sync`; never hand-edit an app's `pubspec.yaml` or `injection.dart`
(RULE-16). Declare the capability the contract needs in every composing app — a tab is `tabs: provided`,
routes `routes: provided` (RULE-81; `composer verify` V3 names the line to paste).

### Step 5: Let other features navigate here — through `<id>_api`

Feature A never imports feature B (RULE-04) and never uses a path string (RULE-22). The module's API package,
`modules/<id>/api` (package `<id>_api`), holds a navigator contract; **one method per route the feature
owns, and only its own routes**. `core_di` holds no module navigator. If the module has no API package yet:

```bash
dart tools/module_generator/generate.dart 6 profile
```

It creates `modules/<id>/api` with a `ProfileNavigator` stub (`toProfile(BuildContext)`), adds `api` to the
module's `layers:` in every manifest (or only `--apps`), runs `composer sync`, and — if `feature_profile`
exists with its generated route — declares `profile_api` in the feature's `dependencies:` and writes
`routing/profile_navigator_impl.dart`. The skill for that package is [`create_api_package`](../create_api_package/SKILL.md).
Then shape the contract and keep the implementation in step (add a parameter-taking method for Step 2's
detail route):

```dart
// modules/profile/api/lib/src/navigators/profile_navigator.dart
abstract class ProfileNavigator {
  void toProfile(BuildContext context);
  void toProfileDetail(BuildContext context, {required String id});
}

// modules/profile/feature/lib/src/routing/profile_navigator_impl.dart
@LazySingleton(as: ProfileNavigator)
class ProfileNavigatorImpl implements ProfileNavigator {
  @override
  void toProfile(BuildContext context) => const ProfileRoute().go(context);

  @override
  void toProfileDetail(BuildContext context, {required String id}) =>
      ProfileDetailRoute(id: id).go(context);
}
```

Real examples: `modules/auth/api/lib/src/navigators/auth_navigator.dart` (`auth_api`),
`modules/home/api/lib/src/navigators/home_navigator.dart` (`home_api`). The implementation lives in the owning
feature and the owning feature declares `<id>_api` in its `dependencies:`; **a caller** lists `<id>_api` too,
never the other feature. Implementation classes are `*NavigatorImpl` in `*_navigator_impl.dart` (RULE-78).

### Step 6: Call it

```dart
getItOrNull<ProfileNavigator>()?.toProfileDetail(context, id: '42');
```

`getItOrNull`, not `getIt` (RULE-12; only `feature_profile` itself may use `getIt<ProfileNavigator>()`), and
`context` straight from the widget (RULE-23): never `NavigatorKeys.*.currentContext`. The app shell uses no
module navigator: it sends a signed-out user to `ISignInLocation.path` and a signed-in one to
`IPostSignInLocation.path`.

### Step 7: Codegen and restart

Run `dart run build_runner build --workspace` after any change to a route annotation or DI annotation, then
**fully restart** the app: hot reload does not pick up new DI registrations. If an annotation imports a type
from `<id>_api` that you just added there, regenerate that package's barrel first; barrels last. See
[`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator). Translated labels (a tab's
`destination`) come from the feature's ARB: [`localize_feature`](../localize_feature/SKILL.md).

## `NavigatorKeys`

`platform/foundation/contracts/lib/src/routing/navigator_keys.dart`: `appKey` (the app `ShellRoute`'s
navigator — a stack route's `$parentNavigatorKey`), `rootKey` (GoRouter's own navigator, for a full-screen
route that must escape the shell) and `nested(String id)` (the same instance per id). **Never add a key to the
class.** A module that needs its own back stack asks for one —
`static final $navigatorKey = NavigatorKeys.nested('checkout');` — on its shell route; a tab inside the
`StatefulShellRoute` gets a branch navigator from GoRouter and needs none. Why the keys sit in `core_di`:
[`06_app_shell.md`](../../../docs/en/architecture/06_app_shell.md#why-navigatorkeys-live-in-core_di).

## Keep features removable

The shell talks to `core_di` contracts, never to feature types, and degrades when a module is missing
(`platform/shell/app_shell/lib/src/navigation/app_router.dart`): no route modules gives empty lists, no
destination a placeholder branch at `/_empty_dashboard`, no `IAppEntryLocation` the first destination's path,
no `IDashboardRouteModule` the bare `navigationShell` (tabs without chrome). Splash is managed by `MainScope`,
not a GoRouter route. How the router is assembled:
[`06_app_shell.md` § 5](../../../docs/en/architecture/06_app_shell.md#5-router-assembly).

## Related

- [`docs/en/architecture/06_app_shell.md`](../../../docs/en/architecture/06_app_shell.md) — how the shell assembles routes
- [`implement_action_handler`](../implement_action_handler/SKILL.md) — cross-feature UI actions that are not navigation
- [`implement_dependency_injection`](../implement_dependency_injection/SKILL.md) — scopes and `getItOrNull`

## Verify

```bash
dart run build_runner build --workspace                  # routes ($fooRoute) and DI
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R3 no feature -> feature, R8 getItOrNull, R10
dart tools/composer/composer.dart verify                 # capabilities (V3), api layer
cd modules/<name>/feature && flutter test
cd apps/mobile && flutter test test/di_smoke_test.dart   # router assembles, tab orders unique (C06, C12)
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77, after a DI or dependency change
```
