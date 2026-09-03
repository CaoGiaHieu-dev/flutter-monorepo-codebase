# Tầng Domain

**File này trả lời:** nghiệp vụ nằm ở đâu trong `packages/domain/*`, vì sao code ở đây bị cấm chạm tới Flutter, và `Result<T>` thực sự cho bạn những gì.

**Đọc xong bạn làm được:** đọc hiểu bất kỳ use case nào trong repo, biết được phép import gì bên trong một domain package, và thêm entity / params / use case mới mà không phá vỡ ranh giới tầng.

---

## 1. Tầng Domain để làm gì

Domain là tâm của luật phụ thuộc: nó không phụ thuộc ai, còn mọi tầng khác phụ thuộc nó thông qua interface.

```
Feature (UI) ──→ Domain ←── Data
```

Một domain package chỉ chứa đúng bốn thứ:

| Thành phần | Thư mục | Trách nhiệm |
|:---|:---|:---|
| **Entities** | `entities/` | Đối tượng nghiệp vụ bất biến (Freezed) |
| **Params** | `params/` | Đầu vào có kiểu cho use case |
| **Repository interface** | `repositories/` | Hợp đồng mà tầng Data phải thoả mãn |
| **Use cases** | `usecases/` | Mỗi lớp một thao tác nghiệp vụ, trả về `Result<T>` |

Không widget, không HTTP, không SQL, không `SharedPreferences`. Nếu use case cần những thứ đó, nó khai báo *interface* và để `packages/data/*` hiện thực hoá.

---

## 2. Quy tắc Pure Dart

### Cấm import

```dart
import 'package:flutter/...';    // ❌
import 'package:dio/...';        // ❌
import 'package:retrofit/...';   // ❌
import 'package:drift/...';      // ❌
```

### Được phép import

| Package | Vì sao được phép |
|:---|:---|
| `dart:core`, `dart:async` | Nền tảng ngôn ngữ |
| `domain_core` | `Result<T>`, `AppFailure`, `BaseEntity<T>`, `BaseUseCase`, `NoParams` |
| `freezed_annotation`, `json_annotation` | Chỉ là annotation cho codegen |
| `injectable`, `get_it` | Annotation DI |

### Tự kiểm chứng

Quy tắc này đúng ở mức mã nguồn. Bạn tự chạy được:

```bash
grep -rn "import 'package:flutter\|import 'package:dio\|import 'package:retrofit" \
  --include="*.dart" packages/domain/
# → không có kết quả
```

> [!NOTE]
> **Đồ thị package cưỡng chế điều này, không chỉ mình khâu review.** Không domain pubspec nào liệt kê `flutter` dưới `dependencies`, và cũng không cái nào khai một package `core_*`:
>
> ```yaml
> # packages/domain/auth/pubspec.yaml
> dependencies:
>   domain_core:
>     path: ../core
>   get_it: ^9.2.1
>   injectable: ^3.0.0
>   freezed_annotation: ^3.1.0
>   json_annotation: ^4.12.0
> ```
>
> Bản thân `domain_core` **không** có phụ thuộc workspace nào cả. Vì vậy một dòng `import 'package:flutter/…'` thêm vào file domain sẽ không phân giải được, thay vì lặng lẽ biên dịch trót lọt. Hãy giữ nguyên như thế: đừng bao giờ thêm `flutter` hay một package `core_*` vào pubspec của domain.
>
> Một điểm cần nói cho chính xác, kẻo tuyên bố trên bị hiểu quá: mọi domain pubspec vẫn mang một ràng buộc `flutter:` dưới mục `environment:`. Đó là khẳng định phiên bản SDK tối thiểu, không phải một dependency — nó không kéo dòng code Flutter nào vào đồ thị package, và phép kiểm tra độ thuần bên trên vẫn qua. Nhưng nó có nghĩa là pub cần Flutter SDK hiện diện để resolve các package này, nên ở trạng thái hiện tại chúng chưa dùng được từ một runtime Dart thuần. Nếu có ngày bạn cần chia sẻ một domain package cho server Dart thuần, hãy bỏ dòng `environment: flutter:` đi.

### Vì sao state của UI đi vòng qua Domain

`ThemeMode` và `Locale` là kiểu của `flutter/material.dart`. Một domain package không thể gọi tên chúng, nên việc đẩy theme/locale qua use case là bất khả thi về mặt cấu trúc. Hai luồng đó cố ý bỏ qua Domain và lưu trữ qua interface do `core_di` sở hữu. Xem [giao tiếp giữa các feature](../guides/10_cross_feature.md).

---

## 3. `domain_core` — bộ từ vựng dùng chung

`packages/domain/core/` được mọi domain package khác phụ thuộc vào.

### `Result<T>` — kiểu trả về của mọi use case

Định nghĩa tại `packages/domain/core/lib/src/repositories/result.dart`, với `AppFailure` nằm ngay cạnh trong `src/failures/`:

```dart
@freezed
sealed class Result<T> with _$Result<T> {
  const Result._();

  const factory Result.success([T? data]) = Success<T>;
  const factory Result.failure(AppFailure error) = Failure<T>;
  const factory Result.none() = None<T>;
  const factory Result.cancel() = Cancel<T>;
```

Vì là `sealed`, pattern matching của Dart 3 sẽ vét cạn:

```dart
switch (result) {
  case Success(:final data): print('Data: $data');
  case Failure(:final error): print('Error: ${error.message}');
  case None(): print('No result');
  case Cancel(): print('Cancelled');
}
```

> [!NOTE]
> **`None` và `Cancel` là hai nhánh dự phòng chưa dùng.** Grep toàn repo: không repository hay use case nào từng trả về `Result.none()` hoặc `Result.cancel()` — chúng chỉ xuất hiện trong `packages/core/provider_state_management/test/base_provider_test.dart`.
>
> Nên câu trả lời trung thực cho *"khi nào `Cancel` xảy ra?"* là: **hiện tại không bao giờ.** Chúng tồn tại để union có thể mở rộng sau này mà không gây breaking change. Cái giá phải trả là bạn vẫn phải xử lý chúng trong `switch` / `whenAsync` vét cạn.

#### Bảng API

| Thành viên | Loại | Ghi chú |
|:---|:---|:---|
| `isSuccess` / `isFailure` | getter | Kiểm tra kiểu |
| `dataOrNull` | getter | Dữ liệu khi `Success`, ngược lại `null` |
| `errorOrNull` | getter | `AppFailure` khi `Failure`, ngược lại `null` |
| `when` / `whenOrNull` / `maybeWhen` | Freezed sinh ra | Nhánh đồng bộ |
| `whenAsync` | viết tay | Dùng khi **bất kỳ** nhánh nào có việc bất đồng bộ |
| `mapData<R>` | viết tay | Biến đổi dữ liệu `Success`, giữ nguyên các nhánh khác |
| `flatMap<R>` | viết tay | Nối tiếp một lời gọi trả `Result` khác |
| `getOrElse(default)` | viết tay | Dữ liệu hoặc giá trị thay thế |
| `getOrThrow()` | viết tay | Dữ liệu, hoặc ném `AppFailure` |

`whenAsync` tồn tại vì `when` do Freezed sinh ra là đồng bộ:

```dart
Future<R> whenAsync<R>({
  required FutureOr<R> Function(T? data) success,
  required FutureOr<R> Function(AppFailure error) failure,
  required FutureOr<R> Function() none,
  required FutureOr<R> Function() cancel,
}) async { ... }
```

Có sẵn hai alias cho payload bọc từ server:

```dart
typedef BaseResult<T> = Result<BaseEntity<T>>;
typedef BasePaginateResult<T> = Result<BaseEntity<PaginatedEntity<T>>>;
```

### `BaseEntity<T>` — vỏ response chuẩn

`packages/domain/core/lib/src/entities/base/base_entity.dart`:

```dart
@Freezed(genericArgumentFactories: true)
abstract class BaseEntity<T> with _$BaseEntity<T> {
  const BaseEntity._();

  const factory BaseEntity({
    @JsonKey(name: 'statusCode') @Default(200) int statusCode,
    @JsonKey(name: 'data') T? data,
    @JsonKey(name: 'message') String? message,
  }) = _BaseEntity<T>;

  bool get isSuccess => statusCode == DomainConstants.SUCCESS_STATUS_CODE;
  bool get hasError => !isSuccess;
```

### `PaginatedEntity<T>` + `MetaPaginate`

`packages/domain/core/lib/src/entities/base/paginate_entity.dart` — danh sách nằm ở `data` (JSON key `items`), thông tin phân trang ở `meta` (`totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`).

### `BaseUseCase<RType, Params>`

```dart
abstract class BaseUseCase<RType, Params> {
  FutureOr<Result<RType>> call(Params params);
}
```

`FutureOr` là cố ý: use case đọc storage cục bộ có thể hoàn toàn đồng bộ (xem `GetLanguageUseCase` bên dưới), còn use case gọi mạng thì trả `Future`.

Dùng `NoParams()` khi thao tác không cần đầu vào.

### Mẫu cache

`domain_core` còn có sẵn một lát cắt cache hoạt động được — `CacheEntryEntity`, `CacheEntryParams`, `ICacheEntryRepository`, và `GetCacheEntryUseCase` / `SaveCacheEntryUseCase` / `GetAllCacheEntriesUseCase`. Đây là nửa Domain của ví dụ Drift mô tả trong [hướng dẫn database](../guides/07_database.md).

---

## 4. `domain_auth`

| File | Nội dung |
|:---|:---|
| `entities/user/user_entity.dart` | `UserEntity` (Freezed) |
| `entities/user/user_role.dart` | enum `UserRole` — `customer`, `owner`, `none`, `unknown` |
| `params/auth_params/login_params.dart` | `LoginParams` |
| `params/auth_params/complete_login_flow_params.dart` | `CompleteLoginFlowParams` |
| `repositories/i_auth_repository.dart` | `IAuthRepository` |
| `usecases/auth/` | `LoginUseCase`, `LogoutUseCase`, `RefreshTokenUseCase` |

### Một use case đầy đủ

`packages/domain/auth/lib/src/usecases/auth/login_usecase.dart`:

```dart
@injectable
class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
  LoginUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<UserEntity>> call(LoginParams params) {
    // Params are already validated at construction - no need to validate here
    // Repository returns Result<UserEntity> directly - no unwrapping needed
    return _authRepository.login(params);
  }
}
```

Ba điều cần sao chép từ đây:

1. **`@injectable`** — use case là factory, không bao giờ là singleton.
2. **Constructor injection** — repository interface đi vào qua constructor. Tuyệt đối không gọi `getIt<T>()` bên trong use case.
3. **Không validate lại, không bóc tách** — params đã tự validate lúc khởi tạo; repository đã trả sẵn `Result<T>`.

Use case đồng bộ chỉ khác ở chỗ bỏ `Future`:

```dart
@injectable
class LogoutUseCase extends BaseUseCase<void, NoParams> {
  LogoutUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Result<void> call(NoParams params) {
    return _authRepository.logout();
  }
}
```

### `UserRole` có thành viên `unknown` là có chủ đích

```dart
enum UserRole {
  @JsonValue('customer') customer,
  @JsonValue('owner') owner,
  @JsonValue('none') none,
  unknown,
}
```

`unknown` không mang `@JsonValue`; nó là điểm rơi cho `@JsonKey(unknownEnumValue: UserRole.unknown)` trong `UserModel`, nhờ đó một role mà server thêm sau này vẫn deserialize được thay vì ném lỗi.

---

## 5. `domain_language` — một stub, và vì sao vẫn giữ

`domain_language` hoàn chỉnh nhưng **không được nối vào màn hình nào**:

| File | Nội dung |
|:---|:---|
| `repositories/i_language_repository.dart` | `ILanguageRepository` — `getLanguage()`, `setLanguage()` |
| `params/set_language_params.dart` | `SetLanguageParams` |
| `usecases/get_language_usecase.dart` | `GetLanguageUseCase` |
| `usecases/set_language_usecase.dart` | `SetLanguageUseCase` |

```dart
abstract class ILanguageRepository {
  Result<void> setLanguage(String languageCode);
  Result<String> getLanguage();
}
```

> [!IMPORTANT]
> **Màn hình Settings KHÔNG gọi các use case này.** Việc đổi ngôn ngữ đi qua `LanguageProvider` trong `core_base_ui`, lưu trữ qua `ILanguageStorage` — bỏ qua hoàn toàn tầng Domain.
>
> Đây không phải sơ suất. `Locale` là kiểu của Flutter, nên một domain package thuần Dart không thể biểu đạt "locale hiện tại" mà không phải bịa ra một biểu diễn `String` song song rồi dịch qua lại ở mọi ranh giới. Với một giá trị không bao giờ rời khỏi UI, thủ tục đó không mang lại gì.
>
> `domain_language` được giữ làm khuôn mẫu cho ngày locale trở thành mối quan tâm *nghiệp vụ* — tuỳ chọn người dùng đồng bộ lên server, mặc định theo tenant — khi đó use case đã có sẵn. Từ giờ tới lúc đó, hãy đọc nó như tài liệu tham khảo và **đừng viết màn hình phụ thuộc vào nó**.

Lưu ý nó không có entity: nó trao đổi trực tiếp một `String` mã ngôn ngữ.

---

## 6. Bố cục package và quy tắc đặt tên

```
packages/domain/<name>/
├── lib/
│   ├── domain_<name>.dart          # barrel công khai
│   ├── di/
│   │   ├── module.dart             # @InjectableInit.microPackage()
│   │   └── di.dart
│   └── src/
│       ├── entities/
│       ├── params/
│       ├── repositories/
│       ├── usecases/
│       ├── services/               # tuỳ chọn
│       ├── utils/                  # hằng số do package sở hữu (nếu có)
│       └── src.dart
└── pubspec.yaml
```

| Thành phần | Hậu tố file | Hậu tố class | Ví dụ |
|:---|:---|:---|:---|
| Entity | `_entity.dart` | `Entity` | `UserEntity` |
| Params | `_params.dart` | `Params` | `LoginParams` |
| Repository interface | `i_<name>_repository.dart` | tiền tố `I` | `IAuthRepository` |
| Use case | `_usecase.dart` | `UseCase` | `LoginUseCase` |

Tiền tố `I` chỉ dành cho interface. Tuyệt đối không đặt tên lớp hiện thực là `IFoo`. Hằng số viết `UPPER_SNAKE_CASE` và nằm trong `utils/` của chính package — xem [quy tắc](../reference/01_rules.md).

### Entity dùng Freezed kèm constructor riêng tư

```dart
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();          // ← bắt buộc để thêm getter/method

  const factory UserEntity({
    required String id,
    String? email,
    // …
  }) = _UserEntity;

  factory UserEntity.fromJson(Map<String, dynamic> json) =>
      _$UserEntityFromJson(json);
}
```

Dòng `const Class._()` là bắt buộc. Thiếu nó, Freezed không sinh được lớp cho phép bạn bổ sung getter riêng (`BaseEntity.isSuccess` phụ thuộc vào điều này).

---

## 7. Thêm mới vào tầng Domain

```bash
# 1. Sinh khung package (tạo thư mục + đăng ký workspace member)
dart tools/module_generator/generate.dart 2 payment

# 2. Viết entity → params → repository interface → use case

# 3. Cập nhật barrel
dart tools/barrel_generator/generate.dart packages/domain/payment/lib

# 4. Sinh code Freezed + injectable
dart run build_runner build -d --workspace
```

Checklist trước khi mở PR:

- [ ] Không có import `flutter` / `dio` / `retrofit` / `drift` ở bất kỳ đâu trong package
- [ ] Entity dùng Freezed kèm `const Class._()`
- [ ] Use case là `@injectable` (không bao giờ singleton) và trả `Result<T>`
- [ ] Phụ thuộc đi vào qua constructor — không `getIt<T>()` trong thân hàm
- [ ] Hằng số nằm trong `utils/` của chính package
- [ ] Package đã khai trong danh sách workspace ở `pubspec.yaml` gốc, có `resolution: workspace`

---

## Liên quan

- [Tầng Data](04_data.md) — ai hiện thực các repository interface này
- [Tầng Feature](05_features.md) — ai gọi các use case này
- [Hướng dẫn: tạo domain + data package](../guides/02_new_domain_data.md)
- [Quy tắc và quy ước](../reference/01_rules.md)
