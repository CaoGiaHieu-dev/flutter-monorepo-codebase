# Quy ước đặt tên

**File này trả lời:** file này đặt tên gì, class này đặt tên gì, thư mục này đặt tên gì?

**Đọc xong bạn có thể:** đặt tên mọi thứ trong repo mà không phải đoán, và nhận ra ngay file đặt tên sai khi review.

Mọi ví dụ dưới đây đều là đường dẫn có thật trong repo — mở ra xem là thấy quy ước được áp dụng.

---

## 1. File và class

| Thành phần | Hậu tố file | Hậu tố class | Ví dụ thật |
|---|---|---|---|
| Màn hình | `_page.dart` / `_screen.dart` | `Page` / `Screen` | `packages/features/auth/lib/src/pages/login_page.dart` |
| Widget con | `_widget.dart` / `_card.dart` | `Widget` / `Card` | `packages/features/auth/lib/src/widgets/auth_header_widget.dart` |
| Controller (Provider) | `_provider.dart` | `Provider` | `packages/features/auth/lib/src/provider/auth_provider.dart` |
| Controller (BLoC) | `_bloc.dart` | `Bloc` | `packages/features/home/lib/src/bloc/home_profile_bloc.dart` |
| Controller (Cubit) | `_cubit.dart` | `Cubit` | *chỉ khi không cần event* |
| Event của BLoC | `_event.dart` | `Event` | `packages/features/home/lib/src/bloc/home_profile_event.dart` |
| Use case | `_usecase.dart` | `UseCase` | `packages/domain/auth/lib/src/usecases/auth/login_usecase.dart` |
| Entity | `_entity.dart` | `Entity` | `packages/domain/auth/lib/src/entities/user/user_entity.dart` |
| Interface repository | `i_<name>_repository.dart` | tiền tố `I` | `packages/domain/auth/lib/src/repositories/i_auth_repository.dart` |
| Impl repository | `_repository_impl.dart` | `RepositoryImpl` | `packages/data/auth/lib/src/repositories_impl/auth_repository_impl.dart` |
| Model / DTO | `_model.dart` / `_response.dart` | `Model` / `Response` | `packages/data/core/lib/src/models/cache_entry_model.dart` |
| Request DTO | `_request.dart` | `Request` | `packages/data/core/lib/src/models/base_request.dart` |
| Data source | `_data_source.dart` | `DataSource` | `packages/data/auth/lib/src/data_sources/local/auth_local_data_source.dart` |
| Interface navigator | `<name>_navigator.dart` | `Navigator` | `packages/core/di/lib/src/navigators/auth_navigator.dart` |
| Impl navigator | `_navigator_impl.dart` | `NavigatorImpl` | `packages/features/auth/lib/src/routing/auth_navigator_impl.dart` |
| Interface action handler | `i_<name>_action_handler.dart` | tiền tố `I` | `packages/core/di/lib/src/actions/i_auth_action_handler.dart` |
| Impl action handler | `_action_handler_impl.dart` | `ActionHandlerImpl` | `packages/features/auth/lib/src/handlers/auth_action_handler_impl.dart` |
| Dialog | `_dialog.dart` | `Dialog` | `packages/core/ui_kit/lib/dialogs/error_dialog.dart` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` | — |
| Route module | `_route_module.dart` | `RouteModule` | `packages/features/home/lib/src/routing/home_route_module.dart` |
| Route path | `<feature>_path.dart` | `Path` | `packages/features/home/lib/src/utils/home_path.dart` |
| Storage key | `<owner>_storage_keys.dart` | `StorageKeys` | `packages/data/auth/lib/src/utils/auth_storage_keys.dart` |
| API endpoint | `<owner>_api_constants.dart` | `ApiConstants` | `packages/data/auth/lib/src/utils/auth_api_constants.dart` |

---

## 2. Tiền tố `I`

`I` đánh dấu **interface, và chỉ interface**.

✅ `IAuthRepository`, `IThemeStorage`, `IFeatureRouteModule`, `IDatabaseMigration`
❌ Không bao giờ đặt tên implementation là `IAuthNavigator` — nó phải là `AuthNavigatorImpl`

> [!NOTE]
> *Interface* Navigator là ngoại lệ có chủ đích duy nhất: chúng tên là `AuthNavigator`, `HomeNavigator` — không có `I`. Chúng nằm ở `core_di/lib/src/navigators/`, và chính hậu tố `Impl` của bản cài đặt là thứ phân biệt hai bên.

---

## 3. Hằng số

`UPPER_SNAKE_CASE`, đặt trong class có private constructor, nằm trong `utils/` của package sở hữu:

```dart
// packages/features/home/lib/src/utils/home_path.dart
class HomePath {
  HomePath._();

  static const String HOME = '/home';
}
```

Private constructor chính là thứ ngăn `HomePath()` bị khởi tạo.

---

## 4. Thư mục

| Thư mục | Ghi chú |
|---|---|
| `data_sources/` | **số nhiều**, snake_case — không bao giờ là `datasources/` |
| `data_sources/remote/` | Retrofit / HTTP |
| `data_sources/local/` | storage / database |
| `repositories/` | interface (Domain) |
| `repositories_impl/` | bản cài đặt (Data) |
| `provider/` | **số ít** — `packages/features/auth/lib/src/provider/` |
| `bloc/` | **số ít** — `packages/features/home/lib/src/bloc/` |
| `utils/` | hằng số do package này sở hữu |
| `routing/` | route module, navigator impl |
| `handlers/` | action handler impl |
| `pages/`, `widgets/` | UI |
| `entities/`, `params/`, `usecases/` | Domain |
| `di/` | `module.dart` + `module.module.dart` sinh ra |
| `gen/` | l10n / asset sinh ra — không bao giờ sửa tay |

> [!WARNING]
> `provider/` và `bloc/` là **số ít**. Generator từng sinh ra `providers/` và `blocs/`, không khớp với bất kỳ feature nào đang có. Thấy thư mục số nhiều nghĩa là nó có từ trước khi lỗi này được sửa.

---

## 5. Package

| Tầng | Tiền tố | Đường dẫn | Ví dụ |
|---|---|---|---|
| Core | `core_` | `packages/core/<name>/` | `core_storage` |
| Domain | `domain_` | `packages/domain/<name>/` | `domain_auth` |
| Data | `data_` | `packages/data/<name>/` | `data_auth` |
| Feature | `feature_` | `packages/features/<name>/` | `feature_home` |

Thư mục mang tên trần; tên package mới mang tiền tố. `packages/features/home/` → `name: feature_home`.

Hai package cố ý phá vỡ quy tắc tiền tố: `provider_state_management` và `bloc_state_management` (đều nằm trong `packages/core/`).

---

## 6. Barrel file

Barrel mang tên thư mục chứa nó và re-export mọi thứ public bên trong:

```
lib/src/utils/utils.dart          → export mọi file trong utils/
lib/src/src.dart                  → export barrel của mọi thư mục con
lib/<package_name>.dart           → API công khai của package
```

Sinh bằng `dart tools/barrel_generator/generate.dart <path>/lib`. Generator bỏ qua `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, và mọi file khai `part of` — những file đó được với tới qua thư viện cha.

> [!CAUTION]
> Generator **xoá sạch mọi dòng `export` viết tay** mỗi lần chạy. Muốn re-export một symbol từ package khác thì đặt `export` trong một file nguồn bình thường (shim), đừng đặt trong barrel.

---

## 7. File sinh tự động

| Mẫu tên | Do ai sinh |
|---|---|
| `*.g.dart` | `json_serializable`, `retrofit`, `drift` |
| `*.freezed.dart` | `freezed` |
| `*.module.dart` | `injectable` (module từng package) |
| `*.config.dart` | `injectable` (lắp ráp ở tầng app) |
| `lib/src/gen/**` | `gen-l10n`, `flutter_gen` |

**Không bao giờ sửa tay.** Hãy đổi annotation ở file nguồn rồi chạy lại:

```bash
dart run build_runner build -d --workspace
```

---

**Tiếp theo:** [`03_tooling.md`](03_tooling.md) · [`01_rules.md`](01_rules.md)
