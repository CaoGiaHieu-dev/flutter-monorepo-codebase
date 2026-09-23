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
| 2 | `profile` | Module name (snake_case). Package becomes `feature_profile` at `modules/profile/feature` |
| 3 | `""` | Custom package prefix — only used when type is `5` (`<prefix>_<name>` at `platform/<name>`). Pass `""` for types 1–4 |
| 4 | `1` | State management — `1` Provider, `2` BLoC, `3` none |
| 5 | `1` | Route contribution — `1` `IFeatureRouteModule`, `2` `INavDestinationModule`, `3` none |

Run it with no arguments to get an interactive prompt instead.

> [!CAUTION]
> If `modules/profile/feature` already exists the tool asks to overwrite and **deletes the
> directory recursively** on `y`. Check the path before answering.

### Choosing argument 5 — this decides your routing shape

| Choose | When | You get |
| :-- | :-- | :-- |
| `1` `IFeatureRouteModule` | A stack of screens pushed on top of the app (auth, onboarding, detail pages) | A `*FeatureRouteModule` stub |
| `2` `INavDestinationModule` | A **primary bottom-navigation destination** that needs its own persistent back stack | A `*NavDestination` stub |
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
4. Adds it to `modules:` in every `apps/<id>/app_manifest.yaml` — then run `dart tools/composer/composer.dart sync`, which regenerates the app's path dependencies and `injection.dart`
5. Runs `dependency_sync.dart`, `flutter pub get`, `flutter gen-l10n`, the barrel generator,
   `build_runner build -d --workspace`, then `dart fix --apply`

**Manual — the tool prints these at the end:**

1. Fill in the `TypedGoRoute` / navigator in `lib/src/routing/`
2. Populate the route module stub (`routes`, and for a tab also `order`, `path`, `destination`)
3. Re-run `build_runner`, then **full restart** the app — new DI registrations are not picked up by hot reload

> [!NOTE]
> FVM is auto-detected (`useFvm` in `tools/shared/toolchain.dart`): the tool prefixes its commands with `fvm ` only
> when both a config file (`.fvmrc` or `.fvm/fvm_config.json`) and a working `fvm --version` are
> present. Otherwise it calls the global `dart` / `flutter`. See
> [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md).

---

## 3. Directory layout

The generator produces this tree in full.

```
modules/profile/feature/
├── assets/language/          en.arb, vi.arb  — feature-scoped translations
├── l10n.yaml                 gen-l10n config (output class, output dir)
├── lib/
│   ├── di/
│   │   ├── module.dart       @InjectableInit.microPackage()
│   │   └── localization.dart IFeatureLocalization implementation
│   ├── feature_profile.dart  public barrel
│   └── src/
│       ├── pages/            *Page / *Screen widgets
│       ├── widgets/          *Widget / *Card sub-widgets
│       ├── provider/         controllers (Provider) — `bloc/` if you chose BLoC
│       ├── routing/          route modules + navigator impl
│       ├── extensions/       l10n extension
│       ├── gen/language/     generated localisations (do not edit)
│       └── utils/            constants owned by this package
└── pubspec.yaml
```

> [!NOTE]
> The controller directory is **singular** — `src/provider/` (as in `feature_auth`) or `src/bloc/`
> (as in `feature_home`). A plural `providers/` / `blocs/` folder is a naming violation; see
> [`../reference/02_naming.md`](../reference/02_naming.md).

Create your path constants first — everything else references them:

```dart
// modules/profile/feature/lib/src/utils/profile_path.dart
class ProfilePath {
  ProfilePath._();

  static const String PROFILE = '/profile';
}
```

This mirrors [`modules/home/feature/lib/src/utils/home_path.dart`](../../../modules/home/feature/lib/src/utils/home_path.dart)
verbatim.

---

## 4. Write the route module

### Option A — a bottom-nav tab (`INavDestinationModule`)

Two files. First the routes themselves — real code from
[`modules/home/feature/lib/src/routing/home_route_module.dart`](../../../modules/home/feature/lib/src/routing/home_route_module.dart):

```dart
import 'package:core_common/core_common.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../bloc/home_profile_bloc.dart';
import '../pages/pages.dart';
import '../utils/home_path.dart';

part 'home_route_module.g.dart';

/// SAMPLE — a tab's route is an ordinary typed route; the shell turns each
/// destination's routes into a `StatefulShellBranch`.
@TypedGoRoute<HomeRoute>(path: HomePath.HOME)
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
[`home_nav_destination.dart`](../../../modules/home/feature/lib/src/routing/home_nav_destination.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import '../extensions/extensions.dart';
import '../utils/home_path.dart';
import 'home_route_module.dart';

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

`order` decides the tab's position and **must be unique** across all registered tabs — `AppRouter`
sorts by it to build the `StatefulShellBranch` list.

### Option B — a pushed stack (`IFeatureRouteModule`)

Much smaller. Real code from
[`modules/auth/feature/lib/src/routing/auth_feature_route_module.dart`](../../../modules/auth/feature/lib/src/routing/auth_feature_route_module.dart):

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
> Never edit `platform/app_shell/lib/presentation/navigation/app_router.dart` to add your routes. It collects
> contributions through `getAllOrEmpty<IFeatureRouteModule>()` and
> `getAllOrEmpty<INavDestinationModule>()`. Hardcoding there breaks feature removability.

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

`modules/profile/feature/l10n.yaml` — copy the shape from
[`modules/home/feature/l10n.yaml`](../../../modules/home/feature/l10n.yaml):

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
[`l10n_home_extension.dart`](../../../modules/home/feature/lib/src/extensions/l10n_home_extension.dart):

```dart
import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

Register the delegate through DI — real code from
[`modules/home/feature/lib/di/localization.dart`](../../../modules/home/feature/lib/di/localization.dart):

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
cd modules/profile/feature && flutter gen-l10n
```

> [!WARNING]
> All user-facing text must be translated. Hardcoded UI strings are forbidden — see
> [`09_localization_theming.md`](09_localization_theming.md).

---

## 7. Navigator — let other features reach you

Other features must never import `feature_profile`. Declare the contract in `core_di`:

```dart
// platform/di/lib/src/navigators/profile_navigator.dart
import 'package:flutter/widgets.dart';

abstract class ProfileNavigator {
  void toProfile(BuildContext context);
}
```

That is exactly the shape of
[`home_navigator.dart`](../../../platform/di/lib/src/navigators/home_navigator.dart).

Implement it inside your own `routing/` — real code from
[`home_navigator_impl.dart`](../../../modules/home/feature/lib/src/routing/home_navigator_impl.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:material_ui/material_ui.dart';
import 'package:injectable/injectable.dart';

import 'home_route_module.dart';

@Singleton(as: HomeNavigator)
class HomeNavigatorImpl implements HomeNavigator {
  @override
  void toHome(BuildContext context) => const HomeRoute().go(context);
}
```

Callers in other packages use `getItOrNull<ProfileNavigator>()?.toProfile(context)` (arch_check R8) — never a hardcoded path, never
`context.go('/profile')`. Always pass `BuildContext` from the calling widget rather than reading it
from `NavigatorKeys`.

---

## 8. Finish and verify

```bash
dart tools/barrel_generator/generate.dart modules/profile/feature/lib
dart run build_runner build -d --workspace
flutter analyze
```

Then **full restart** the app (not hot reload) so the new DI graph is built.

### Checklist

- [ ] `resolution: workspace` present in the package `pubspec.yaml`
- [ ] Every dependency actually used is declared — verify with `dart tools/unused_checker/check_unused_packages.dart`
- [ ] Constants live in `src/utils/`, not scattered
- [ ] Route registered via `IFeatureRouteModule` / `INavDestinationModule` — `app_router.dart` untouched
- [ ] Controller created at route level, page does **not** re-wrap it
- [ ] Screen controller is `@injectable`, not a singleton
- [ ] `IFeatureLocalization` registered — `root_app.dart` untouched
- [ ] No hardcoded user-facing strings
- [ ] Sizes go through context — `context.w()` / `context.h()` / `context.sp()` / `context.r()`
- [ ] Navigator interface in `core_di`, implementation local
- [ ] No import of another feature (no exception — shared widgets come from `core_ui_kit`)

---

## 9. Removing a feature

The app must keep running when any feature is deleted. Remove in this order:

1. Its line under `modules:` in every `apps/<id>/app_manifest.yaml` that composes it
2. `dart tools/composer/composer.dart sync` — regenerates `injection.dart`, the app's path dependencies and the root `workspace:` list
3. The `modules/<name>/feature/` directory
4. `flutter pub get && dart run build_runner build -d --workspace`

**Let the tool do it.** `remove_sample.dart` performs these steps and, more importantly,
tells you what the manual list above cannot:

```bash
dart tools/sample_cleanup/remove_sample.dart --list   # what is sample vs framework
dart tools/sample_cleanup/remove_sample.dart auth     # dry-run, writes nothing
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

> [!CAUTION]
> **These steps are not always sufficient.** The shell degrades gracefully — it resolves
> everything through `core_di` contracts with `getAllOrEmpty` / `getItOrNull` fallbacks — but
> *other samples* may hold a hard dependency on the one you are deleting. Removing `auth` breaks
> one of them, and another degrades safely:
>
> | Consumer | How it couples | Result |
> |---|---|---|
> | `feature_home` (`home_profile_bloc.dart:25`) | `IAuthStatusStream` via **constructor injection** | DI cannot build `HomeProfileBloc` at all |
> | `feature_settings` (`settings_page.dart:47`) | `getItOrNull<IAuthActionHandler>()` | The logout row is simply hidden |
>
> The dry-run prints both, plus the `core_di` contracts that become dead code. Read it before
> deleting anything.

> [!NOTE]
> `injection.dart` naming feature packages is the composition root's **one intentional hard
> reference** — a composition root must name what it composes. It is also the only one, and a
> machine holds that: `arch_check` R10 fails any other file in an app that imports a module, and the
> shared shell in `platform/app_shell/` is a `platform/` package, which R1 forbids from importing one
> at all. The shell does import `core_ui_kit`, which is fine — that is a core package, not a
> removable feature.

---

## Related

- [`04_routing.md`](04_routing.md) — routing contracts in depth
- [`03_state_management.md`](03_state_management.md) — Provider vs BLoC
- [`05_di.md`](05_di.md) — registration scopes and module ordering
- [`10_cross_feature.md`](10_cross_feature.md) — talking to other features
- [`../architecture/05_features.md`](../architecture/05_features.md) — layer rules
