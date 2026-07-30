# 07. Strict Naming Conventions & Programming Rules (Rules & Conventions)

To ensure the monorepo maintains absolute consistency in source code aesthetics and prevents Architecture Breakdown when multiple developers work together, **all members are strictly required to 100% comply with the following regulations.**

---

## 💎 1. Data Class Initialization Rule (Freezed Standard)

- **Regulation**: All raw data objects in the Data layer (Models/DTOs) and UI state entities (State Models) **MUST** be structured using the `freezed` library to ensure Immutability.
- **Entities (Domain layer) & Request Params**: Using `freezed` is **OPTIONAL** (encouraged for shorter code, but pure Dart classes combined with `equatable` are allowed if you want to keep the Domain clean and independent of code generators).

✅ **Example Domain Entity Using Freezed (Standard):**
```dart
@freezed
class UserEntity with _$UserEntity {
  const UserEntity._(); // Must declare this empty constructor to use getters/methods!
  
  const factory UserEntity({
    required String id,
    required String fullName,
  }) = _UserEntity;
}
```

---

## 🏷️ 2. Uniform Class & File Suffixes (Naming Suffixes)

All files and class names must be uniformly named based on their technical function for easy searching:

| Architectural Layer        | File Suffix (Snake Case)      | Class Name Suffix (Pascal Case) | Example                   |
| :------------------------- | :---------------------------- | :------------------------------ | :------------------------ |
| **User Interface (Pages)** | `_page.dart` / `_screen.dart` | `Page` / `Screen`               | `LoginPage`, `HomeScreen` |
| **User Interface (Widgets)**| `_widget.dart` / `_card.dart` | `Widget` / `Card`               | `PrimaryButtonWidget`     |
| **UI Controller**          | `_provider.dart` / `_bloc.dart` | `Provider` / `Bloc` / `Cubit`   | `LoginProvider`, `AuthBloc` |
| **Business Logic**         | `_usecase.dart`               | `UseCase`                       | `LoginUseCase`            |
| **Clean Entity**           | `_entity.dart`                | `Entity`                        | `UserEntity`              |
| **Repository Interface**   | `i_` + `_repository.dart`     | Starts with letter `I`          | `IAuthRepository`         |
| **Receive API Object**     | `_response.dart`              | `Response`                      | `UserResponse`            |
| **Send API Object**        | `_request.dart`               | `Request`                       | `LoginRequest`            |
| **Repository Impl**        | `_repository_impl.dart`       | `RepositoryImpl`                | `AuthRepositoryImpl`      |
| **Specific Navigator Impl**| `_navigator_impl.dart`        | `NavigatorImpl`                 | `AuthNavigatorImpl`       |
| **Action Handler Interface**| `i_` + `_action_handler.dart` | Starts with letter `I`          | `IAuthActionHandler`      |
| **Action Handler Impl**    | `_action_handler_impl.dart`   | `ActionHandlerImpl`             | `AuthActionHandlerImpl`   |

---

## 🔠 3. Constants & Multi-Environment Configuration Rules (Constants & Flavors)

- **Regulation**: Absolutely no hard-coding of String strings, API endpoints, HEX color codes, or memory keys directly in UI code. All must be centrally declared in the `core_common` or `core_base_ui` packages.
- **Format**: Constant variable names **MUST BE WRITTEN IN ALL UPPERCASE WITH UNDERSCORES (`UPPER_SNAKE_CASE`)** to distinguish them from regular variables.
- **Multi-environment**: Use `AppConfig.appFlavor` to retrieve the current Flavor (`Flavor.dev`, `Flavor.staging`, `Flavor.prod`) instead of manually checking `kDebugMode` to tightly control system behavior according to the development Flavor.

```dart
class ApiConstants {
  ApiConstants._();
  
  // MUST BE UPPER_SNAKE_CASE
  static const String BASE_URL = 'https://api.codebase.com/v1';
  static const String SUBMIT_APPLICATION = '/jobs/apply';
}
```

---

## 🧱 4. Strict Physical Layer Separation (Strict Layer Isolation & DI)

The Domain business layer (`packages/domain/* (Micro-packages)`) plays the central role and absolutely must not contain any imports related to Flutter UI or network calling libraries:

- **Banned imports at Domain**: `package:flutter/material.dart`, `package:dio/dio.dart`, `package:retrofit/retrofit.dart`.
- **Dependency Injection Scope Definition**:
  - **Feature UI Controllers (ViewModel / Bloc)**: UI logics tied to a screen **MUST** be registered using `@injectable` so GetIt can instantiate a completely new object upon each retrieval. Absolutely do not use Singleton for them. Then, at the Routing layer (`Route level`), use the corresponding provider Widget (e.g., `ChangeNotifierProvider` or `BlocProvider`) so the system automatically disposes (Auto-dispose) when the user leaves the screen.
  - **Global Controllers (App-wide)**: Allowed to use `@lazySingleton` (e.g., `AuthProvider`, `ThemeProvider`, `LanguageProvider`) because they need to maintain state throughout the application lifecycle.
  - **Constructor Injection**: Absolutely **do not** use the static call `getIt<T>()` directly inside business classes. All Navigators, UseCases, Repositories, and Configurations must receive their Dependencies via **Constructor Injection** to perfectly support Mocking & Unit testing.

```dart
// domain/lib/usecases/login_usecase.dart

// ❌ ABSOLUTELY FORBIDDEN (SEVERE ARCHITECTURE ERROR)
import 'package:dio/dio.dart'; 
import 'package:flutter/widgets.dart';

// ✅ VALID (PURE DART)
import 'package:domain/repositories/i_auth_repository.dart';
```

---

## 🚦 5. Safe Routing & Navigation Standard

The `go_router` routing system is completely redesigned to be independent, type-safe, and uses decentralized scoped routing:

- **`AppRouter` is Singleton**: The `AppRouter` class is managed as a GetIt `@singleton`. Do not write static properties or static lookups.
- **Dynamic DI route assembly**: Do **not** edit `app_router.dart` to append `$…Route` / hardcode `StatefulShellBranch`. Features register `IFeatureRouteModule` (stack; **no order**) or `IDashboardTabModule` (tabs; **with order**). Optional: `IAppEntryLocation`. Dashboard chrome: `DashboardRouteModule` only in `feature_dashboard`. Host uses `getAllOrEmpty` / `getItOrNull` with empty/`SizedBox` fallbacks. Details: `docs/en/08_routing.md` § Dashboard.
- **Decentralized Navigators**: Navigator interfaces are centrally defined at `core_di` and `NavigatorImpl` implementation classes must be placed locally inside the `routing/` directory of each corresponding Feature package (not centrally implemented at the App Shell).
- **Direct context passing**: Navigation methods must receive `BuildContext context` from the UI class to ensure widget lifecycle and execute transition actions via GoRouteData:
  ```dart
  @Singleton(as: AuthNavigator)
  class AuthNavigatorImpl implements AuthNavigator {
    @override
    void toLogin(BuildContext context) => const LoginRoute().go(context);
  }
  ```
- **Safe Deep Link Initialization**: The deep link processing flow (`DeeplinkProvider` configured as `@lazySingleton`) must be safely called inside the end-of-frame drawing event (`WidgetsBinding.instance.endOfFrame.whenComplete`) at the `initState` of `NavigatorWrapperWidget` in `app/lib/presentation/widgets/navigator_wrapper_widget.dart`. This ensures `BuildContext` has finished rendering and completely avoids UI lifecycle conflicts when redirecting instantly.
- **Shell Error Page**: GoRouter's `errorPageBuilder` MUST use `UndefineRouteWidget` (not an inline anonymous widget).

---

## 🚀 6. Centralized Application Boot & Main.dart Restructuring

To keep the project's entrypoint always clean and maintainable:
- **`AppInitializer`**: All initial system configuration logic (DI Container, HttpOverrides, Logger, Screen Orientation, System UI Overlay) must be centrally encapsulated in the static method `AppInitializer.init()`.
- **Streamlined `main.dart`**: The `main.dart` file **does not** contain miscellaneous service initialization source code. It only serves the sole purpose of wrapping the application in `runZonedGuarded` and handing over to `AppInitializer.init` within the `MainScope` environment.

---

## 🔒 7. SSL/TLS Certificate Pinning Security & HttpOverrides Control

Network infrastructure must be strictly protected against Man-in-the-Middle (MITM) eavesdropping attacks:

- **Global SSL Pinning**: Installing public key hashes (SPKI SHA-256 hashes) is managed centrally via `HttpOverrides.global` using `_MyHttpSecurityPinningHttpOverrides` wrapping `HttpSecurityPinningClient`.
- **Flavor Control**:
  - In **Development Environment (`Flavor.dev`)**: Activate SSL bypass `badCertificateCallback = (...) => true` to support testing internal servers with self-signed certificates.
  - In **Staging and Production Environments (`Flavor.staging` / `Flavor.prod`)**: **MANDATORY** to disable SSL bypass and strictly execute SPKI hash matching to ensure absolute safety for end users.

---

## 🛑 8. Crash Prevention & UI Error Leak Management

- **Regulation**: It is absolutely forbidden to use the `throw` statement to throw Exceptions freely from the Data layer straight out to the UI. The User Interface (UI) has no responsibility to try-catch to handle connection errors.
- **Solution**: All errors must be neatly caught at the Data layer's `RepositoryImpl`, converted into a compatible `AppFailure` entity, and returned as `Result.failure(failure)`.

```dart
// data/lib/repositories_impl/auth_repository_impl.dart

// ✅ STANDARD
try {
  final response = await _remoteDataSource.login(params);
  return Result.success(response.toEntity());
} on DioException catch (e) {
  return Result.failure(AppFailure.serverError(message: e.message));
}
```

---

## 🚦 9. UI State Management Automation (State Management Agnostic)

Because the system supports multi-platform state management, you must strictly comply with the Base Class of the library you are using:

- **Provider**: Mandatory to inherit `BaseProvider<T>` and use `executeOperation` to automate Loading and Error.
- **BLoC**: Prefer inheriting `BaseBloc` (use `BaseCubit` only when events are unnecessary). **`ViewState<T>` is recommended for simple screens but not mandatory** — complex features may define their own Freezed UI state and use `BaseBloc<Event, CustomState>` with `emit()`.

*(Please dive deep into the README.md documentation inside the `provider_state_management` or `bloc_state_management` packages to see detailed examples).*

---

## 🛠️ 10. Scripts Standards & Monorepo Structure

- **Flat Workspace**: The Monorepo structure is organized flatly via the `resolution: workspace` configuration at the root `pubspec.yaml`. Do not create intermediate workspace nodes in subdirectories.
- **CLI Tools & Scripts**: All scripts supporting automated code generation or system tasks (e.g., `barrel_generator`, `generate_localization`) are only allowed to be created as executable files running on Linux/macOS (`.sh`) and Windows Command Prompt (`.bat`). **ABSOLUTELY FORBIDDEN** to create Windows PowerShell (`.ps1`) script files due to restrictive script execution security policies on Windows.

---

## 📦 11. Centralized Dependency Management

To completely resolve the Dependency Version Conflict problem between Feature Packages and Core Packages in the monorepo when many developers work together, the system applies a **Centralized Management via Catalog** mechanism:

- **Root Configuration File**: All versions of third-party libraries (third-party dependencies & dev_dependencies) must be declared solely in the [pubspec_dependencies.yaml](file:///c:/Users/PC/Desktop/codebase/pubspec_dependencies.yaml) file at the monorepo's root directory. This is the **Single Source of Truth (SSOT)** for the entire project.
- **Auto Sync Tool**: Absolutely do not arbitrarily declare versions in the `pubspec.yaml` files of individual child packages. Instead, after adding/modifying libraries, developers MUST run the sync command:
  ```bash
  dart tools/dependency_sync.dart
  ```
  This tool will automatically analyze and accurately synchronize versions from `pubspec_dependencies.yaml` to all packages in the monorepo.
- **Consistency Checking (CI/CD & Git Hook)**:
  Developers can check version consistency using the command:
  ```bash
  dart tools/dependency_sync.dart --check
  ```
  This command will scan the entire workspace and report an error (exit code 1) if it detects any mismatch compared to the catalog. This command is directly integrated into the CI/CD pipeline and Git Pre-commit Hook to completely prevent pushing version-conflicted source code to the system.

---

## 🎨 12. Theme & Styles Usage Standards (Design System)

To ensure consistent interfaces, automatically support Dark/Light mode, and scale accurately across multiple device sizes (responsive), all UI must use the Design System from the `core_base_ui` package:

- **Absolutely no hard-coding** colors, spacings, border radii (e.g., `Colors.white`, `16.0`, `Radius.circular(8)`).
- **Colors**: Colors are supported to automatically switch according to the Theme (Light/Dark). Quick access via `context.colors`:
  - `context.colors.textPrimary`, `context.colors.textSecondary`, `context.colors.surface`, `context.colors.primary`, etc.
  - *(Important Note: Color variable names, text styles, spacings must be named 100% IN SYNC with the names on the Figma/Design System blueprint. If the Design dictates the name is `wht`, `l2`, `bk` or `abc`, developers must keep exactly that name in the code to ensure uniform communication with Designers).*
- **Typography / Text Styles**: Mandatory to use the predefined Typography system via `context` (configured with `flutter_screenutil`'s `.sp` to auto-scale text size):
  - Example: `AppTextStyles.bodyMediumStyle(context)Style`, `AppTextStyles.titleLargeStyle(context)Style`, `AppTextStyles.displaySmallStyle(context)Style`, `AppTextStyles.labelSmallStyle(context)Style`.
  - Do not hard-code `TextStyle(fontSize: 14)` directly on Widgets.
- **Sizing & Spacing (Padding/Margin)**: Use `AppSpacing` to ensure padding/margin auto-scales according to `.w` (of `flutter_screenutil`):
  - `AppSpacing.xs`, `AppSpacing.sm`, `AppSpacing.md`, `AppSpacing.lg`, `AppSpacing.xl`
- **Border Radius**: Use `AppRadius` to automatically scale border radii according to `.r`:
  - Get double constant: `AppRadius.sm`, `AppRadius.md`, `AppRadius.circular`
  - Get BorderRadius object: `AppRadius.smRadius`, `AppRadius.mdRadius`, `AppRadius.circularRadius`
- **Gradients & Shadows**: Use centrally from `AppGradients` and `AppShadows`.

---

## 🌍 13. Multi-language & Assets Standards (Localization)

- **Mandatory Translation**: All text displayed on the interface (hardcoded UI text, toast messages, server error messages) **MUST** be integrated into the multi-language system.
- **Feature-Scoped Translations**: Each Feature must define its own `.arb` translation files inside the `assets/language/` directory (e.g., `packages/features/auth/assets/language/en.arb`). The `core_base_ui` package MUST ONLY be used to contain global translation strings.
- When calling a translation, use that specific Feature's extension (e.g., `context.l10nAuth.translationKey`) instead of a global delegate.
- **Absolutely forbidden** to hardcode strings directly on the UI.
- **Decentralized Delegation**: Feature packages **MUST NOT** edit the `app/lib/presentation/root_app.dart` file to add `LocalizationsDelegates`. Instead, they must provide an implementation of the `IFeatureLocalization` interface and register it into the local DI (`@LazySingleton(as: IFeatureLocalization)`). The root app will dynamically collect all delegates via `getIt.getAll<IFeatureLocalization>()`. The same pattern applies to routing: register `IFeatureRouteModule` / `IDashboardTabModule` / `IAppEntryLocation` / `DashboardRouteModule`; the host collects them with `getAllOrEmpty` / `getItOrNull` — never hardcode feature routes into `app_router.dart`.

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
