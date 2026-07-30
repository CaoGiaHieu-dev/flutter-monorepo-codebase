# 10. Pull Request Review Checklist (Review Checklist)

This document provides a standard checklist mandatory for all developers and Reviewers to apply before Merging any Pull Request (PR) into the main branch. The ultimate goal is to maintain the perfection of the **Micro-packages Monorepo** architecture, **SOLID** principles, and system safety regulations.

---

## 📂 1. Module Structure (Monorepo & Packages Structure)
- [ ] **Workspace Resolution**: Has the `pubspec.yaml` file of the new or modified package declared the `resolution: workspace` property in the config file?
- [ ] **Barrel File Export**: Have all public APIs and Widgets been fully exported via the main barrel file `lib/<package_name>.dart` for other packages to use? (And are the detailed implementation files kept hidden inside `src/`?)
- [ ] **Git Isolation**: Does the new package contain a separate `.gitignore` manager file to isolate generated code files (`.g.dart`, `.freezed.dart`) locally?

---

## 🧬 2. Core Packages Layer Review (Core Packages Layer)
- [ ] **Constants (Constants)**: Have all new constants been declared in all uppercase and using underscores (`UPPER_SNAKE_CASE`) in the `core_common` package?
- [ ] **Design System Standard**: Are there any raw display Widgets being written overwriting the general design? Have the components of `core_base_ui` been reused?
- [ ] **Theme Extensions**: Does the fetching of colors and typography at the UI correctly use the utility Extensions (`context.themeExtension.primary`, `context.textTheme`)?

---

## 🧠 3. Business Layer Review (Domain Package Layer)
- [ ] **Pure Dart Constraint**: Are the new source files belonging to the `packages/domain/*` packages 100% clean of imports related to Flutter UI (`material.dart`, `widgets.dart`) and network calling libraries (`dio`, `retrofit`)?
- [ ] **Entities Immutability**: Are the new data entities safely wrapped and ensuring immutability (`freezed`)? Has the empty constructor `const Class._()` been declared?
- [ ] **Single Responsibility UseCases**: Does each UseCase ensure it performs only a single business action and returns the result via the sealed class `Result<T, AppFailure>`?

---

## 💾 4. Data Package Layer Review (Data Package Layer)
- [ ] **Data Class Serialization**: Do the Models (DTOs) fully declare the `.toEntity()` function to transform raw data into clean entities before returning them to the Domain?
- [ ] **Exception Catcher Boundary**: Does the `RepositoryImpl` implementation class use a `try-catch` block to intercept all Exceptions and transform them into controlled `AppFailure` error entities? (Absolutely forbidden to use the `throw` statement to throw errors to the UI).
- [ ] **Retrofit API Interfaces**: Does the API connection correctly use the Retrofit Generator instead of manually coding network sending commands?

---

## 🖥️ 5. UI Presentation Layer Review (Feature Presentation Layer)
- [ ] **Feature Boundary**: Does each Feature package own a single bounded UI concern? Unrelated tabs/screens (e.g. Home vs Settings) are **not** dumped into one package; Dashboard only composes routes.
- [ ] **UI Controller Standard**: Do the UI Controllers (ViewModel / Bloc) inherit from standard Base Classes (`BaseProvider`, `BaseBloc`...)? Prefer Bloc over Cubit; Cubit only when events are unnecessary. Custom Freezed UI state is allowed when `ViewState<T>` is insufficient.
- [ ] **Controller Lifecycle (Auto-dispose)**: Do the UI logics tied to the screen ensure they are **NOT** registered as Singletons (`@singleton` or `@lazySingleton`)? Are they marked `@injectable` and properly managed in lifecycle at the Route Level (via `ChangeNotifierProvider` or `BlocProvider`) to free memory when turning off the screen?
- [ ] **Decentralized Localization**: Does the Feature use the `IFeatureLocalization` interface to register translations into DI instead of directly interfering with `root_app.dart`? Are the text strings on the interface localized instead of hardcoded?

---

## 🚦 6. Routing & Coordination (Decoupled Routing & DI)
- [ ] **Decoupled Scoped Navigators**: Do the interface classes (Pages) and ViewModels comply with the rule of calling indirectly via the local Interface Scoped Navigator (e.g., `AuthNavigator`) instead of directly importing the route file of another Feature?
- [ ] **Dynamic route DI**: Is the feature exposed via `IFeatureRouteModule` and/or `IDashboardTabModule` (and optional `IAppEntryLocation`) — **without** editing hardcoded `$…Route` lists in `app_router.dart`?
- [ ] **Dashboard misuse**: If touching tabs/shell — is `feature_dashboard` limited to `DashboardRouteModule` chrome? Are tab pages **not** imported into dashboard? Is `IDashboardTabModule` reserved for real bottom-nav destinations (not push-only screens)?
- [ ] **Action Handlers**: For cross-feature UI actions (e.g., logout from Settings), is an `I*ActionHandler` in `core_di` used with `*ActionHandlerImpl` in the owning feature (never import the owning feature package directly)?
- [ ] **Shell Widgets**: Does the App Shell use `NavigatorWrapperWidget` / `UndefineRouteWidget` (not legacy `_RootChildWrapper` / `UndefineRouteScreen`)?
- [ ] **Fallbacks**: Are missing modules handled with `getAllOrEmpty` / `getItOrNull` + empty/`SizedBox.shrink()`?
- [ ] **Platform Transitions**: Do the Routes of the new Feature correctly inherit `GoRouteDataCustom` to have platform transitions and automatically record Screen View logs?
- [ ] **Injectable Module Registers**: Does the new package declare the local DI module `@InjectableInit.microPackage()` at `di/module.dart`? Has that module been registered into the `app/lib/di/injection.dart` file of the Host App?

---

## 🛠️ 7. Development Tools & CLI Script Tools
- [ ] **No Print Rule**: Do the development tools (e.g., CLI tools in `tools/`) comply with the strict regulation of absolutely not using the `print()` command but switching to use `stdout.writeln` / `stderr.writeln`?
- [ ] **No Linter Ignores**: Are the files totally clean of non-standard linter ignore comments like `// ignore_for_file: avoid_print`?

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
