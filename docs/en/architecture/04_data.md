# Data Layer

**What this answers:** how `packages/data/*` fulfils the repository contracts declared by Domain — where models, data sources and error handling live, and which boundaries this layer must not leak across.

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
packages/data/<name>/
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
| `data_core` | `IBaseRepository`, `BaseModel`, request models, the cache sample |
| `data_auth` | `UserModel`, auth data sources, `AuthRepositoryImpl` |
| `data_language` | `LanguageRepositoryImpl` (sample, see §7) |

---

## 3. `IBaseRepository` — why repositories have no `try/catch`

`packages/data/core/lib/src/base/i_base_repository.dart` gives every repository two wrappers. A `RepositoryImpl` `extends IBaseRepository` and calls them instead of handling errors itself.

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

If `T` is nullable and no `mapper` is supplied, `Success(null as T)` is returned — that is how `Future<Result<void>>` operations work without ceremony.

### `executeSync<R, T>()` — synchronous

Same shape for local, non-async work. `onFailure` here receives the thrown `Object`, not the response.

### Error conversion

Both wrappers funnel every throw into `ErrorHandler.handleError(e)` from `core_common`, which returns an `AppFailure`.

> [!NOTE]
> Older docs told you never to call `AppFailure.fromException()`. **That method does not exist in this codebase** (`grep fromException packages/core/common/lib` → nothing). The rule still stands as intent: convert through `ErrorHandler`, never hand-roll a failure at the call site. The helpers `ErrorHandler.serverFailure(...)`, `.networkFailure(...)`, `.authFailure(...)` etc. are there when you must construct one explicitly.

### What `ErrorHandler` actually recognises

`packages/core/common/lib/src/error/error_handler.dart` branches on, in order: `AppException` → `DioException` → `SocketException` → `HttpException` → `FormatException` → fallback.

> [!WARNING]
> **There is no `FirebaseException` / `FirebaseAuthException` / `PlatformException` branch.** Since `AuthRepositoryImpl` talks to the Firebase SDK directly (§6), every Firebase error — wrong password, user-not-found, network-request-failed — falls through to the generic tail:
>
> ```dart
> return ServerFailure(
>   message: kDebugMode ? error.toString() : 'Unknown error occurred',
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
// packages/data/core/lib/src/models/base_model.dart
abstract class BaseModel<E> {
  E toEntity() {
    throw UnimplementedError();
  }
}
```

### A network Model

`packages/data/auth/lib/src/models/user/user_model.dart` — Freezed + `json_serializable`:

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

`fromEntity` is the reverse trip, needed when writing back (`updateUserProfile`).

### A database Model

`packages/data/core/lib/src/models/cache_entry_model.dart` — Freezed, **no** `json_serializable`:

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

This is the rule that `CacheEntryModel` exists to satisfy. `packages/data/core/lib/src/data_sources/local/cache_entry_local_data_source.dart`:

```dart
/// Contract for reading/writing cache rows.
///
/// Signatures speak in [CacheEntryModel], never in Drift's generated row
/// class — that keeps Drift an implementation detail of `data_core` instead
/// of leaking it to every consumer of this package.
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);
  Future<String?> get(String key);
  Future<CacheEntryModel?> getEntry(String key);
  Future<void> delete(String key);
  Future<List<CacheEntryModel>> getAll();
}
```

The implementation converts at the boundary and takes a **narrow database handle**, not the whole database:

```dart
@LazySingleton(as: ICacheEntryLocalDataSource)
class CacheEntryLocalDataSource implements ICacheEntryLocalDataSource {
  CacheEntryLocalDataSource(IDatabaseHandle handle)
    : _dao = handle.accessor(CacheEntriesDao.new);

  final CacheEntriesDao _dao;

  @override
  Future<CacheEntryModel?> getEntry(String key) async {
    final row = await _dao.getEntry(key);
    return row == null ? null : CacheEntryModel.fromRow(row);
  }

  @override
  Future<List<CacheEntryModel>> getAll() async {
    final rows = await _dao.getAll();
    return rows.map(CacheEntryModel.fromRow).toList();
  }
  // …
}
```

Injecting `AppDatabase` would hand this class every DAO in the app; `IDatabaseHandle.accessor(...)` hands it exactly one. See [the database guide](../guides/07_database.md).

### Rule 3 — let exceptions bubble

Data sources do **not** catch. `execute()` in the repository is the single catch point; swallowing an error lower down means the repository reports success on a failed call.

### Rule 4 — storage keys belong to the package that owns them

`core_storage` provides only the mechanism. Each consumer declares its own `StorageValue`s and keeps its keys in its own `utils/`.

`packages/data/auth/lib/src/utils/auth_storage_keys.dart`:

```dart
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

`packages/data/auth/lib/src/data_sources/local/auth_local_data_source.dart`:

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

REST endpoints follow the same ownership rule — `packages/data/auth/lib/src/utils/auth_api_constants.dart` holds `AuthApiConstants`, which used to sit in `core_common` as `ApiConstants` where every package could read it.

---

## 6. `data_auth` — read this before copying it

`AuthRepositoryImpl` is the most-copied file in the template. Every collaborator arrives through the constructor — including the three third-party SDKs:

```dart
@Injectable(as: IAuthRepository)
class AuthRepositoryImpl extends IBaseRepository implements IAuthRepository {
  AuthRepositoryImpl(
    this._googleSignIn,
    this._localDataSource,
    this._firebaseAuth,
    this._firestore,
    this._facebookAuth,
  );

  final GoogleSignIn _googleSignIn;
  final AuthLocalDataSource _localDataSource;
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final FacebookAuth _facebookAuth;
```

The SDK singletons are bound once in [`packages/data/auth/lib/di/register_module.dart`](../../../packages/data/auth/lib/di/register_module.dart):

```dart
@module
abstract class RegisterModule {
  @preResolve
  Future<GoogleSignIn> get googleSignIn async { … }

  @lazySingleton
  FirebaseAuth get firebaseAuth => FirebaseAuth.instance;

  @lazySingleton
  FirebaseFirestore get firestore => FirebaseFirestore.instance;

  @lazySingleton
  FacebookAuth get facebookAuth => FacebookAuth.instance;
}
```

Reaching for `.instance` inside the repository would hide those dependencies from the container and leave no seam to pass a fake through, which is why they are registered here instead.

> [!IMPORTANT]
> **It calls the Firebase SDK directly, not `AuthRemoteDataSource`.**
>
> `AuthRemoteDataSource` (Retrofit, in `data_sources/remote/`) is fully written but **not wired into the live flow** — it is kept as a reference for a REST backend. If you are building on Firebase, follow `AuthRepositoryImpl`. If you are building on REST, follow `AuthRemoteDataSource` and inject it.
>
> Do not assume both are active: they are two parallel examples, and only the Firebase one runs.

### Session persistence

Every successful authentication funnels through one helper:

```dart
/// Persists the session through its owner, [AuthLocalDataSource].
///
/// Every successful authentication funnels through here so the Firebase ID
/// token reaches local storage. Without it `NetworkConfig.getToken()` stays
/// null, no `Authorization` header is ever sent, and the 401 refresh flow in
/// `core_network` can never trigger.
Future<UserModel> _persistSession(
  User firebaseUser,
  UserModel model, {
  bool forceRefreshToken = false,
}) async {
  final token = await firebaseUser.getIdToken(forceRefreshToken);
  _localDataSource.saveUserToken(token);
  _localDataSource.saveUserData(model);
  return model;
}
```

The three connected behaviours:

| Method | Behaviour |
|:---|:---|
| `login` / `registerWithEmail` / `loginWithGoogle` / `loginWithFacebook` / `getCurrentUser` | call `_persistSession` → token reaches storage |
| `logout` | also calls `_localDataSource.clearAllAuthData()` — signing out of the SDKs alone would leave a stale token that `getToken()` keeps attaching |
| `refreshToken` | calls `_persistSession(..., forceRefreshToken: true)` — reusing the cached token would loop, since the caller is here *because* that token was rejected |

This is what closes the loop with `core_network`'s 401 refresh interceptor. See [the networking guide](../guides/08_networking.md).

---

## 7. `data_language` — sample only

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
  Future<void> initialize() async => _locale.readFromStorage();

  @override
  Result<String> getLanguage() {
    return executeSync<String, String>(() {
      final language = _locale.value;
      if (language != null) return language;
      return AppConfig.defaultLanguage.languageCode;
    });
  }
  // …
}
```

Two things to notice:

1. **`executeSync`, not `execute`** — reading a hydrated `StorageValue` is synchronous, so `Result<String>` comes back without a `Future`.
2. **It shares the physical key `'locale'` with `LanguageStorageImpl` in the app shell**, and the file says so in a comment. The app shell's copy is the one the Settings UI actually uses; this repository is the unused domain path (see [Domain layer §5](03_domain.md#5-domain_language--a-stub-and-why-it-stays)). Two independent `StorageValue` instances over one key are not kept in sync — acceptable only because one of them is dead code.

---

## 8. Writing a new repository

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
dart tools/barrel_generator/generate.dart packages/data/<name>/lib
dart run build_runner build -d --workspace
```

---

## Related

- [Domain layer](03_domain.md) — the interfaces implemented here
- [Guide: new domain + data package](../guides/02_new_domain_data.md)
- [Guide: storage](../guides/06_storage.md) · [database](../guides/07_database.md) · [networking](../guides/08_networking.md)
- [Rules and conventions](../reference/01_rules.md)
