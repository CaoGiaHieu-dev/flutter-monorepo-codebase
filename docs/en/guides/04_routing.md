# Routing & Navigation

**This guide answers:** how do I add a screen, and how do I navigate to a screen owned by another feature?

**After reading you can:** register routes from inside a feature package without touching the app shell, build type-safe routes with `go_router_builder`, and navigate across features through interfaces instead of hardcoded paths.

---

## 1. The core idea: routing is decentralised

`platform/shell/app_shell/lib/presentation/navigation/app_router.dart` is **assembly only**. It never names a feature's routes — it collects whatever features registered through DI:

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

All live in `platform/foundation/contracts/lib/src/routing/`.

| Contract | Use for | Ordered? | Implemented by |
|---|---|---|---|
| `IFeatureRouteModule` | Top-level / stack routes under the app shell | No — GoRouter matches by path | auth, onboarding, … |
| `INavDestinationModule` | One primary destination + its `StatefulShellBranch` | **Yes** — ascending `order` | home, settings, … |
| `IAppEntryLocation` | First-launch location (`initialLocation` until it has been shown once) | n/a | usually onboarding |
| `ISignInLocation` | Where the shell sends a signed-out user (boot, sign-out, session loss) | n/a | the session owner — `feature_auth` |
| `IPostSignInLocation` | Where the shell sends a signed-in user (boot, sign-in); else `fallbackLocation` | n/a | the landing module — `feature_home` |
| `DashboardRouteModule` | Dashboard chrome (scaffold + bottom bar / rail host) | n/a | **only** `feature_dashboard` |

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
  // Re-tap on the active tab. Concrete, not abstract: the default body only
  // logs — override it for "scroll to top / pop to root".
  void onRestore() {
    DynamicLogger.log('onRestore $runtimeType', level: LogLevel.INFO);
  }
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

Among workspace packages `feature_dashboard` depends on just `core_di`, `core_responsive` and `platform_kernel` — it physically **cannot** import another feature. Its page builds the navigation from DI (`modules/dashboard/feature/lib/src/pages/dashboard_page.dart`): a bottom bar on a `compact` window, a `NavigationRail` from `medium` up.

```dart
final tabs = getAllOrEmpty<INavDestinationModule>().toList()
  ..sort((a, b) => a.order.compareTo(b.order));
if (tabs.length < 2) return Scaffold(body: navigationShell);
// …
final sizeClass = context.windowSizeClass;
if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
  return Scaffold(
    body: navigationShell,
    bottomNavigationBar: BottomNavigationBar(
      // …
    ),
  );
}
// … otherwise a NavigationRail beside the navigationShell
```

The dashboard **must not**:
- import `feature_home` / `feature_settings` or embed their pages
- own tab pages or business BLoCs
- hardcode a destination list instead of reading DI
- register `INavDestinationModule` itself for a "fake" tab

Note `tabs.length < 2` drops the bar (or rail) entirely when fewer than two tabs are registered — part of the graceful-degradation story in §7. A tab's `destination` is a neutral `NavDestination`, so the same contribution renders as a bar item or a rail item; why the chrome switches on window size class is in [`11_design_system.md`](11_design_system.md#7-adaptive-layouts-tablets-foldables-split-screen).

---

## 3. Type-safe routes with `go_router_builder`

Routes are declared with annotations and generated into `*_route_module.g.dart`. **Run `dart run build_runner build --workspace` after any change.**

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
> The page itself must **not** wrap in a second provider. See [`03_state_management.md`](03_state_management.md) §4.

Routes for screens backed by a **global** controller (e.g. `LoginPage` with the `@lazySingleton` `AuthProvider`) build the page directly, with no wrapper.

---

## 5. Cross-feature navigation

Feature A must never import Feature B. Navigation crosses the boundary through an interface in **module B's API package** — `modules/<id>/api`, named `<id>_api` — which feature A depends on instead of feature B (`arch_check` R3). `core_di` holds no module's navigator.

**1. Declare** — `modules/auth/api/lib/src/navigators/auth_navigator.dart` (package `auth_api`):

```dart
abstract class AuthNavigator {
  void toLogin(BuildContext context);
}
```

One method per route the feature owns — and only routes it owns.

A **new** file in the API package is invisible to every consumer until the barrel exports it — `package:auth_api/auth_api.dart` re-exports `src/navigators/navigators.dart`, which is generated. Regenerate it (never hand-add the `export`; the generator deletes hand-written lines). A module with no API package yet gets one first: `docs/en/guides/12_module_isolation.md` § 7.

```bash
dart tools/barrel_generator/generate.dart modules/auth/api/lib
```

**2. Implement in the owning feature** — `modules/auth/feature/lib/src/routing/auth_navigator_impl.dart`:

```dart
@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) => const LoginRoute().go(context);
}
```

**3. Consume from any feature that lists `auth_api` in its `dependencies:`:**

```dart
// From any package other than the owner — the owner is removable:
getItOrNull<AuthNavigator>()?.toLogin(context);

// Only inside feature_auth itself, which cannot be absent from its own code:
getIt<AuthNavigator>().toLogin(context);
```

### Rules

- **RULE-22** · A Navigator interface exposes **only** routes its own feature owns.
- **RULE-22** · **Never** hardcode a path string or call `GoRouter.of(context).go('/auth/login')` to reach another feature.
- **RULE-23** · **`BuildContext` must be passed in directly from the calling widget.** Do not reach for `NavigatorKeys.*.currentContext` or `appRouter.currentContext` — those bypass the widget lifecycle and produce "used after dispose" bugs.
- **RULE-12** · Use `getItOrNull` at call sites that must survive the target feature being removed.
- **RULE-22** · **The app shell uses no module navigator.** A signed-out user goes to `ISignInLocation.path`, a signed-in one to `IPostSignInLocation.path` — product-neutral `core_di` contracts the session owner and the landing module contribute (`AuthSignInLocation`, `HomePostSignInLocation`); `NavigatorWrapperWidget` calls `context.go(path)` itself.

---

## 6. `NavigatorKeys` — why they live in the DI Hub

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

String get entryLocation {
  final entry = getItOrNull<IAppEntryLocation>();
  return resolveEntryLocation(
    entryPath: entry?.path,
    // The shell's own first-launch flag, set by NavigatorWrapperWidget.
    entrySeen:
        entry != null &&
        (getItOrNull<AppBootStorage>()?.viewedOnboard.value ?? false),
    fallback: fallbackLocation,
  );
}
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
| `ISignInLocation` | No redirect to a sign-in screen, at boot or on sign-out — correct with no session owner |
| `IPostSignInLocation` | After sign-in the app goes to `fallbackLocation` instead of staying on the login screen |

There are two locations, deliberately different. `entryLocation` is where a cold start lands — onboarding when it is composed, but **only on the first launch**: once `NavigatorWrapperWidget` has recorded it as seen (the shell's `AppBootStorage.viewedOnboard`), every later cold start lands on `fallbackLocation`, so a returning user is not shown onboarding while the session restores. `fallbackLocation` is "home": `back()` with nothing to pop, `UndefineRouteWidget`'s go-home button, and after sign-in when no `IPostSignInLocation` is registered. It is always a registered route and never onboarding — a user who just signed in must not be sent back to it.

Unmatched paths land on `errorPageBuilder` → `UndefineRouteWidget` (a real widget class, never an inline anonymous one).

---

## 8. Add a screen — end to end

1. **Path constant** → `lib/src/utils/<feature>_path.dart`.
2. **Route class** → `lib/src/routing/<feature>_route_module.dart` with `@TypedGoRoute` / `@TypedShellRoute`; create the controller in `build()`.
3. **Register the contract** → `IFeatureRouteModule` for a stack route, or `INavDestinationModule` for a tab, annotated `@LazySingleton(as: ...)`.
4. **Cross-feature entry?** Add a method to that module's Navigator interface in its API package (`modules/<id>/api`) and implement it in the feature's `*_navigator_impl.dart`. A module with no Navigator yet gets a **new** file in `modules/<id>/api/lib/src/navigators/` — then run `dart tools/barrel_generator/generate.dart modules/<id>/api/lib` so the API barrel exports it (§5).
5. **Generate** → `dart run build_runner build --workspace`.
6. **Barrels** → `dart tools/barrel_generator/generate.dart modules/<name>/feature/lib`.

---

## 9. Deep links: platform setup

Two link shapes reach the app, and both land on the same router location:

| Link | Router location |
|:---|:---|
| `https://<WEB_DOMAIN>/settings?tab=2` (Android App Link / iOS universal link) | `/settings?tab=2` |
| `<scheme>://settings?tab=2` (custom scheme — the first segment sits in the host position) | `/settings?tab=2` |

The platform delivers the URI to `app_links`, and `DeeplinkProvider` (`platform/shell/app_shell/lib/presentation/providers/deeplink_provider.dart`) turns it into a location with `locationOf` and routes it — but only after `canRoute` has checked the session, and only once `NavigatorWrapperWidget` has started it (never over onboarding or login). A path no module registered lands on `UndefineRouteWidget`, like any unknown location.

### Why Flutter's own deep linking is off

Since Flutter 3.27 the engine also handles deep links by default: it pushes the URI straight into `GoRouter`, skipping `DeeplinkProvider` and its session check — a signed-out user could open a signed-in screen, and each link would be routed twice. Both platforms therefore switch it off:

- Android — inside `<activity>` in `apps/mobile/android/app/src/main/AndroidManifest.xml`: `<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />`
- iOS — `apps/mobile/ios/Runner/Info.plist`: `FlutterDeepLinkingEnabled` = `false`

Do not remove either while `DeeplinkProvider` is the router's only way in.

### Per-flavor values

| Flavor | Custom scheme | Android application id | iOS bundle id |
|:---|:---|:---|:---|
| `dev` | `codebase-dev` | `com.example.codebase.dev` | `com.example.codebase.dev` |
| `staging` | `codebase-stg` | `com.example.codebase.stg` | `com.example.codebase.staging` |
| `prod` | `codebase` | `com.example.codebase` | `com.example.codebase` |

One scheme per flavor, so dev, staging and prod installed side by side never compete for a link. The scheme is declared twice and the two must agree: `resValue("string", "DEEP_LINK_SCHEME", …)` in each `productFlavors` entry of `apps/mobile/android/app/build.gradle.kts`, and the `DEEP_LINK_SCHEME` build setting of each Runner configuration in `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (Xcode: *Runner → Build Settings → User-Defined*). Rename all six together when you rename the app.

`WEB_DOMAIN` comes from the flavor's env file (`apps/mobile/env.dev`, …). The committed env files leave it empty.

### Android

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

`@string/WEB_DOMAIN` is a `resValue` that `build.gradle.kts` decodes from the dart-defines. When the env file leaves `WEB_DOMAIN` empty it becomes `example.invalid` — a reserved domain that never resolves — because an empty host would make the filter claim every https link.

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

The fingerprint is that of the key the **installed** APK is signed with: `keytool -list -v -keystore <release.jks> -alias <alias>` for a key you sign with yourself; for a Play build under Play App Signing, copy the *App signing key certificate* SHA-256 from Play Console → *Test and release → App integrity* — not your upload key's. Check the result on a device:

```bash
adb shell pm get-app-links com.example.codebase            # "verified" per domain
adb shell pm verify-app-links --re-verify com.example.codebase
adb shell am start -a android.intent.action.VIEW -d "codebase-dev://settings?tab=2"
adb shell am start -a android.intent.action.VIEW -d "https://<WEB_DOMAIN>/settings?tab=2"
```

### iOS

**Custom scheme.** `Info.plist` registers it under `CFBundleURLTypes`, with `CFBundleURLSchemes` = `$(DEEP_LINK_SCHEME)` and `CFBundleURLName` = `$(PRODUCT_BUNDLE_IDENTIFIER)`. Nothing else is needed: `xcrun simctl openurl booted "codebase-dev://settings?tab=2"` opens the dev build.

**Universal links** stay off until you own the domain, because the entitlement makes provisioning fail for an App ID without the capability. To turn them on:

1. Enable **Associated Domains** on each App ID in the Apple Developer portal (or *Signing & Capabilities → + Capability* in Xcode) and regenerate the provisioning profiles.
2. Uncomment the `com.apple.developer.associated-domains` block in `apps/mobile/ios/Runner/Runner.entitlements`. Its value, `applinks:$(WEB_DOMAIN)$(APP_LINK_MODE)`, is expanded from `Flutter/Environment.xcconfig`, which each flavor scheme's build pre-action writes from the dart-defines — so build through a flavor scheme (`--flavor`). Leave `APP_LINK_MODE` empty in production; `?mode=developer` bypasses Apple's CDN cache on a device with *Associated Domains Development* enabled.
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

`ABCDE12345` is your Team ID; add one `appIDs` entry per bundle id served from that domain. Apple fetches the file through its CDN when the app is installed, so a change can take a while to reach devices — that is what `?mode=developer` is for.

## Checklist

- [ ] `app_router.dart` untouched
- [ ] Path constants under `src/utils/`, not `routing/`
- [ ] Controller created in the route's `build()`, page does not re-wrap
- [ ] `INavDestinationModule.order` sorts the tab into the intended position (ascending sort key, not an index) and is unique
- [ ] Cross-feature navigation goes through the target module's `<id>_api` Navigator interface
- [ ] `BuildContext` passed from the UI, never taken from `NavigatorKeys`
- [ ] `build_runner` re-run after touching route annotations
- [ ] Deep links still reach the router only through `DeeplinkProvider` — `flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled` stay `false` (§9)

## Related

- [`03_state_management.md`](03_state_management.md) — controller lifecycle
- [`05_di.md`](05_di.md) — how contracts get registered and collected
- [`10_cross_feature.md`](10_cross_feature.md) — the other cross-feature models
- [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) — router assembly
