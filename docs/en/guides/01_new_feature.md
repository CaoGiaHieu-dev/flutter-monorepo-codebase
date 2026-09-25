# Guide: Create a New Feature

## Goal

You add a new screen area to the app, end to end, from an empty folder to a route the app can reach. The worked example is a `profile` feature. At the end you have:

- a generated package, composed into the apps you chose;
- a route wired through DI, never through `app_router.dart`;
- a controller instantiated at route level;
- the feature's own translations;
- a navigator other features can call without importing you.

## Prerequisites

- A working setup — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).
- New to the repo? Do [`../getting-started/04_first_feature_tutorial.md`](../getting-started/04_first_feature_tutorial.md) first. It walks this guide's path once, with every command verified.
- How a feature package is organised and what it may depend on — [`../architecture/05_features.md`](../architecture/05_features.md).

---

## 1. Generate the package

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

The five positional arguments are read by [`tools/module_generator/src/input_actions.dart`](../../../tools/module_generator/src/input_actions.dart):

| Position | Value | Meaning |
| :-- | :-- | :-- |
| 1 | `1` | Module type — `1` Feature, `2` Domain, `3` Data, `4` Core, `5` Custom |
| 2 | `profile` | Module name (snake_case). Package becomes `feature_profile` at `modules/profile/feature` |
| 3 | `""` | Custom package prefix — only used when type is `5` (`<prefix>_<name>` at `platform/<group>/<name>`). Pass `""` for types 1–4 |
| 4 | `1` | State management — `1` Provider, `2` BLoC, `3` none |
| 5 | `1` | Route contribution — `1` `IFeatureRouteModule`, `2` `INavDestinationModule`, `3` none |

Run it with no arguments on a terminal to get an interactive prompt instead. Without a terminal, a missing argument exits 64 rather than guessing. `--help` prints the usage.

An optional `--apps <id,id>` after the positional arguments composes the module into those apps only. The ids are the `app.id`s from `apps/*/app_manifest.yaml`, e.g. `--apps mobile`. Without it the module joins every app. An unknown id exits 64 before anything is written.

> [!NOTE]
> If a package named `feature_profile` already exists, the tool **refuses** and exits 64. It exits 1 if the directory `modules/profile/feature` exists without that package. It never overwrites or deletes an existing package: remove or rename it yourself first.

### Choose argument 5 — it decides your routing shape

| Choose | When | You get |
| :-- | :-- | :-- |
| `1` `IFeatureRouteModule` | A stack of screens pushed on top of the app (auth, onboarding, detail pages) | A `*FeatureRouteModule` stub |
| `2` `INavDestinationModule` | A **primary navigation destination** — bottom bar on a phone, `NavigationRail` from a medium window up — that needs its own persistent back stack | A `*NavDestination` stub |
| `3` none | You will wire routing yourself later, or the feature has no routes | No routing stub |

> [!WARNING]
> Use `2` only for real bottom-nav tabs (RULE-24). Pushed screens (login, detail) belong in an `IFeatureRouteModule`. Registering a fake tab breaks the dashboard's index ordering — see [`04_routing.md`](04_routing.md).

## 2. Check what the generator did

**Automatic** (see [`tools/module_generator/generate.dart`](../../../tools/module_generator/generate.dart)):

1. Creates the directory tree and `pubspec.yaml`.
2. Writes `lib/di/module.dart` with `@InjectableInit.microPackage()`.
3. Adds the module to `modules:` in **every** `apps/<id>/app_manifest.yaml` — `admin` as well as `mobile` — unless `--apps` names a subset.
   - Then it runs `dart tools/composer/composer.dart sync` itself. That regenerates the root `pubspec.yaml` `workspace:` list and each app's path dependencies and `injection.dart`.
   - Nothing to run by hand — but see the note below if the module does not belong in every app.
4. Runs `dependency_sync.dart`, `flutter pub get`, `flutter gen-l10n`, the barrel generator, `build_runner build --workspace`, then `dart fix --apply`.
5. Writes tests that pass as generated: `test/profile_page_test.dart` and `test/profile_provider_test.dart` (`test/<name>_bloc_test.dart` for BLoC, no controller test for SM `3`). The page test pumps the page under `ResponsiveInit` and its localizations, with the controller provided the way the route provides it. CI Gate 3 runs them.

> [!IMPORTANT]
> **Without `--apps`, every app composes the new module — `apps/admin` included.** `apps/admin` is deliberately a subset (auth + settings). For a module meant for `mobile` only, say so when generating:
>
> ```bash
> dart tools/module_generator/generate.dart 1 profile "" 1 1 --apps mobile
> ```
>
> Already generated it into every app? Take it back out of `admin` by hand:
>
> 1. Delete its `- { id: <name>, layers: [...] }` line under `modules:` in `apps/admin/app_manifest.yaml` (or drop only the layers that app does not want from `layers:`).
> 2. `dart tools/composer/composer.dart sync` — rewrites `apps/admin/pubspec.yaml`'s path dependencies and `apps/admin/lib/di/injection.dart`; the root `workspace:` list keeps the package as long as another app composes it.
> 3. `flutter pub get && dart run build_runner build --workspace` — regenerates admin's `injection.config.dart`.
>
> Commit the manifest together with what `sync` regenerated: CI Gate 0 (`composer verify`) fails when they disagree (RULE-16).

**Manual — the tool prints this list at the end:**

1. Fill in the `TypedGoRoute` / navigator in `lib/src/routing/`.
2. Populate the route module stub (`routes`, and for a tab also `order`, `path`, `destination`).
3. Item 3 still mentions a navigator contract in `core_di`. Navigators now live in the module's API package instead (step 7, RULE-22); run the barrel generator for that package.
4. Re-run `build_runner`, then **full restart** the app — hot reload does not pick up new DI registrations.

> [!NOTE]
> FVM is auto-detected (`useFvm` in `tools/shared/toolchain.dart`, RULE-73). The tool prefixes its commands with `fvm ` only when both a config file (`.fvmrc` or `.fvm/fvm_config.json`) and a working `fvm --version` are present. Otherwise it calls the global `dart` / `flutter`. See [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md).

## 3. Find your way around the package

The generator produces this tree, plus the generated `gen/`, `*.g.dart` and `module.module.dart` files. `widgets/` is created **empty**. Git does not track an empty directory, so it disappears from a commit or a fresh clone until your first sub-widget lands in it.

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
│       ├── widgets/          *Widget / *Card sub-widgets (created empty)
│       ├── provider/         controllers (Provider) — `bloc/` if you chose BLoC
│       ├── routing/          route modules + navigator impl
│       ├── extensions/       l10n extension
│       ├── gen/language/     generated localisations (do not edit)
│       └── utils/            constants owned by this package
└── pubspec.yaml
```

> [!NOTE]
> The controller directory is **singular** — `src/provider/` (as in `feature_auth`) or `src/bloc/` (as in `feature_home`). A plural `providers/` / `blocs/` folder is a naming violation (RULE-78); see [`../reference/02_naming.md`](../reference/02_naming.md).

The path constants are already there: the generator writes them to `lib/src/utils/<name>_path.dart`, and everything else references them (RULE-09). **Edit the generated file** to change or add a path; do not create a second one:

```dart
// modules/profile/feature/lib/src/utils/profile_path.dart — as generated
class ProfilePath {
  ProfilePath._();

  static const String PROFILE = '/profile';
}
```

It has the same shape as [`modules/home/feature/lib/src/utils/home_path.dart`](../../../modules/home/feature/lib/src/utils/home_path.dart).

## 4. Write the route module

### Option A — a bottom-nav tab (`INavDestinationModule`)

Two files. First the routes themselves — real code from [`modules/home/feature/lib/src/routing/home_route_module.dart`](../../../modules/home/feature/lib/src/routing/home_route_module.dart):

```dart
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
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

Then the DI contribution — real code from [`home_nav_destination.dart`](../../../modules/home/feature/lib/src/routing/home_nav_destination.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

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

`order` decides the tab's position and **must be unique** across all registered tabs. `AppRouter` sorts by it to build the `StatefulShellBranch` list.

### Option B — a pushed stack (`IFeatureRouteModule`)

Much smaller. Real code from [`modules/auth/feature/lib/src/routing/auth_feature_route_module.dart`](../../../modules/auth/feature/lib/src/routing/auth_feature_route_module.dart):

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

No `order`: these routes are matched by path, not by index.

> [!CAUTION]
> Never edit `platform/shell/app_shell/lib/src/navigation/app_router.dart` to add your routes (RULE-20). It collects contributions through `getAllOrEmpty<IFeatureRouteModule>()` and `getAllOrEmpty<INavDestinationModule>()`. Hardcoding there breaks feature removability.

## 5. Create the controller at the route

The controller is created in the route's `build`, never inside the page (RULE-21).

```dart
// BLoC — from home_route_module.dart above
return BlocProvider(
  // Auth is optional: an app composed without `feature_auth` registers
  // no ISessionStatusStream, and Home then shows the signed-out state.
  create: (_) => getIt<HomeProfileBloc>(
    param1: getItOrNull<ISessionStatusStream>(),
  ),
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
> **Never wrap the controller again inside the Page.** `BlocProvider` / `ChangeNotifierProvider` already lives at the route. A second wrapper creates a *second instance*: the page reads state that nothing writes to, and the first instance leaks. This is the single most common bug in this codebase's pattern.

Screen-scoped controllers are `@injectable`: a factory, disposed with the route. Only app-wide controllers — `AuthProvider`, `ThemeProvider`, `LanguageProvider` — are `@lazySingleton`. Registering a screen controller as a singleton leaks it for the process lifetime (RULE-10). Details in [`05_di.md`](05_di.md).

## 6. Edit the translations

Feature translations live in the feature. Nothing is added to the app shell (RULE-34).

**The generator already writes all four pieces below**: `l10n.yaml`, the two ARB files, the `context.l10n<Name>` extension and the `IFeatureLocalization` registration. It also runs `gen-l10n` once. Your job is to **edit the generated files**, chiefly the ARBs; do not create them again. They are shown here so you know what each one does.

`modules/profile/feature/l10n.yaml` — as generated, the same shape as [`modules/home/feature/l10n.yaml`](../../../modules/home/feature/l10n.yaml):

```yaml
arb-dir: assets/language
template-arb-file: en.arb
output-localization-file: app_localizations.dart
output-class: FeatureProfileLocalizations
preferred-supported-locales: [en, vi]
untranslated-messages-file: untranslated-messages.txt
output-dir: lib/src/gen/language
```

`assets/language/en.arb` (and a matching `vi.arb`) is generated with one key, `title`. The generated page — and, for a tab, the generated destination label — reads it as `context.l10nProfile.title`. Add your keys next to it, in `lowerCamelCase` (RULE-35). Translate the `vi.arb` value too: the generator writes the English word into both.

```json
{
  "@@locale": "en",
  "title": "Profile"
}
```

The extension — the generated one follows this real code from [`l10n_home_extension.dart`](../../../modules/home/feature/lib/src/extensions/l10n_home_extension.dart):

```dart
import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

The DI registration of the delegate — generated as `lib/di/localization.dart`, like this real code from [`modules/home/feature/lib/di/localization.dart`](../../../modules/home/feature/lib/di/localization.dart):

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

The app shell's [`app_material_wrapper.dart`](../../../platform/shell/app_shell/lib/src/app_material_wrapper.dart) collects every registered `IFeatureLocalization` with `getAllOrEmpty`. So **do not edit `root_app.dart`** (or the wrapper).

Regenerate after editing any `.arb`:

```bash
cd modules/profile/feature && flutter gen-l10n
```

> [!WARNING]
> All user-facing text must be translated. Hardcoded UI strings are forbidden — see [`09_localization_theming.md`](09_localization_theming.md).

## 7. Expose a navigator to other features

Other features must never import `feature_profile` (RULE-04). Declare the contract in your module's **API package**, `modules/<name>/api` — here `profile_api`, with foundation and Flutter dependencies only (`arch_check` R3). How to create one: [`12_module_isolation.md` § 4](12_module_isolation.md#4-create-a-module-api-package). Callers depend on `profile_api`, never on `feature_profile`; `core_di` holds no module's navigator (RULE-22):

```dart
// modules/profile/api/lib/src/navigators/profile_navigator.dart
import 'package:flutter/widgets.dart';

abstract class ProfileNavigator {
  void toProfile(BuildContext context);
}
```

That is exactly the shape of [`home_navigator.dart`](../../../modules/home/api/lib/src/navigators/home_navigator.dart) in `home_api`.

Implement it inside your own `routing/` — real code from [`home_navigator_impl.dart`](../../../modules/home/feature/lib/src/routing/home_navigator_impl.dart):

```dart
import 'package:home_api/home_api.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'home_route_module.dart';

@Singleton(as: HomeNavigator)
class HomeNavigatorImpl implements HomeNavigator {
  @override
  void toHome(BuildContext context) => const HomeRoute().go(context);
}
```

Callers in other packages use `getItOrNull<ProfileNavigator>()?.toProfile(context)` (RULE-12, `arch_check` R8). Never a hardcoded path, never `context.go('/profile')`. Always pass `BuildContext` from the calling widget rather than reading it from `NavigatorKeys` (RULE-23).

## 8. Regenerate and restart

```bash
# 1. Export the new ProfileNavigator from its API package's barrel (§7 added a file to modules/profile/api/lib)
dart tools/barrel_generator/generate.dart modules/profile/api/lib
# 2. Regenerate DI / routes — injectable must see ProfileNavigator through `package:profile_api/profile_api.dart`
dart run build_runner build --workspace
# 3. Re-export your feature's new files (and the generated ones) from its barrel
dart tools/barrel_generator/generate.dart modules/profile/feature/lib
flutter analyze
```

> [!IMPORTANT]
> Skip step 1 and `flutter analyze` reports `Undefined name 'ProfileNavigator'` in the navigator impl and its generated registration. The API package's barrel is generated, so a file added under `modules/profile/api/lib/src/` is invisible to other packages until the barrel generator runs for `modules/profile/api/lib`. The same holds for any package you add a file to: rerun the barrel generator for its `lib/` (RULE-75).

Then **full restart** the app (not hot reload), so the new DI graph is built.

## 9. Remove a feature

The app must keep running when any feature is deleted (RULE-05). Remove in this order:

1. Its line under `modules:` in every `apps/<id>/app_manifest.yaml` that composes it
2. `dart tools/composer/composer.dart sync` — regenerates `injection.dart`, the app's path dependencies and the root `workspace:` list
3. The `modules/<name>/feature/` directory
4. `flutter pub get && dart run build_runner build --workspace`

**For a sample, let the tool do it.** `remove_sample.dart` performs these steps. More importantly, it tells you what the manual list above cannot:

```bash
dart tools/sample_cleanup/remove_sample.dart --list   # what is sample vs framework
dart tools/sample_cleanup/remove_sample.dart auth     # dry-run, writes nothing
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

The tutorial's *Clean up* section walks the manual path once, for a module that is not a sample ([`../getting-started/04_first_feature_tutorial.md`](../getting-started/04_first_feature_tutorial.md#clean-up-remove-the-module)).

> [!CAUTION]
> **These steps are not always sufficient.** The shell degrades gracefully — it resolves everything through `core_di` contracts with `getAllOrEmpty` / `getItOrNull` fallbacks — but *other samples* may hold a hard dependency on the one you are deleting. A contract owned by a removable feature must reach its consumers the same way — never through a required constructor parameter, which DI cannot satisfy once the owner is gone. Removing `auth` today breaks no sample; three consumers degrade safely:
>
> | Consumer | How it couples | Result |
> |---|---|---|
> | `feature_home` (`home_route_module.dart:25`) | `getItOrNull<ISessionStatusStream>()` passed as a **factory param** | Home shows the signed-out state |
> | `feature_settings` (`settings_page.dart:47`) | `getItOrNull<IAuthActionHandler>()` (from `auth_api`, which `remove_sample` keeps while it is imported) | The logout row is simply hidden |
> | `feature_onboarding` (`OnboardingPage`) | `getItOrNull<AuthNavigator>()` (from `auth_api`, likewise kept) | The button goes to Home instead (`HomeNavigator`); with neither composed it does nothing |
>
> The dry-run prints every coupling it knows — `breaks` and `safe_couplings` in `tools/sample_manifest.yaml` — plus the API packages it keeps because another package still imports them. Read it before deleting anything.

> [!NOTE]
> `injection.dart` naming feature packages is the composition root's **one intentional hard reference** — a composition root must name what it composes. It is also the only one, and a machine holds that: `arch_check` R10 fails any other file in an app that imports a module, and the shared shell in `platform/shell/app_shell/` is a `platform/` package, which R1 forbids from importing one at all. The shell does import `core_ui_kit`, which is fine — that is a core package, not a removable feature.

---

## Verify

```bash
flutter analyze                                           # No issues found!
dart tools/arch_check/check.dart                          # ✅ All architecture rules hold across N packages.
dart tools/composer/composer.dart verify                  # ✅ Generated artifacts are up to date.
cd modules/profile/feature && flutter test && cd -        # All tests passed!
cd apps/mobile && flutter test test/di_smoke_test.dart    # All tests passed! — the new registrations resolve
dart tools/unused_checker/check_unused_packages.dart      # ✅ Success! No unused packages found …
```

Finish with a debug APK build after any DI or dependency change (RULE-77): `cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev`.

Review checklist:

- [ ] `resolution: workspace` present in the package `pubspec.yaml`
- [ ] Every dependency actually used is declared — verify with `dart tools/unused_checker/check_unused_packages.dart`
- [ ] Constants live in `src/utils/`, not scattered
- [ ] Route registered via `IFeatureRouteModule` / `INavDestinationModule` — `app_router.dart` untouched
- [ ] Controller created at route level, page does **not** re-wrap it
- [ ] Screen controller is `@injectable`, not a singleton
- [ ] `IFeatureLocalization` registered — `root_app.dart` untouched
- [ ] No hardcoded user-facing strings
- [ ] Sizes go through context — `context.w()` / `context.h()` / `context.sp()` / `context.r()`
- [ ] Navigator interface in the module's `<id>_api`, implementation in the feature's `routing/`
- [ ] No import of another feature (no exception — shared widgets come from `core_ui_kit`)

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| The generator exits 64 | A missing argument without a terminal, an invalid name, an unknown `--apps` id, or `feature_<name>` already exists | Pass all five arguments; pick another name or remove the old package (step 1) |
| The new module shows up in `apps/admin` | Generated without `--apps` | Remove it from `apps/admin/app_manifest.yaml`, then `composer sync` (step 2) |
| `composer verify` fails in CI | A manifest changed without `composer sync`, or a managed region was hand-edited | Run `dart tools/composer/composer.dart sync` and commit what it writes |
| `Undefined name 'ProfileNavigator'` | The API package's barrel does not export the new file | Run the barrel generator for `modules/profile/api/lib` (step 8) |
| The screen state never updates | The page wraps a second provider | Remove the wrapper from the page (step 5) |
| A new route or registration has no effect | Hot reload does not rebuild the DI graph | `build_runner`, then full restart (step 8) |
| `context.l10nProfile.<key>` does not exist | `gen-l10n` has not run since the ARB edit | `cd modules/profile/feature && flutter gen-l10n` (step 6) |

## Related

- Rules: RULE-04, RULE-05, RULE-09, RULE-10, RULE-16, RULE-20, RULE-21, RULE-22, RULE-23, RULE-24, RULE-34, RULE-35 — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../getting-started/04_first_feature_tutorial.md`](../getting-started/04_first_feature_tutorial.md) — this path once, end to end, verified
- [`04_routing.md`](04_routing.md) — routing contracts in depth
- [`03_state_management.md`](03_state_management.md) — Provider vs BLoC
- [`05_di.md`](05_di.md) — registration scopes and module ordering
- [`10_cross_feature.md`](10_cross_feature.md) — talking to other features
- [`../architecture/05_features.md`](../architecture/05_features.md) — layer rules
