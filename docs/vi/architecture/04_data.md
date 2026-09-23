# Tầng Data

**File này trả lời:** `modules/*/data` thoả mãn các hợp đồng repository do Domain khai báo bằng cách nào — model, data source và xử lý lỗi nằm ở đâu, và tầng này tuyệt đối không được để lộ những gì ra ngoài.

**Đọc xong bạn làm được:** viết một repository trả `Result<T>` mà không cần một dòng `try/catch` nào, quyết định được một giá trị thuộc về Model hay Entity, và biết chính xác kiểu nào được phép xuất hiện trong chữ ký của data source.

---

## 1. Vị trí và trách nhiệm

```
Feature (UI) ──→ Domain ←── Data
                              ↓
              core_network / core_storage / core_database
```

Data phụ thuộc **vào trong** là Domain (để hiện thực interface của Domain) và **ra ngoài** là hạ tầng `core_*`. Không ai phụ thuộc Data ngoại trừ app shell — nơi lắp ráp tất cả. Một feature package tuyệt đối không được import `data_*`.

| Công việc | Nằm ở đâu |
|:---|:---|
| Nói chuyện với network / DB / storage | `data_sources/` |
| Chuyển định dạng wire & row thành object có kiểu | `models/` |
| Thoả mãn `I*Repository` của Domain | `repositories_impl/` |
| Hằng số và key do package sở hữu | `utils/` |

---

## 2. Bố cục package

```
modules/<name>/data/
├── lib/
│   ├── data_<name>.dart             # barrel công khai
│   ├── di/
│   │   ├── module.dart              # @InjectableInit.microPackage()
│   │   └── register_module.dart     # tuỳ chọn — @module bind thư viện ngoài
│   └── src/
│       ├── data_sources/
│       │   ├── remote/              # Retrofit / HTTP
│       │   └── local/               # storage / database
│       ├── models/                  # DTO có .toEntity()
│       ├── repositories_impl/
│       ├── utils/                   # key, endpoint — thuộc sở hữu package này
│       └── src.dart
└── pubspec.yaml
```

> [!CAUTION]
> Thư mục là **`data_sources/`** (snake_case, số nhiều, có gạch dưới) — **không phải** `datasources/`. Các generator và checklist review đều giả định cách viết này.

Các package hiện có:

| Package | Nội dung |
|:---|:---|
| `data_core` | `IBaseRepository`, `BaseModel`, request model |
| `data_auth` | `UserModel`, data source auth, `AuthRepositoryImpl` |
| `data_cache` | `CacheDatabase` (database Drift do package tự sở hữu), `CacheEntryModel`, local data source, `CacheEntryRepositoryImpl` |

---

## 3. `IBaseRepository` — vì sao repository không có `try/catch`

`platform/data_core/lib/src/base/i_base_repository.dart` cung cấp cho mọi repository hai hàm bọc. `RepositoryImpl` sẽ `extends IBaseRepository` rồi gọi chúng thay vì tự xử lý lỗi.

### `execute<R, T>()` — bất đồng bộ

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
      // …ánh xạ R → T…
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

Hai tham số kiểu, và chúng **không** giống nhau:

- **`R`** — thứ data source trả về (một Model, danh sách Model, `void`)
- **`T`** — thứ Domain mong đợi (một Entity, danh sách Entity, `void`)
- **`mapper`** — cầu nối `R → T`, thường là `(model) => model.toEntity()`

Nếu lời gọi trả về `null`, `T` nullable và không truyền `mapper`, hàm trả `Success(null as T)` — đó là cách các thao tác `Future<Result<void>>` hoạt động mà không cần thủ tục thừa. Response khác `null` vẫn được trả về dưới dạng `T` kể cả khi `T` nullable.

### `executeSync<R, T>()` — đồng bộ

Cùng hình dạng, dành cho công việc cục bộ không bất đồng bộ. `onFailure` ở đây nhận `Object` bị ném ra, không phải response.

### Cơ chế chuyển đổi lỗi

Cả hai hàm bọc đều dồn mọi throw vào `ErrorHandler.handleError(e)` của `platform_kernel` (cũng tới được qua re-export của `core_common`), và hàm này trả về một `AppFailure`.

> [!NOTE]
> `ErrorHandler` là điểm chuyển đổi duy nhất. Không hề có `AppFailure.fromException()` — đừng bịa ra một cái, và cũng đừng tự nặn failure tại chỗ gọi. Khi buộc phải tạo tường minh, hãy dùng các hàm trợ giúp `ErrorHandler.serverFailure(...)`, `.networkFailure(...)`, `.authFailure(...)`…

### `ErrorHandler` thực sự nhận diện được gì

`platform/kernel/lib/src/error/error_handler.dart` phân nhánh theo thứ tự: `AppException` → `DioException` → `SocketException` → `HttpException` → `FormatException` → nhánh mặc định.

> [!WARNING]
> **Không có nhánh nào cho `FirebaseException` / `FirebaseAuthException` / `PlatformException`.** `AuthRepositoryImpl` đi kèm template dùng Retrofit nên sample không dính lỗi này — nhưng đổi transport sang Firebase SDK thì mọi lỗi Firebase — sai mật khẩu, không tìm thấy user, mất mạng — đều rơi xuống nhánh mặc định:
>
> ```dart
> return ServerFailure(
>   message: _isDebug ? error.toString() : 'Unknown error occurred',
>   code: 9999,
> );
> ```
>
> Ở bản release, người dùng thấy **"Unknown error occurred"** cho mọi lần đăng nhập thất bại. Tệ hơn, mọi UI phân loại lỗi theo code — chẳng hạn `AuthProvider._mapAuthFailure` đang switch theo `401` / `404` — sẽ **không bao giờ khớp**, vì code luôn là `9999`.
>
> Nếu bạn thêm repository chạy trên Firebase, hãy bổ sung nhánh tương ứng vào `ErrorHandler` trước.

---

## 4. Model

Model là biểu diễn của riêng tầng Data. Nó không bao giờ lọt vào Domain — phải chuyển đổi trước.

### Hợp đồng

```dart
// platform/data_core/lib/src/models/base_model.dart
abstract class BaseModel<E> {
  E toEntity() {
    throw UnimplementedError();
  }
}
```

### Model cho mạng

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

`unknownEnumValue: UserRole.unknown` nghĩa là một role backend thêm sau này sẽ deserialize thành `unknown` thay vì ném lỗi.

`fromEntity` là chiều ngược lại, dùng khi ghi một entity ngược lên API hay cache. Sample chưa có luồng ghi ngược nào, nên hiện chỉ `modules/auth/data/test/user_model_test.dart` dùng tới nó.

### Model cho database

`modules/cache/data/lib/src/models/cache_entry_model.dart` — Freezed, **không** dùng `json_serializable`:

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

Dữ liệu đến từ SQLite chứ không phải API, nên không có hợp đồng JSON nào phải tuân thủ — thêm `json_serializable` chỉ là nhiễu. Hãy chọn codegen theo nguồn dữ liệu, đừng theo thói quen.

---

## 5. Data source

### Quy tắc 1 — trả Model, không bao giờ trả Entity

Nhiệm vụ của data source dừng ở mức "object có kiểu". Ánh xạ sang Domain là việc của repository.

### Quy tắc 2 — không để lộ kiểu của tầng vận chuyển

Đây chính là lý do `CacheEntryModel` tồn tại. `modules/cache/data/lib/src/data_sources/local/cache_entry_local_data_source.dart`:

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

Lớp hiện thực chuyển đổi ngay tại ranh giới, và nhận **handle hẹp** thay vì cả database:

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

Inject nguyên object database sẽ trao cho lớp này **mọi DAO** có trên đó; `IDatabaseHandle.accessor(...)` chỉ trao đúng một cái. Xem [hướng dẫn database](../guides/07_database.md).

### Quy tắc 3 — để exception nổi lên

Data source **không** bắt lỗi. `execute()` trong repository là điểm bắt duy nhất; nuốt lỗi ở tầng dưới đồng nghĩa repository báo thành công cho một lời gọi đã thất bại.

### Quy tắc 4 — storage key thuộc về package sở hữu nó

`core_storage` chỉ cung cấp cơ chế. Mỗi bên tiêu thụ tự khai `StorageValue` của mình và giữ key trong `utils/` của chính nó.

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
> **`@lazySingleton` ở đây mang tính sống còn — dùng `@injectable` sẽ hỏng âm thầm.**
>
> `StorageValue` giữ một cache trong RAM, được `initialize()` nạp từ đĩa đúng một lần lúc khởi động. Đăng ký dạng factory sẽ tạo instance **mới, rỗng** ở mỗi lần inject, nên `getUserToken()` trả `null` dù token vẫn nằm trên đĩa. Cặp bắt buộc là: đăng ký singleton **+** `@PostConstruct(preResolve: true)`.

Endpoint REST cũng theo đúng quy tắc sở hữu này — `modules/auth/data/lib/src/utils/auth_api_constants.dart` chứa `AuthApiConstants`, vì những endpoint đó thuộc về auth và không thuộc về bất cứ thứ gì khác.

---

## 6. `data_auth` — đọc phần này trước khi copy

`AuthRepositoryImpl` là file bị copy nhiều nhất trong template, nên nó được viết đúng như tài liệu này mô tả về tầng data: một Retrofit data source cho mạng, một `StorageValue` data source cho phiên đăng nhập, `execute()` bọc cả hai, và ánh xạ model → entity ngay tại ranh giới.

```dart
@LazySingleton(as: IAuthRepository)
class AuthRepositoryImpl extends IBaseRepository implements IAuthRepository {
  AuthRepositoryImpl(this._remote, this._local);

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;
```

Retrofit client được dựng một lần trong [`modules/auth/data/lib/di/register_module.dart`](../../../modules/auth/data/lib/di/register_module.dart) từ `Dio` dùng chung, nên data source thừa hưởng toàn bộ chuỗi interceptor — header auth, refresh 401, retry, logging — mà không cần biết chúng tồn tại:

```dart
@module
abstract class RegisterModule {
  @lazySingleton
  AuthRemoteDataSource authRemoteDataSource(Dio dio) =>
      AuthRemoteDataSource(dio);
}
```

Dựng ở đây thay vì bên trong repository giữ cho dependency hiển lộ với container — đó chính là khe hở để test truyền một fake vào.

> [!NOTE]
> **Muốn xác thực qua Firebase?** Đổi transport bên trong `AuthRepositoryImpl` và giữ nguyên hình dạng bên dưới — nhưng hãy thêm nhánh Firebase vào `ErrorHandler` trước (§4). Thiếu nhánh đó, mọi lỗi Firebase đều thành *"Unknown error occurred"* ở bản release.

### Lưu giữ phiên đăng nhập

Cả hai endpoint đều đi qua một helper, vì chúng làm cùng bốn việc:

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

Ba chi tiết gánh toàn bộ sức nặng:

| Chi tiết | Vì sao quan trọng |
|:---|:---|
| `successCondition` | Thiếu nó, `execute` coi **mọi** response không ném exception là thành công. Một API báo lỗi trong body 200 sẽ cho người dùng đăng nhập được |
| `onSuccess` lưu token | `NetworkConfig.getToken()` đọc lại token qua `IAuthSessionGateway`, do `data_auth` hiện thực trên nền `AuthLocalDataSource`. Bỏ bước này thì không header `Authorization` nào được gửi, và luồng refresh 401 trong `core_network` không bao giờ kích hoạt |
| `token` nằm ở `UserModel`, không nằm ở `UserEntity` | Credential là thứ transport trả về, không phải một phần danh tính người dùng. Nó được đọc đúng một lần ở đây và không bao giờ đi lên trên — có hẳn một test khẳng định điều đó |

`logout` dùng `executeSync` chứ không phải `execute`: nó chỉ xoá storage, không có gì để await.

Đây chính là mắt xích khép vòng với interceptor refresh 401 của `core_network`. Xem [hướng dẫn networking](../guides/08_networking.md).

## 7. Viết một repository mới

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

- [ ] `extends IBaseRepository` và dùng `execute` / `executeSync` — không `try/catch` trần
- [ ] `@LazySingleton(as: IFooRepository)` hoặc `@Injectable(as: ...)`, bind vào **interface của Domain**
- [ ] Data source trả Model; `mapper` chuyển sang Entity
- [ ] Không kiểu Drift / Dio / Retrofit nào xuất hiện trong chữ ký công khai
- [ ] Storage key và endpoint nằm trong `utils/` của package này
- [ ] Lớp sở hữu storage là singleton kèm `@PostConstruct(preResolve: true)`
- [ ] Mọi package thực sự dùng đều đã khai trong `pubspec.yaml` — kiểm tra bằng `dart tools/unused_checker/check_unused_packages.dart`

Sau đó:

```bash
dart tools/barrel_generator/generate.dart modules/<name>/data/lib
dart run build_runner build -d --workspace
```

---

## Liên quan

- [Tầng Domain](03_domain.md) — các interface được hiện thực ở đây
- [Hướng dẫn: tạo domain + data package](../guides/02_new_domain_data.md)
- [Hướng dẫn: storage](../guides/06_storage.md) · [database](../guides/07_database.md) · [networking](../guides/08_networking.md)
- [Quy tắc và quy ước](../reference/01_rules.md)
