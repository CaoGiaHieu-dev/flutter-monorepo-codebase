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
| `core_common` | Constants, `AppFailure`, helpers, `getIt` helpers |
| `core_base_ui` | Design tokens, theme, `ThemeProvider` / `LanguageProvider` |
| `provider_state_management` **or** `bloc_state_management` | Whichever state approach the feature uses |
| `core_ui_kit` | Reusable widgets (a **core** package, not a feature) |

### Forbidden

> [!CAUTION]
> - **Never import `data_*`.** A feature talks to Domain interfaces; the app shell binds the implementations.
> - **Never import another feature package.** There is no exception — shared widgets come from `core_ui_kit`, which lives in core. Cross-feature needs go through a contract in `core_di` — see [cross-feature communication](../guides/10_cross_feature.md).
> - **Never edit `app/lib/presentation/navigation/app_router.dart`** to add your routes, and never edit `root_app.dart` to add a localization delegate. Both are assembled from DI contributions.

The pubspec enforces most of this: `feature_dashboard` declares only `core_di` and `core_common`, so it *physically cannot* import another feature.

---

## 2. Package layout

```
packages/features/<name>/
├── assets/
│   └── language/            # <name>_en.arb, <name>_vi.arb
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
// packages/features/auth/lib/src/utils/auth_path.dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
  static const String REGISTER = '/auth/register';
  static const String FORGOT_PASSWORD = '/auth/forgot-password';
}
```

---

## 3. The feature packages in this template

| Package | Concern | State management | Registers |
|:---|:---|:---|:---|
| `feature_onboarding` | First-run intro | none | `IFeatureRouteModule`, `IAppEntryLocation` |
| `feature_auth` | Login / register / forgot password | **Provider** | `IFeatureRouteModule`, `AuthNavigator`, `IAuthStatusStream`, `IAuthActionHandler` |
| `feature_dashboard` | Bottom-nav shell chrome | none | `DashboardRouteModule` |
| `feature_home` | Home tab | **BLoC** | `IDashboardTabModule` (order 0), `HomeNavigator` |
| `feature_settings` | Settings tab | none (uses global providers) | `IDashboardTabModule` (order 1), `SettingsNavigator` |
| `feature_splash` | Splash screen | none | `IFeatureLocalization` only — **not a route** |

`feature_auth` and `feature_home` are deliberately built on **different** state approaches so the template demonstrates both. See [state management](../guides/03_state_management.md) — and read the honest comparison there before choosing, because the two branches are not equally equipped.

> [!NOTE]
> `feature_splash` has no `routing/` directory. The splash screen is shown by `MainScope` before `GoRouter` exists, so it is not a route at all. See [app shell](06_app_shell.md).

---

## 4. `feature_dashboard` is chrome only

The dashboard owns the `Scaffold` and the `BottomNavigationBar` — nothing else. It builds both from whatever tabs are registered in DI:

```dart
// packages/features/dashboard/lib/src/pages/dashboard_page.dart
@override
Widget build(BuildContext context) {
  final index = navigationShell.currentIndex;
  final tabs = getAllOrEmpty<IDashboardTabModule>().toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return Scaffold(
    body: navigationShell,
    bottomNavigationBar: tabs.length < 2
        ? null
        : BottomNavigationBar(
            currentIndex: index.clamp(0, tabs.length - 1),
            onTap: (tabIndex) => _onTap(context, tabIndex, tabs[tabIndex].onRestore),
            items: [for (final tab in tabs) tab.navigationBarItem(context)],
          ),
  );
}
```

Because it reads `getAllOrEmpty`, deleting `feature_home` removes the Home tab and the app still starts. With fewer than two tabs the bar is hidden entirely.

### The dashboard must not

- Import `feature_home` / `feature_settings`, or embed their pages
- Own `HomePage` / `SettingsPage`, or any business BLoC for a tab
- Hardcode a `BottomNavigationBarItem` list instead of reading DI
- Register `IDashboardTabModule` itself to fake a tab

### Contributing a tab

A feature registers one implementation and gets a branch plus a nav item:

```dart
// packages/features/home/lib/src/routing/home_dashboard_tab_module.dart
@LazySingleton(as: IDashboardTabModule)
class HomeDashboardTabModule extends IDashboardTabModule {
  @override
  int get order => 0;                       // must match the intended tab index

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

`IDashboardTabModule` also provides a virtual `onRestore()` — called when the user taps the tab they are already on (the usual "scroll to top / pop to root" gesture). Override it if the tab should react.

Use `IDashboardTabModule` **only** for primary bottom-nav destinations that need their own `StatefulShellBranch`. A screen pushed on top of a tab is an ordinary route inside that branch.

---

## 5. Shared widgets live in core, not here

The reusable widget library is **`core_ui_kit`** at `packages/core/ui_kit` — a core package, not a feature. It was moved out of `packages/features/` so that everything remaining here is a genuinely removable product surface. Its structure, dependency direction and the UI-agnostic authoring rule are documented in [the core layer](02_core.md).

What matters on the feature side is the **caller's** obligation:

```dart
// the widget takes raw numbers; the feature scales them
CustomButton(width: 120.w, height: 44.h)
```

`core_ui_kit` widgets never apply `flutter_screenutil_plus` internally. If you pass an already-scaled value they would double-scale it, so scaling is always done here, at the call site.

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
// packages/features/home/lib/src/routing/home_route_module.dart
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

> [!CAUTION]
> **Do not wrap again inside the page.** If the route already provides the controller, a second `BlocProvider` / `ChangeNotifierProvider` in `HomePage.build` creates a *different* instance. The page then renders one object while events go to another — state appears frozen, and neither instance is disposed properly.

A global controller needs no wrapper at all. `AuthProvider` is `@lazySingleton`, so `LoginRoute` builds `const LoginPage()` directly and the page reads it with `Consumer<AuthProvider>`:

```dart
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.authKey;

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

The BLoC one was renamed from `ViewState` to `BlocViewState<T>` precisely so a file importing both barrels does not hit a name collision:

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<UserEntity?>> {
  HomeProfileBloc(this._authStatusStream)
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
# type=1 (feature), name, dir, SM: 1=Provider 2=BLoC 3=none, route: 1=stack 2=tab 3=none
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

The generator creates the package, adds it to the workspace, and registers its DI module in `app/lib/di/injection.dart`. Then:

```bash
dart tools/barrel_generator/generate.dart packages/features/profile/lib
dart run build_runner build -d --workspace
```

Checklist:

- [ ] `resolution: workspace` in the pubspec; no `data_*` and no other feature in dependencies
- [ ] Routes registered via `IFeatureRouteModule` or `IDashboardTabModule` — `app_router.dart` untouched
- [ ] Localization registered via `IFeatureLocalization` — `root_app.dart` untouched
- [ ] Screen controllers `@injectable`, created at the route, not re-wrapped in the page
- [ ] Path constants in `src/utils/<name>_path.dart`
- [ ] Cross-feature navigation through a Navigator interface from `core_di`, with `BuildContext` passed from the caller
- [ ] All sizing scaled with `.w` / `.h` / `.sp` / `.r`
- [ ] Feature-specific assets inside the feature package, not in `core_base_ui`

---

## Related

- [App shell](06_app_shell.md) — how these packages are assembled into one app
- [Guide: create a feature](../guides/01_new_feature.md)
- [Guide: state management](../guides/03_state_management.md) · [routing](../guides/04_routing.md) · [cross-feature communication](../guides/10_cross_feature.md)
- [Rules](../reference/01_rules.md) · [Naming](../reference/02_naming.md)
