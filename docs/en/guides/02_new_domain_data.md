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
> For types `2` and `3` the generator scaffolds the folders, `pubspec.yaml`, `lib/di/module.dart`
> and **one stub each**: `IPaymentRepository` in `domain/lib/src/repositories/` and
> `PaymentRepositoryImpl extends IBaseRepository` in `data/lib/src/repositories_impl/`, both with a
> placeholder `ping()`. Generate the domain **first**: the data package then depends on
> `domain_payment` and registers `@LazySingleton(as: IPaymentRepository)`. Replace `ping()` with
> the real operations of §5 (repository interface) and §9 (RepositoryImpl) below — every other
> class you write by hand. See
> the `ModuleType.domain` / `ModuleType.data` branches in
> [`tools/module_generator/generate.dart`](../../../tools/module_generator/generate.dart).

It creates:

```
modules/payment/domain/lib/src/     entities/  usecases/  repositories/
modules/payment/data/lib/src/       models/    data_sources/  repositories_impl/
```

Each also gets an empty `utils/` — every package owns its constants there
([`../reference/01_rules.md`](../reference/01_rules.md)).

---

## 2. Build in this order

Each step only depends on the ones above it, so nothing needs rework:

| # | Layer | What | Where, under `modules/` |
| :-- | :-- | :-- | :-- |
| 1 | Domain | Entity | `payment/domain/lib/src/entities/` |
| 2 | Domain | Params | `payment/domain/lib/src/params/` |
| 3 | Domain | Repository **interface** | `payment/domain/lib/src/repositories/` |
| 4 | Domain | UseCase | `payment/domain/lib/src/usecases/` |
| 5 | Data | Model | `payment/data/lib/src/models/` |
| 6 | Data | DataSource | `payment/data/lib/src/data_sources/{remote,local}/` |
| 7 | Data | RepositoryImpl | `payment/data/lib/src/repositories_impl/` |

> [!CAUTION]
> The domain layer is **pure Dart**. Importing `package:flutter/...`, `package:dio/...` or
> `package:retrofit/...` anywhere under `modules/*/domain/` is forbidden — and so is any `core_*`
> package. Allowed: `dart:*`, `domain_core`, `freezed_annotation`, `json_annotation`,
> `injectable`, `get_it`.

---

## 3. Entity

Freezed, immutable, with the `const Class._()` private constructor so you can add methods later.
Real code from
[`modules/auth/domain/lib/src/entities/user/user_entity.dart`](../../../modules/auth/domain/lib/src/entities/user/user_entity.dart):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_role.dart';

part 'user_entity.freezed.dart';

/// SAMPLE — the user as the auth module models it.
///
/// Add the fields your product needs; whatever you add here is visible to
/// everything that can see this entity, which is why the cross-module
/// contract carries a narrower `AuthPrincipal` instead of this type.
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

Entities carry **business** fields only — no `statusCode`, no `message`, no transport concerns.

## 4. Params

Also Freezed. Real code from
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

Use `NoParams` from `domain_core` when a use case takes no input.

## 5. Repository interface

Named `i_<name>_repository.dart`, class prefixed `I`. Every method returns `Result<T>`:

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

The interface lives in **domain**; the implementation lives in **data**. That inversion is what
keeps domain free of Dio, Firebase and Drift.

## 6. UseCase

`@injectable`, extends `BaseUseCase<ReturnType, Params>`, returns `Result<T>`. Real code from
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

`BaseUseCase` is a single-method contract
([`base_use_case.dart`](../../../platform/domain_core/lib/src/usecases/base_use_case.dart)) —
one use case, one operation. Dependencies come through the constructor; never call `getIt<T>()`
inside a use case.

---

## 7. Model

Freezed + `json_serializable`, `implements BaseModel<Entity>`, with a `toEntity()` mapper. Real
code from
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

`@JsonKey` absorbs the server's naming so the entity never has to. `unknownEnumValue` keeps an
unexpected server enum from throwing.

## 8. DataSource

Directories are `data_sources/remote/` (Retrofit) and `data_sources/local/` (storage / DB) —
**snake_case, plural, never `datasources/`**.

> [!IMPORTANT]
> A DataSource returns a **Model**, never an Entity — mapping to the entity is the repository's
> job. It must also never expose a *generated* type in its signatures: a Drift row class or a
> Retrofit envelope leaking through the interface couples every consumer to that library. The
> `cache` sample module (`data_cache`) shows the pattern — its interface speaks only in its own
> `CacheEntryModel`, and converts the Drift row at the boundary:
>
> ```dart
> abstract class ICacheEntryLocalDataSource {
>   Future<void> save(String key, String value);
>
>   Future<CacheEntryModel?> getEntry(String key);
> }
> ```

DataSources let exceptions bubble up — the repository is the only place that catches.

### Owning storage keys

If your package persists key-value data, it declares its **own** `StorageValue` from the injected
`StorageManager`. `core_storage` provides the mechanism only; it defines no keys.

Keys go in `utils/` — real code from
[`modules/auth/data/lib/src/utils/auth_storage_keys.dart`](../../../modules/auth/data/lib/src/utils/auth_storage_keys.dart):

```dart
/// Physical storage keys owned exclusively by `feature_auth`'s data layer.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

The owner then builds its values and hydrates them at boot
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
> A storage owner must be a **singleton** (`@lazySingleton` / `@singleton`) with
> `@PostConstruct(preResolve: true)`. Register it as `@injectable` and every injection builds a
> fresh instance with an **empty in-memory cache** — synchronous getters then return `null` even
> though the value is on disk. More in [`06_storage.md`](06_storage.md).

## 9. RepositoryImpl

Extends `IBaseRepository` from `data_core` and wraps every call in `execute()` (async) or
`executeSync()` (sync). Real code from
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

Note the shape: the data source returns **models**, and `mapper` converts them to entities at
this boundary. Nothing above this layer ever sees a `CacheEntryModel`.


`execute<R, T>` takes the raw operation and an optional `mapper` to convert Model → Entity:

```dart
// modules/auth/data/lib/src/repositories_impl/auth_repository_impl.dart — _authenticate
return execute<BaseEntity<UserModel>, UserEntity>(
  request, // Future<BaseEntity<UserModel>> Function()
  // Without successCondition, a 200 whose body reports failure would count as success.
  successCondition: (response) => response.isSuccess && response.data != null,
  mapper: (response) => response.data!.toEntity(),
);
```

The remote data source returns the `BaseEntity<UserModel>` envelope, so `R` is the envelope and `mapper` unwraps it. `successCondition` turns a 200 with an error body (or no `data`) into a `Failure` before `mapper` runs — which is what makes the `!` safe.


Both wrappers `catch` everything and funnel it through `ErrorHandler.handleError(e)` into a
`Failure` — see the outer `catch (e)` of `execute` and of `executeSync` in
[`i_base_repository.dart`](../../../platform/data_core/lib/src/base/i_base_repository.dart).

> [!CAUTION]
> Use `ErrorHandler.handleError(e)`. **Never** `AppFailure.fromException()`. And never let a
> `throw` escape the data layer — the UI must only ever receive a `Result`.

> [!WARNING]
> **`ErrorHandler` has no Firebase branch today.** Reading `ErrorHandler._classify` (behind
> `handleError`) in [`error_handler.dart`](../../../platform/kernel/lib/src/error/error_handler.dart):
> it handles `AppException`, `DioException`, `SocketException`, `HttpException` and
> `FormatException` — but not `FirebaseException`, `FirebaseAuthException` or `PlatformException`.
> Every Firebase error therefore lands on the fallback:
>
> ```dart
> return ServerFailure(
>   message: _isDebug ? error.toString() : _unknownMessage, // 'Unknown error occurred'
>   code: ErrorCodes.UNKNOWN, // 9999
> );
> ```
>
> In a release build a wrong password and a network outage are indistinguishable — both say
> *"Unknown error occurred"*. If your package uses Firebase, add a branch before relying on error
> codes in the UI.

---

## 10. Wire it up

Declare dependencies explicitly in both `pubspec.yaml` files. The generator already wrote the
starting set — for the data package, the three workspace packages below plus `injectable`,
`freezed_annotation` and `json_annotation`. Add the rest **as your code starts importing them**,
not before: `check_unused_packages` fails on a dependency declared but never imported, and
`arch_check` R5 fails on one imported but not declared.

```yaml
# modules/payment/data/pubspec.yaml
dependencies:
  data_core:
    path: ../../../platform/data_core
  domain_core:
    path: ../../../platform/domain_core
  domain_payment:
    path: ../domain

  # Add when you write the §8 storage owner (StorageManager, StorageValue):
  # core_storage:
  #   path: ../../../platform/storage
  # Add when you write a Retrofit data source (ApiClient, Dio) — plus `dio:`
  # and `retrofit:` with an empty value, then run dependency_sync:
  # core_network:
  #   path: ../../../platform/network
```

`platform_kernel` is not on the list: `execute()` / `executeSync()` already route every error
through `ErrorHandler`, so a repository that only uses them never imports the kernel. Declare it
only if your own code calls `ErrorHandler`, `getIt` or another kernel symbol directly.

A workspace package is a `path:` dependency and has no version. An external one (`dio`,
`retrofit`) is written with an empty value — its version lives in `pubspec_dependencies.yaml`, and
`dart tools/dependency_sync.dart` writes it in.

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
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/payment/domain/lib
dart tools/barrel_generator/generate.dart modules/payment/data/lib
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

## 11. Consume it from a feature

A feature reaches this capability through the **use case**, never through `data_payment` —
`arch_check` R3 forbids a feature importing a `data_*` package. The data package still ships:
each `generate.dart` run added its layer to the module's entry in every `app_manifest.yaml`
(`- { id: payment, layers: [domain, data, feature] }` once all three exist), and DI registers
`PaymentRepositoryImpl` as `IPaymentRepository` from there.

**1. Generate the feature** for the same module. [`01_new_feature.md`](01_new_feature.md) walks
through a feature with `profile`; everything there applies with `payment` substituted:

```bash
dart tools/module_generator/generate.dart 1 payment "" 1 1   # Provider + stack route; "" 2 1 for BLoC
```

**2. Declare the domain** in the feature's `pubspec.yaml`, next to what the generator wrote (the
Provider template already declares `domain_core`, for `Result`), then run `flutter pub get`:

```yaml
# modules/payment/feature/pubspec.yaml
dependencies:
  domain_payment:
    path: ../domain
```

**3. Inject the use case** through the controller's constructor. Injectable resolves it because
`domain_payment`'s DI module registers every `@injectable` use case — no `getIt` call in the
controller:

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

`executeOperation` unwraps the `Result` and drives the loading / error / success states. A BLoC
takes the use case the same way (`PaymentBloc(this._chargeUseCase) : super(...)`) but unwraps the
`Result` by hand in each handler — see
[`03_state_management.md`](03_state_management.md) §3.5.

**4. Regenerate** — the controller's constructor changed, so its DI registration did too:

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/payment/feature/lib
flutter analyze
dart tools/arch_check/check.dart
dart tools/unused_checker/check_unused_packages.dart
```

The route keeps creating the controller exactly as in
[`01_new_feature.md`](01_new_feature.md) §5 — `getIt<PaymentProvider>()` at route level, which
now builds the whole chain: provider ← use case ← `IPaymentRepository` ← data sources.

---

## Related

- [`01_new_feature.md`](01_new_feature.md) — the feature side in full (routes, localisation, navigator)
- [`06_storage.md`](06_storage.md) — key-value storage in depth
- [`07_database.md`](07_database.md) — relational data with Drift
- [`08_networking.md`](08_networking.md) — Dio, Retrofit, interceptors
- [`../architecture/03_domain.md`](../architecture/03_domain.md) · [`../architecture/04_data.md`](../architecture/04_data.md)
