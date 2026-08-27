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
3. *If creating a Feature: How should routes join the App Shell? (1. `IFeatureRouteModule` stack/standalone, 2. `IDashboardTabModule` bottom-nav tab, 3. None)*
   - Choose **2** only for a **primary authenticated bottom-nav destination**. Read `docs/{en,vi}/guides/04_routing.md` § Dashboard before choosing tab.
   - Login / detail / onboarding / push screens → **1**, never **2**.

Once the answers are obtained, run the corresponding command (the Agent runs the command directly instead of interactive execution):

### Step 1: Initialize Structure using the Automated Tool

```bash
# Syntax: dart tools/module_generator/generate.dart <type> <module_name> <directory> [sm] [route_contribution]
# <type>: 1 (Feature), 2 (Domain), 3 (Data), 4 (Core), 5 (Custom)
# <module_name>: Business entity name (e.g., profile, payment, logging)
# <directory>: Usually left empty "" (only used for Custom)
# [sm]: (Feature only) 1 (Provider), 2 (BLoC), 3 (None)
# [route_contribution]: (Feature only) 1 (IFeatureRouteModule), 2 (IDashboardTabModule), 3 (none)
```

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

### What the tool guarantees

| Behaviour | Detail |
| :--- | :--- |
| `lib/src/utils/` | Created for **every** module type — the repo requires each package to own its constants there. For a feature with routes, `<name>_path.dart` is written into `utils/`, not `routing/`. |
| State-management folder | `lib/src/provider/` or `lib/src/bloc/` — **singular**, matching `feature_auth` / `feature_home`. |
| Toolchain detection | Auto-detects FVM: uses it only when a config (`.fvmrc` or `.fvm/fvm_config.json`) exists **and** `fvm --version` succeeds; otherwise falls back to global `dart` / `flutter`. |
| Fail-safe | `assertToolchainAvailable()` runs **before any write**; an existing module directory aborts instead of being silently overwritten. |
| Rollback | The three shared files (root `pubspec.yaml`, `app/pubspec.yaml`, `app/lib/di/injection.dart`) are snapshotted first; any later failure restores them and deletes the new module directory. |

### Step 2: Implement Boilerplate & Route Definition (for Feature)
The tool generates the basic directory structure (including `assets/language` and `l10n.yaml`), registers `IFeatureLocalization`, and scaffolds either `*_feature_route_module.dart` or `*_dashboard_tab_module.dart` according to `[route_contribution]`.

**Clean Architecture / feature boundary (mandatory):**
- One feature package = one bounded UI concern (e.g. `feature_home`, `feature_settings`, `feature_auth`).
- Do **not** put unrelated shell tabs in the same package (Home + Settings = two packages).
- **`feature_dashboard` is chrome only** (`DashboardRouteModule`). It does **not** own tab pages. Tabs register `IDashboardTabModule`; `AppRouter` assembles branches.
- Cross-feature UI actions use Action Handlers / Navigators in `core_di` — never import another feature package.
- **core packages must never depend on your feature.** The only approved inward exceptions are
  `core_di → domain_auth`, `provider_state_management → domain_core` and
  `core_common → domain_core`.

For Features, complete the TypedGoRoute file (e.g. `lib/src/routing/*_route_module.dart`) and fill the DI contribution stub:

**If using Provider:**
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
- Fill `IFeatureRouteModule.routes` **or** `IDashboardTabModule` (`order`, `path`, `routes`, `navigationBarItem`).
- Optional cold-start: `@LazySingleton(as: IAppEntryLocation)`.
- Host already collects with `getAllOrEmpty` / `getItOrNull`. Follow `implement_navigation_route` Step 6.

### Step 4: Run Code Generation & Sync
```bash
dart tools/dependency_sync.dart
dart run build_runner build -d --workspace
```
Then **hot restart** the app (new DI registrations are not applied by hot reload).

### Step 5: Keep the module removable

The app must still build after any feature package is deleted. Before finishing, confirm:

- Nothing outside the feature imports `package:feature_<name>/...` except
  `app/lib/di/injection.dart` (the composition root — an intentional hard reference).
- Anything the shell or another feature consumes from you is published as a **contract in
  `core_di`**, resolved with `getItOrNull` / `getAllOrEmpty` and a fallback.
- Removal procedure (documented in `injection.dart`): drop the `ExternalModule(...)` entry
  and its import → the `feature_x:` entry in `app/pubspec.yaml` → the path in the root
  `pubspec.yaml` `workspace:` list → `flutter pub get` + `build_runner`.

---

## 🔗 Related

- `docs/{en,vi}/guides/01_new_feature.md` — the long-form walkthrough
- `docs/{en,vi}/guides/02_new_domain_data.md` — domain + data packages
- `implement_navigation_route`, `implement_dependency_injection`
