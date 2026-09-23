# Data Layer

**What this answers:** how `modules/*/data` fulfils the repository contracts declared by Domain — where models, data sources and error handling live, and which boundaries this layer must not leak across.

**After reading you can:** implement a repository that returns `Result<T>` without writing a single `try/catch`, decide whether a value belongs in a Model or an Entity, and know exactly which types are allowed to appear in a data source's signature.

---

## 1. Position and responsibility

```
Feature (UI) ──→ Domain ←── Data
                              ↓
              core_network / core_storage / core_database
```

Data depends **inward** on Domain (to implement its interfaces) and **outward** on `core_*` infrastructure. Nothing depends on Data except the app shell, which assembles it. A feature package may never import `data_*`.

| Job | Where |
|:---|:---|
| Talk to the network / DB / storage | `data_sources/` |
| Convert wire & row formats into typed objects | `models/` |
| Satisfy `I*Repository` from Domain | `repositories_impl/` |
| Package-owned constants and keys | `utils/` |

---

## 2. Package layout

```
modules/<name>/data/
├── lib/
│   ├── data_<name>.dart             # public barrel
│   ├── di/
│   │   ├── module.dart              # @InjectableInit.microPackage()
│   │   └── register_module.dart     # optional @module third-party bindings
│   └── src/
│       ├── data_sources/
│       │   ├── remote/              # Retrofit / HTTP
│       │   └── local/               # storage / database
│       ├── models/                  # DTOs with .toEntity()
│       ├── repositories_impl/
│       ├── utils/                   # keys, endpoints — owned by this package
│       └── src.dart
└── pubspec.yaml
```

> [!CAUTION]
> The directory is **`data_sources/`** (snake_case, plural, underscored) — not `datasources/`. The generators and review checklist assume this spelling.

Current packages:

| Package | Contents |
|:---|:---|
| `data_core` | `IBaseRepository`, `BaseModel`, request models |
| `data_auth` | `UserModel`, auth data sources, `AuthRepositoryImpl` |
| `data_cache` | `CacheDatabase` (a package-owned Drift database), `CacheEntryModel`, local data source, `CacheEntryRepositoryImpl` |

---

## 3. `IBaseRepository` — why repositories have no `try/catch`

`platform/data_core/lib/src/base/i_base_repository.dart` gives every repository two wrappers. A `RepositoryImpl` `extends IBaseRepository` and calls them instead of handling errors itself.

### `execute<R, T>()` — asynchronous

```dart
Future<Result<T>> execute<R, T>(
  Future<R> Function() request, {
  T Function(R data)? mapper,
  FutureOr<void> Function(R response)? onSuccess,
  FutureOr<void> Function(R response)? onFailure,
  bool Function(R response)? successCondition,
}) async {
  try {
    final response = await request.call();
    final isSuccess = successCondition?.call(response) ?? true;
    if (isSuccess) {
      await onSuccess?.call(response);
      // …map R → T…
      return Success(mappedData);
    }
    await onFailure?.call(response);
    return Failure(
      ErrorHandler.serverFailure('Request failed based on success condition', null),
    );
  } catch (e) {
    return Failure(ErrorHandler.handleError(e));
  }
}
```

Two type parameters, and they are not the same thing:

- **`R`** — what the data source hands back (a Model, a list of Models, `void`)
- **`T`** — what Domain expects (an Entity, a list of Entities, `void`)
- **`mapper`** — the `R → T` bridge, normally `(model) => model.toEntity()`

If the call returns `null`, `T` is nullable and no `mapper` is supplied, `Success(null as T)` is returned — that is how `Future<Result<void>>` operations work without ceremony. A non-null response is passed through as `T` even when `T` is nullable.

### `executeSync<R, T>()` — synchronous

Same shape for local, non-async work. `onFailure` here receives the thrown `Object`, not the response.

### Error conversion

Both wrappers funnel every throw into `ErrorHandler.handleError(e)` from `platform_kernel` (also reachable through `core_common`'s re-export), which returns an `AppFailure`.

> [!NOTE]
> `ErrorHandler` is the only conversion point. There is no `AppFailure.fromException()` — do not invent one, and do not hand-roll a failure at the call site. When you must construct one explicitly, use the helpers `ErrorHandler.serverFailure(...)`, `.networkFailure(...)`, `.authFailure(...)` and so on.

### What `ErrorHandler` actually recognises

`platform/kernel/lib/src/error/error_handler.dart` branches on, in order: `AppException` → `DioException` → `SocketException` → `HttpException` → `FormatException` → fallback.

> [!WARNING]
> **There is no `FirebaseException` / `FirebaseAuthException` / `PlatformException` branch.** The shipped `AuthRepositoryImpl` goes through Retrofit, so this does not bite the sample — but swap its transport for the Firebase SDK and every Firebase error — wrong password, user-not-found, network-request-failed — falls through to the generic tail:
>
> ```dart
> return ServerFailure(
>   message: _isDebug ? error.toString() : 'Unknown error occurred',
>   code: 9999,
> );
> ```
>
> In a release build the user sees **"Unknown error occurred"** for every failed sign-in. Worse, any UI that maps failures by code — such as `AuthProvider._mapAuthFailure`, which switches on `401` / `404` — can never match, because the code is always `9999`.
>
> If you add a Firebase-backed repository, add the matching branch to `ErrorHandler` first.

---

## 4. Models

A Model is the Data layer's own representation. It never escapes into Domain — it is converted first.

### Contract

```dart
// platform/data_core/lib/src/models/base_model.dart
abstract class BaseModel<E> {
  E toEntity() {
    throw UnimplementedError();
  }
}
```

### A network Model

`modules/auth/data/lib/src/models/user/user_model.dart` — Freezed + `json_serializable`:

```dart
@freezed
abstract class UserModel with _$UserModel implements BaseModel<UserEntity> {
  const UserModel._();

  const factory UserModel({
    @JsonKey(name: 'id') required String id,
    @JsonKey(name: 'email') String? email,
    @JsonKey(name: 'name') String? name,
    @JsonKey(name: 'role', unknownEnumValue: UserRole.unknown) UserRole? role,
    // …
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  @override
  UserEntity toEntity() {
    return UserEntity(id: id, email: email, name: name, role: role, /* … */);
  }

  factory UserModel.fromEntity(UserEntity entity) { /* … */ }
}
```

`unknownEnumValue: UserRole.unknown` means a role the backend adds later deserialises to `unknown` instead of throwing.

`fromEntity` is the reverse trip, for writing an entity back to the API or a cache. Nothing in the sample writes back, so today only `modules/auth/data/test/user_model_test.dart` exercises it.

### A database Model

`modules/cache/data/lib/src/models/cache_entry_model.dart` — Freezed, **no** `json_serializable`:

```dart
@freezed
abstract class CacheEntryModel
    with _$CacheEntryModel
    implements BaseModel<CacheEntryEntity> {
  const CacheEntryModel._();

  const factory CacheEntryModel({
    required String key,
    required String value,
    required DateTime updatedAt,
  }) = _CacheEntryModel;

  /// Maps a Drift row into the data-layer model.
  factory CacheEntryModel.fromRow(CacheEntry row) {
    return CacheEntryModel(key: row.key, value: row.value, updatedAt: row.updatedAt);
  }

  @override
  CacheEntryEntity toEntity() {
    return CacheEntryEntity(key: key, value: value, updatedAt: updatedAt);
  }
}
```

Rows come from SQLite, not from an API, so there is no JSON contract to honour — adding `json_serializable` would be noise. Match the codegen to the source of the data, not to habit.

---

## 5. Data sources

### Rule 1 — return Models, never Entities

A data source's job stops at "typed object". Mapping to Domain is the repository's job.

### Rule 2 — never leak the transport type

This is the rule that `CacheEntryModel` exists to satisfy. `modules/cache/data/lib/src/data_sources/local/cache_entry_local_data_source.dart`:

```dart
/// Contract for reading/writing cache rows.
///
/// Signatures speak in [CacheEntryModel], never in Drift's generated row
/// class — that keeps Drift an implementation detail of `data_cache` instead
/// of leaking it to every consumer of this package.
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);

  Future<CacheEntryModel?> getEntry(String key);
}
```

The implementation converts at the boundary and takes a **narrow database handle**, not the whole database:

```dart
@LazySingleton(as: ICacheEntryLocalDataSource)
class CacheEntryLocalDataSource implements ICacheEntryLocalDataSource {
  CacheEntryLocalDataSource(IDatabaseHandle<CacheDatabase> handle)
    : _dao = handle.accessor(CacheEntriesDao.new);

  final CacheEntriesDao _dao;

  @override
  Future<void> save(String key, String value) => _dao.upsert(key, value);

  @override
  Future<CacheEntryModel?> getEntry(String key) async {
    final row = await _dao.getEntry(key);
    return row == null ? null : CacheEntryModel.fromRow(row);
  }
}
```

Injecting `AppDatabase` would hand this class every DAO in the app; `IDatabaseHandle.accessor(...)` hands it exactly one. See [the database guide](../guides/07_database.md).

### Rule 3 — let exceptions bubble

Data sources do **not** catch. `execute()` in the repository is the single catch point; swallowing an error lower down means the repository reports success on a failed call.

### Rule 4 — storage keys belong to the package that owns them

`core_storage` provides only the mechanism. Each consumer declares its own `StorageValue`s and keeps its keys in its own `utils/`.

`modules/auth/data/lib/src/utils/auth_storage_keys.dart`:

```dart
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

`modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart`:

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

  /// Hydrates the in-memory cache from disk at startup so synchronous
  /// getters below return correct values immediately.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }
  // …
}
```

> [!CAUTION]
> **`@lazySingleton` here is load-bearing — `@injectable` would silently break it.**
>
> `StorageValue` keeps an in-memory cache that `initialize()` fills from disk once at boot. A factory registration builds a **new, empty** instance on every injection, so `getUserToken()` would return `null` even though the token is on disk. The pairing is: singleton registration **+** `@PostConstruct(preResolve: true)`.

REST endpoints follow the same ownership rule — `modules/auth/data/lib/src/utils/auth_api_constants.dart` holds `AuthApiConstants`, because those endpoints belong to auth and to nothing else.

---

## 6. `data_auth` — read this before copying it

`AuthRepositoryImpl` is the most-copied file in the template, so it is written exactly the way this document describes the layer: a Retrofit data source for the network, a `StorageValue` data source for the session, `execute()` around both, and a model-to-entity mapping at the boundary.

```dart
@LazySingleton(as: IAuthRepository)
class AuthRepositoryImpl extends IBaseRepository implements IAuthRepository {
  AuthRepositoryImpl(this._remote, this._local);

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;
```

The Retrofit client is built once in [`modules/auth/data/lib/di/register_module.dart`](../../../modules/auth/data/lib/di/register_module.dart) from the shared `Dio`, so the data source inherits the whole interceptor chain — auth header, 401 refresh, retry, logging — without knowing any of it exists:

```dart
@module
abstract class RegisterModule {
  @lazySingleton
  AuthRemoteDataSource authRemoteDataSource(Dio dio) =>
      AuthRemoteDataSource(dio);
}
```

Constructing it here rather than inside the repository keeps the dependency visible to the container, which is what leaves a seam for a fake in tests.

> [!NOTE]
> **Authenticating through Firebase instead?** Swap the transport inside `AuthRepositoryImpl` and keep the shape below — but add a Firebase branch to `ErrorHandler` first (§4). Without one, every Firebase error collapses to *"Unknown error occurred"* in release.

### Session persistence

Both endpoints funnel through one helper, because they do the same four things:

```dart
Future<Result<UserEntity>> _authenticate(
  Future<BaseEntity<UserModel>> Function() request,
) {
  return execute<BaseEntity<UserModel>, UserEntity>(
    request,
    successCondition: (response) =>
        response.isSuccess && response.data != null,
    onSuccess: (response) {
      final user = response.data!;
      _local.saveUserToken(user.token);
      _local.saveUserData(user);
    },
    mapper: (response) => response.data!.toEntity(),
  );
}
```

Three details carry the weight:

| Detail | Why it matters |
|:---|:---|
| `successCondition` | Without it, `execute` treats **any** response that did not throw as a success. An API that reports failure inside a 200 body would log the user in |
| `onSuccess` saves the token | `NetworkConfig.getToken()` reads it back through `IAuthSessionGateway`, which `data_auth` implements over `AuthLocalDataSource`. Skip this and no `Authorization` header is ever sent, and the 401 refresh flow in `core_network` can never trigger |
| `token` lives on `UserModel`, not `UserEntity` | A credential is something the transport hands back, not part of who the user is. It is read once here and never travels upward — there is a test asserting exactly that |

`logout` is `executeSync`, not `execute`: it only clears storage, and there is nothing to await.

This is what closes the loop with `core_network`'s 401 refresh interceptor. See [the networking guide](../guides/08_networking.md).

## 7. Writing a new repository

```dart
@LazySingleton(as: IPaymentRepository)
class PaymentRepositoryImpl extends IBaseRepository
    implements IPaymentRepository {
  PaymentRepositoryImpl(this._remote);

  final PaymentRemoteDataSource _remote;

  @override
  Future<Result<PaymentEntity>> charge(ChargeParams params) {
    return execute<PaymentModel, PaymentEntity>(
      () => _remote.charge(params.toJson()),
      mapper: (model) => model.toEntity(),
    );
  }
}
```

Checklist:

- [ ] `extends IBaseRepository` and uses `execute` / `executeSync` — no bare `try/catch`
- [ ] `@LazySingleton(as: IFooRepository)` or `@Injectable(as: ...)`, bound to the **Domain interface**
- [ ] Data sources return Models; the `mapper` converts to Entities
- [ ] No Drift / Dio / Retrofit type appears in any public signature
- [ ] Storage keys and endpoints live in this package's `utils/`
- [ ] Storage-owning classes are singletons with `@PostConstruct(preResolve: true)`
- [ ] Every package actually used is declared in `pubspec.yaml` — verify with `dart tools/unused_checker/check_unused_packages.dart`

Then:

```bash
dart run build_runner build -d --workspace
dart tools/barrel_generator/generate.dart modules/<name>/data/lib
```

---

## Related

- [Domain layer](03_domain.md) — the interfaces implemented here
- [Guide: new domain + data package](../guides/02_new_domain_data.md)
- [Guide: storage](../guides/06_storage.md) · [database](../guides/07_database.md) · [networking](../guides/08_networking.md)
- [Rules and conventions](../reference/01_rules.md)
