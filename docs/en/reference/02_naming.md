# Naming Conventions

**This file answers:** what do I call this file, this class, this folder?

**After reading you can:** name anything in the repo without guessing, and spot a misnamed file in review.

Every example below is a real path in this repository — open it to see the convention applied.

---

## 1. Files and classes

| Component | File suffix | Class suffix | Real example |
|---|---|---|---|
| Screen | `_page.dart` / `_screen.dart` | `Page` / `Screen` | `packages/features/auth/lib/src/pages/login_page.dart` |
| Sub-widget | `_widget.dart` / `_card.dart` | `Widget` / `Card` | `packages/features/auth/lib/src/widgets/auth_header_widget.dart` |
| Controller (Provider) | `_provider.dart` | `Provider` | `packages/features/auth/lib/src/provider/auth_provider.dart` |
| Controller (BLoC) | `_bloc.dart` | `Bloc` | `packages/features/home/lib/src/bloc/home_profile_bloc.dart` |
| Controller (Cubit) | `_cubit.dart` | `Cubit` | *only when events are unnecessary* |
| BLoC events | `_event.dart` | `Event` | `packages/features/home/lib/src/bloc/home_profile_event.dart` |
| Use case | `_usecase.dart` | `UseCase` | `packages/domain/auth/lib/src/usecases/auth/login_usecase.dart` |
| Entity | `_entity.dart` | `Entity` | `packages/domain/auth/lib/src/entities/user/user_entity.dart` |
| Repository interface | `i_<name>_repository.dart` | prefix `I` | `packages/domain/auth/lib/src/repositories/i_auth_repository.dart` |
| Repository impl | `_repository_impl.dart` | `RepositoryImpl` | `packages/data/auth/lib/src/repositories_impl/auth_repository_impl.dart` |
| Model / DTO | `_model.dart` / `_response.dart` | `Model` / `Response` | `packages/data/core/lib/src/models/cache_entry_model.dart` |
| Request DTO | `_request.dart` | `Request` | `packages/data/core/lib/src/models/base_request.dart` |
| Data source | `_data_source.dart` | `DataSource` | `packages/data/auth/lib/src/data_sources/local/auth_local_data_source.dart` |
| Navigator interface | `<name>_navigator.dart` | `Navigator` | `packages/core/di/lib/src/navigators/auth_navigator.dart` |
| Navigator impl | `_navigator_impl.dart` | `NavigatorImpl` | `packages/features/auth/lib/src/routing/auth_navigator_impl.dart` |
| Action handler interface | `i_<name>_action_handler.dart` | prefix `I` | `packages/core/di/lib/src/actions/i_auth_action_handler.dart` |
| Action handler impl | `_action_handler_impl.dart` | `ActionHandlerImpl` | `packages/features/auth/lib/src/handlers/auth_action_handler_impl.dart` |
| Dialog | `_dialog.dart` | `Dialog` | `packages/core/ui_kit/lib/dialogs/error_dialog.dart` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` | — |
| Route module | `_route_module.dart` | `RouteModule` | `packages/features/home/lib/src/routing/home_route_module.dart` |
| Route paths | `<feature>_path.dart` | `Path` | `packages/features/home/lib/src/utils/home_path.dart` |
| Storage keys | `<owner>_storage_keys.dart` | `StorageKeys` | `packages/data/auth/lib/src/utils/auth_storage_keys.dart` |
| API endpoints | `<owner>_api_constants.dart` | `ApiConstants` | `packages/data/auth/lib/src/utils/auth_api_constants.dart` |

---

## 2. The `I` prefix

`I` marks an **interface and nothing else**.

✅ `IAuthRepository`, `IThemeStorage`, `IFeatureRouteModule`, `IDatabaseMigration`
❌ Never name an implementation `IAuthNavigator` — it is `AuthNavigatorImpl`

> [!NOTE]
> Navigator *interfaces* are the one intentional deviation: they are named `AuthNavigator`, `HomeNavigator` — no `I`. They live in `core_di/lib/src/navigators/` and their implementations carry the `Impl` suffix, which is what disambiguates them.

---

## 3. Constants

`UPPER_SNAKE_CASE`, in a class with a private constructor, inside the owning package's `utils/`:

```dart
// packages/features/home/lib/src/utils/home_path.dart
class HomePath {
  HomePath._();

  static const String HOME = '/home';
}
```

The private constructor is what prevents `HomePath()` from ever being instantiated.

---

## 4. Directories

| Directory | Note |
|---|---|
| `data_sources/` | **plural**, snake_case — never `datasources/` |
| `data_sources/remote/` | Retrofit / HTTP |
| `data_sources/local/` | storage / database |
| `repositories/` | interfaces (Domain) |
| `repositories_impl/` | implementations (Data) |
| `provider/` | **singular** — `packages/features/auth/lib/src/provider/` |
| `bloc/` | **singular** — `packages/features/home/lib/src/bloc/` |
| `utils/` | constants owned by this package |
| `routing/` | route modules, navigator impls |
| `handlers/` | action handler impls |
| `pages/`, `widgets/` | UI |
| `entities/`, `params/`, `usecases/` | Domain |
| `di/` | `module.dart` + generated `module.module.dart` |
| `gen/` | generated l10n / assets — never hand-edited |

> [!WARNING]
> `provider/` and `bloc/` are **singular**, matching every shipped feature and what `module_generator` scaffolds. A plural `providers/` or `blocs/` folder is a violation — rename it.

---

## 5. Packages

| Layer | Prefix | Path | Example |
|---|---|---|---|
| Core | `core_` | `packages/core/<name>/` | `core_storage` |
| Domain | `domain_` | `packages/domain/<name>/` | `domain_auth` |
| Data | `data_` | `packages/data/<name>/` | `data_auth` |
| Feature | `feature_` | `packages/features/<name>/` | `feature_home` |

The directory is the bare name; the package name carries the prefix. `packages/features/home/` → `name: feature_home`.

Two packages break the prefix pattern by design: `provider_state_management` and `bloc_state_management` (both under `packages/core/`).

---

## 6. Barrel files

A barrel is named after its directory and re-exports everything public in it:

```
lib/src/utils/utils.dart          → exports every file in utils/
lib/src/src.dart                  → exports every subdirectory barrel
lib/<package_name>.dart           → the package's public API
```

Generated by `dart tools/barrel_generator/generate.dart <path>/lib`. The generator skips `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, and any file declaring `part of` — those are reached through their parent library.

> [!CAUTION]
> The generator **strips every hand-written `export` line** on each run. To re-export a symbol from another package, do it from a normal source file (a shim), not from the barrel.

---

## 7. Generated files

| Pattern | Produced by |
|---|---|
| `*.g.dart` | `json_serializable`, `retrofit`, `drift` |
| `*.freezed.dart` | `freezed` |
| `*.module.dart` | `injectable` (per-package module) |
| `*.config.dart` | `injectable` (app-level assembly) |
| `lib/src/gen/**` | `gen-l10n`, `flutter_gen` |

**Never edit these by hand.** Change the source annotation and re-run:

```bash
dart run build_runner build -d --workspace
```

---

**Next:** [`03_tooling.md`](03_tooling.md) · [`01_rules.md`](01_rules.md)
