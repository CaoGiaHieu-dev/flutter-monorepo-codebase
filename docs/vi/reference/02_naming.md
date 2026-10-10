<!-- translated-from: docs/en/reference/02_naming.md@4b2b033 -->
# Quy ước đặt tên

**File này trả lời:** file này đặt tên gì, class này đặt tên gì, thư mục này đặt tên gì?

**Đọc xong bạn có thể:** đặt tên mọi thứ trong repo mà không phải đoán, và nhận ra ngay file đặt tên sai khi review.

Mọi ví dụ dưới đây đều là đường dẫn có thật trong repo — mở ra xem là thấy quy ước được áp dụng.

---

## 1. File và class

| Thành phần | Hậu tố file | Hậu tố class | Ví dụ thật |
|---|---|---|---|
| Màn hình | `_page.dart` / `_screen.dart` | `Page` / `Screen` | `modules/auth/feature/lib/src/pages/login_page.dart` |
| Widget con | `_widget.dart` / `_card.dart` | `Widget` / `Card` | `platform/ui/ui_kit/lib/src/feedback/loading_widget.dart` |
| Controller (Provider) | `_provider.dart` | `Provider` | `modules/auth/feature/lib/src/provider/auth_provider.dart` |
| Controller (BLoC) | `_bloc.dart` | `Bloc` | `modules/home/feature/lib/src/bloc/home_profile_bloc.dart` |
| Controller (Cubit) | `_cubit.dart` | `Cubit` | *chỉ khi không cần event* |
| Event của BLoC | `_event.dart` | `Event` | `modules/home/feature/lib/src/bloc/home_profile_event.dart` |
| Use case | `_usecase.dart` | `UseCase` | `modules/auth/domain/lib/src/usecases/login_usecase.dart` |
| Entity | `_entity.dart` | `Entity` | `modules/auth/domain/lib/src/entities/user_entity.dart` |
| Interface repository | `i_<name>_repository.dart` | tiền tố `I` | `modules/auth/domain/lib/src/repositories/i_auth_repository.dart` |
| Impl repository | `_repository_impl.dart` | `RepositoryImpl` | `modules/auth/data/lib/src/repositories_impl/auth_repository_impl.dart` |
| Model / DTO | `_model.dart` / `_response.dart` | `Model` / `Response` | `modules/cache/data/lib/src/models/cache_entry_model.dart` |
| Request DTO | `_request.dart` | `Request` | `platform/layers/data/lib/src/models/base_request.dart` |
| Tham số use case | `_params.dart` | `Params` | `modules/auth/domain/lib/src/params/login_params.dart` |
| Data source | `_data_source.dart` | `DataSource` | `modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart` |
| Interface navigator | `<name>_navigator.dart` | `Navigator` | `modules/auth/api/lib/src/navigators/auth_navigator.dart` |
| Impl navigator | `_navigator_impl.dart` | `NavigatorImpl` | `modules/auth/feature/lib/src/routing/auth_navigator_impl.dart` |
| Interface action handler | `i_<name>_action_handler.dart` | tiền tố `I` | `modules/auth/api/lib/src/actions/i_auth_action_handler.dart` |
| Package API của module | package `<id>_api` tại `modules/<id>/api` | — | `modules/auth/api/pubspec.yaml` (`auth_api`) |
| Đóng góp vị trí session | `_sign_in_location.dart` / `_post_sign_in_location.dart` | `SignInLocation` / `PostSignInLocation` | `modules/auth/feature/lib/src/routing/auth_sign_in_location.dart` |
| Impl action handler | `_action_handler_impl.dart` | `ActionHandlerImpl` | `modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart` |
| Stream trạng thái session (`ISessionStatusStream`) | `_status_stream_impl.dart` | `StatusStreamImpl` | `modules/auth/feature/lib/src/session/auth_status_stream_impl.dart` |
| Gateway session (`ISessionGateway`) | `_session_gateway_impl.dart` | `SessionGatewayImpl` | `modules/auth/data/lib/src/session/auth_session_gateway_impl.dart` |
| Tree wrapper của app (`IAppTreeWrapper`) | `_tree_wrapper.dart` | `TreeWrapper` | `modules/auth/feature/lib/src/app/auth_tree_wrapper.dart` |
| Splash screen của app (`IAppSplashScreen`) | `_screen_impl.dart` | `ScreenImpl` | `modules/splash/feature/lib/src/app/splash_screen_impl.dart` |
| Localization của feature (`IFeatureLocalization`) | `_localization_impl.dart` | `LocalizationImpl` | `modules/auth/feature/lib/src/localization/auth_localization_impl.dart` |
| Accessor l10n trên `BuildContext` | `l10n_<feature>_extension.dart` | `Context<Feature>Extension` | `modules/auth/feature/lib/src/extensions/l10n_auth_extension.dart` |
| Error state (Freezed) | `_error_state.dart` | `ErrorState` | `modules/auth/feature/lib/src/provider/auth_error_state.dart` |
| Dialog | `_dialog.dart` | `Dialog` | `platform/ui/ui_kit/lib/src/dialogs/retry_dialog.dart` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` | *chưa có ví dụ* |
| Định nghĩa route (`GoRouteData`) | `_route_module.dart` | `Route` | `modules/home/feature/lib/src/routing/home_route_module.dart` (khai `HomeRoute`) |
| Đóng góp route stack (`IFeatureRouteModule`) | `_feature_route_module.dart` | `FeatureRouteModule` | `modules/auth/feature/lib/src/routing/auth_feature_route_module.dart` (feature chỉ có một route có thể để nó trong `_route_module.dart` của mình, như `modules/onboarding/feature/lib/src/routing/onboarding_route_module.dart`) |
| Điểm đến điều hướng (`INavDestinationModule`) | `_nav_destination.dart` | `NavDestination` | `modules/home/feature/lib/src/routing/home_nav_destination.dart` |
| Route path | `<feature>_path.dart` | `Path` | `modules/home/feature/lib/src/utils/home_path.dart` |
| Storage key | `<owner>_storage_keys.dart` | `StorageKeys` | `platform/shell/adapters/lib/src/utils/theme_storage_keys.dart` |
| API endpoint | `<owner>_api_constants.dart` | `ApiConstants` | `modules/auth/data/lib/src/utils/auth_constants.dart` (chứa `AuthApiConstants` và `AuthStorageKeys` — package nhỏ có thể gộp cả hai vào một `<owner>_constants.dart`) |
| Hằng số UI | `<owner>_ui_constants.dart` | `UiConstants` | `platform/ui/ui_kit/lib/src/utils/shared_ui_constants.dart` |
| Database Drift | `_database.dart` (trong `database/`) | `Database` | `modules/cache/data/lib/src/database/cache_database.dart` |
| Bảng Drift | `_table.dart` (trong `database/tables/`) | danh từ số nhiều, không hậu tố | `modules/cache/data/lib/src/database/tables/cache_entries_table.dart` (khai `CacheEntries`) |
| DAO Drift | `_dao.dart` (trong `database/dao/`) | `Dao` | `modules/cache/data/lib/src/database/dao/cache_entries_dao.dart` |

---

## 2. Tiền tố `I`

`I` đánh dấu **interface, và chỉ interface** (RULE-78, do `arch_check` R15 thực thi: class cụ thể tên `I[A-Z]…` sẽ fail).

✅ `IAuthRepository`, `IThemeStorage`, `IFeatureRouteModule`, `IDatabaseMigration`
❌ Không bao giờ đặt tên implementation là `IAuthNavigator` — nó phải là `AuthNavigatorImpl`

> [!NOTE]
> *Interface* Navigator là ngoại lệ có chủ đích duy nhất: chúng tên là `AuthNavigator`, `HomeNavigator` — không có `I`. Chúng nằm trong package API của module sở hữu (`modules/<id>/api/lib/src/navigators/`), và chính hậu tố `Impl` của bản cài đặt là thứ phân biệt hai bên.

---

## 3. Hằng số

`UPPER_SNAKE_CASE`, đặt trong class có private constructor, nằm trong `utils/` của package sở hữu (RULE-09, `arch_check` R4):

```dart
// modules/home/feature/lib/src/utils/home_path.dart
class HomePath {
  HomePath._();
  static const String HOME = '/home';
}
```

Private constructor chính là thứ ngăn `HomePath()` bị khởi tạo.

---

## 4. Thư mục

Trong một package, `lib/src/` chứa code còn `lib/di/` chứa điểm vào DI; package chỉ có những thư mục nó cần.

| Thư mục | Ghi chú |
|---|---|
| `data_sources/` | **số nhiều**, snake_case — không bao giờ là `datasources/` (RULE-40) |
| `data_sources/remote/` | Retrofit / HTTP |
| `data_sources/local/` | storage / database |
| `database/`, `database/tables/`, `database/dao/` | database Drift riêng của package — `modules/cache/data/lib/src/database/` |
| `repositories/` | interface (Domain) |
| `repositories_impl/` | bản cài đặt (Data) |
| `models/` | model Freezed + JSON (Data) |
| `session/` | phần đóng góp session: status stream ở feature, gateway ở package data |
| `provider/` | **số ít** — `modules/auth/feature/lib/src/provider/` |
| `bloc/` | **số ít** — `modules/home/feature/lib/src/bloc/` |
| `utils/` | hằng số do package này sở hữu |
| `routing/` | route module, navigator impl, vị trí sign-in / post-sign-in, nav destination |
| `handlers/` | action handler impl |
| `app/` | thứ feature đóng góp vào cây app: tree wrapper, splash screen |
| `localization/` | phần đóng góp `IFeatureLocalization` |
| `extensions/` | extension của `BuildContext`, ví dụ accessor `l10n<Feature>` |
| `pages/`, `widgets/` | UI |
| `entities/`, `params/`, `usecases/` | Domain |
| `navigators/`, `actions/` | contract của package API (`modules/<id>/api/lib/src/`) |
| `di/` | `lib/di/module.dart`; `module.module.dart` sinh ra nằm cạnh nó |
| `gen/` | `lib/src/gen/` — l10n / asset sinh ra, không bao giờ sửa tay |

> [!WARNING]
> `provider/` và `bloc/` là **số ít**, khớp với mọi feature có sẵn và với đúng thứ `module_generator` sinh ra. Thư mục `providers/` hay `blocs/` số nhiều là vi phạm — hãy đổi tên lại.

---

## 5. Package

| Tầng | Tiền tố | Đường dẫn | Ví dụ |
|---|---|---|---|
| Core | `core_` | `platform/<group>/<dir>/` | `core_storage` tại `platform/infra/storage` |
| Domain | `domain_` | `modules/<name>/domain/` | `domain_auth` |
| Data | `data_` | `modules/<name>/data/` | `data_auth` |
| Feature | `feature_` | `modules/<name>/feature/` | `feature_home` |
| API của module | hậu tố `_api` | `modules/<name>/api/` | `auth_api` |

Thư mục của module mang tên trần; tên package mang tầng. `modules/home/feature/` → `name: feature_home`, `modules/auth/api/` → `name: auth_api`. `arch_check` R3 báo package có tên không khớp thư mục. Trong `platform/` thì tên thư mục và tên package có thể khác nhau tuỳ ý: `platform/ui/design_system` là `core_base_ui`, `platform/foundation/contracts` là `core_di`.

Một số package cố ý phá vỡ quy tắc tiền tố: `platform_kernel`, `platform_app_shell`, `platform_shell_adapters`, `provider_state_management` và `bloc_state_management` (đều nằm trong `platform/`), các app (`mobile_app`, `admin_app`), và package công cụ `core_tools`.

---

## 6. Barrel file

Một package có **một** barrel, mang tên package: `lib/<package_name>.dart` (`modules/home/feature/lib/feature_home.dart`, `platform/ui/design_system/lib/core_base_ui.dart`). Nó là API công khai của package và export mọi file Dart dưới `lib/`, đã sắp xếp. Không có barrel theo từng thư mục; trong một package, các file import file cụ thể (`../pages/home_page.dart`), không bao giờ import barrel. App, root và `tools/` không có barrel.

Sinh bằng `dart tools/barrel_generator/generate.dart <package>/lib` sau khi thêm, đổi tên hoặc xoá một file trong `lib/` (RULE-75). Generator bỏ qua `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, `firebase_options*`, và mọi file khai `part of` — những file đó được với tới qua thư viện cha. Các file sinh khác đang có trên đĩa (`module.module.dart`, `lib/src/gen/**`) *vẫn* được export, nên hãy chạy nó sau `build_runner` / `gen-l10n`.

> [!CAUTION]
> Generator **thay mọi directive `export` trong barrel** và xoá barrel thư mục viết tay mỗi lần chạy. Muốn re-export một symbol từ package khác thì đặt `export` trong một file nguồn bình thường (shim), đừng đặt trong barrel.

---

## 7. File sinh tự động

| Mẫu tên | Do ai sinh |
|---|---|
| `*.g.dart` | `json_serializable`, `retrofit`, `drift`, `go_router_builder` (route có kiểu) |
| `*.freezed.dart` | `freezed` |
| `*.module.dart` | `injectable` (module từng package) |
| `*.config.dart` | `injectable` (lắp ráp ở tầng app) |
| `lib/src/gen/**` | `gen-l10n`, `flutter_gen` |

**Không bao giờ sửa tay** (RULE-76; `arch_check` R6 báo file thiếu header của generator). Hãy đổi annotation ở file nguồn rồi chạy lại:

```bash
dart run build_runner build --workspace   # mọi thứ trừ gen-l10n
flutter gen-l10n                          # trong package có l10n.yaml
```

`dart tools/workspace_setup/configure.dart` chạy cả hai cho mọi package.

---

**Tiếp theo:** [`03_tooling.md`](03_tooling.md) · [`01_rules.md`](01_rules.md)
