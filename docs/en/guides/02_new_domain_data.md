# Guide: Create a Domain + Data Package

This guide answers **"where does my business logic and my API/database code go?"**. We add a
`payment` capability as the worked example: `domain_payment` (pure business rules) and
`data_payment` (the implementation that talks to the outside world).

By the end you will have a use case a feature can call, backed by a repository that converts
every failure into a `Result` — with no `throw` escaping to the UI.

---

## 1. Generate both packages

```bash
dart tools/module_generator/generate.dart 2 payment   # domain_payment
dart tools/module_generator/generate.dart 3 payment   # data_payment
```

> [!NOTE]
> For types `2` and `3` the generator **only scaffolds empty folders** plus `pubspec.yaml` and
> `lib/di/module.dart`. Unlike a feature, there are no starter templates — every class below you
> write by hand. See
> [`tools/module_generator/generate.dart:90-101`](../../../tools/module_generator/generate.dart).

It creates:

```
packages/domain/payment/lib/src/     entities/  usecases/  repositories/
packages/data/payment/lib/src/       models/    data_sources/  repositories_impl/
```

Add `utils/` to each yourself — every package owns its constants there
([`../reference/01_rules.md`](../reference/01_rules.md)).

---

## 2. Build in this order

Each step only depends on the ones above it, so nothing needs rework:

| # | Layer | What | Where |
| :-- | :-- | :-- | :-- |
| 1 | Domain | Entity | `domain/payment/lib/src/entities/` |
| 2 | Domain | Params | `domain/payment/lib/src/params/` |
| 3 | Domain | Repository **interface** | `domain/payment/lib/src/repositories/` |
| 4 | Domain | UseCase | `domain/payment/lib/src/usecases/` |
| 5 | Data | Model | `data/payment/lib/src/models/` |
| 6 | Data | DataSource | `data/payment/lib/src/data_sources/{remote,local}/` |
| 7 | Data | RepositoryImpl | `data/payment/lib/src/repositories_impl/` |

> [!CAUTION]
> The domain layer is **pure Dart**. Importing `package:flutter/...`, `package:dio/...` or
> `package:retrofit/...` anywhere under `packages/domain/` is forbidden — and so is any `core_*`
> package. Allowed: `dart:*`, `domain_core`, `freezed_annotation`, `json_annotation`,
> `injectable`, `get_it`.

---

## 3. Entity

Freezed, immutable, with the `const Class._()` private constructor so you can add methods later.
Real code from
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

Entities carry **business** fields only — no `statusCode`, no `message`, no transport concerns.

## 4. Params

Also Freezed. Real code from
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

Use `NoParams` from `domain_core` when a use case takes no input.

## 5. Repository interface

Named `i_<name>_repository.dart`, class prefixed `I`. Every method returns `Result<T>`:

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

The interface lives in **domain**; the implementation lives in **data**. That inversion is what
keeps domain free of Dio, Firebase and Drift.

## 6. UseCase

`@injectable`, extends `BaseUseCase<ReturnType, Params>`, returns `Result<T>`. Real code from
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

`BaseUseCase` is a single-method contract
([`base_use_case.dart`](../../../packages/domain/core/lib/src/usecases/base_use_case.dart)) —
one use case, one operation. Dependencies come through the constructor; never call `getIt<T>()`
inside a use case.

---

## 7. Model

Freezed + `json_serializable`, `implements BaseModel<Entity>`, with a `toEntity()` mapper. Real
code from
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

`@JsonKey` absorbs the server's naming so the entity never has to. `unknownEnumValue` keeps an
unexpected server enum from throwing.

## 8. DataSource

Directories are `data_sources/remote/` (Retrofit) and `data_sources/local/` (storage / DB) —
**snake_case, plural, never `datasources/`**.

> [!IMPORTANT]
> A DataSource returns a **Model**, never an Entity — mapping to the entity is the repository's
> job. It must also never expose a *generated* type in its signatures: a Drift row class or a
> Retrofit envelope leaking through the interface couples every consumer to that library. The
> cache sample in `data_core` shows the pattern — its interface speaks only in its own
> `CacheEntryModel`, and converts the Drift row at the boundary:
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

DataSources let exceptions bubble up — the repository is the only place that catches.

### Owning storage keys

If your package persists key-value data, it declares its **own** `StorageValue` from the injected
`StorageManager`. `core_storage` provides the mechanism only; it defines no keys.

Keys go in `utils/` — real code from
[`packages/data/auth/lib/src/utils/auth_storage_keys.dart`](../../../packages/data/auth/lib/src/utils/auth_storage_keys.dart):

```dart
/// Physical storage keys owned exclusively by `feature_auth`'s data layer.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

The owner then builds its values and hydrates them at boot
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
> A storage owner must be a **singleton** (`@lazySingleton` / `@singleton`) with
> `@PostConstruct(preResolve: true)`. Register it as `@injectable` and every injection builds a
> fresh instance with an **empty in-memory cache** — synchronous getters then return `null` even
> though the value is on disk. More in [`06_storage.md`](06_storage.md).

## 9. RepositoryImpl

Extends `IBaseRepository` from `data_core` and wraps every call in `execute()` (async) or
`executeSync()` (sync). Real code from
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

`execute<R, T>` takes the raw operation and an optional `mapper` to convert Model → Entity:

```dart
return execute<UserModel, UserEntity>(
  () async => _remote.login(request),
  mapper: (model) => model.toEntity(),
);
```

Both wrappers `catch` everything and funnel it through `ErrorHandler.handleError(e)` into a
`Failure` — see
[`i_base_repository.dart:57-59`](../../../packages/data/core/lib/src/base/i_base_repository.dart).

> [!CAUTION]
> Use `ErrorHandler.handleError(e)`. **Never** `AppFailure.fromException()`. And never let a
> `throw` escape the data layer — the UI must only ever receive a `Result`.

> [!WARNING]
> **`ErrorHandler` has no Firebase branch today.** Reading
> [`error_handler.dart:50-88`](../../../packages/core/common/lib/src/error/error_handler.dart):
> it handles `AppException`, `DioException`, `SocketException`, `HttpException` and
> `FormatException` — but not `FirebaseException`, `FirebaseAuthException` or `PlatformException`.
> Every Firebase error therefore lands on the fallback:
>
> ```dart
> return ServerFailure(
>   message: kDebugMode ? error.toString() : 'Unknown error occurred',
>   code: 9999,
> );
> ```
>
> In a release build a wrong password and a network outage are indistinguishable — both say
> *"Unknown error occurred"*. If your package uses Firebase, add a branch before relying on error
> codes in the UI.

---

## 10. Wire it up

Declare dependencies explicitly in both `pubspec.yaml` files:

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
> Pub Workspaces share one `package_config.json`, so an **undeclared** dependency still compiles.
> It is still wrong: the package breaks the moment it is extracted, and the dependency graph lies.
> Put production dependencies in `dependencies`, not `dev_dependencies`. Verify with:
>
> ```bash
> dart tools/unused_checker/check_unused_packages.dart
> ```

Then regenerate:

```bash
dart tools/barrel_generator/generate.dart packages/domain/payment/lib
dart tools/barrel_generator/generate.dart packages/data/payment/lib
dart run build_runner build -d --workspace
flutter analyze
```

### Checklist

- [ ] Domain imports no Flutter / Dio / Retrofit
- [ ] Entity is Freezed with `const Class._()`
- [ ] Repository interface in domain, implementation in data
- [ ] UseCase is `@injectable`, returns `Result<T>`, dependencies via constructor
- [ ] Model has `.toEntity()` and `implements BaseModel<E>`
- [ ] DataSource returns Models, exposes no generated types, directory is `data_sources/`
- [ ] RepositoryImpl extends `IBaseRepository`, uses `execute()` / `executeSync()`
- [ ] Errors go through `ErrorHandler.handleError` — no `AppFailure.fromException()`, no escaping `throw`
- [ ] Storage owner is a singleton with `@PostConstruct(preResolve: true)`, keys in `utils/`
- [ ] Every dependency declared explicitly and in the right section

---

## Related

- [`01_new_feature.md`](01_new_feature.md) — consume this use case from a feature
- [`06_storage.md`](06_storage.md) — key-value storage in depth
- [`07_database.md`](07_database.md) — relational data with Drift
- [`08_networking.md`](08_networking.md) — Dio, Retrofit, interceptors
- [`../architecture/03_domain.md`](../architecture/03_domain.md) · [`../architecture/04_data.md`](../architecture/04_data.md)
