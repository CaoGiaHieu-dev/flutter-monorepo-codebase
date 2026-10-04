# Routing & Navigation

## Goal

You add a screen from inside a feature package, without touching the app shell. You build it as a type-safe route with `go_router_builder`, register it through DI, and let other features navigate to it through an interface instead of a hardcoded path. Optionally, you make it reachable from a deep link.

## Prerequisites

- A feature package — [`01_new_feature.md`](01_new_feature.md).
- **How the router is assembled** from DI contributions, the shell tree it builds, and how it degrades when a module is missing: [`../architecture/06_app_shell.md` § 5](../architecture/06_app_shell.md#5-router-assembly). The short version: `app_router.dart` is assembly only and never names a feature's routes (RULE-20).
- What the dashboard may and may not own: [`../architecture/05_features.md` § 4](../architecture/05_features.md#4-feature_dashboard-is-chrome-only).

---

## 1. Pick the routing contract

All contracts live in `platform/foundation/contracts/lib/src/routing/`.

| Contract | Use for | Ordered? | Implemented by |
|---|---|---|---|
| `IFeatureRouteModule` | Top-level / stack routes under the app shell | No — GoRouter matches by path | auth, onboarding, … |
| `INavDestinationModule` | One primary destination + its `StatefulShellBranch` | **Yes** — ascending `order` | home, settings, … |
| `IAppEntryLocation` | First-launch location (`initialLocation` until it has been shown once) | n/a | usually onboarding |
| `ISignInLocation` | Where the shell sends a signed-out user (boot, sign-out, session loss) | n/a | the session owner — `feature_auth` |
| `IPostSignInLocation` | Where the shell sends a signed-in user (boot, sign-in); else `fallbackLocation` | n/a | the landing module — `feature_home` |
| `IDashboardRouteModule` | Dashboard chrome (scaffold + bottom bar / rail host) | n/a | **only** `feature_dashboard` |

Use `INavDestinationModule` **only** for a real bottom-nav destination that needs its own persistent back stack. A screen you merely push onto the stack belongs in `IFeatureRouteModule` (RULE-24).

What the **app** — not a feature — decides about the router is declared in `apps/<id>/`: `RouterProfile` (from `platform_kernel`) in `lib/app/app_profile.dart` (`entry`: `EntryPolicy.firstLaunch` by default, `always` or `never`; `fallbackPath`: the first tab by default) and, in `lib/app/app_hooks.dart`, `ShellHooks.navigatorObservers` and `ShellHooks.redirect` — one app-wide guard; a module's own guard still goes in its `GoRouteData.redirect`. Deep links are per platform: `platforms.<p>.deep_links` in the manifest is on by default, and a platform that turns it off logs one line naming the key ([`13_app_composition.md`](13_app_composition.md)).

## 2. Add the path constant

Path constants live in the feature's `src/utils/` folder, not in `routing/` (RULE-09). `modules/auth/feature/lib/src/utils/auth_path.dart`:

```dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
}
```

## 3. Declare the typed route

Routes are declared with annotations and generated into `*_route_module.g.dart`. `modules/auth/feature/lib/src/routing/auth_route_module.dart`:

```dart
/// SAMPLE — a feature contributing a top-level route.
///
/// The login screen sits on the app navigator, above the dashboard's tabs,
/// so it names [NavigatorKeys.appKey] as its parent. Add sibling screens as
/// further `@TypedGoRoute` classes here and list them in
/// `AuthFeatureRouteModule.routes`.
///
/// Controllers are instantiated at the route, not inside the page — RULE-21.
/// Here `AuthProvider` is a global `@lazySingleton` mounted by
/// `AuthTreeWrapper`, so this route builds the page directly. A screen-scoped
/// controller would wrap it in
/// `ChangeNotifierProvider(create: (_) => getIt<XProvider>())` instead.
@TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();

  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget build(BuildContext context, GoRouterState state) => const LoginPage();
}
```

A stack route sits on the app navigator, above the dashboard's tabs, so it names `NavigatorKeys.appKey` as its `$parentNavigatorKey`. A tab's route (`HomeRoute`) names none: the shell mounts it in the tab's own `StatefulShellBranch`. Add sibling screens as further `@TypedGoRoute` classes in the same file and list their generated `$…Route` getters in the feature's `IFeatureRouteModule.routes` (step 5).

### Pass route parameters

A path parameter is a `:name` segment in the path constant; a query parameter is any other constructor field. `go_router_builder` matches both to the route class's constructor fields by name and parses them to their Dart type. In `lib/src/utils/profile_path.dart`:

```dart
static const String DETAIL = '/profile/:id';
```

In the route file:

```dart
@TypedGoRoute<ProfileDetailRoute>(path: ProfilePath.DETAIL)
class ProfileDetailRoute extends GoRouteDataCustom with $ProfileDetailRoute {
  const ProfileDetailRoute({required this.id, this.tab});

  final String id; // path parameter — `/profile/42`
  final int? tab; // query parameter — `/profile/42?tab=2`

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ChangeNotifierProvider(
      create: (_) => getIt<ProfileDetailProvider>(param1: id),
      child: ProfileDetailPage(initialTab: tab ?? 0),
    );
  }
}
```

Navigate with the typed class — `const ProfileDetailRoute(id: '42', tab: 2).go(context)` — never by building the string. The controller takes the id as a factory parameter, `ProfileDetailProvider(@factoryParam this._id)`, passed from the route as above (RULE-11, RULE-21). A factory with a **non-nullable** `@factoryParam` is the one kind the DI smoke test cannot build without its screen: list its type in `_factoriesNeedingArguments` in `apps/<id>/test/di_smoke_test.dart`, with the reason (`F01`, [`05_di.md`](05_di.md)). Another feature reaches the screen through a navigator method that takes the parameter — `void toProfileDetail(BuildContext context, {required String id})` in `profile_api` (step 6).

### Page behaviour: screen analytics, back gesture, page key

`GoRouteDataCustom` builds the page for you, on every platform including the web: it wraps `build()`'s result in a `RouteAwareWidget`, so each screen is reported to the optional `IAnalytics` as a screen view, and it picks the transition the platform expects (a `CupertinoPage` on iOS, a plain `MaterialPage` on the web, a Cupertino-style slide elsewhere). Two getters change that page, and both apply on every platform:

```dart
class CheckoutRoute extends GoRouteDataCustom with $CheckoutRoute {
  const CheckoutRoute();

  @override
  bool get canPop => false; // the system back gesture or button does not dismiss it

  @override
  ValueKey<Object?>? get pageKey => const ValueKey('checkout'); // two locations share one page

  @override
  Widget build(BuildContext context, GoRouterState state) => const CheckoutPage();
}
```

`canPop` defaults to `true`. `pageKey` defaults to `null`, which uses `state.pageKey`; return a stable key only when go_router should update one page in place instead of replacing it. Do not override `buildPage`, and do not call `routePageFor`, the function behind it: it is public for tests only.

## 4. Create the controller in the route

The route's `build()` is where a screen controller is created and bound to the tree (RULE-21).

**BLoC** — `modules/home/feature/lib/src/routing/home_route_module.dart`:

```dart
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

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
> The page itself must **not** wrap in a second provider. See [`03_state_management.md`](03_state_management.md) § 9.

A screen backed by a **global** controller (e.g. `LoginPage` with the `@lazySingleton` `AuthProvider`) builds the page directly, with no wrapper.

## 5. Register the route contract

Register it in the feature's own DI module, annotated `@LazySingleton(as: ...)`. Never add the route to `app_router.dart` (RULE-20).

### A stack route — `IFeatureRouteModule`

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
```

Where the first launch starts is a separate contract, registered next to it — `onboarding_app_entry_location.dart`:

```dart
@LazySingleton(as: IAppEntryLocation)
class OnboardingAppEntryLocation implements IAppEntryLocation {
  @override
  String get path => OnboardingPath.ONBOARDING;
}
```

Use unique paths and avoid overlapping catch-alls: sibling order between modules is not guaranteed.

### A primary tab — `INavDestinationModule`

```dart
abstract class INavDestinationModule {
  int get order; // ascending sort key, 0 = first tab
  String get path; // canonical path, used for fallbacks
  List<RouteBase> get routes; // mounted in one StatefulShellBranch
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

`order` is an ascending sort key, not an index, and must be unique across tabs. `destination` returns a neutral `NavDestination` (`label`, `icon`, optional `selectedIcon`), so the same contribution renders as a bottom-bar item or a rail item. `feature_dashboard` builds that chrome from every registered tab and drops it when fewer than two are registered ([`../architecture/05_features.md` § 4](../architecture/05_features.md#4-feature_dashboard-is-chrome-only)); re-tapping the current tab returns its branch to the first page. An app that composes two or more tabs must compose `feature_dashboard` too and declare `dashboard: provided`, or only the first tab is reachable — `checkAppContract` fails the smoke test with `C12` ([`13_app_composition.md` § 6](13_app_composition.md#6-contracts-what-the-shell-asks-of-an-app)). Why the chrome switches on window size class: [`11_design_system.md` § 7](11_design_system.md#7-lay-out-for-tablets-foldables-and-split-screen).

### The dashboard chrome — `IDashboardRouteModule`

Only `feature_dashboard` implements this contract. The shell sorts the registered tabs by `order` once and hands that same list to the dashboard, so destination `i` is branch `i` of `navigationShell`; render the list, do not collect the tabs again:

```dart
abstract class IDashboardRouteModule {
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
    List<INavDestinationModule> destinations,
  );
}
```

```dart
// modules/dashboard/feature/lib/src/routing/dashboard_route_module_impl.dart
@Singleton(as: IDashboardRouteModule)
class DashboardRouteModuleImpl implements IDashboardRouteModule {
  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
    List<INavDestinationModule> destinations,
  ) {
    return DashboardPage(
      navigationShell: navigationShell,
      destinations: destinations,
    );
  }
}
```

Without it the destinations still render, just without chrome.

## 6. Let other features navigate to your screen

Feature A never imports feature B (RULE-04). Navigation crosses the boundary through an interface in **module B's API package** — `modules/<id>/api`, named `<id>_api`. Feature A depends on that instead of feature B (`arch_check` R3). `core_di` holds no module's navigator (RULE-22).

**1. Declare** — `modules/auth/api/lib/src/navigators/auth_navigator.dart` (package `auth_api`):

```dart
abstract class AuthNavigator {
  void toLogin(BuildContext context);
}
```

One method per route the feature owns — and only routes it owns.

A **new** file in the API package is invisible to every consumer until the package barrel, `package:auth_api/auth_api.dart`, exports it. The barrel is generated: regenerate it, never hand-add the `export`, because the generator replaces every export it finds (RULE-75). A module with no API package yet gets one first: `dart tools/module_generator/generate.dart 6 <name>` writes the package and the navigator stub, and implements it in the module's feature if that exists ([`01_new_feature.md`](01_new_feature.md) § 7; layout and what `arch_check` holds it to: [`12_module_isolation.md` § 4](12_module_isolation.md#4-create-a-module-api-package)).

```bash
dart tools/barrel_generator/generate.dart modules/auth/api/lib
```

**2. Implement it in the owning feature** — `modules/auth/feature/lib/src/routing/auth_navigator_impl.dart`:

```dart
@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) => const LoginRoute().go(context);
}
```

**3. Call it from any feature that lists `auth_api` in its `dependencies:`:**

```dart
// From any package other than the owner — the owner is removable:
getItOrNull<AuthNavigator>()?.toLogin(context);

// Only inside feature_auth itself, which cannot be absent from its own code:
getIt<AuthNavigator>().toLogin(context);
```

Rules that apply at the call site:

- **RULE-22** · Never hardcode a path string or call `GoRouter.of(context).go('/auth/login')` to reach another feature.
- **RULE-23** · Pass `BuildContext` straight from the calling widget. Do not use `NavigatorKeys.*.currentContext` or `appRouter.currentContext`: those bypass the widget lifecycle and cause "used after dispose" bugs.
- **RULE-12** · Use `getItOrNull` wherever the call must survive the target feature being removed.
- **RULE-22** · The app shell uses no module navigator. A signed-out user goes to `ISignInLocation.path`, a signed-in one to `IPostSignInLocation.path`. The session owner and the landing module contribute those (`AuthSignInLocation`, `HomePostSignInLocation`), and `NavigatorWrapperWidget` calls `context.go(path)` itself.

## 7. Give a module its own back stack

`platform/foundation/contracts/lib/src/routing/navigator_keys.dart`:

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

Two keys are fixed: `appKey`, the navigator of the shell route that wraps every in-app route (a stack route names it as its `$parentNavigatorKey`, as `LoginRoute` does in step 3), and `rootKey`, the root navigator, for a full-screen route that must escape the shell. Ask for `NavigatorKeys.nested('<id>')` **only** when a module genuinely needs its own nested navigator — its own back stack. The shell route and its child routes must name the same id:

```dart
class CheckoutShellRoute extends ShellRouteData {
  static final $navigatorKey = NavigatorKeys.nested('checkout');
}
```

Destinations inside `StatefulShellRoute` get a branch navigator from GoRouter and need none. Why the keys live in `core_di`: [`../architecture/06_app_shell.md` § 5](../architecture/06_app_shell.md#why-navigatorkeys-live-in-core_di).

## 8. Generate the routes and export the files

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<name>/feature/lib
```

Run `build_runner` after **any** change to a route annotation. Then run the barrel generator for every package you added a file to — including `modules/<id>/api/lib` when you added a navigator (step 6).

## 9. Set up deep links

Two link shapes reach the app, and both land on the same router location:

| Link | Router location |
|:---|:---|
| `https://<WEB_DOMAIN>/settings?tab=2` (Android App Link / iOS universal link) | `/settings?tab=2` |
| `<scheme>://settings?tab=2` (custom scheme — the first segment sits in the host position) | `/settings?tab=2` |

The platform delivers the URI to `app_links`. `DeeplinkProvider` (`platform/shell/app_shell/lib/src/provider/deeplink_provider.dart`) turns it into a location with `locationOf` and routes it. It does so only after `canRoute` has checked the session, and only once `NavigatorWrapperWidget` has started it — never over onboarding or login. A path no module registered lands on `UndefinedRouteWidget`, like any unknown location.

### Keep Flutter's own deep linking off

Since Flutter 3.27 the engine also handles deep links by default. It pushes the URI straight into `GoRouter`, skipping `DeeplinkProvider` and its session check: a signed-out user could open a signed-in screen, and each link would be routed twice. Both platforms therefore switch it off:

- Android — inside `<activity>` in `apps/mobile/android/app/src/main/AndroidManifest.xml`: `<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />`
- iOS — `apps/mobile/ios/Runner/Info.plist`: `FlutterDeepLinkingEnabled` = `false`

Do not remove either while `DeeplinkProvider` is the router's only way in.

### Set the per-flavor values

| Flavor | Custom scheme | Android application id | iOS bundle id |
|:---|:---|:---|:---|
| `dev` | `codebase-dev` | `com.example.codebase.dev` | `com.example.codebase.dev` |
| `staging` | `codebase-stg` | `com.example.codebase.stg` | `com.example.codebase.staging` |
| `prod` | `codebase` | `com.example.codebase` | `com.example.codebase` |

One scheme per flavor, so dev, staging and prod installed side by side never compete for a link. The scheme is declared twice, and the two must agree:

- `resValue("string", "DEEP_LINK_SCHEME", …)` in each `productFlavors` entry of `apps/mobile/android/app/build.gradle.kts`;
- the `DEEP_LINK_SCHEME` build setting of each Runner configuration in `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (Xcode: *Runner → Build Settings → User-Defined*).

Rename the Android and the iOS values together when you rename the app.

`WEB_DOMAIN` comes from the flavor's env file (`apps/mobile/env.dev`, …). The committed env files leave it empty.

### Configure Android

`AndroidManifest.xml` declares two `VIEW` intent-filters on `MainActivity`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" />
    <data android:host="@string/WEB_DOMAIN" />
</intent-filter>
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="@string/DEEP_LINK_SCHEME" />
</intent-filter>
```

`@string/WEB_DOMAIN` is a `resValue` that `build.gradle.kts` decodes from the dart-defines. When the env file leaves `WEB_DOMAIN` empty it becomes `example.invalid`, a reserved domain that never resolves. An empty host would make the filter claim every https link.

**App Links verification.** `autoVerify` makes Android fetch `https://<WEB_DOMAIN>/.well-known/assetlinks.json` at install time. Serve it over https, with no redirect, as `application/json`, listing every flavor that uses that domain:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.codebase",
      "sha256_cert_fingerprints": ["AA:BB:…"]
    }
  }
]
```

The fingerprint is that of the key the **installed** APK is signed with:

- for a key you sign with yourself: `keytool -list -v -keystore <release.jks> -alias <alias>`;
- for a Play build under Play App Signing: the *App signing key certificate* SHA-256 from Play Console → *Test and release → App integrity* — not your upload key's.

Check the result on a device:

```bash
adb shell pm get-app-links com.example.codebase            # "verified" per domain
adb shell pm verify-app-links --re-verify com.example.codebase
adb shell am start -a android.intent.action.VIEW -d "codebase-dev://settings?tab=2"
adb shell am start -a android.intent.action.VIEW -d "https://<WEB_DOMAIN>/settings?tab=2"
```

### Configure iOS

**Custom scheme.** `Info.plist` registers it under `CFBundleURLTypes`, with `CFBundleURLSchemes` = `$(DEEP_LINK_SCHEME)` and `CFBundleURLName` = `$(PRODUCT_BUNDLE_IDENTIFIER)`. Nothing else is needed: `xcrun simctl openurl booted "codebase-dev://settings?tab=2"` opens the dev build.

**Universal links** stay off until you own the domain, because the entitlement makes provisioning fail for an App ID without the capability. To turn them on:

1. Enable **Associated Domains** on each App ID in the Apple Developer portal (or *Signing & Capabilities → + Capability* in Xcode) and regenerate the provisioning profiles.
2. Uncomment the `com.apple.developer.associated-domains` block in `apps/mobile/ios/Runner/Runner.entitlements`.
   - Its value, `applinks:$(WEB_DOMAIN)$(APP_LINK_MODE)`, is expanded from `Flutter/Environment.xcconfig`. Each flavor scheme's build pre-action writes that file from the dart-defines, so build through a flavor scheme (`--flavor`).
   - Leave `APP_LINK_MODE` empty in production; `?mode=developer` bypasses Apple's CDN cache on a device with *Associated Domains Development* enabled.
3. Serve `https://<WEB_DOMAIN>/.well-known/apple-app-site-association` — no file extension, `application/json`, no redirect:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["ABCDE12345.com.example.codebase"],
        "components": [{ "/": "/*" }]
      }
    ]
  }
}
```

`ABCDE12345` is your Team ID; add one `appIDs` entry per bundle id served from that domain. Apple fetches the file through its CDN when the app is installed, so a change can take a while to reach devices. That is what `?mode=developer` is for.

---

## Verify

```bash
dart run build_runner build --workspace   # the *.g.dart route files and DI registrations
flutter analyze                           # No issues found!
dart tools/arch_check/check.dart          # ✅ All architecture rules hold … (R3, R8, R10)
cd apps/mobile && flutter test test/di_smoke_test.dart   # every route module resolves
```

`platform/shell/app_shell/test/app_router_test.dart` shows how to test routing against a real `AppRouter`. For deep links, use the `adb` and `xcrun` commands of step 9.

Review checklist:

- [ ] `app_router.dart` untouched
- [ ] Path constants under `src/utils/`, not `routing/`
- [ ] Controller created in the route's `build()`, page does not re-wrap
- [ ] `INavDestinationModule.order` sorts the tab into the intended position (ascending sort key, not an index) and is unique
- [ ] Cross-feature navigation goes through the target module's `<id>_api` Navigator interface
- [ ] `BuildContext` passed from the UI, never taken from `NavigatorKeys`
- [ ] `build_runner` re-run after touching route annotations
- [ ] Deep links still reach the router only through `DeeplinkProvider` — `flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled` stay `false` (step 9)

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `Undefined name '$myRoute'` or a missing `*.g.dart` | `build_runner` has not run since the annotation changed | `dart run build_runner build --workspace` (step 8) |
| The new screen is unreachable; GoRouter shows `UndefinedRouteWidget` | The route contract is not registered, or the app was hot-reloaded | Check the `@LazySingleton(as: IFeatureRouteModule)` annotation, re-run `build_runner`, then **full restart** |
| `Undefined name 'MyNavigator'` in a consumer | The API package's barrel does not export the new file | Run the barrel generator for `modules/<id>/api/lib` (step 6) |
| Tabs appear in the wrong order, or one replaces another | Two `INavDestinationModule`s share an `order` | Give each tab a unique `order` (step 5) |
| No bottom bar or rail | Fewer than two tabs are registered | Expected: the dashboard drops the chrome below two tabs |
| A deep link opens a screen while signed out, or routes twice | Flutter's own deep linking was turned back on | Restore `flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled` = `false` (step 9) |
| `pm get-app-links` does not report `verified` | `assetlinks.json` is missing, redirected, or lists the wrong fingerprint | Serve it as in step 9, with the installed APK's signing key |
| Provisioning fails after enabling universal links | The App ID lacks the Associated Domains capability | Enable it and regenerate the profiles (step 9) |

## Related

- Rules: RULE-04 (no feature → feature import), RULE-12 (optional lookups), RULE-20 (never edit `app_router.dart`), RULE-21 (controller at the route), RULE-22 (navigators in `<id>_api`), RULE-23 (`BuildContext` from the caller), RULE-24 (tabs vs pushed screens) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/06_app_shell.md` § 5](../architecture/06_app_shell.md#5-router-assembly) — router assembly, entry vs fallback location, graceful degradation
- [`13_app_composition.md`](13_app_composition.md) — `RouterProfile`, the routing hooks and the per-platform deep-link switch
- [`03_state_management.md`](03_state_management.md) — controller lifecycle
- [`05_di.md`](05_di.md) — how contracts get registered and collected
- [`10_cross_feature.md`](10_cross_feature.md) — the other cross-feature models
