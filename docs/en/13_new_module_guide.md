# 13. New Module Creation Guide (New Module Creation Guide)
This document provides detailed instructions to create a new **Feature**, **Domain**, **Data**, or **Core** Package in the Monorepo system.

---

## 🚀 1. Using Automated Tools (Recommended)

The project provides a CLI toolset at `tools/module_generator/generate.dart` to automate the entire boilerplate setup process.

### General Syntax:
```bash
dart tools/module_generator/generate.dart <type> <module_name> [<directory>] [<state_management>]
```

| Parameter | Value | Description |
|:--------|:--------|:------|
| `<type>` | `1` Feature, `2` Domain, `3` Data, `4` Core, `5` Custom | Module type |
| `<module_name>` | Example: `profile`, `payment`, `chat` | Business name |
| `<directory>` | (Only for Custom) Example: `features` | Parent directory |
| `<state_management>` | (Only for Feature) `1` Provider, `2` BLoC, `3` None | State management tool |

### Practical Examples:
```bash
# Create 'profile' Feature with Provider:
dart tools/module_generator/generate.dart 1 profile "" 1

# Create 'payment' Domain micro-package:
dart tools/module_generator/generate.dart 2 payment

# Create 'payment' Data micro-package:
dart tools/module_generator/generate.dart 3 payment
```

### The tool will automatically perform:
1. Create standard directory structure for the corresponding module type.
2. Generate `pubspec.yaml` with full dependencies (including `retrofit`/`dio` for Data, `go_router` for Feature).
3. Setup Micro-package DI (`lib/di/module.dart`).
4. Generate `.gitignore` for code generation.
5. Register the new package into `workspace` in root `pubspec.yaml`.
6. Register DI module into `app/lib/di/injection.dart` (automatically categorize into lists like `_coreModules`, `_featureModules`, etc.).
7. Run `dependency_sync.dart` to synchronize library versions.
8. Run `flutter pub get`.
9. Generate barrel files (`lib/<package_name>.dart`).
10. Run `build_runner build --workspace` to generate DI code.

---

## 🏗️ 2. Feature Package Creation Process

### Step 1: Run Generator
```bash
dart tools/module_generator/generate.dart 1 profile "" 1
```

### Step 2: Generated directory structure
```text
packages/features/profile/
├── lib/
│   ├── di/
│   │   └── module.dart
│   └── src/
│       ├── pages/
│       ├── providers/      # Or blocs/ depending on choice
│       ├── routing/
│       └── widgets/
└── pubspec.yaml
```

### Step 3: Define Route
Create a routing file in `lib/src/routing/`. Example with Provider:
```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

part 'route_module.g.dart';

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

### Step 4: Register routes via DI (not AppRouter lists)
Do **not** open `app_router.dart` to append routes.

1. Complete TypedGoRoute + Navigator in the feature `routing/` folder.
2. Register either:
   - `@LazySingleton(as: IFeatureRouteModule)` for stack/standalone screens, or
   - `@LazySingleton(as: IDashboardTabModule)` **only** for a primary bottom-nav tab (`order` + `path` + `routes` + `navigationBarItem`).
3. Optional: `@LazySingleton(as: IAppEntryLocation)` for cold start.
4. Ensure the package is in `app/pubspec.yaml` and `ExternalModule` in `injection.dart` (CLI usually does this).
5. Run `build_runner` and **hot restart**.

See `docs/en/08_routing.md` § Dashboard before choosing `IDashboardTabModule`.

---

## 🧬 3. Domain Micro-Package Creation Process

### Step 1: Run Generator
```bash
dart tools/module_generator/generate.dart 2 payment
```

### Step 2: Generated structure
```text
packages/domain/payment/
├── lib/
│   ├── di/
│   │   └── module.dart
│   └── src/
│       ├── entities/
│       ├── repositories/
│       └── usecases/
└── pubspec.yaml
```

### Step 3: Business Implementation
1. Create Entity at `lib/src/entities/`.
2. Create Repository interface at `lib/src/repositories/`.
3. Create UseCase at `lib/src/usecases/` (mark with `@injectable`).
4. Run barrel generator: `dart tools/barrel_generator/generate.dart packages/domain/payment/lib`
5. Run build_runner: `dart run build_runner build -d --workspace`

---

## 💾 4. Data Micro-Package Creation Process

### Step 1: Run Generator
```bash
dart tools/module_generator/generate.dart 3 payment
```

### Step 2: Generated structure
```text
packages/data/payment/
├── lib/
│   ├── di/
│   │   └── module.dart
│   └── src/
│       ├── data_sources/
│       ├── models/
│       └── repositories_impl/
└── pubspec.yaml
```

### Step 3: Integration Implementation
1. Create DTO/Model at `lib/src/models/` (along with `.toEntity()`).
2. Create Remote DataSource at `lib/src/data_sources/remote/` (Retrofit `@RestApi()`).
3. Create RepositoryImpl at `lib/src/repositories_impl/` (inheriting `IBaseRepository` from `data_core`).
4. Run barrel generator and build_runner.

---

## 🔧 5. Core Package Creation Process

### Step 1: Run Generator
```bash
dart tools/module_generator/generate.dart 4 analytics
```

### Step 2: Register into Workspace & DI
Generator automatically performs:
1. Adds to `workspace` in root `pubspec.yaml`.
2. Creates `lib/di/module.dart` with `@InjectableInit.microPackage()`.
3. Registers `CoreAnalyticsPackageModule` into `app/lib/di/injection.dart` (into `_coreModules` list).

---

## 💡 Important Notes
- **Use Barrel Tool**: Always run `dart tools/barrel_generator/generate.dart` when adding a new file or directory.
- **Version synchronization**: After creating a module, run `dart tools/dependency_sync.dart` if you need to update library versions.
- **Layer Compliance**: Features MUST NOT depend directly on the Data layer. They can only depend on the Domain layer.
- **Micro-package DI**: Always use `@InjectableInit.microPackage()` for child packages.
- **Stdout/Stderr**: If writing additional tools in `tools/`, absolutely do not use `print`, please use `stdout` and `stderr`.
- **Build Runner**: Use command `dart run build_runner build -d --workspace` (flag `-d` replaces the deprecated `--delete-conflicting-outputs`).

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
