# Hướng dẫn: Networking

**File này trả lời:** một HTTP request rời khỏi app này như thế nào — đi qua những interceptor nào, phiên hết hạn được làm mới ra sao, và cái gì đang (và **không** đang) bảo vệ kết nối.

**Đọc xong bạn làm được:** khai một API service mới, cho một request bỏ qua auth hoặc retry, nối luồng refresh token, và bật certificate pinning cho đúng.

---

## 1. `ApiClient` — factory tạo Dio

`core_network` không bao giờ hard-code thông tin đăng nhập hay UI. Nó nhận mọi thứ qua `NetworkConfig` (§3), do app shell implement.

```dart
// packages/core/network/lib/src/api_client.dart
@lazySingleton
class ApiClient {
  final NetworkConfig _config;

  ApiClient(this._config);

  /// Default base options for Dio.
  BaseOptions get _defaultOptions => BaseOptions(
    baseUrl: EnvConstants.BASE_URL,
    connectTimeout: NetworkConstants.CONNECT_TIMEOUT,
    receiveTimeout: NetworkConstants.RECEIVE_TIMEOUT,
    sendTimeout: NetworkConstants.SEND_TIMEOUT,
    followRedirects: false,
    headers: {HttpHeaders.contentTypeHeader: ContentType.json.value},
  );
```

Tham số của `createClient()`:

| Tham số | Tác dụng |
|---|---|
| `baseUrl` | Ghi đè `EnvConstants.BASE_URL` cho client này |
| `interceptors` | Interceptor bổ sung, gắn **sau** bộ mặc định |
| `useDefaultInterceptors` | `false` sẽ bỏ qua toàn bộ chuỗi mặc định — dùng cho client public/không cần auth |
| `options` | Thay thế hoàn toàn `_defaultOptions` (được `copyWith` nên không làm hỏng state dùng chung) |

Muốn có client thứ hai với luật riêng thì đăng ký qua một DI module, ví dụ client public với `useDefaultInterceptors: false`.

---

## 2. Chuỗi interceptor

Dio chạy interceptor theo **đúng thứ tự được thêm vào** — cho cả `onRequest` lẫn `onError`. Thứ tự thật trong `createClient()` là:

```
1. AuthInterceptor            → gắn header Authorization + language
2. RefreshTokenInterceptor    → bắt 401, làm mới phiên, replay   (chỉ khi có cấu hình)
3. RetryInterceptor           → bắt lỗi timeout / mất kết nối
4. LoggingInterceptor         → log có cấu trúc (chỉ bản debug)
```

```dart
// packages/core/network/lib/src/api_client.dart
dio.interceptors.add(
  AuthInterceptor(
    getToken: _config.getToken,
    getLocale: _config.getLocale,
  ),
);

// Renewing an expired session must happen before the retry pass,
// otherwise a 401 would be replayed with the same stale token.
// Only wired when the app supplies a refresh callback; without one a
// 401 surfaces to the caller unchanged.
final onRefreshToken = _config.onRefreshToken;
if (onRefreshToken != null) {
  final onRefreshFailed = _config.onRefreshFailed;
  dio.interceptors.add(
    RefreshTokenInterceptor(
      RefreshTokenHandler(
        dio: dio,
        onRefreshToken: onRefreshToken,
        onRefreshFailed: onRefreshFailed ?? () async {},
      ),
    ),
  );
}

dio.interceptors.addAll([
  RetryInterceptor(
    handleRetry: retryHandler.handleRetry,
    retryWhen: retryHandler.retryWhen,
  ),
  LoggingInterceptor(tag: NetworkConstants.CLIENT_LOG_TAG),
]);
```

Auth chạy trước để token được gắn trước mọi thứ; refresh đứng trước retry để một lỗi 401 được **làm mới** chứ không bị replay với đúng cái token đã chết.

### Opt-out theo từng request

Cả hai cờ nằm trong `RequestOptions.extra` và mặc định là `true`:

```dart
// packages/core/network/lib/src/utils/network_constants.dart
/// Set `false` to stop [AuthInterceptor] attaching the bearer token.
static const String EXTRA_NEED_AUTHENTICATION = 'needAuthentication';

/// Set `false` to opt a request out of [RetryInterceptor].
static const String EXTRA_CAN_RETRY = 'canRetry';
```

### `AuthInterceptor`

Gắn header `language` viết hoa (fallback về locale thiết bị, rồi về `vi`), và bearer token khi request cần auth:

```dart
// packages/core/network/lib/src/interceptors/auth_interceptor.dart
if (needAuthentication) {
  final token = getToken() ?? '';
  if (token.isNotEmpty) {
    options.headers.addAll({
      HttpHeaders.authorizationHeader:
          '${NetworkConstants.BEARER_PREFIX} $token',
    });
  }
}
```

> [!NOTE]
> Tên header ngôn ngữ là `'language'` (không chuẩn), **không phải** `Accept-Language`. Phía server phải khớp đúng tên này.

### `RetryInterceptor`

Chỉ lỗi tầng vận chuyển mới được retry — **không** retry theo HTTP status code:

```dart
// packages/core/network/lib/src/handlers/retry_handler.dart
bool retryWhen(DioExceptionType type) {
  return type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.connectionError ||
      type == DioExceptionType.connectionTimeout;
}
```

Nhiều request lỗi đồng thời được gom vào một hàng đợi và chỉ hiện **một** dialog retry duy nhất qua `NetworkConfig.onRetryCallback`. Nếu không truyền callback, mọi request trong hàng đợi sẽ bị huỷ thay vì treo.

### `LoggingInterceptor`

Cả ba hook đều nằm sau `kDebugMode`, và header chứa thông tin đăng nhập bị che **ngay cả ở bản debug**:

```dart
// packages/core/network/lib/src/interceptors/logging_interceptor.dart
Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) {
  const redactedKeys = {
    HttpHeaders.authorizationHeader,
    HttpHeaders.cookieHeader,
    HttpHeaders.setCookieHeader,
    HttpHeaders.proxyAuthorizationHeader,
  };

  return {
    for (final entry in headers.entries)
      entry.key: redactedKeys.contains(entry.key.toLowerCase())
          ? '***REDACTED***'
          : entry.value,
  };
}
```

---

## 3. `NetworkConfig` — app shell cung cấp chi tiết

```dart
// packages/core/network/lib/src/network_config.dart
abstract class NetworkConfig implements SslPinningConfig {
  String? Function() get getToken;
  String? Function() get getLocale;

  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  });

  Future<String?> Function()? get onRefreshToken => null;
  Future<void> Function()? get onRefreshFailed => null;

  @override
  List<String> get sslPinningHashes;
}
```

Hai getter refresh mặc định `null`, nên trong một app không có endpoint refresh thì `401` đi thẳng tới caller, nguyên vẹn.

Phần implement giao mỗi giá trị cho đúng chủ sở hữu của nó, thay vì tự đọc storage:

```dart
// app/lib/di/network_config_impl.dart
@LazySingleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  NetworkConfigImpl(
    this._authLocalDataSource,
    this._languageStorage,
    this._refreshTokenUseCase,
  );

  @override
  String? Function() get getToken => _authLocalDataSource.getUserToken;

  @override
  String? Function() get getLocale =>
      () => _languageStorage.getLanguage().languageCode;

  @override
  Future<String?> Function()? get onRefreshToken => _refreshSession;

  @override
  Future<void> Function()? get onRefreshFailed => _clearSession;
```

> [!IMPORTANT]
> `NetworkConfigImpl` là `@LazySingleton`, **không phải** `@Singleton`. Nó phụ thuộc `AuthLocalDataSource` thuộc `data_auth` — module được nạp **sau** khối DI cục bộ của app. Nếu để eager singleton, nó sẽ resolve ngay trong `configureDependencies()` và ném lỗi "not registered". `flutter analyze` **không** bắt được lỗi này; phải kiểm tra ở file sinh ra `app/lib/di/injection.config.dart`. Xem [`05_di.md`](05_di.md).

---

## 4. Luồng refresh token

`_refreshSession` chạy use case ở tầng domain, rồi đọc lại token từ chủ sở hữu — bản thân config không lưu gì cả:

```dart
// app/lib/di/network_config_impl.dart
Future<String?> _refreshSession() async {
  final result = await _refreshTokenUseCase(const NoParams());
  if (!result.isSuccess) return null;

  return _authLocalDataSource.getUserToken();
}
```

### N request 401 đồng thời → chỉ một lần refresh

`RefreshTokenHandler` xếp hàng mọi thứ sau một `Completer`. Request 401 đầu tiên thực hiện refresh; những cái còn lại chờ trên cùng future đó:

```dart
// packages/core/network/lib/src/handlers/refresh_token_handler.dart
// If a refresh is already in progress, wait for it to complete.
if (_completer != null) {
  final String? newToken = await _completer!.future;
  if (newToken != null) {
    // The token was successfully refreshed, retry the original request.
    return _retryRequest(err, handler);
  } else {
    // The token refresh failed, reject the original request.
    return handler.reject(err);
  }
}
```

Việc `await` lần retry là **cố ý**:

```dart
// `await` keeps the refresh lock (`_completer`) held until the retry
// finishes; without it the `finally` below clears the lock early and a
// concurrent 401 would start a second, redundant refresh.
return await _retryRequest(err, handler);
```

Body dạng `FormData` được dựng lại trước khi replay, vì stream của form chỉ đọc được một lần.

### Ba lớp chống đệ quy vô hạn

```dart
// packages/core/network/lib/src/interceptors/refresh_token_interceptor.dart
/// Three guards keep the flow from looping:
/// 1. Requests that opted out of auth
///    ([NetworkConstants.EXTRA_NEED_AUTHENTICATION] `= false`) are ignored, so
///    the refresh call itself never triggers a refresh.
/// 2. A request already replayed after a refresh is marked with
///    [NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] and is not refreshed a
///    second time.
/// 3. [RefreshTokenHandler] serialises concurrent `401`s behind a single
///    `Completer`, so N failing requests cause exactly one refresh.
```

Lớp 2 tinh tế — cờ được set **trước khi** giao việc, vì bản replay quay lại chính interceptor này:

```dart
// Mark the options *before* handing over: `RefreshTokenHandler` replays
// this same RequestOptions through `dio.fetch`, which re-enters this
// interceptor. The flag makes that second pass fall through to `super`.
err.requestOptions.extra[NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] = true;
```

> [!NOTE]
> Nếu endpoint refresh của bạn cũng là một HTTP call qua chính client này, hãy set `extra[EXTRA_NEED_AUTHENTICATION] = false` cho nó (lớp 1). Cài đặt hiện tại gọi thẳng Firebase nên chưa gặp tình huống này.

---

## 5. SSL pinning

> [!WARNING]
> **Pinning hiện đang TẮT.** `sslPinningHashes` trả về `const []`, và list rỗng nghĩa là pinning bị vô hiệu hoá hoàn toàn. Chừng nào chưa điền vào, app chấp nhận **mọi** certificate mà thiết bị tin tưởng — kể cả cert do proxy chèn vào.

Initializer **không im lặng bỏ qua** chuyện này:

```dart
// packages/core/common/lib/src/config/app_initializer.dart
if (hashes != null && hashes.isNotEmpty) {
  HttpOverrides.global = _MyHttpSecurityPinningHttpOverrides(hashes);
} else {
  // Never fail silently here: without pinning the app still talks to the
  // server over plain TLS, so a proxy with a trusted root can read every
  // request. Surfacing it keeps a misconfiguration from shipping unnoticed.
  DynamicLogger.log(
    config == null
        ? 'SSL pinning skipped: no SslPinningConfig registered in GetIt. ...'
        : 'SSL pinning skipped: sslPinningHashes is empty. ...',
    tag: 'Security',
    level: LogLevel.ERROR,
  );
}
```

### Cái bẫy khi đăng ký DI

`NetworkConfig implements SslPinningConfig`, nhưng đăng ký impl `as: NetworkConfig` **không** làm nó phân giải được dưới kiểu `SslPinningConfig` — GetIt khớp đúng kiểu đã đăng ký. Thiếu một binding thứ hai, `getItOrNull<SslPinningConfig>()` trả về `null` và pinning âm thầm vô hiệu trên mọi flavor, kể cả production. Binding ngăn điều đó:

```dart
// app/lib/di/network_binding_module.dart
/// GetIt resolves by the exact type a binding was registered under — it does
/// **not** walk the supertype chain. `NetworkConfigImpl` is registered as
/// `NetworkConfig`, so without this module `getItOrNull<SslPinningConfig>()`
/// (called by `AppInitializer._setupHttpOverrides`) resolves to `null` and
/// certificate pinning is silently skipped on staging and production.
@module
abstract class NetworkBindingModule {
  @lazySingleton
  SslPinningConfig bindSslPinningConfig(NetworkConfig config) => config;
}
```

Tham số khai kiểu `NetworkConfig` nên phép upcast được **compiler kiểm tra** — không cần ép kiểu `as`.

### Lấy giá trị pin

```sh
openssl s_client -servername <host> -connect <host>:443 </dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

Pin **ít nhất hai** key — leaf cộng một key dự phòng — để khi xoay vòng certificate không khoá chết toàn bộ client đã cài trên máy người dùng.

Flavor `dev` bỏ qua kiểm tra certificate hoàn toàn (phục vụ server tự ký cục bộ); `staging` và `prod` đi qua đường pinning.

---

## 6. Khai API service bằng Retrofit

```dart
// packages/data/auth/lib/src/data_sources/remote/auth_remote_data_source.dart
@RestApi()
abstract class AuthRemoteDataSource {
  factory AuthRemoteDataSource(Dio dio, {String? baseUrl}) =
      _AuthRemoteDataSource;

  /// Authenticates user with provided credentials
  @POST(AuthApiConstants.LOGIN)
  Future<BaseEntity<UserModel>> login(@Body() Map<String, dynamic> loginData);

  /// Refreshes the current authentication token
  @POST(AuthApiConstants.REFRESH_TOKEN)
  Future<BaseEntity<UserModel>> refreshToken();
}
```

Các bước: khai abstract class → thêm `part 'x.g.dart';` → chạy `dart run build_runner build -d --workspace`.

> [!IMPORTANT]
> `AuthRemoteDataSource` là **mẫu tham khảo, không phải đường chạy thật**. `AuthRepositoryImpl` gọi thẳng Firebase SDK và **không bao giờ** gọi class này. Hãy giữ nó làm khuôn mẫu cho backend REST; đừng tưởng traffic auth đang đi qua đây.

### Endpoint thuộc về package sở hữu

```dart
// packages/data/auth/lib/src/utils/auth_api_constants.dart
class AuthApiConstants {
  AuthApiConstants._();

  static const String LOGIN = '/user/login';
  static const String REGISTER = '/user/register';
  static const String REFRESH_TOKEN = '/user/refresh-token';
  // ...
}
```

Hằng số endpoint nằm cùng package sở hữu chúng, không bao giờ ở `core_common` — đúng luật sở hữu như với storage key. Một file endpoint dùng chung sẽ cho phép mọi tầng đọc, và gõ nhầm, route của package khác.

---

## 7. Cấu trúc bao response

`BaseEntity<T>` bao một response chuẩn của server:

```dart
// packages/domain/core/lib/src/entities/base/base_entity.dart
const factory BaseEntity({
  @JsonKey(name: 'statusCode') @Default(200) int statusCode,
  @JsonKey(name: 'data') T? data,
  @JsonKey(name: 'message') String? message,
}) = _BaseEntity<T>;

bool get isSuccess => statusCode == ApiStatusConstants.SUCCESS;
bool get hasError => !isSuccess;
```

`PaginatedEntity<T>` mang theo trang dữ liệu cộng metadata:

```dart
// packages/domain/core/lib/src/entities/base/paginate_entity.dart
typedef BaseEntityPaginate<T> = BaseEntity<PaginatedEntity<T>>;

const factory PaginatedEntity({
  @JsonKey(name: 'items') @Default([]) List<T> data,
  @JsonKey(name: 'meta') @Default(MetaPaginate()) MetaPaginate meta,
}) = _PaginatedEntity<T>;
```

`MetaPaginate` chứa `totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`.

`BaseRequest<T>` là bộ dựng request phân trang:

```dart
// packages/data/core/lib/src/models/base_request.dart
const factory BaseRequest({
  @JsonKey(name: 'page') @Default(1) int page,
  @JsonKey(name: 'pageSize') @Default(25) int pageSize,
  @JsonKey(name: 'data') T? data,
}) = _BaseRequest<T>;
```

Repository bóc các lớp bao này thành `Result<T>` qua `execute()` — xem [`02_new_domain_data.md`](02_new_domain_data.md).

---

## 8. Checklist

- [ ] Hằng số endpoint nằm trong `utils/` của package data sở hữu, không ở `core_common`
- [ ] Đã khai Retrofit service, thêm `part`, chạy `build_runner`
- [ ] Request không được mang token thì set `EXTRA_NEED_AUTHENTICATION = false`
- [ ] Impl `NetworkConfig` giữ `@LazySingleton` (không bao giờ eager)
- [ ] `sslPinningHashes` đã điền ≥2 pin trước khi phát hành
- [ ] `SslPinningConfig` được bind tường minh trong `@module` — kiểm tra `injection.config.dart`
- [ ] Không log nguyên văn bất kỳ thông tin đăng nhập nào

## Xem thêm

- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_network` trong bức tranh chung
- [`05_di.md`](05_di.md) — thứ tự đăng ký và bẫy eager singleton
- [`06_storage.md`](06_storage.md) — nơi token được lưu
- [`02_new_domain_data.md`](02_new_domain_data.md) — repository và cách map `Result<T>`
