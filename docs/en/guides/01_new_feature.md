# Guide: Create a New Feature

This guide answers **"how do I add a new screen area to the app?"** — end to end, from an empty
folder to a route the app can reach. We build a `profile` feature as the worked example.

By the end you will have: a generated package, a route wired through DI (never through
`app_router.dart`), a controller instantiated at route level, its own translations, and a
navigator other features can call without importing you.

---

## 1. Generate the package

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

The five positional arguments are read by
[`tools/module_generator/src/input_actions.dart`](../../../tools/module_generator/src/input_actions.dart):

| Position | Value | Meaning |
| :-- | :-- | :-- |
| 1 | `1` | Module type — `1` Feature, `2` Domain, `3` Data, `4` Core, `5` Custom |
| 2 | `profile` | Module name (snake_case). Package becomes `feature_profile` at `packages/features/profile` |
| 3 | `""` | Custom directory — only used when type is `5`. Pass `""` for types 1–4 |
| 4 | `1` | State management — `1` Provider, `2` BLoC, `3` none |
| 5 | `1` | Route contribution — `1` `IFeatureRouteModule`, `2` `IDashboardTabModule`, `3` none |

Run it with no arguments to get an interactive prompt instead.

> [!CAUTION]
> If `packages/features/profile` already exists the tool asks to overwrite and **deletes the
> directory recursively** on `y`. Check the path before answering.

### Choosing argument 5 — this decides your routing shape

| Choose | When | You get |
| :-- | :-- | :-- |
| `1` `IFeatureRouteModule` | A stack of screens pushed on top of the app (auth, onboarding, detail pages) | A `*FeatureRouteModule` stub |
| `2` `IDashboardTabModule` | A **primary bottom-navigation destination** that needs its own persistent back stack | A `*DashboardTabModule` stub |
| `3` none | You will wire routing yourself later, or the feature has no routes | No routing stub |

> [!WARNING]
> Use `2` only for real bottom-nav tabs. Pushed screens (login, detail) belong in a
> `IFeatureRouteModule`. Registering a fake tab breaks the dashboard's index ordering — see
> [`04_routing.md`](04_routing.md).

---

## 2. What the tool does, and what it leaves for you

**Automatic** (see [`tools/module_generator/generate.dart`](../../../tools/module_generator/generate.dart)):

1. Creates the directory tree and `pubspec.yaml`
2. Writes `lib/di/module.dart` with `@InjectableInit.microPackage()`
3. Registers the package in the root `pubspec.yaml` `workspace:` list
4. Registers it in `app/pubspec.yaml` **and** in `app/lib/di/injection.dart`
5. Runs `dependency_sync.dart`, `flutter pub get`, `flutter gen-l10n`, the barrel generator,
   `build_runner build -d --workspace`, then `dart fix --apply`

**Manual — the tool prints these at the end:**

1. Fill in the `TypedGoRoute` / navigator in `lib/src/routing/`
2. Populate the route module stub (`routes`, and for a tab also `order`, `path`, `navigationBarItem`)
3. Re-run `build_runner`, then **full restart** the app — new DI registrations are not picked up by hot reload

> [!NOTE]
> The generator invokes every command through `fvm` (`generate.dart:135-181`). If you do not use
> FVM the tool will fail at step 8; run the commands yourself in that case. See
> [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md).

---

## 3. Directory layout

The generator produces this; the two entries marked ➕ you add by hand.

```
packages/features/profile/
├── assets/language/          en.arb, vi.arb  — feature-scoped translations
├── l10n.yaml                 gen-l10n config (output class, output dir)
├── lib/
│   ├── di/
│   │   ├── module.dart       @InjectableInit.microPackage()
│   │   └── localization.dart ➕ IFeatureLocalization implementation
│   ├── feature_profile.dart  public barrel
│   └── src/
│       ├── pages/            *Page / *Screen widgets
│       ├── widgets/          *Widget / *Card sub-widgets
│       ├── providers/        controllers (Provider) — see note below
│       ├── routing/          route modules + navigator impl
│       ├── extensions/       l10n extension
│       ├── gen/language/     generated localisations (do not edit)
│       └── utils/            ➕ constants owned by this package
└── pubspec.yaml
```

> [!WARNING]
> Two gaps in the generator you must fix by hand:
>
> - It creates **`src/providers/`** and **`src/blocs/`** (plural), but the shipped features use
>   **`src/provider/`** (`feature_auth`) and **`src/bloc/`** (`feature_home`) — singular. Rename to
>   match the existing convention.
> - It does **not** create `src/utils/`. Every package must own its constants there
>   ([`../reference/01_rules.md`](../reference/01_rules.md)), so create it and put your route paths
>   in it.

Create your path constants first — everything else references them:

```dart
// packages/features/profile/lib/src/utils/profile_path.dart
class ProfilePath {
  ProfilePath._();

  static const String PROFILE = '/profile';
}
```

This mirrors [`packages/features/home/lib/src/utils/home_path.dart`](../../../packages/features/home/lib/src/utils/home_path.dart)
verbatim.

---

## 4. Write the route module

### Option A — a bottom-nav tab (`IDashboardTabModule`)

Two files. First the routes themselves — real code from
[`packages/features/home/lib/src/routing/home_route_module.dart`](../../../packages/features/home/lib/src/routing/home_route_module.dart):

```dart
import 'package:core_common/core_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/home_profile_bloc.dart';
import '../pages/pages.dart';
import '../utils/home_path.dart';

part 'home_route_module.g.dart';

@TypedShellRoute<HomeShellRoute>(
  routes: [TypedGoRoute<HomeRoute>(path: HomePath.HOME)],
)
class HomeShellRoute extends ShellRouteData {
  const HomeShellRoute();

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return navigator;
  }
}

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

Then the DI contribution — real code from
[`home_dashboard_tab_module.dart`](../../../packages/features/home/lib/src/routing/home_dashboard_tab_module.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import '../extensions/extensions.dart';
import '../utils/home_path.dart';
import 'home_route_module.dart';

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

`order` decides the tab's position and **must be unique** across all registered tabs — `AppRouter`
sorts by it to build the `StatefulShellBranch` list.

### Option B — a pushed stack (`IFeatureRouteModule`)

Much smaller. Real code from
[`packages/features/auth/lib/src/routing/auth_feature_route_module.dart`](../../../packages/features/auth/lib/src/routing/auth_feature_route_module.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import 'auth_route_module.dart';

@LazySingleton(as: IFeatureRouteModule)
class AuthFeatureRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [$authShellRoute];
}
```

No `order` — these routes are matched by path, not by index.

> [!CAUTION]
> Never edit `app/lib/presentation/navigation/app_router.dart` to add your routes. It collects
> contributions through `getAllOrEmpty<IFeatureRouteModule>()` and
> `getAllOrEmpty<IDashboardTabModule>()`. Hardcoding there breaks feature removability.

---

## 5. Instantiate the controller at route level

The controller is created in the route's `build`, never inside the page.

```dart
// BLoC — from home_route_module.dart above
return BlocProvider(
  create: (_) => getIt<HomeProfileBloc>(),
  child: const HomePage(),
);
```

```dart
// Provider — same shape
return ChangeNotifierProvider(
  create: (_) => getIt<ProfileProvider>(),
  child: const ProfilePage(),
);
```

> [!CAUTION]
> **Never wrap the controller again inside the Page.** `BlocProvider` / `ChangeNotifierProvider`
> already lives at the route. A second wrapper creates a *second instance*: the page reads state
> that nothing writes to, and the first instance leaks. This is the single most common bug in this
> codebase's pattern.

Screen-scoped controllers are `@injectable` (a factory, disposed with the route). Only
app-wide controllers — `AuthProvider`, `ThemeProvider`, `LanguageProvider` — are `@lazySingleton`.
Registering a screen controller as a singleton leaks it for the process lifetime. Details in
[`05_di.md`](05_di.md).

---

## 6. Localisation

Feature translations live in the feature. Nothing is added to the app shell.

`packages/features/profile/l10n.yaml` — copy the shape from
[`packages/features/home/l10n.yaml`](../../../packages/features/home/l10n.yaml):

```yaml
arb-dir: assets/language
template-arb-file: en.arb
output-localization-file: app_localizations.dart
output-class: FeatureProfileLocalizations
preferred-supported-locales: [en, vi]
untranslated-messages-file: untranslated-messages.txt
output-dir: lib/src/gen/language
```

`assets/language/en.arb` (and a matching `vi.arb`):

```json
{
  "@@locale": "en",
  "profile": "Profile",
  "tabLabel": "Profile"
}
```

Expose it through an extension — real code from
[`l10n_home_extension.dart`](../../../packages/features/home/lib/src/extensions/l10n_home_extension.dart):

```dart
import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

Register the delegate through DI — real code from
[`packages/features/home/lib/di/localization.dart`](../../../packages/features/home/lib/di/localization.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_home.dart';

@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureHomeLocalizations.delegate;
}
```

The root app collects every registered `IFeatureLocalization`, so **do not edit `root_app.dart`**.

Regenerate after editing any `.arb`:

```bash
cd packages/features/profile && flutter gen-l10n
```

> [!WARNING]
> All user-facing text must be translated. Hardcoded UI strings are forbidden — see
> [`09_localization_theming.md`](09_localization_theming.md).

---

## 7. Navigator — let other features reach you

Other features must never import `feature_profile`. Declare the contract in `core_di`:

```dart
// packages/core/di/lib/src/navigators/profile_navigator.dart
import 'package:flutter/widgets.dart';

abstract class ProfileNavigator {
  void toProfile(BuildContext context);
}
```

That is exactly the shape of
[`home_navigator.dart`](../../../packages/core/di/lib/src/navigators/home_navigator.dart).

Implement it inside your own `routing/` — real code from
[`home_navigator_impl.dart`](../../../packages/features/home/lib/src/routing/home_navigator_impl.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'home_route_module.dart';

@Singleton(as: HomeNavigator)
class HomeNavigatorImpl implements HomeNavigator {
  @override
  void toHome(BuildContext context) => const HomeRoute().go(context);
}
```

Callers use `getIt<ProfileNavigator>().toProfile(context)` — never a hardcoded path, never
`context.go('/profile')`. Always pass `BuildContext` from the calling widget rather than reading it
from `NavigatorKeys`.

---

## 8. Finish and verify

```bash
dart tools/barrel_generator/generate.dart packages/features/profile/lib
dart run build_runner build -d --workspace
flutter analyze
```

Then **full restart** the app (not hot reload) so the new DI graph is built.

### Checklist

- [ ] `resolution: workspace` present in the package `pubspec.yaml`
- [ ] Every dependency actually used is declared — verify with `dart tools/unused_checker/check_unused_packages.dart`
- [ ] Constants live in `src/utils/`, not scattered
- [ ] Route registered via `IFeatureRouteModule` / `IDashboardTabModule` — `app_router.dart` untouched
- [ ] Controller created at route level, page does **not** re-wrap it
- [ ] Screen controller is `@injectable`, not a singleton
- [ ] `IFeatureLocalization` registered — `root_app.dart` untouched
- [ ] No hardcoded user-facing strings
- [ ] Sizes use `.w` / `.h` / `.sp` / `.r`
- [ ] Navigator interface in `core_di`, implementation local
- [ ] No import of another feature (no exception — shared widgets come from `core_ui_kit`)

---

## 9. Removing a feature

The app must keep running when any feature is deleted. Remove in this order:

1. Its `ExternalModule(...)` entry **and** the matching import in `app/lib/di/injection.dart`
2. Its entry in `app/pubspec.yaml`
3. Its path in the root `pubspec.yaml` `workspace:` list
4. The `packages/features/<name>/` directory
5. `flutter pub get && dart run build_runner build -d --workspace`

Nothing else should need editing: everything the shell consumes at runtime resolves through
`core_di` contracts with `getAllOrEmpty` / `getItOrNull` fallbacks.

> [!NOTE]
> `injection.dart` naming feature packages is the composition root's **one intentional hard
> reference** — a composition root must name what it composes. Some shell files still hold direct
> `feature_auth` / `feature_splash` / `core_ui_kit` imports; check their doc comments before
> removing those specific features.

---

## Related

- [`04_routing.md`](04_routing.md) — routing contracts in depth
- [`03_state_management.md`](03_state_management.md) — Provider vs BLoC
- [`05_di.md`](05_di.md) — registration scopes and module ordering
- [`10_cross_feature.md`](10_cross_feature.md) — talking to other features
- [`../architecture/05_features.md`](../architecture/05_features.md) — layer rules
