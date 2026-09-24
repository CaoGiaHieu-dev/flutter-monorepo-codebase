---
name: create_feature_module
description: Automatically initialize a new feature, domain, data, or core package adhering to the codebase's Monorepo architecture.
---

# 🛠️ Skill: Create New Module (Create Module)

Use this skill when the developer requests to create a new package/module in the monorepo (e.g., `feature_profile`, `domain_payment`, `data_payment`, `core_logging`, etc.).

---

## 📋 Step-by-Step Instructions

### MANDATORY STEP (MOST IMPORTANT): IDENTIFY MODULE TYPE AND STATE MANAGEMENT
Before creating the module, the Agent **MUST** ask the user if they have not provided clear specifications:
1. *What type of module do you want to create? (1. Feature, 2. Domain, 3. Data, 4. Core, 5. Custom)*
2. *If creating a Feature: Which State Management do you want to use? (1. Provider, 2. BLoC, 3. None)*
3. *If creating a Feature: How should routes join the App Shell? (1. `IFeatureRouteModule` stack/standalone, 2. `INavDestinationModule` bottom-nav tab, 3. None)*
   - Choose **2** only for a **primary authenticated bottom-nav destination**. Read `docs/{en,vi}/guides/04_routing.md` § Dashboard before choosing tab.
   - Login / detail / onboarding / push screens → **1**, never **2**.

Once the answers are obtained, run the corresponding command (the Agent runs the command directly instead of interactive execution):

### Step 1: Initialize Structure using the Automated Tool

```bash
# Syntax: dart tools/module_generator/generate.dart <type> <module_name> [prefix] [sm] [route_contribution]
# <type>: 1 (Feature), 2 (Domain), 3 (Data), 4 (Core → core_<name> at platform/<name>), 5 (Custom)
# <module_name>: Business entity name (e.g., profile, payment, logging)
# [prefix]: pass "" except for Custom — there it is the package-name PREFIX, not a directory:
#           the package is <prefix>_<name>, always at platform/<name>. A layer word
#           (feature, domain, data, core) is refused.
# [sm]: (Feature only) 1 (Provider), 2 (BLoC), 3 (None)
# [route_contribution]: (Feature only) 1 (IFeatureRouteModule), 2 (INavDestinationModule), 3 (none)
```

> [!IMPORTANT]
> For a **feature, always pass all five arguments**. A feature missing `[sm]` or
> `[route_contribution]` prompts for it on a terminal, which blocks an agent, and without a
> terminal (or with stdin at end of input) exits `64` instead of picking a default. Types 2–4
> need only `<type> <module_name>` — a non-empty third argument is refused for them; type 5
> needs the prefix as the third argument (prompted for on a terminal, exit `64` otherwise).
>
> Arguments are checked **before anything is written**, each refusal exiting `64` with the
> usage: `<module_name>` and a prefix must be Dart package names (lowercase letters, digits,
> `_`, starting with a letter, not a Dart keyword — `Bad-Name` is refused); `[sm]` and
> `[route_contribution]` accept only `1`/`2`/`3` and only for type 1; unknown flags are
> refused. `dart tools/module_generator/generate.dart --help` prints the usage.

**Examples:**

1. Feature `profile` with Provider + stack routes:
```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

2. Feature `chat` as a dashboard bottom-nav tab with BLoC:
```bash
dart tools/module_generator/generate.dart 1 chat "" 2 2
```

3. Domain micro-package `payment`:
```bash
dart tools/module_generator/generate.dart 2 payment
```

4. Custom platform package `acme_billing` (created at platform/billing):
```bash
dart tools/module_generator/generate.dart 5 billing acme
```

### What the tool guarantees

| Behaviour | Detail |
| :--- | :--- |
| `lib/src/utils/` | Created for **every** module type, because a package's constants belong there (a package that ends up with none may drop the empty folder — `arch_check` R4 never asks for one). For every feature, `<name>_path.dart` is written into `utils/` (not `routing/`) together with `routing/<name>_route_module.dart` — both regardless of the route choice; delete them if the feature contributes no routes. |
| State-management folder | `lib/src/provider/` or `lib/src/bloc/` — **singular**, matching `feature_auth` / `feature_home`. |
| Toolchain detection | Auto-detects FVM: uses it only when a config (`.fvmrc` or `.fvm/fvm_config.json`) exists **and** `fvm --version` succeeds; otherwise falls back to global `dart` / `flutter`. |
| Fail-safe | `assertToolchainAvailable()` runs **before any write**; an existing module directory aborts instead of being silently overwritten. |
| Rollback | The shared files it touches — every `app_manifest.yaml`, plus what `composer sync` rewrites (the root `pubspec.yaml`, each app's `pubspec.yaml` and `lib/di/injection.dart`) — are snapshotted first; any later failure restores them and deletes the new module directory, and the tool exits `1`. |
| Registration check | Presence in each `app_manifest.yaml` is decided by parsing the YAML, not by substring (`core_net` is no longer taken as registered because `core_network` exists). Every edit is re-parsed; a manifest the module could not be added to rolls everything back and exits `1`. |
| Barrels around codegen | The barrel generator runs before `build_runner` (the templates import sibling barrels) and again after it, so generated files (`module.module.dart`, `lib/src/gen/**`) are exported too. |

### Step 2: Implement Boilerplate & Route Definition (for Feature)
The tool generates the basic directory structure (including `assets/language` and `l10n.yaml`), registers `IFeatureLocalization`, and scaffolds either `*_feature_route_module.dart` or `*_nav_destination.dart` according to `[route_contribution]`.

**Clean Architecture / feature boundary (mandatory):**
- One feature package = one bounded UI concern (e.g. `feature_home`, `feature_settings`, `feature_auth`).
- Do **not** put unrelated shell tabs in the same package (Home + Settings = two packages).
- **`feature_dashboard` is chrome only** (`DashboardRouteModule`). It does **not** own tab pages. Tabs register `INavDestinationModule`; `AppRouter` assembles branches.
- Cross-feature UI actions use Action Handlers / Navigators in `core_di` — never import another feature package.
- **core packages must never depend on your feature.** The only approved inward exceptions are
  `platform_kernel → domain_core`, `provider_state_management → domain_core` and
  `bloc_state_management → domain_core`. Three, and nothing else.

For Features, complete the TypedGoRoute file (e.g. `lib/src/routing/*_route_module.dart`) and fill the DI contribution stub:

**If using Provider:** the generated `*Provider` already overrides `initialize()` — the hook
`BaseProvider` calls after construction. Put setup there; a method named anything else (e.g.
`init()`) never runs.
```dart
@TypedGoRoute<ProfileRoute>(path: ProfilePath.PROFILE)
class ProfileRoute extends GoRouteDataCustom with $ProfileRoute {
  const ProfileRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ChangeNotifierProvider(
      create: (context) => getIt<ProfileProvider>(),
      child: const ProfilePage(),
    );
  }
}
```

**If using BLoC:** prefer `BaseBloc` with `BlocViewState<T>` (Cubit only when events are
unnecessary). Note the BLoC branch has no `executeOperation` — see `implement_bloc_ui`.

### Step 3: Expose routes via DI (do **not** edit `app_router.dart` lists)
- Fill `IFeatureRouteModule.routes` **or** `INavDestinationModule` (`order`, `path`, `routes`, `destination`).
- Optional cold-start: `@LazySingleton(as: IAppEntryLocation)`.
- Host already collects with `getAllOrEmpty` / `getItOrNull`. Follow `implement_navigation_route` Step 6.

### Step 4: Run Code Generation & Sync
```bash
dart tools/dependency_sync.dart
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<name>/feature/lib   # after build_runner: barrels export generated files too
```
Then **hot restart** the app (new DI registrations are not applied by hot reload).

### Step 5: Keep the module removable

The app must still build after any feature package is deleted. Before finishing, confirm:

- Nothing outside the feature imports `package:feature_<name>/...` except each composing app's
  `apps/<id>/lib/di/injection.dart` (the composition root — an intentional, generated hard reference).
- Anything the shell or another feature consumes from you is published as a **contract in
  `core_di`**, resolved with `getItOrNull` / `getAllOrEmpty` and a fallback.
- Removal procedure: drop its line from `modules:` in every `apps/<id>/app_manifest.yaml` →
  `dart tools/composer/composer.dart sync` (regenerates `injection.dart`, the app pubspecs and the
  root `workspace:` list) → `flutter pub get` + `build_runner`. For a shipped sample only, run
  `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` — it accepts only the bundles
  listed in `tools/sample_manifest.yaml` (not a module you generated) and is a dry run without `--apply`.

---

## 🔗 Related

- `docs/{en,vi}/guides/01_new_feature.md` — the long-form walkthrough
- `docs/{en,vi}/guides/02_new_domain_data.md` — domain + data packages
- `implement_navigation_route`, `implement_dependency_injection`
