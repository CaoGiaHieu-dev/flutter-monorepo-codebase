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
   - Choose **2** only for a **primary authenticated bottom-nav destination**. Read `docs/en/08_routing.md` § Dashboard before choosing tab.
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

### Step 2: Implement Boilerplate & Route Definition (for Feature)
The tool generates the basic directory structure (including `assets/language` and `l10n.yaml`), registers `IFeatureLocalization`, and scaffolds either `*_feature_route_module.dart` or `*_dashboard_tab_module.dart` according to `[route_contribution]`.

**Clean Architecture / feature boundary (mandatory):**
- One feature package = one bounded UI concern (e.g. `feature_home`, `feature_settings`, `feature_auth`).
- Do **not** put unrelated shell tabs in the same package (Home + Settings = two packages).
- **`feature_dashboard` is chrome only** (`DashboardRouteModule`). It does **not** own tab pages. Tabs register `IDashboardTabModule`; `AppRouter` assembles branches. See `docs/en/08_routing.md` § Dashboard.
- Cross-feature UI actions use Action Handlers / Navigators in `core_di` — never import another feature package.

For Features, complete the TypedGoRoute file (e.g. `lib/src/routing/*_route_module.dart`) and fill the DI contribution stub:

**If using Provider:**
```dart
@TypedGoRoute<ProfileRoute>(path: '/profile')
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

**If using BLoC:** prefer `BaseBloc` (Cubit only when events are unnecessary).

### Step 3: Expose routes via DI (do **not** edit `app_router.dart` lists)
- Fill `IFeatureRouteModule.routes` **or** `IDashboardTabModule` (`order`, `path`, `routes`, `navigationBarItem`).
- Optional cold-start: `@LazySingleton(as: IAppEntryLocation)`.
- Host already collects with `getAllOrEmpty` / `getItOrNull`. Follow `implement_navigation_route` Step 5.

### Step 4: Run Code Generation & Sync
```bash
dart tools/dependency_sync.dart
dart run build_runner build -d --workspace
```
Then **hot restart** the app (new DI registrations are not applied by hot reload).
