# Hướng dẫn: Tạo package Domain + Data

File này trả lời câu hỏi **"logic nghiệp vụ và code gọi API/database của tôi nằm ở đâu?"**. Ví dụ
xuyên suốt: thêm nghiệp vụ `payment` gồm `domain_payment` (quy tắc nghiệp vụ thuần) và
`data_payment` (phần cài đặt nói chuyện với thế giới bên ngoài).

Đọc xong bạn sẽ có một use case mà feature gọi được, đứng sau là repository biến mọi lỗi thành
`Result` — không có `throw` nào lọt lên UI.

---

## 1. Sinh cả hai package

```bash
dart tools/module_generator/generate.dart 2 payment   # domain_payment
dart tools/module_generator/generate.dart 3 payment   # data_payment
```

> [!NOTE]
> Với loại `2` và `3`, generator **chỉ tạo thư mục rỗng** cùng `pubspec.yaml` và
> `lib/di/module.dart`. Khác với feature, ở đây không có template khởi tạo — mọi class dưới đây
> bạn viết tay. Xem
> [`tools/module_generator/generate.dart:90-101`](../../../tools/module_generator/generate.dart).

Nó tạo ra:

```
packages/domain/payment/lib/src/     entities/  usecases/  repositories/
packages/data/payment/lib/src/       models/    data_sources/  repositories_impl/
```

Bạn tự thêm `utils/` cho mỗi package — mọi package tự giữ hằng số của mình ở đó
([`../reference/01_rules.md`](../reference/01_rules.md)).

---

## 2. Xây theo đúng thứ tự này

Mỗi bước chỉ phụ thuộc các bước phía trên, nên không phải làm lại:

| # | Tầng | Thành phần | Đặt ở đâu |
| :-- | :-- | :-- | :-- |
| 1 | Domain | Entity | `domain/payment/lib/src/entities/` |
| 2 | Domain | Params | `domain/payment/lib/src/params/` |
| 3 | Domain | **Interface** Repository | `domain/payment/lib/src/repositories/` |
| 4 | Domain | UseCase | `domain/payment/lib/src/usecases/` |
| 5 | Data | Model | `data/payment/lib/src/models/` |
| 6 | Data | DataSource | `data/payment/lib/src/data_sources/{remote,local}/` |
| 7 | Data | RepositoryImpl | `data/payment/lib/src/repositories_impl/` |

> [!CAUTION]
> Tầng domain là **Dart thuần**. Cấm import `package:flutter/...`, `package:dio/...` hay
> `package:retrofit/...` ở bất kỳ đâu dưới `packages/domain/`. Được phép: `dart:core`,
> `core_common`, `domain_core`, `freezed_annotation`, `json_annotation`, `injectable`.

---

## 3. Entity

Freezed, bất biến, kèm constructor riêng `const Class._()` để sau này thêm method được. Code thật
từ
[`packages/domain/auth/lib/src/entities/user/user_entity.dart`](../../../packages/domain/auth/lib/src/entities/user/user_entity.dart):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_role.dart';

part 'user_entity.freezed.dart';
part 'user_entity.g.dart';

/// Entity representing a user in the domain layer.
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();

  const factory UserEntity({
    required String id,
    String? email,
    String? name,
    UserRole? role,
    String? bankName,
    String? bankAccount,
    String? fcmToken,
  }) = _UserEntity;

  factory UserEntity.fromJson(Map<String, dynamic> json) =>
      _$UserEntityFromJson(json);
}
```

Entity chỉ mang trường **nghiệp vụ** — không `statusCode`, không `message`, không dính gì tới
tầng truyền tải.

## 4. Params

Cũng dùng Freezed. Code thật từ
[`login_params.dart`](../../../packages/domain/auth/lib/src/params/auth_params/login_params.dart):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_params.freezed.dart';
part 'login_params.g.dart';

@freezed
abstract class LoginParams with _$LoginParams {
  const factory LoginParams({required String email, required String password}) =
      _LoginParams;

  factory LoginParams.fromJson(Map<String, dynamic> json) =>
      _$LoginParamsFromJson(json);
}
```

Dùng `NoParams` từ `domain_core` khi use case không cần đầu vào.

## 5. Interface Repository

Đặt tên file `i_<name>_repository.dart`, class có tiền tố `I`. Mọi method trả `Result<T>`:

```dart
// packages/domain/payment/lib/src/repositories/i_payment_repository.dart
import 'package:domain_core/domain_core.dart';

import '../entities/payment/payment_entity.dart';
import '../params/payment_params/charge_params.dart';

abstract class IPaymentRepository {
  Future<Result<PaymentEntity>> charge(ChargeParams params);

  Result<void> clearPendingCharge();
}
```

Interface nằm ở **domain**; implementation nằm ở **data**. Chính phép đảo ngược này giữ cho domain
sạch khỏi Dio, Firebase và Drift.

## 6. UseCase

`@injectable`, kế thừa `BaseUseCase<KiểuTrảVề, Params>`, trả `Result<T>`. Code thật từ
[`packages/domain/auth/lib/src/usecases/auth/login_usecase.dart`](../../../packages/domain/auth/lib/src/usecases/auth/login_usecase.dart):

```dart
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../../entities/user/user.dart';
import '../../params/auth_params/login_params.dart';
import '../../repositories/i_auth_repository.dart';

/// Login use case - authenticates user with credentials
@injectable
class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
  LoginUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<UserEntity>> call(LoginParams params) {
    return _authRepository.login(params);
  }
}
```

`BaseUseCase` là hợp đồng chỉ một method
([`base_use_case.dart`](../../../packages/domain/core/lib/src/usecases/base_use_case.dart)) —
một use case, một thao tác. Phụ thuộc truyền qua constructor; không bao giờ gọi `getIt<T>()` bên
trong use case.

---

## 7. Model

Freezed + `json_serializable`, `implements BaseModel<Entity>`, kèm mapper `toEntity()`. Code thật
từ
[`packages/data/auth/lib/src/models/user/user_model.dart`](../../../packages/data/auth/lib/src/models/user/user_model.dart):

```dart
import 'package:data_core/data_core.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

@freezed
abstract class UserModel with _$UserModel implements BaseModel<UserEntity> {
  const UserModel._();

  const factory UserModel({
    @JsonKey(name: 'id') required String id,
    @JsonKey(name: 'email') String? email,
    @JsonKey(name: 'name') String? name,
    @JsonKey(name: 'role', unknownEnumValue: UserRole.unknown) UserRole? role,
    @JsonKey(name: 'bankName') String? bankName,
    @JsonKey(name: 'bankAccount') String? bankAccount,
    @JsonKey(name: 'fcmToken') String? fcmToken,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  @override
  UserEntity toEntity() {
    return UserEntity(
      id: id,
      email: email,
      name: name,
      role: role,
      bankName: bankName,
      bankAccount: bankAccount,
      fcmToken: fcmToken,
    );
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      email: entity.email,
      name: entity.name,
      role: entity.role,
      bankName: entity.bankName,
      bankAccount: entity.bankAccount,
      fcmToken: entity.fcmToken,
    );
  }
}
```

`@JsonKey` hứng cách đặt tên của server để entity không phải gánh. `unknownEnumValue` giúp enum lạ
từ server không làm ném lỗi.

## 8. DataSource

Thư mục là `data_sources/remote/` (Retrofit) và `data_sources/local/` (storage / DB) —
**snake_case, số nhiều, tuyệt đối không phải `datasources/`**.

> [!IMPORTANT]
> DataSource trả về **Model**, không trả Entity — việc map sang entity là của repository. Nó cũng
> không được để lộ kiểu *sinh tự động* trong chữ ký hàm: một class row của Drift hay một envelope
> của Retrofit lọt qua interface sẽ trói mọi bên tiêu thụ vào thư viện đó. Mẫu cache trong
> `data_core` cho thấy pattern này — interface chỉ nói bằng `CacheEntryModel` của chính nó, và
> chuyển đổi row Drift ngay tại biên:
>
> ```dart
> abstract class ICacheEntryLocalDataSource {
>   Future<void> save(String key, String value);
>   Future<String?> get(String key);
>   Future<CacheEntryModel?> getEntry(String key);
>   Future<void> delete(String key);
>   Future<List<CacheEntryModel>> getAll();
> }
> ```

DataSource để exception nổi lên — repository là nơi duy nhất bắt lỗi.

### Sở hữu key lưu trữ riêng

Nếu package của bạn lưu dữ liệu key-value, nó tự khai `StorageValue` **của riêng mình** từ
`StorageManager` được inject. `core_storage` chỉ cấp cơ chế; nó không định nghĩa key nào cả.

Key đặt trong `utils/` — code thật từ
[`packages/data/auth/lib/src/utils/auth_storage_keys.dart`](../../../packages/data/auth/lib/src/utils/auth_storage_keys.dart):

```dart
/// Physical storage keys owned exclusively by `feature_auth`'s data layer.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

Bên sở hữu dựng giá trị và nạp sẵn lúc khởi động
([`auth_local_data_source.dart`](../../../packages/data/auth/lib/src/data_sources/local/auth_local_data_source.dart)):

```dart
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );

  late final _authUser = StorageValue<Map<String, dynamic>>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.AUTH_USER,
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }
  // …
}
```

> [!CAUTION]
> Lớp sở hữu storage bắt buộc là **singleton** (`@lazySingleton` / `@singleton`) kèm
> `@PostConstruct(preResolve: true)`. Nếu đăng ký `@injectable` thì mỗi lần inject sẽ dựng instance
> mới với **cache trong RAM rỗng** — getter đồng bộ trả `null` dù dữ liệu vẫn nằm trên đĩa. Chi
> tiết ở [`06_storage.md`](06_storage.md).

## 9. RepositoryImpl

Kế thừa `IBaseRepository` từ `data_core` và bọc mọi lời gọi trong `execute()` (bất đồng bộ) hoặc
`executeSync()` (đồng bộ). Code thật từ
[`packages/data/language/lib/src/repositories_impl/language_repository_impl.dart`](../../../packages/data/language/lib/src/repositories_impl/language_repository_impl.dart):

```dart
@LazySingleton(as: ILanguageRepository)
class LanguageRepositoryImpl extends IBaseRepository
    implements ILanguageRepository {
  LanguageRepositoryImpl(this._storageManager);

  final StorageManager _storageManager;

  late final _locale = StorageValue<String>(
    _storageManager.getStorage(StorageType.pref),
    LanguageStorageKeys.LOCALE,
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await _locale.readFromStorage();
  }

  @override
  Result<String> getLanguage() {
    return executeSync<String, String>(() {
      final language = _locale.value;
      if (language != null) return language;
      return AppConfig.defaultLanguage.languageCode;
    });
  }

  @override
  Result<void> setLanguage(String languageCode) {
    return executeSync<void, void>(() {
      _locale.value = languageCode;
    });
  }
}
```

`execute<R, T>` nhận thao tác thô và một `mapper` tuỳ chọn để chuyển Model → Entity:

```dart
return execute<UserModel, UserEntity>(
  () async => _remote.login(request),
  mapper: (model) => model.toEntity(),
);
```

Cả hai wrapper đều `catch` mọi thứ rồi dồn qua `ErrorHandler.handleError(e)` thành `Failure` — xem
[`i_base_repository.dart:57-59`](../../../packages/data/core/lib/src/base/i_base_repository.dart).

> [!CAUTION]
> Dùng `ErrorHandler.handleError(e)`. **Không bao giờ** dùng `AppFailure.fromException()`. Và tuyệt
> đối không để `throw` nào thoát khỏi tầng data — UI chỉ được nhận `Result`.

> [!WARNING]
> **`ErrorHandler` hiện chưa có nhánh cho Firebase.** Đọc
> [`error_handler.dart:50-88`](../../../packages/core/common/lib/src/error/error_handler.dart):
> nó xử lý `AppException`, `DioException`, `SocketException`, `HttpException` và `FormatException`
> — nhưng **không** có `FirebaseException`, `FirebaseAuthException` hay `PlatformException`. Mọi
> lỗi Firebase vì thế rơi vào nhánh mặc định:
>
> ```dart
> return ServerFailure(
>   message: kDebugMode ? error.toString() : 'Unknown error occurred',
>   code: 9999,
> );
> ```
>
> Ở bản release, sai mật khẩu và mất mạng là không phân biệt được — cả hai đều hiện
> *"Unknown error occurred"*. Nếu package của bạn dùng Firebase, hãy bổ sung nhánh xử lý trước khi
> dựa vào mã lỗi ở UI.

---

## 10. Nối dây

Khai báo dependency tường minh ở cả hai `pubspec.yaml`:

```yaml
# packages/data/payment/pubspec.yaml
dependencies:
  core_common:
    path: ../../core/common
  data_core:
    path: ../core
  domain_core:
    path: ../../domain/core
  domain_payment:
    path: ../../domain/payment
```

> [!WARNING]
> Pub Workspaces dùng chung một `package_config.json`, nên dependency **không khai** vẫn compile
> được. Nhưng vẫn là sai: package sẽ vỡ ngay khi tách ra, và đồ thị phụ thuộc nói dối. Đặt
> dependency production vào `dependencies`, không phải `dev_dependencies`. Kiểm tra bằng:
>
> ```bash
> dart tools/unused_checker/check_unused_packages.dart
> ```

Rồi sinh lại:

```bash
dart tools/barrel_generator/generate.dart packages/domain/payment/lib
dart tools/barrel_generator/generate.dart packages/data/payment/lib
dart run build_runner build -d --workspace
flutter analyze
```

### Checklist

- [ ] Domain không import Flutter / Dio / Retrofit
- [ ] Entity dùng Freezed kèm `const Class._()`
- [ ] Interface repository ở domain, implementation ở data
- [ ] UseCase là `@injectable`, trả `Result<T>`, phụ thuộc qua constructor
- [ ] Model có `.toEntity()` và `implements BaseModel<E>`
- [ ] DataSource trả Model, không lộ kiểu sinh tự động, thư mục là `data_sources/`
- [ ] RepositoryImpl kế thừa `IBaseRepository`, dùng `execute()` / `executeSync()`
- [ ] Lỗi đi qua `ErrorHandler.handleError` — không `AppFailure.fromException()`, không `throw` lọt ra
- [ ] Lớp sở hữu storage là singleton kèm `@PostConstruct(preResolve: true)`, key ở `utils/`
- [ ] Mọi dependency khai tường minh và đúng mục

---

## Liên quan

- [`01_new_feature.md`](01_new_feature.md) — gọi use case này từ một feature
- [`06_storage.md`](06_storage.md) — lưu trữ key-value chi tiết
- [`07_database.md`](07_database.md) — dữ liệu quan hệ với Drift
- [`08_networking.md`](08_networking.md) — Dio, Retrofit, interceptor
- [`../architecture/03_domain.md`](../architecture/03_domain.md) · [`../architecture/04_data.md`](../architecture/04_data.md)
