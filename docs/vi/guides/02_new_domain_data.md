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
> Với loại `2` và `3`, generator tạo thư mục, `pubspec.yaml`, `lib/di/module.dart` và **mỗi
> package một stub**: `IPaymentRepository` trong `domain/lib/src/repositories/` và
> `PaymentRepositoryImpl extends IBaseRepository` trong `data/lib/src/repositories_impl/`, cả hai
> có một method giữ chỗ `ping()`. Hãy sinh domain **trước**: package data khi đó phụ thuộc
> `domain_payment` và đăng ký `@LazySingleton(as: IPaymentRepository)`. Thay `ping()` bằng các
> thao tác thật ở §5 (interface repository) và §9 (RepositoryImpl) bên dưới — mọi class khác bạn
> viết tay. Xem nhánh `ModuleType.domain` / `ModuleType.data` trong
> [`tools/module_generator/generate.dart`](../../../tools/module_generator/generate.dart).

Nó tạo ra:

```
modules/payment/domain/lib/src/     entities/  usecases/  repositories/
modules/payment/data/lib/src/       models/    data_sources/  repositories_impl/
```

Mỗi package cũng có sẵn một thư mục `utils/` rỗng — mọi package tự giữ hằng số của mình ở đó
([`../reference/01_rules.md`](../reference/01_rules.md)).

---

## 2. Xây theo đúng thứ tự này

Mỗi bước chỉ phụ thuộc các bước phía trên, nên không phải làm lại:

| # | Tầng | Thành phần | Đặt ở đâu, trong `modules/` |
| :-- | :-- | :-- | :-- |
| 1 | Domain | Entity | `payment/domain/lib/src/entities/` |
| 2 | Domain | Params | `payment/domain/lib/src/params/` |
| 3 | Domain | **Interface** Repository | `payment/domain/lib/src/repositories/` |
| 4 | Domain | UseCase | `payment/domain/lib/src/usecases/` |
| 5 | Data | Model | `payment/data/lib/src/models/` |
| 6 | Data | DataSource | `payment/data/lib/src/data_sources/{remote,local}/` |
| 7 | Data | RepositoryImpl | `payment/data/lib/src/repositories_impl/` |

> [!CAUTION]
> Tầng domain là **Dart thuần**. Cấm import `package:flutter/...`, `package:dio/...` hay
> `package:retrofit/...` ở bất kỳ đâu dưới `modules/*/domain/` — và cấm luôn mọi package `core_*`.
> Được phép: `dart:*`, `domain_core`, `freezed_annotation`, `json_annotation`, `injectable`,
> `get_it`.

---

## 3. Entity

Freezed, bất biến, kèm constructor riêng `const Class._()` để sau này thêm method được. Code thật
từ
[`modules/auth/domain/lib/src/entities/user/user_entity.dart`](../../../modules/auth/domain/lib/src/entities/user/user_entity.dart):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_role.dart';

part 'user_entity.freezed.dart';

/// SAMPLE — the user as the auth module models it.
///
/// Add the fields your product needs; whatever you add here is visible to
/// everything that can see this entity, which is why the cross-module
/// contract carries a narrower `SessionPrincipal` instead of this type.
///
/// No `fromJson`: parsing a payload is the data layer's job (`UserModel`).
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();

  const factory UserEntity({
    required String id,
    String? email,
    String? name,
    UserRole? role,
  }) = _UserEntity;
}
```

Entity chỉ mang trường **nghiệp vụ** — không `statusCode`, không `message`, không dính gì tới
tầng truyền tải.

## 4. Params

Cũng dùng Freezed. Code thật từ
[`login_params.dart`](../../../modules/auth/domain/lib/src/params/auth_params/login_params.dart):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_params.freezed.dart';

@freezed
abstract class LoginParams with _$LoginParams {
  /// Input is validated by the login form before this is built; the params
  /// object itself only carries it.
  const factory LoginParams({required String email, required String password}) =
      _LoginParams;
}
```

Dùng `NoParams` từ `domain_core` khi use case không cần đầu vào.

## 5. Interface Repository

Đặt tên file `i_<name>_repository.dart`, class có tiền tố `I`. Mọi method trả `Result<T>`:

```dart
// modules/payment/domain/lib/src/repositories/i_payment_repository.dart
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
[`modules/auth/domain/lib/src/usecases/auth/login_usecase.dart`](../../../modules/auth/domain/lib/src/usecases/auth/login_usecase.dart):

```dart
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../../entities/user/user.dart';
import '../../params/auth_params/login_params.dart';
import '../../repositories/i_auth_repository.dart';

/// Authenticates a user with email and password.
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
([`base_use_case.dart`](../../../platform/layers/domain/lib/src/usecases/base_use_case.dart)) —
một use case, một thao tác. Phụ thuộc truyền qua constructor; không bao giờ gọi `getIt<T>()` bên
trong use case.

---

## 7. Model

Freezed + `json_serializable`, `implements BaseModel<Entity>`, kèm mapper `toEntity()`. Code thật
từ
[`modules/auth/data/lib/src/models/user/user_model.dart`](../../../modules/auth/data/lib/src/models/user/user_model.dart):

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

    /// Session credential from the login/refresh response.
    ///
    /// Deliberately absent from [UserEntity]: a token is something the
    /// transport hands back, not part of who the user is. It is read once
    /// here, handed to the local data source, and never travels upward.
    @JsonKey(name: 'token') String? token,
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
    );
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      email: entity.email,
      name: entity.name,
      role: entity.role,
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
> `data_cache` cho thấy pattern này — interface chỉ nói bằng `CacheEntryModel` của chính nó, và
> chuyển đổi row Drift ngay tại biên:
>
> ```dart
> abstract class ICacheEntryLocalDataSource {
>   Future<void> save(String key, String value);
>
>   Future<CacheEntryModel?> getEntry(String key);
> }
> ```

DataSource để exception nổi lên — repository là nơi duy nhất bắt lỗi.

### Sở hữu key lưu trữ riêng

Nếu package của bạn lưu dữ liệu key-value, nó tự khai `StorageValue` **của riêng mình** từ
`StorageManager` được inject. `core_storage` chỉ cấp cơ chế; nó không định nghĩa key nào cả.

Key đặt trong `utils/` — code thật từ
[`modules/auth/data/lib/src/utils/auth_storage_keys.dart`](../../../modules/auth/data/lib/src/utils/auth_storage_keys.dart):

```dart
/// Physical storage keys owned exclusively by `feature_auth`'s data layer.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

Bên sở hữu dựng giá trị và nạp sẵn lúc khởi động
([`auth_local_data_source.dart`](../../../modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart)):

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
[`modules/cache/data/lib/src/repositories_impl/cache_entry_repository_impl.dart`](../../../modules/cache/data/lib/src/repositories_impl/cache_entry_repository_impl.dart):

```dart
@LazySingleton(as: ICacheEntryRepository)
class CacheEntryRepositoryImpl extends IBaseRepository
    implements ICacheEntryRepository {
  CacheEntryRepositoryImpl(this._local);

  final ICacheEntryLocalDataSource _local;

  @override
  Future<Result<CacheEntryEntity?>> getByKey(String key) {
    return execute<CacheEntryModel?, CacheEntryEntity?>(
      () => _local.getEntry(key),
      mapper: (model) => model?.toEntity(),
    );
  }

  @override
  Future<Result<void>> save(CacheEntryParams params) {
    return execute<void, void>(() => _local.save(params.key, params.value));
  }
}
```

Chú ý hình dạng: data source trả về **model**, và `mapper` chuyển chúng thành entity ngay tại
biên này. Không tầng nào phía trên nhìn thấy `CacheEntryModel`.


`execute<R, T>` nhận thao tác thô và một `mapper` tuỳ chọn để chuyển Model → Entity:

```dart
// modules/auth/data/lib/src/repositories_impl/auth_repository_impl.dart — _authenticate
return execute<BaseEntity<UserModel>, UserEntity>(
  request, // Future<BaseEntity<UserModel>> Function()
  // Thiếu successCondition, một response 200 mà body báo lỗi vẫn bị tính là thành công.
  successCondition: (response) => response.isSuccess && response.data != null,
  mapper: (response) => response.data!.toEntity(),
);
```

Remote data source trả về envelope `BaseEntity<UserModel>`, nên `R` là envelope và `mapper` gỡ nó ra. `successCondition` biến một response 200 có body báo lỗi (hoặc không có `data`) thành `Failure` trước khi `mapper` chạy — đó là lý do dấu `!` an toàn.


Cả hai wrapper đều `catch` mọi thứ rồi dồn qua `ErrorHandler.handleError(e)` thành `Failure` — xem
khối `catch (e)` ngoài cùng của `execute` và của `executeSync` trong
[`i_base_repository.dart`](../../../platform/layers/data/lib/src/base/i_base_repository.dart).

> [!CAUTION]
> Dùng `ErrorHandler.handleError(e)`. **Không bao giờ** dùng `AppFailure.fromException()`. Và tuyệt
> đối không để `throw` nào thoát khỏi tầng data — UI chỉ được nhận `Result`.

> [!WARNING]
> **`ErrorHandler` hiện chưa có nhánh cho Firebase.** Đọc `ErrorHandler._classify` (nằm sau
> `handleError`) trong [`error_handler.dart`](../../../platform/foundation/kernel/lib/src/error/error_handler.dart):
> nó xử lý `AppException`, mọi thứ mà một `ErrorClassifier` đã đăng ký nhận (`DioFailureClassifier`
> của `core_network` ánh xạ `DioException`), `SocketException`, `HttpException` và `FormatException`
> — nhưng **không** có `FirebaseException`, `FirebaseAuthException` hay `PlatformException`. Mọi
> lỗi Firebase vì thế rơi vào nhánh mặc định:
>
> ```dart
> return ServerFailure(
>   message: _isDebug ? error.toString() : _unknownMessage, // 'Unknown error occurred'
>   code: ErrorCodes.UNKNOWN, // 9999
> );
> ```
>
> Ở bản release, sai mật khẩu và mất mạng là không phân biệt được — cả hai đều hiện
> *"Unknown error occurred"*. Nếu package của bạn dùng Firebase, hãy đăng ký một `ErrorClassifier` cho
> exception của nó (`ErrorHandler.registerClassifier`, từ DI module của package — như cách
> `DioFailureClassifier` làm) trước khi dựa vào mã lỗi ở UI.

---

## 10. Nối dây

Khai báo dependency tường minh ở cả hai `pubspec.yaml`. Generator đã ghi sẵn bộ khởi đầu — với
package data là ba package workspace dưới đây cùng `injectable`, `freezed_annotation` và
`json_annotation`. Thêm phần còn lại **khi code của bạn bắt đầu import chúng**, không sớm hơn:
`check_unused_packages` fail khi một dependency được khai mà không import, còn `arch_check` R5
fail khi một package được import mà không khai.

```yaml
# modules/payment/data/pubspec.yaml
dependencies:
  data_core:
    path: ../../../platform/layers/data
  domain_core:
    path: ../../../platform/layers/domain
  domain_payment:
    path: ../domain

  # Add when you write the §8 storage owner (StorageManager, StorageValue):
  # core_storage:
  #   path: ../../../platform/infra/storage
  # Add when you write a Retrofit data source (ApiClient, Dio) — plus `dio:`
  # and `retrofit:` with an empty value, then run dependency_sync:
  # core_network:
  #   path: ../../../platform/infra/network
```

Danh sách không có `platform_kernel`: `execute()` / `executeSync()` đã đưa mọi lỗi qua
`ErrorHandler`, nên một repository chỉ dùng chúng thì không bao giờ import kernel. Chỉ khai nó khi
chính code của bạn gọi trực tiếp `ErrorHandler`, `getIt` hay một symbol khác của kernel.

Package workspace là dependency `path:` và không có version. Package bên ngoài (`dio`,
`retrofit`) được ghi với giá trị rỗng — version của nó nằm trong `pubspec_dependencies.yaml`, và
`dart tools/dependency_sync.dart` sẽ ghi vào.

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
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/payment/domain/lib
dart tools/barrel_generator/generate.dart modules/payment/data/lib
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

## 11. Dùng nó từ một feature

Feature chạm tới nghiệp vụ này qua **use case**, không bao giờ qua `data_payment` — `arch_check`
R3 cấm feature import package `data_*`. Package data vẫn được đóng gói vào app: mỗi lần chạy
`generate.dart` đã thêm tầng của nó vào mục của module trong mọi `app_manifest.yaml`
(`- { id: payment, layers: [domain, data, feature] }` khi đủ cả ba tầng), và DI đăng ký
`PaymentRepositoryImpl` dưới dạng `IPaymentRepository` từ đó.

**1. Sinh feature** cho cùng module. [`01_new_feature.md`](01_new_feature.md) đi qua một feature
với tên `profile`; mọi thứ ở đó áp dụng y nguyên khi thay bằng `payment`:

```bash
dart tools/module_generator/generate.dart 1 payment "" 1 1   # Provider + stack route; "" 2 1 for BLoC
```

**2. Khai domain** trong `pubspec.yaml` của feature, cạnh những gì generator đã ghi (template
Provider đã khai `domain_core`, cho `Result`), rồi chạy `flutter pub get`:

```yaml
# modules/payment/feature/pubspec.yaml
dependencies:
  domain_payment:
    path: ../domain
```

**3. Inject use case** qua constructor của controller. Injectable phân giải được vì DI module của
`domain_payment` đăng ký mọi use case `@injectable` — controller không gọi `getIt`:

```dart
// modules/payment/feature/lib/src/provider/payment_provider.dart
import 'package:domain_payment/domain_payment.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

@injectable
class PaymentProvider extends BaseProvider<PaymentEntity> {
  PaymentProvider(this._chargeUseCase);

  final ChargeUseCase _chargeUseCase;

  Future<void> charge(ChargeParams params) => executeOperation(
    OperationConfig(operation: () => _chargeUseCase(params)),
  );
}
```

`executeOperation` bóc `Result` và điều khiển các trạng thái loading / error / success. BLoC nhận
use case theo đúng cách đó (`PaymentBloc(this._chargeUseCase) : super(...)`) nhưng phải tự bóc
`Result` trong từng handler — xem [`03_state_management.md`](03_state_management.md) §3.5.

**4. Sinh lại** — constructor của controller đổi thì phần đăng ký DI của nó cũng đổi:

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/payment/feature/lib
flutter analyze
dart tools/arch_check/check.dart
dart tools/unused_checker/check_unused_packages.dart
```

Route vẫn tạo controller đúng như [`01_new_feature.md`](01_new_feature.md) §5 —
`getIt<PaymentProvider>()` ở tầng route, giờ dựng cả chuỗi: provider ← use case ←
`IPaymentRepository` ← data source.

---

## Liên quan

- [`01_new_feature.md`](01_new_feature.md) — toàn bộ phía feature (route, đa ngôn ngữ, navigator)
- [`06_storage.md`](06_storage.md) — lưu trữ key-value chi tiết
- [`07_database.md`](07_database.md) — dữ liệu quan hệ với Drift
- [`08_networking.md`](08_networking.md) — Dio, Retrofit, interceptor
- [`../architecture/03_domain.md`](../architecture/03_domain.md) · [`../architecture/04_data.md`](../architecture/04_data.md)
