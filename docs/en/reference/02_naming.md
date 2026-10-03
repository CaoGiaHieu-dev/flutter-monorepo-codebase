# Naming Conventions

**This file answers:** what do I call this file, this class, this folder?

**After reading you can:** name anything in the repo without guessing, and spot a misnamed file in review.

Every example below is a real path in this repository — open it to see the convention applied.

---

## 1. Files and classes

| Component | File suffix | Class suffix | Real example |
|---|---|---|---|
| Screen | `_page.dart` / `_screen.dart` | `Page` / `Screen` | `modules/auth/feature/lib/src/pages/login_page.dart` |
| Sub-widget | `_widget.dart` / `_card.dart` | `Widget` / `Card` | `modules/auth/feature/lib/src/widgets/auth_header_widget.dart` |
| Controller (Provider) | `_provider.dart` | `Provider` | `modules/auth/feature/lib/src/provider/auth_provider.dart` |
| Controller (BLoC) | `_bloc.dart` | `Bloc` | `modules/home/feature/lib/src/bloc/home_profile_bloc.dart` |
| Controller (Cubit) | `_cubit.dart` | `Cubit` | *only when events are unnecessary* |
| BLoC events | `_event.dart` | `Event` | `modules/home/feature/lib/src/bloc/home_profile_event.dart` |
| Use case | `_usecase.dart` | `UseCase` | `modules/auth/domain/lib/src/usecases/login_usecase.dart` |
| Entity | `_entity.dart` | `Entity` | `modules/auth/domain/lib/src/entities/user_entity.dart` |
| Repository interface | `i_<name>_repository.dart` | prefix `I` | `modules/auth/domain/lib/src/repositories/i_auth_repository.dart` |
| Repository impl | `_repository_impl.dart` | `RepositoryImpl` | `modules/auth/data/lib/src/repositories_impl/auth_repository_impl.dart` |
| Model / DTO | `_model.dart` / `_response.dart` | `Model` / `Response` | `modules/cache/data/lib/src/models/cache_entry_model.dart` |
| Request DTO | `_request.dart` | `Request` | `platform/layers/data/lib/src/models/base_request.dart` |
| Use-case parameters | `_params.dart` | `Params` | `modules/auth/domain/lib/src/params/login_params.dart` |
| Data source | `_data_source.dart` | `DataSource` | `modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart` |
| Navigator interface | `<name>_navigator.dart` | `Navigator` | `modules/auth/api/lib/src/navigators/auth_navigator.dart` |
| Navigator impl | `_navigator_impl.dart` | `NavigatorImpl` | `modules/auth/feature/lib/src/routing/auth_navigator_impl.dart` |
| Action handler interface | `i_<name>_action_handler.dart` | prefix `I` | `modules/auth/api/lib/src/actions/i_auth_action_handler.dart` |
| Module API package | package `<id>_api` at `modules/<id>/api` | — | `modules/auth/api/pubspec.yaml` (`auth_api`) |
| Session location contribution | `_sign_in_location.dart` / `_post_sign_in_location.dart` | `SignInLocation` / `PostSignInLocation` | `modules/auth/feature/lib/src/routing/auth_sign_in_location.dart` |
| Action handler impl | `_action_handler_impl.dart` | `ActionHandlerImpl` | `modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart` |
| Session status stream (`ISessionStatusStream`) | `_status_stream_impl.dart` | `StatusStreamImpl` | `modules/auth/feature/lib/src/session/auth_status_stream_impl.dart` |
| Session gateway (`ISessionGateway`) | `_session_gateway_impl.dart` | `SessionGatewayImpl` | `modules/auth/data/lib/src/session/auth_session_gateway_impl.dart` |
| App tree wrapper (`IAppTreeWrapper`) | `_tree_wrapper.dart` | `TreeWrapper` | `modules/auth/feature/lib/src/app/auth_tree_wrapper.dart` |
| App splash screen (`IAppSplashScreen`) | `_screen_impl.dart` | `ScreenImpl` | `modules/splash/feature/lib/src/app/splash_screen_impl.dart` |
| Feature localization (`IFeatureLocalization`) | `_localization_impl.dart` | `LocalizationImpl` | `modules/auth/feature/lib/src/localization/auth_localization_impl.dart` |
| `BuildContext` l10n accessor | `l10n_<feature>_extension.dart` | `Context<Feature>Extension` | `modules/auth/feature/lib/src/extensions/l10n_auth_extension.dart` |
| Error state (Freezed) | `_error_state.dart` | `ErrorState` | `modules/auth/feature/lib/src/provider/auth_error_state.dart` |
| Dialog | `_dialog.dart` | `Dialog` | `platform/ui/ui_kit/lib/src/dialogs/retry_dialog.dart` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` | *no sample yet* |
| Route definitions (`GoRouteData`) | `_route_module.dart` | `Route` | `modules/home/feature/lib/src/routing/home_route_module.dart` (declares `HomeRoute`) |
| Stack route contribution (`IFeatureRouteModule`) | `_feature_route_module.dart` | `FeatureRouteModule` | `modules/auth/feature/lib/src/routing/auth_feature_route_module.dart` |
| Nav destination (`INavDestinationModule`) | `_nav_destination.dart` | `NavDestination` | `modules/home/feature/lib/src/routing/home_nav_destination.dart` |
| Route paths | `<feature>_path.dart` | `Path` | `modules/home/feature/lib/src/utils/home_path.dart` |
| Storage keys | `<owner>_storage_keys.dart` | `StorageKeys` | `modules/auth/data/lib/src/utils/auth_storage_keys.dart` |
| API endpoints | `<owner>_api_constants.dart` | `ApiConstants` | `modules/auth/data/lib/src/utils/auth_api_constants.dart` |
| UI constants | `<owner>_ui_constants.dart` | `UiConstants` | `modules/auth/feature/lib/src/utils/auth_ui_constants.dart` |
| Drift database | `_database.dart` (in `database/`) | `Database` | `modules/cache/data/lib/src/database/cache_database.dart` |
| Drift table | `_table.dart` (in `database/tables/`) | plural noun, no suffix | `modules/cache/data/lib/src/database/tables/cache_entries_table.dart` (declares `CacheEntries`) |
| Drift DAO | `_dao.dart` (in `database/dao/`) | `Dao` | `modules/cache/data/lib/src/database/dao/cache_entries_dao.dart` |

---

## 2. The `I` prefix

`I` marks an **interface and nothing else** (RULE-78, enforced by `arch_check` R15: a concrete class named `I[A-Z]…` fails).

✅ `IAuthRepository`, `IThemeStorage`, `IFeatureRouteModule`, `IDatabaseMigration`
❌ Never name an implementation `IAuthNavigator` — it is `AuthNavigatorImpl`

> [!NOTE]
> Navigator *interfaces* are the one intentional deviation: they are named `AuthNavigator`, `HomeNavigator` — no `I`. They live in the owning module's API package (`modules/<id>/api/lib/src/navigators/`) and their implementations carry the `Impl` suffix, which is what disambiguates them.

---

## 3. Constants

`UPPER_SNAKE_CASE`, in a class with a private constructor, inside the owning package's `utils/` (RULE-09, `arch_check` R4):

```dart
// modules/home/feature/lib/src/utils/home_path.dart
class HomePath {
  HomePath._();

  static const String HOME = '/home';
}
```

The private constructor is what prevents `HomePath()` from ever being instantiated.

---

## 4. Directories

Inside a package, `lib/src/` holds the code and `lib/di/` the DI entry; a package only has the folders it needs.

| Directory | Note |
|---|---|
| `data_sources/` | **plural**, snake_case — never `datasources/` (RULE-40) |
| `data_sources/remote/` | Retrofit / HTTP |
| `data_sources/local/` | storage / database |
| `database/`, `database/tables/`, `database/dao/` | a package's own Drift database — `modules/cache/data/lib/src/database/` |
| `repositories/` | interfaces (Domain) |
| `repositories_impl/` | implementations (Data) |
| `models/` | Freezed + JSON models (Data) |
| `session/` | session contributions: the status stream in a feature, the gateway in a data package |
| `provider/` | **singular** — `modules/auth/feature/lib/src/provider/` |
| `bloc/` | **singular** — `modules/home/feature/lib/src/bloc/` |
| `utils/` | constants owned by this package |
| `routing/` | route modules, navigator impls, sign-in / post-sign-in locations, nav destinations |
| `handlers/` | action handler impls |
| `app/` | what a feature contributes to the app tree: tree wrapper, splash screen |
| `localization/` | the `IFeatureLocalization` contribution |
| `extensions/` | `BuildContext` extensions, such as the `l10n<Feature>` accessor |
| `pages/`, `widgets/` | UI |
| `entities/`, `params/`, `usecases/` | Domain |
| `navigators/`, `actions/` | an API package's contracts (`modules/<id>/api/lib/src/`) |
| `di/` | `lib/di/module.dart`; the generated `module.module.dart` appears beside it |
| `gen/` | `lib/src/gen/` — generated l10n / assets, never hand-edited |

> [!WARNING]
> `provider/` and `bloc/` are **singular**, matching every shipped feature and what `module_generator` scaffolds. A plural `providers/` or `blocs/` folder is a violation — rename it.

---

## 5. Packages

| Layer | Prefix | Path | Example |
|---|---|---|---|
| Core | `core_` | `platform/<group>/<dir>/` | `core_storage` at `platform/infra/storage` |
| Domain | `domain_` | `modules/<name>/domain/` | `domain_auth` |
| Data | `data_` | `modules/<name>/data/` | `data_auth` |
| Feature | `feature_` | `modules/<name>/feature/` | `feature_home` |
| Module API | suffix `_api` | `modules/<name>/api/` | `auth_api` |

A module's directory is the bare name; the package name carries the layer. `modules/home/feature/` → `name: feature_home`, `modules/auth/api/` → `name: auth_api`. `arch_check` R3 reports a package whose name does not match its folder. Under `platform/` the folder and the package name differ freely: `platform/ui/design_system` is `core_base_ui`, `platform/foundation/contracts` is `core_di`.

Some packages break the prefix pattern by design: `platform_kernel`, `platform_app_shell`, `platform_shell_adapters`, `provider_state_management` and `bloc_state_management` (all under `platform/`), the apps (`mobile_app`, `admin_app`), and the tooling package `core_tools`.

---

## 6. Barrel files

A package has **one** barrel, named after the package: `lib/<package_name>.dart` (`modules/home/feature/lib/feature_home.dart`, `platform/ui/design_system/lib/core_base_ui.dart`). It is the package's public API and exports every Dart file under `lib/`, sorted. There are no per-folder barrels; inside a package, files import the concrete file (`../pages/home_page.dart`), never a barrel. Apps, the root and `tools/` have none.

Generate it with `dart tools/barrel_generator/generate.dart <package>/lib` after adding, renaming or deleting a `lib/` file (RULE-75). The generator skips `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, `firebase_options*`, and any file declaring `part of` — those are reached through their parent library. Other generated files present on disk (`module.module.dart`, `lib/src/gen/**`) *are* exported, so run it after `build_runner` / `gen-l10n`.

> [!CAUTION]
> The generator **replaces every `export` directive in the barrel** and deletes a hand-written directory barrel on each run. To re-export a symbol from another package, do it from a normal source file (a shim), not from the barrel.

---

## 7. Generated files

| Pattern | Produced by |
|---|---|
| `*.g.dart` | `json_serializable`, `retrofit`, `drift`, `go_router_builder` (typed routes) |
| `*.freezed.dart` | `freezed` |
| `*.module.dart` | `injectable` (per-package module) |
| `*.config.dart` | `injectable` (app-level assembly) |
| `lib/src/gen/**` | `gen-l10n`, `flutter_gen` |

**Never edit these by hand** (RULE-76; `arch_check` R6 reports one that lacks its generator header). Change the source annotation and re-run:

```bash
dart run build_runner build --workspace   # everything but gen-l10n
flutter gen-l10n                          # in a package with an l10n.yaml
```

`dart tools/workspace_setup/configure.dart` runs both for every package.

---

**Next:** [`03_tooling.md`](03_tooling.md) · [`01_rules.md`](01_rules.md)
