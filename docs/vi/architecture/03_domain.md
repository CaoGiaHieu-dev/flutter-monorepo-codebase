<!-- translated-from: docs/en/architecture/03_domain.md@4b2b033 -->
# Tầng Domain

**File này trả lời:** nghiệp vụ nằm ở đâu trong `modules/*/domain`, vì sao code ở đây bị cấm chạm tới Flutter, và `Result<T>` thực sự cho bạn những gì.

**Đọc xong bạn làm được:** đọc hiểu bất kỳ use case nào trong repo, biết được phép import gì bên trong một domain package, và thêm entity / params / use case mới mà không phá vỡ ranh giới tầng.

---

## 1. Tầng Domain để làm gì

Domain là tâm của luật phụ thuộc: nó không phụ thuộc gì ngoài `domain_core`, còn mọi tầng khác phụ thuộc nó thông qua interface.

```
Feature (UI) ──→ Domain ←── Data
```

Một domain package chứa bốn thứ:

| Thành phần | Thư mục | Trách nhiệm |
|:---|:---|:---|
| **Entities** | `entities/` | Đối tượng nghiệp vụ bất biến (Freezed) |
| **Params** | `params/` | Đầu vào có kiểu cho use case |
| **Repository interface** | `repositories/` | Hợp đồng mà tầng Data phải thoả mãn |
| **Use cases** | `usecases/` | Mỗi lớp một thao tác nghiệp vụ, trả về `Result<T>` |

Không widget, không HTTP, không SQL, không `SharedPreferences`. Nếu use case cần những thứ đó, nó khai báo *interface* và để `modules/*/data` hiện thực hoá.

---

## 2. Quy tắc Pure Dart

Registry: RULE-03 — `arch_check` R2 đọc import, `dependencies:`, `dev_dependencies:` và import trong test của domain, nên danh sách dưới đây được kiểm tra chứ không chỉ là quy ước.

### Cấm

```dart
import 'package:flutter/...';    // ❌ Flutter, hay mọi package cần Flutter SDK
import 'package:dio/...';        // ❌ transport
import 'package:retrofit/...';   // ❌ transport
import 'package:drift/...';      // ❌ persistence
import 'package:platform_kernel/...';  // ❌ mọi package core_* / platform_*
```

Cũng bị cấm: `data_*`, `feature_*`, domain của module khác, và các thư viện `dart:` chỉ dành cho engine như `dart:ui`.

### Được phép import

| Package | Vì sao được phép |
|:---|:---|
| `dart:core`, `dart:async` | Nền tảng ngôn ngữ |
| `domain_core` | `Result<T>`, `AppFailure`, `BaseEntity<T>`, `PaginatedEntity<T>`, `BaseUseCase`, `NoParams` |
| `freezed_annotation` | Chỉ là annotation cho codegen |
| `injectable` | Annotation DI |

### Tự kiểm chứng

Quy tắc này đúng ở mức mã nguồn. Bạn tự chạy được:

```bash
grep -rn "import 'package:flutter\|import 'package:dio\|import 'package:retrofit" \
  --include="*.dart" modules/*/domain/
# → không có kết quả
```

> [!NOTE]
> **Đồ thị package và `arch_check` cưỡng chế điều này, không chỉ mình khâu review.** Không domain pubspec nào liệt kê `flutter` dưới `dependencies`, và cũng không cái nào khai một package `core_*`:
>
> ```yaml
> # modules/auth/domain/pubspec.yaml
> dependencies:
>   domain_core:
>     path: ../../../platform/layers/domain
>   injectable: ^3.0.0
>   freezed_annotation: "^3.1.0"
> ```
>
> Bản thân `domain_core` **không** có phụ thuộc workspace nào cả. Vì vậy một dòng `import 'package:flutter/…'` thêm vào file domain sẽ không phân giải được, thay vì lặng lẽ biên dịch trót lọt, còn một dependency `core_*` thì làm Gate 1 đỏ. Test của domain chạy trên `package:test`, không phải `flutter_test`.
>
> Một điểm cần nói cho chính xác, kẻo tuyên bố trên bị hiểu quá: mọi domain pubspec vẫn mang một ràng buộc `flutter:` dưới mục `environment:`. Đó là khẳng định phiên bản SDK tối thiểu, không phải một dependency — nó không kéo dòng code Flutter nào vào đồ thị package, và phép kiểm tra độ thuần bên trên vẫn qua. Nhưng nó có nghĩa là pub cần Flutter SDK hiện diện để resolve các package này, nên ở trạng thái hiện tại chúng chưa dùng được từ một runtime Dart thuần. Nếu có ngày bạn cần chia sẻ một domain package cho server Dart thuần, hãy bỏ dòng `environment: flutter:` đi.

### Vì sao state của UI đi vòng qua Domain

`ThemeMode` và `Locale` là kiểu của `flutter/material.dart`. Một domain package không thể gọi tên chúng, nên việc đẩy theme/locale qua use case là bất khả thi về mặt cấu trúc. Hai luồng đó cố ý bỏ qua Domain và lưu trữ qua interface do `core_di` sở hữu. Xem [giao tiếp giữa các feature](../guides/10_cross_feature.md).

---

## 3. `domain_core` — bộ từ vựng dùng chung

`platform/layers/domain/` được mọi domain package khác phụ thuộc vào.

### `Result<T>` — kiểu trả về của mọi use case

Định nghĩa tại `platform/layers/domain/lib/src/result/result.dart`, với `AppFailure` trong `src/failures/app_failure.dart`:

```dart
@freezed
sealed class Result<T> with _$Result<T> {
  const Result._();

  const factory Result.success([T? data]) = Success<T>;
  const factory Result.failure(AppFailure<dynamic> error) = Failure<T>;
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
> **`None` và `Cancel` là hai nhánh dự phòng chưa dùng.** Grep toàn repo: không repository hay use case nào từng trả về `Result.none()` hoặc `Result.cancel()` — ngoài `result.dart`, chúng chỉ xuất hiện trong `platform/layers/domain/test/result_test.dart`.
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
  required FutureOr<R> Function(AppFailure<dynamic> error) failure,
  required FutureOr<R> Function() none,
  required FutureOr<R> Function() cancel,
}) async { ... }
```

### `BaseEntity<T>` — vỏ response chuẩn

`platform/layers/domain/lib/src/entities/base_entity.dart`:

```dart
@Freezed(genericArgumentFactories: true)
abstract class BaseEntity<T> with _$BaseEntity<T> {
  const BaseEntity._(); // private constructor for getters

  const factory BaseEntity({
    @JsonKey(name: 'statusCode') @Default(200) int statusCode,
    @JsonKey(name: 'data') T? data,
    @JsonKey(name: 'message') String? message,
  }) = _BaseEntity<T>;

  /// Whether the envelope reports success: any 2xx. A create answered `201`
  /// or an action answered `204` is as successful as a `200`; only an
  /// envelope reporting a 1xx, 3xx, 4xx or 5xx is [hasError].
  bool get isSuccess =>
      statusCode >= DomainConstants.SUCCESS_STATUS_CODE &&
      statusCode < DomainConstants.SUCCESS_STATUS_CEILING;
  bool get hasError => !isSuccess;
```

`isSuccess` là mọi mã 2xx (`200` ≤ `statusCode` < `300`), nên một envelope `201` hay `204` là thành công.

### `PaginatedEntity<T>` + `MetaPaginate`

`platform/layers/domain/lib/src/entities/paginated_entity.dart` — danh sách nằm ở `data` (JSON key `items`), thông tin phân trang ở `meta` (`totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`).

### `BaseUseCase<RType, Params>`

```dart
abstract class BaseUseCase<RType, Params> {
  /// Execute the use case with given parameters
  ///
  /// Parameters are expected to be already validated at construction time.
  /// Returns Result<RType> containing either Success with data or Failure with error.
  FutureOr<Result<RType>> call(Params params);
}
```

`FutureOr` là cố ý: use case chỉ đọc state cục bộ có thể trả thẳng một `Result<T>`, còn use case gọi mạng thì trả `Future`. Mọi use case đang có đều trả `Future`.

Dùng `NoParams()` khi thao tác không cần đầu vào.

### Mẫu cache

Package domain mẫu thứ hai, `domain_cache` (`modules/cache/domain`), là lát cắt nhỏ nhất — `CacheEntryEntity` và `ICacheEntryRepository`, không có lớp params và không có use case phía trên: hợp đồng là tất cả những gì `data_cache` phải hiện thực. Đây là nửa Domain của ví dụ Drift mô tả trong [hướng dẫn database](../guides/07_database.md).

---

## 4. `domain_auth`

| File | Nội dung |
|:---|:---|
| `entities/user_entity.dart` | `UserEntity` (Freezed) — `id`, `email`, `name` |
| `params/login_params.dart` | `LoginParams` |
| `repositories/i_auth_repository.dart` | `IAuthRepository` — `login`, `logout`, `refreshToken` |
| `usecases/` | `LoginUseCase` — use case duy nhất |

### Một use case đầy đủ

`modules/auth/domain/lib/src/usecases/login_usecase.dart`:

```dart
/// Authenticates a user with email and password.
@injectable
class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
  LoginUseCase(this._repository);

  final IAuthRepository _repository;

  @override
  Future<Result<UserEntity>> call(LoginParams params) =>
      _repository.login(params);
}
```

Ba điều cần sao chép từ đây:

1. **`@injectable`** — use case là factory, không bao giờ là singleton.
2. **Constructor injection** — repository interface đi vào qua constructor. Tuyệt đối không gọi `getIt<T>()` bên trong use case.
3. **Không validate, không bóc tách** — use case chuyển thẳng params đi tiếp. `LoginParams` cũng không tự validate; nó chỉ mang dữ liệu đầu vào, vốn đã được trang đăng nhập (`LoginPage` trong `feature_auth`) kiểm tra — cả hai trường đều đã điền — trước khi dựng params. Quy tắc nào phải đúng bất kể bên gọi là ai thì thuộc về use case, trả về dưới dạng `Failure` — repository đã trả sẵn `Result<T>`, nên không có gì phải bóc tách.

Use case không có đầu vào nhận `NoParams` và trông y như vậy, chỉ khác kiểu tham số: `BaseUseCase<List<ThingEntity>, NoParams>`, gọi bằng `_getThings(const NoParams())`. Bản mẫu không có use case nào như vậy: `AuthProvider` tự gọi `IAuthRepository.logout()` và `refreshToken()`, nên `LoginUseCase` là use case duy nhất của module và không có lớp bọc nào chỉ để chuyển tiếp một lời gọi.

---

## 5. Bố cục package và quy tắc đặt tên

```
modules/<name>/domain/
├── lib/
│   ├── domain_<name>.dart          # barrel duy nhất của package (được sinh)
│   ├── di/
│   │   ├── module.dart             # @InjectableInit.microPackage()
│   │   └── module.module.dart      # do injectable sinh
│   └── src/
│       ├── entities/
│       ├── params/
│       ├── repositories/
│       ├── usecases/
│       ├── services/               # tuỳ chọn
│       └── utils/                  # hằng số do package sở hữu (nếu có)
└── pubspec.yaml
```

| Thành phần | Hậu tố file | Hậu tố class | Ví dụ |
|:---|:---|:---|:---|
| Entity | `_entity.dart` | `Entity` | `UserEntity` |
| Params | `_params.dart` | `Params` | `LoginParams` |
| Repository interface | `i_<name>_repository.dart` | tiền tố `I` | `IAuthRepository` |
| Use case | `_usecase.dart` | `UseCase` | `LoginUseCase` |

Tiền tố `I` chỉ đánh dấu interface (RULE-78); hằng số nằm trong `utils/` của chính package (RULE-09) — xem [quy tắc](../reference/01_rules.md).

### Entity dùng Freezed kèm constructor riêng tư

```dart
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();

  const factory UserEntity({required String id, String? email, String? name}) =
      _UserEntity;
}
```

Hãy giữ dòng `const Class._()`: thiếu nó, Freezed không sinh được lớp cho phép bạn bổ sung getter riêng (`BaseEntity.isSuccess` phụ thuộc vào điều này).

---

## 6. Thêm mới vào tầng Domain

```bash
# 1. Sinh khung package (thêm vào mọi app manifest, rồi chạy `composer sync`)
dart tools/module_generator/generate.dart 2 payment

# 2. Viết entity → params → repository interface → use case

# 3. Sinh code Freezed + injectable
dart run build_runner build --workspace

# 4. Sinh lại barrel của package — sau codegen, vì barrel cũng export file sinh ra
dart tools/barrel_generator/generate.dart modules/payment/domain/lib
```

Checklist trước khi mở PR:

- [ ] Không có import hay dependency `flutter` / `dio` / `retrofit` / `drift` / `core_*` ở bất kỳ đâu trong package (`dart tools/arch_check/check.dart`)
- [ ] Entity dùng Freezed kèm `const Class._()`
- [ ] Use case là `@injectable` (không bao giờ singleton) và trả `Result<T>`
- [ ] Phụ thuộc đi vào qua constructor — không `getIt<T>()` trong thân hàm
- [ ] Hằng số nằm trong `utils/` của chính package
- [ ] Một app lắp package này (`app_manifest.yaml` → `composer sync`) và pubspec của nó có `resolution: workspace`

---

## Liên quan

- [Tầng Data](04_data.md) — ai hiện thực các repository interface này
- [Tầng Feature](05_features.md) — ai gọi các use case này
- [Hướng dẫn: tạo domain + data package](../guides/02_new_domain_data.md)
- [Quy tắc và quy ước](../reference/01_rules.md)
