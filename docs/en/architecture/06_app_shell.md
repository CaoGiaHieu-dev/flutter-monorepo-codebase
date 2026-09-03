# The App Shell (`app/`)

This document answers **"what happens between tapping the icon and seeing the first screen, and who wires everything together?"**. After reading it you should be able to debug a startup failure, add an app-local adapter, and understand why the DI module order in `injection.dart` is not arbitrary.

The app shell is the **composition root**. It is the only place allowed to depend on every layer, and the only place that knows the full list of packages.

---

## 1. What lives here

```
app/lib/
├── main.dart                    entry point, error zone
├── main_scope.dart              splash → init → root transition
├── app.dart                     barrel
├── di/
│   ├── injection.dart           DI assembly (module order matters)
│   ├── theme_storage_impl.dart      IThemeStorage    → StorageValue<ThemeMode>
│   ├── language_storage_impl.dart   ILanguageStorage → StorageValue<String>
│   ├── app_boot_storage.dart        boot flags       → StorageValue<bool>
│   ├── network_config_impl.dart     NetworkConfig
│   ├── network_binding_module.dart  SslPinningConfig binding
│   └── utils/                   storage keys owned by the shell
└── presentation/
    ├── root_app.dart            the routed MaterialApp
    ├── app_material_wrapper.dart shared MaterialApp config
    ├── navigation/app_router.dart GoRouter assembly
    ├── providers/               AppProvider, DeeplinkProvider
    └── widgets/                 NavigatorWrapperWidget, UndefineRouteWidget
```

---

## 2. Boot lifecycle

```mermaid
sequenceDiagram
    autonumber
    participant M as main.dart
    participant DI as configureDependencies()
    participant S as MainScope.run()
    participant N as FlutterNativeSplash
    participant I as AppInitializer.init()
    participant R as RootApp / AppRouter

    M->>M: runZonedGuarded(...)
    M->>M: WidgetsFlutterBinding.ensureInitialized()
    M->>DI: await configureDependencies()
    Note over DI: every module registered<br/>before any UI exists
    DI-->>M: container ready
    M->>S: MainScope(splashScreen, root, initService).run()

    alt splashScreen == null (iOS)
        S->>N: preserve()
        S->>I: await [initService(), delay 2s]
        S->>N: remove()
        S->>R: runApp(root)
    else splashScreen != null (Android / Web)
        S->>N: remove()
        S->>S: runApp(AppMaterialWrapper(home: splash))
        S->>S: await endOfFrame
        S->>I: await [initService(), delay 2s]
        S->>R: widget.value = root  (AnimatedSwitcher fade)
    end

    R->>R: AppRouter.router built lazily on first access
```

### Step by step

1. **`runZonedGuarded`** wraps everything so uncaught async errors are reported rather than lost. The release-mode Crashlytics hook is present but commented out.
2. **`WidgetsFlutterBinding.ensureInitialized()`** — required before any plugin call.
3. **`await configureDependencies()`** runs *before* `MainScope`. By the time any widget builds, the whole container is resolved.
4. **`MainScope`** is constructed with three things: which splash widget to show (if any), the root widget, and `initService` — here `AppInitializer.init(routeObserver: getIt<AppRouter>().routeObserver)`.
5. **`mainScope.run()`** branches on whether a Dart splash widget was supplied.

### The two splash paths

`main.dart` chooses the splash per platform:

```dart
splashScreen: kIsWeb
    ? const SplashPage()
    : Platform.isIOS
    ? null
    : const SplashPage(),
```

| Platform | `splashScreen` | Behaviour |
|:--|:--|:--|
| iOS | `null` | Native splash is **preserved** across init, then removed once work finishes. No Dart splash is ever rendered. |
| Android, Web | `SplashPage()` | Native splash is removed immediately; a Dart `SplashPage` renders instead and cross-fades into `RootApp` via `AnimatedSwitcher`. |

Both paths await `Future.wait([initService(), Future.delayed(_minimumDelay)])`, where `_minimumDelay` is 2 seconds. The delay is a **floor**, not an addition — fast initialisation still waits so the splash does not flicker.

> [!NOTE]
> `SplashPage` is shown by `MainScope`, **not** by GoRouter. It has no route and never appears in the navigation stack.

### `_ResponsiveWrapper`

Both paths wrap the tree in **`ResponsiveInit`** from `core_responsive`, with `AppConfig.design` (375×812), `minTextAdapt: true`, `splitScreenMode: true` and a custom `fontSizeResolver` that scales text by real screen width. It sits at the very root, so every widget below it can call `context.w(x)` / `context.h(x)` / `context.sp(x)` / `context.r(x)`.

`ResponsiveInit` publishes the metrics through a `ResponsiveScope` `InheritedWidget`, so a widget that reads them subscribes to them — there is no rebuild flag to tune. Sizing must go through `BuildContext`: there is no `num` extension, so `16.h` does not even compile. See [rule 12](../reference/01_rules.md#12-responsive-ui) for the reasoning, and note that `arch_check` rule R7 blocks the bare form on every PR.

> [!NOTE]
> Supplying a `fontSizeResolver` overrides text scaling completely, so the `minTextAdapt: true` above is inert while the resolver is set. Dropping the resolver is a deliberate visual change, not a cleanup.

---

## 3. DI assembly — and why the order matters

[`app/lib/di/injection.dart`](../../../app/lib/di/injection.dart) declares the module order:

```dart
@InjectableInit(
  externalPackageModulesBefore: [..._coreModules],
  externalPackageModulesAfter: [
    ..._uiModules,       // CoreBaseUiPackageModule
    ..._domainModules,
    ..._dataModules,
    ..._featureModules,
    ..._otherModules,
  ],
)
```

Resolution order in the generated `injection.config.dart`:

| # | Registered | Notes |
|:-:|:--|:--|
| 1 | `_coreModules` | `core_common`, `core_network`, `core_notifications`, `core_storage`, `core_database`, `core_di` |
| 2 | **app-local bindings** | `AppRouter`, `AppProvider`, `DeeplinkProvider`, `AppBootStorage`, `ILanguageStorage`, `IThemeStorage`, `NetworkConfig`, `SslPinningConfig` |
| 3 | `_uiModules` | `core_base_ui` |
| 4 | `_domainModules` → `_dataModules` → `_featureModules` → `_otherModules` | |

### Why `CoreBaseUiPackageModule` sits in `_uiModules`, not `_coreModules`

This is the single most important implicit rule in the DI setup, and the source file says so in a comment.

`core_base_ui` registers `ThemeProvider` and `LanguageProvider`, which inject `IThemeStorage` and `ILanguageStorage`. Those two interfaces are implemented **app-locally** (`theme_storage_impl.dart`, `language_storage_impl.dart`) — they are not part of any core package. App-local bindings are emitted *between* `…Before` and `…After`, so `core_base_ui` must run in the `…After` group. Move it into `_coreModules` and startup fails with "IThemeStorage is not registered".

### The eager-singleton ordering trap

> [!CAUTION]
> An eager `@Singleton` is constructed **at registration time**. If it depends on a type registered by a module that runs *later*, startup throws `… is not registered`.
>
> `flutter analyze` cannot detect this — it is a runtime ordering fault. Verify by reading the generated `app/lib/di/injection.config.dart` and checking that every dependency appears *above* its consumer.

Real example: `NetworkConfigImpl` depends on `AuthLocalDataSource`, which lives in `data_auth` — registered in step 4, after the app-local block in step 2. It is therefore declared `@LazySingleton(as: NetworkConfig)`, which defers construction until first use. Its only consumer, `ApiClient`, is itself lazy, so nothing is lost.

### `AppRouter` is eager, but its router is not

`AppRouter` *is* `@singleton` (eager), yet this is safe: `router` is a `late final` field.

```dart
late final GoRouter router = GoRouter( … );
```

The `GoRouter` — and the `getAllOrEmpty<IFeatureRouteModule>()` calls inside it — is not evaluated until something first reads `.router`. By then every feature module has registered. Had `router` been a plain field, the router would be assembled during step 2 and would collect **zero** feature routes.

---

## 4. App-local adapters

The shell implements the contracts that core packages declare but cannot satisfy themselves. Each owns its own `StorageValue` and keeps its keys in `app/lib/di/utils/`.

| File | Implements | Owns | Registration |
|:--|:--|:--|:--|
| `theme_storage_impl.dart` | `IThemeStorage` | `themeMode` (pref) | `@Singleton(as: IThemeStorage)` + `@PostConstruct(preResolve: true)` |
| `language_storage_impl.dart` | `ILanguageStorage` | `locale` (pref) | same |
| `app_boot_storage.dart` | — | `viewed_onboard` (pref) | `@singleton` + `@PostConstruct(preResolve: true)` |
| `network_config_impl.dart` | `NetworkConfig` | — | `@LazySingleton(as: NetworkConfig)` |
| `network_binding_module.dart` | binds `SslPinningConfig` | — | `@module` |

### Why `SslPinningConfig` needs a separate binding

`NetworkConfig implements SslPinningConfig`, but **GetIt resolves by exact registered type and does not walk the supertype chain**. Registering only `as: NetworkConfig` left `getItOrNull<SslPinningConfig>()` returning `null`, so `AppInitializer` skipped pinning entirely — silently, on every flavor.

The fix is a module binding, the same dual-registration pattern `feature_auth` uses for `IAuthStatusStream`:

```dart
@module
abstract class NetworkBindingModule {
  @lazySingleton
  SslPinningConfig bindSslPinningConfig(NetworkConfig config) => config;
}
```

The parameter is typed `NetworkConfig`, so the upcast is compiler-checked — no `as` cast.

---

## 5. Router assembly

[`app_router.dart`](../../../app/lib/presentation/navigation/app_router.dart) builds GoRouter **entirely from DI contributions**.

```dart
List<RouteBase> get _featureRoutes => [
  for (final module in getAllOrEmpty<IFeatureRouteModule>()) ...module.routes,
];

List<IDashboardTabModule> get _dashboardTabs =>
    getAllOrEmpty<IDashboardTabModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
```

Structure produced:

```
GoRouter(navigatorKey: NavigatorKeys.rootKey)
└── ShellRoute(navigatorKey: appKey)          → NavigatorWrapperWidget
    ├── ..._featureRoutes                      ← IFeatureRouteModule
    └── StatefulShellRoute.indexedStack        ← IDashboardTabModule (sorted by order)
        └── builder → DashboardRouteModule
```

Every collection point degrades gracefully when nothing is registered:

| Missing | Fallback |
|:--|:--|
| `IFeatureRouteModule` | empty list |
| `IDashboardTabModule` | one placeholder branch at `/_empty_dashboard` rendering `SizedBox.shrink()` |
| `DashboardRouteModule` | `SizedBox.shrink()` |
| `IAppEntryLocation` | first dashboard tab path, else `/` |

Deleting a feature package therefore cannot crash the shell.

> [!CAUTION]
> **Never hardcode a feature route in `app_router.dart`.** Register `IFeatureRouteModule` or `IDashboardTabModule` in the feature's own DI module instead. See [`../guides/04_routing.md`](../guides/04_routing.md).

`refreshListenable: getItOrNull<AuthProvider>()` makes GoRouter re-evaluate redirects when auth state changes. `errorPageBuilder` renders `UndefineRouteWidget` — a named widget, never an inline closure.

---

## 6. `NavigatorWrapperWidget` — first navigation and auth transitions

Sits inside the app `ShellRoute` and wraps every in-app route. It splits navigation into two distinct responsibilities.

**Boot redirect** runs once, in `initState`, deferred to `endOfFrame`:

```dart
WidgetsBinding.instance.endOfFrame.whenComplete(() async {
  await authProvider.ensureInitialized();
  if (!mounted) return;
  // onboarding? → login? → home
  _bootCompleted = true;
});
```

Waiting for `endOfFrame` guarantees the first frame is on screen before any redirect, and `ensureInitialized()` waits for session restore to finish so the decision is made against real state.

**Later transitions** are handled by a `ProviderStateListener<AuthProvider, UserEntity>` in `build`, gated on `_bootCompleted && authProvider.hasRestoredSession`. The gate exists so the listener does not fight the boot redirect over the very first navigation.

> [!WARNING]
> `_goToOnboarding()` sets `viewedOnboard.value = true` inside a `finally` block, so the flag is written even when the method returns `false` because a user is already signed in. The onboarding screen was never shown in that case. Harmless today, but the flag does not mean quite what its name suggests.

---

## 7. `AppMaterialWrapper` and `RootApp`

`AppMaterialWrapper` exists so the splash `MaterialApp` and the routed `MaterialApp` share one configuration. Two constructors: the default (plain `MaterialApp`, used for splash) and `.router` (used by `RootApp`).

Provider tree it installs:

```
MultiProvider(ThemeProvider, LanguageProvider)
└── Consumer2<ThemeProvider, LanguageProvider>
    └── AnnotatedRegion<SystemUiOverlayStyle>
        └── TooltipVisibility(visible: false)
            └── MultiProvider(AppProvider, AuthProvider, DeeplinkProvider)
                └── MaterialApp[.router]
```

The outer `Consumer2` is what makes theme and locale changes propagate app-wide.

Localization delegates are collected from DI, so features never edit this file:

```dart
final delegates = [
  ...getIt.getAll<IFeatureLocalization>().map((e) => e.delegate),
  ...AppLocalizations.localizationsDelegates,
];
```

`RootApp` supplies the four router objects from `getIt<AppRouter>().router` and adds the global `builder`: overlay hosts, `AppDialogController`, a `GestureDetector` that unfocuses the keyboard on outside taps, and `MediaQuery.withNoTextScaling` to keep layout stable.

---

## 8. Where to go next

| Task | Guide |
|:--|:--|
| Register routes from a feature | [`../guides/04_routing.md`](../guides/04_routing.md) |
| Add a DI registration correctly | [`../guides/05_di.md`](../guides/05_di.md) |
| Add a stored value | [`../guides/06_storage.md`](../guides/06_storage.md) |
| Configure networking / pinning | [`../guides/08_networking.md`](../guides/08_networking.md) |
| Understand the layers underneath | [`01_overview.md`](01_overview.md) |
