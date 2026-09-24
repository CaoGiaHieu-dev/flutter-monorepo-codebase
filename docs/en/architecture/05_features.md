# Feature Layer

**What this answers:** how a screen-owning package is organised, what it is allowed to depend on, and how features stay isolated from one another while still composing into one app.

**After reading you can:** place any new file in the right directory of a feature package, choose between `@injectable` and `@lazySingleton` for a controller, and recognise the boundary violations this layer is designed to prevent.

---

## 1. One feature = one bounded UI concern

A feature package owns **one** product surface. Home and Settings are separate packages even though both are dashboard tabs, because they answer to different concerns and change for different reasons.

The practical test: *if this screen were cut from the product, would the package disappear with it?* If not, it is two features.

### Allowed dependencies

| May depend on | Why |
|:---|:---|
| `domain_*` | Use cases, entities, repository interfaces |
| `core_di` | Navigator / action-handler / routing / stream contracts |
| `core_common` | Constants, `ErrorHandler`, helpers, `getIt` helpers — and a re-export of `AppFailure` from `domain_core` |
| `core_base_ui` | Design tokens, theme, `ThemeProvider` / `LanguageProvider` |
| `provider_state_management` **or** `bloc_state_management` | Whichever state approach the feature uses |
| `core_ui_kit` | Reusable widgets (a **core** package, not a feature) |
| `core_responsive` | `context.w` / `.h` / `.sp` / `.r` — required by any file that sizes a widget; `context.adaptive`, `AdaptiveLayout` and the other adaptive widgets for a screen whose layout changes with the window |

### Forbidden

> [!CAUTION]
> - **Never import `data_*`.** A feature talks to Domain interfaces; the app shell binds the implementations.
> - **Never import another feature package.** There is no exception — shared widgets come from `core_ui_kit`, which lives in core. Cross-feature needs go through a contract in `core_di` — see [cross-feature communication](../guides/10_cross_feature.md).
> - **Never edit `platform/shell/app_shell/lib/presentation/navigation/app_router.dart`** to add your routes, and never edit `root_app.dart` to add a localization delegate. Both are assembled from DI contributions.

The pubspec enforces most of this: `feature_dashboard`'s only workspace dependencies are `core_di`, `core_responsive` and `platform_kernel`, so it *physically cannot* import another feature.

---

## 2. Package layout

```
modules/<name>/feature/
├── assets/
│   └── language/            # en.arb, vi.arb
├── lib/
│   ├── feature_<name>.dart  # public barrel
│   ├── di/
│   │   ├── module.dart      # @InjectableInit.microPackage()
│   │   ├── localization.dart# IFeatureLocalization implementation
│   │   └── di.dart
│   └── src/
│       ├── pages/           # *_page.dart — full screens
│       ├── widgets/         # *_widget.dart, *_card.dart — sub-widgets
│       ├── provider/  OR  bloc/
│       ├── routing/         # route modules, NavigatorImpl
│       ├── utils/           # <name>_path.dart + package constants
│       ├── handlers/        # optional — I*ActionHandler implementations
│       ├── services/        # optional — agnostic stream implementations
│       ├── extensions/      # l10n extension
│       ├── gen/             # generated l10n — do not edit
│       └── src.dart
└── pubspec.yaml
```

> [!IMPORTANT]
> **Route path constants live in `src/utils/`, not `src/routing/`.**
>
> Every package keeps its constants in its own `utils/` directory, and route paths are constants. `feature_auth` holds `src/utils/auth_path.dart`; `feature_home` holds `src/utils/home_path.dart`. The route *modules* stay in `src/routing/` and import the path from `../utils/`.

```dart
// modules/auth/feature/lib/src/utils/auth_path.dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
}
```

---

## 3. The feature packages in this template

| Package | Concern | State management | Registers |
|:---|:---|:---|:---|
| `feature_onboarding` | First-run intro | none | `IFeatureRouteModule`, `IAppEntryLocation` |
| `feature_auth` | Login (one screen) | **Provider** | `IFeatureRouteModule`, `ISignInLocation`, `ISessionStatusStream`, `ISessionState`, `ISessionRefreshListenable`, `IAppTreeWrapper` (`core_di`); `AuthNavigator`, `IAuthActionHandler` (its own `auth_api`) |
| `feature_dashboard` | Navigation shell chrome (bottom bar / rail) | none | `DashboardRouteModule` |
| `feature_home` | Home tab | **BLoC** | `INavDestinationModule` (order 0), `IPostSignInLocation` (`core_di`); `HomeNavigator` (its own `home_api`) |
| `feature_settings` | Settings tab | none (uses global providers) | `INavDestinationModule` (order 1) |
| `feature_splash` | Splash screen | none | `IAppSplashScreen` — **not a route**; shown by `MainScope` |

Every one with user-facing strings also registers its `IFeatureLocalization` — all but `feature_dashboard`, which has none. `ISessionGateway` is registered by `data_auth`, not by the feature. `feature_onboarding` imports `auth_api` and `home_api`, `feature_settings` imports `auth_api` — the only cross-module edges, each to an API package, never to another feature.

`feature_auth` and `feature_home` are deliberately built on **different** state approaches so the template demonstrates both. See [state management](../guides/03_state_management.md) — and read the honest comparison there before choosing, because the two branches are not equally equipped.

> [!NOTE]
> `feature_splash` has no `routing/` directory. The splash screen is shown by `MainScope` before `GoRouter` exists, so it is not a route at all. See [app shell](06_app_shell.md).

---

## 4. `feature_dashboard` is chrome only

The dashboard owns the `Scaffold` and the navigation chrome — a `BottomNavigationBar` on a `compact` window, a `NavigationRail` from `medium` up, extended from `large` up — nothing else. It builds them from whatever tabs are registered in DI:

```dart
// modules/dashboard/feature/lib/src/pages/dashboard_page.dart
@override
Widget build(BuildContext context) {
  final index = navigationShell.currentIndex;
  final tabs = getAllOrEmpty<INavDestinationModule>().toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  if (tabs.length < 2) return Scaffold(body: navigationShell);

  final selected = index.clamp(0, tabs.length - 1);
  void onSelect(int tabIndex) => _onTap(tabIndex, tabs[tabIndex].onRestore);
  // This is where a neutral [NavDestination] becomes one app's widget —
  // the same modules feed both forms below, unchanged.
  final destinations = [for (final tab in tabs) tab.destination(context)];

  // A phone keeps the bottom bar (the shell locks phone-sized displays to
  // portrait). From a medium window up — a tablet in either orientation,
  // an unfolded foldable, a desktop window — the tabs move to a side
  // rail, which costs width the window has to spare instead of height it
  // has not.
  final sizeClass = context.windowSizeClass;
  if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selected,
        onTap: onSelect,
        items: [for (final d in destinations) _itemOf(d)],
      ),
    );
  }

  final extended = sizeClass.isAtLeast(WindowSizeClass.large);
  // The rail sits at the start edge: the left in LTR, the right in RTL
  // (a `Row` follows the text direction). It pads for the insets on its
  // outer side only; the side facing the content is the content's to pad.
  final isRtl = Directionality.of(context) == TextDirection.rtl;
  return Scaffold(
    body: Row(
      children: [
        SafeArea(
          left: !isRtl,
          right: isRtl,
          child: NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: onSelect,
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: [for (final d in destinations) _railItemOf(d)],
          ),
        ),
        Expanded(child: navigationShell),
      ],
    ),
  );
}
```

Among workspace packages `feature_dashboard` depends on just `core_di`, `core_responsive` and `platform_kernel` — it physically **cannot** import another feature. Because it reads `getAllOrEmpty`, deleting `feature_home` removes the Home tab and the app still starts. With fewer than two tabs there is no bar or rail at all.

The chrome is chosen by **window size class**, not by device — a tablet in either orientation, an iPad in Split View and a desktop window each get the chrome their window has room for. (A phone-sized display is locked to portrait at launch by `AppInitializer`, so it always shows the bottom bar; remove that lock and a phone in landscape gets the rail by the same rule.) It is the template's reference for adaptive layout; the widgets and rules are in [design system §7](../guides/11_design_system.md#7-lay-out-for-tablets-foldables-and-split-screen).

### The dashboard must not

- Import `feature_home` / `feature_settings`, or embed their pages
- Own `HomePage` / `SettingsPage`, or any business BLoC for a tab
- Hardcode a destination list instead of reading DI
- Register `INavDestinationModule` itself to fake a tab

### Contributing a tab

A feature registers one implementation and gets a branch plus a nav item:

```dart
// modules/home/feature/lib/src/routing/home_nav_destination.dart
@LazySingleton(as: INavDestinationModule)
class HomeNavDestination extends INavDestinationModule {
  @override
  int get order => 0;                       // ascending sort key, unique per tab

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

`INavDestinationModule` also provides a virtual `onRestore()` — called when the user taps the tab they are already on (the usual "scroll to top / pop to root" gesture). Override it if the tab should react.

Use `INavDestinationModule` **only** for primary bottom-nav destinations that need their own `StatefulShellBranch`. A screen pushed on top of a tab is an ordinary route inside that branch.

---

## 5. Shared widgets live in core, not here

The reusable widget library is **`core_ui_kit`** at `platform/ui/ui_kit` — a core package, not a feature. It sits outside `modules/*/feature/` so that everything under that directory is a genuinely removable product surface. Its structure, dependency direction and the UI-agnostic authoring rule are documented in [the core layer](02_core.md).

What matters on the feature side is the **caller's** obligation:

```dart
// the widget takes raw numbers; the feature scales them
CustomButton(width: context.w(120), height: context.h(44))
```

`core_ui_kit` widgets never re-scale a value passed in — they use it as received, and scale only their own default constants through `core_responsive`. Scaling a parameter again inside the widget would double-scale it, so scaling a value you pass is always done here, at the call site. Note there is no `num` extension — `120.w` does not compile, only `context.w(120)` does.

## 6. UI controller lifecycle

| Scope | Annotation | Use for |
|:---|:---|:---|
| **Screen-scoped** | `@injectable` (factory) | ViewModels / BLoCs tied to one screen |
| **App-global** | `@lazySingleton` | `AuthProvider`, `ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider` |

> [!CAUTION]
> **Never register a screen-scoped controller as a singleton.** GetIt would hold the instance forever, so state leaks between visits to the screen and the object is never disposed.

### Route-level instantiation

Controllers are created in the route's `build`, not inside the page:

```dart
// modules/home/feature/lib/src/routing/home_route_module.dart
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

> [!CAUTION]
> **Do not wrap again inside the page.** If the route already provides the controller, a second `BlocProvider` / `ChangeNotifierProvider` in `HomePage.build` creates a *different* instance. The page then renders one object while events go to another — state appears frozen, and neither instance is disposed properly.

A global controller needs no wrapper at all. `AuthProvider` is `@lazySingleton`, so `LoginRoute` builds `const LoginPage()` directly and the page reads it with `Consumer<AuthProvider>`:

```dart
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.nested('auth');

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const LoginPage();
  }
}
```

### Which `ViewState`?

Both state packages export a state union, and they are **not interchangeable**:

| | `provider_state_management` | `bloc_state_management` |
|:---|:---|:---|
| Type | `ViewState` (inside `ViewStateModel<T>`) | `BlocViewState<T>` |
| Generic | no | yes |
| Variants | 5 (includes `loadingMore`) | 4 |
| Error | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — required |

The BLoC type is named `BlocViewState<T>` rather than `ViewState` so that a file importing both barrels does not meet two different types under one name:

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<SessionPrincipal?>> {
  HomeProfileBloc(@factoryParam this._sessionStatusStream)
    : super(const BlocViewState.initial()) { … }
```

---

## 7. Naming

| Component | File suffix | Class suffix | Example |
|:---|:---|:---|:---|
| Screen | `_page.dart` / `_screen.dart` | `Page` / `Screen` | `LoginPage` |
| Sub-widget | `_widget.dart` / `_card.dart` | `Widget` / `Card` | `AuthHeaderWidget` |
| Provider controller | `_provider.dart` | `Provider` | `AuthProvider` |
| BLoC controller | `_bloc.dart` | `Bloc` | `HomeProfileBloc` |
| Cubit | `_cubit.dart` | `Cubit` | only when events add nothing |
| Navigator impl | `_navigator_impl.dart` | `NavigatorImpl` | `AuthNavigatorImpl` |
| Action handler impl | `_action_handler_impl.dart` | `ActionHandlerImpl` | `AuthActionHandlerImpl` |
| Dialog | `_dialog.dart` | `Dialog` | `ConfirmationDialog` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` | `HomeSettingsBottomSheet` |

Dialogs and bottom sheets are **always** their own widget class — never an inline closure inside `showDialog(builder: …)`.

All user-facing text is translated; hardcoded strings are forbidden. See [localization and theming](../guides/09_localization_theming.md).

---

## 8. Creating a feature

```bash
# type=1 (feature), name, prefix (type 5 only — pass ""), SM: 1=Provider 2=BLoC 3=none, route: 1=stack 2=tab 3=none
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

The generator creates the package, adds it to every `app_manifest.yaml` and runs `composer sync`, which regenerates the root `workspace:` list and each app's `pubspec.yaml` and `injection.dart`. After you add files by hand:

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/profile/feature/lib
```

Checklist:

- [ ] `resolution: workspace` in the pubspec; no `data_*` and no other feature in dependencies
- [ ] Routes registered via `IFeatureRouteModule` or `INavDestinationModule` — `app_router.dart` untouched
- [ ] Localization registered via `IFeatureLocalization` — `root_app.dart` untouched
- [ ] Screen controllers `@injectable`, created at the route, not re-wrapped in the page
- [ ] Path constants in `src/utils/<name>_path.dart`
- [ ] Cross-feature navigation through a Navigator interface from `core_di`, with `BuildContext` passed from the caller
- [ ] All sizing scaled through `BuildContext` — `context.w()` / `context.h()` / `context.sp()` / `context.r()`
- [ ] A layout that changes with the window chooses by window size class (`context.adaptive`, `AdaptiveLayout`) — never by device or platform
- [ ] Feature-specific assets inside the feature package, not in `core_base_ui`

---

## 9. Cross-feature communication — why it is shaped this way

Features never import each other. The how-to — which of the six models to pick and how to wire it — is [`../guides/10_cross_feature.md`](../guides/10_cross_feature.md). This section explains the shape.

Registry: RULE-04, RULE-08, RULE-12, RULE-25, RULE-54.

```
feature_a  ──✗──>  feature_b        forbidden, always
feature_a  ──✓──>  b_api            module B's contracts for other features live here
feature_b  ──✓──>  b_api            B implements them and registers against them
anyone     ──✓──>  core_di          product-neutral contracts (session, locations, routing)
```

A contract lives in one of two neutral places. **Module B's API package** (`modules/<b>/api`,
`b_api`) holds what exists so *other features can reach B* — its navigator, its action
handlers, a widget builder (`auth_api`, `home_api` in the samples); it depends on the
foundation and Flutter only, and B's feature implements it. **`core_di`**, the DI Hub, holds
only what is product-neutral — what the platform itself needs, named for that need (the
session, the sign-in / post-sign-in locations, routing), never for the module that provides it.
Either way both sides depend on the contract, neither on the other. That is what makes a
feature removable; `arch_check` R3 holds the API rules.

### Why `SessionPrincipal` and not `UserEntity`

A `core_di` contract may not name a type from a
`domain_*` package (RULE-08): the import would make every consumer depend on
`domain_auth` at compile time, which `getItOrNull` cannot soften. So `core_di` owns a small value
type,
[`SessionPrincipal`](../../../platform/foundation/contracts/lib/src/session/session_principal.dart), and the auth
feature narrows its entity to it at the boundary (`AuthStatusStreamImpl.toPrincipal`). The contract is
deliberately smaller than the entity — a consumer that only asks *who is signed in* never sees the
rest.

### Why `currentUser` exists alongside the stream

`sessionStatusStream` is a *broadcast* stream: it
does not replay its last value to new listeners. A consumer subscribing after login would sit blind
until the next change, so it reads `currentUser` for the state at subscription time.

### Why the stream is registered twice

The concrete class is registered so `feature_auth` can inject
`AuthStatusStreamImpl` directly and call the writer method `updateAuthStatus` — no `getIt` lookup,
no `as` cast. The `@module` binding then exposes the *same instance* under the read-only interface
for everyone else. Owner writes, consumers read.

### Why theme and locale bypass Domain

A use case would have to accept and return `ThemeMode`, which is a
`package:flutter/material.dart` type. The domain layer is pure Dart and **cannot import Flutter**,
so routing theme through it is impossible by construction — not a shortcut, a hard constraint.

The implementation lives in the app shell (`platform/shell/adapters/lib/src/theme_storage_impl.dart`) because that is
where `core_base_ui`'s provider and `core_storage`'s mechanism meet without creating a cycle.

### Anti-patterns

| Don't | Why | Instead |
| :-- | :-- | :-- |
| `import 'package:feature_b/...'` from feature A | Hard couples two features; neither is removable | A contract in `b_api` (or a product-neutral one in `core_di`) |
| A module-specific contract (`AuthNavigator`) in `core_di` | The platform then names a product module, and keeps a dead contract when it is removed | The owning module's `<id>_api` |
| Expose a `Bloc` or `ChangeNotifier` across features | Forces the other feature to adopt your state library | Model 3 — neutral stream |
| `getIt<FeatureOwnedType>()` | Throws when that feature is gone | `getItOrNull<T>()` + fallback |
| Action Handler for navigation | Wrong tool; loses type-safe routes | Navigator interface |
| Put shared business logic in `core_ui_kit` | It is a UI package | A domain UseCase |
| A `core_di` contract naming a `domain_*` entity | Every consumer then depends on that domain package; contradicts RULE-08 | A contract-owned value type (`SessionPrincipal`) |

---

## Related

- [App shell](06_app_shell.md) — how these packages are assembled into one app
- [Guide: create a feature](../guides/01_new_feature.md)
- [Guide: state management](../guides/03_state_management.md) · [routing](../guides/04_routing.md) · [cross-feature communication](../guides/10_cross_feature.md)
- [Rules](../reference/01_rules.md) · [Naming](../reference/02_naming.md)
