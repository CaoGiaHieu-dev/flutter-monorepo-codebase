# Hướng dẫn: Networking

**File này trả lời:** một HTTP request rời khỏi app này như thế nào — đi qua những interceptor nào, phiên hết hạn được làm mới ra sao, và cái gì đang (và **không** đang) bảo vệ kết nối.

**Đọc xong bạn làm được:** khai một API service mới, cho một request bỏ qua auth hoặc retry, nối luồng refresh token, và bật certificate pinning cho đúng.

---

## 1. `ApiClient` — factory tạo Dio

`core_network` không bao giờ hard-code thông tin đăng nhập hay UI. Nó nhận mọi thứ qua `NetworkConfig` (§3), do app shell implement.

```dart
// platform/network/lib/src/api_client.dart
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
// platform/network/lib/src/api_client.dart
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

Cả ba cờ nằm trong `RequestOptions.extra` và mặc định là `true`:

```dart
// platform/network/lib/src/utils/network_constants.dart
/// Set `false` to stop [AuthInterceptor] attaching the bearer token.
static const String EXTRA_NEED_AUTHENTICATION = 'needAuthentication';

/// Set `false` to opt a request out of [RetryInterceptor].
static const String EXTRA_CAN_RETRY = 'canRetry';

/// Set `false` on a request whose `401` must never start a token refresh —
/// the login and refresh calls themselves. The bearer token is still
/// attached; only the refresh reaction is skipped. Without it a `401` from
/// the refresh call waits on the refresh that is waiting on it.
static const String EXTRA_CAN_REFRESH_TOKEN = 'canRefreshToken';
```

### `AuthInterceptor`

Gắn header `language` viết hoa (fallback về locale thiết bị, rồi về `vi`), và bearer token khi request cần auth:

```dart
// platform/network/lib/src/interceptors/auth_interceptor.dart
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
// platform/network/lib/src/handlers/retry_handler.dart
bool retryWhen(DioExceptionType type) {
  return type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.connectionError ||
      type == DioExceptionType.connectionTimeout;
}
```

Nhiều request lỗi đồng thời được gom vào một hàng đợi và chỉ hiện **một** dialog retry duy nhất qua `NetworkConfig.onRetryCallback`. Nếu không truyền callback, mọi request trong hàng đợi sẽ bị huỷ thay vì treo. "Retry" lấy mọi request ra khỏi hàng đợi (mỗi bên gọi một mục) và gửi lại qua chính `Dio` đó với `canRetry: false`: interceptor auth và refresh chạy lại (token mới, 401 được refresh), timeout thì đưa bên gọi trở lại hàng đợi cho dialog kế tiếp, còn lỗi khác tới tay bên gọi đúng là lỗi *đó* chứ không phải timeout ban đầu.

### `LoggingInterceptor`

Cả ba hook đều nằm sau `kDebugMode`, và header chứa thông tin đăng nhập bị che **ngay cả ở bản debug**:

```dart
// platform/network/lib/src/interceptors/logging_interceptor.dart
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

Body cũng được che, ở mọi độ sâu: giá trị dưới `password`, `token`, `access_token` / `accessToken`, `refresh_token`, `id_token`, `secret` hoặc `client_secret` được in thành `***REDACTED***` — request login mang password trong body, còn response trả token trong body.

---

## 3. `NetworkConfig` — app shell cung cấp chi tiết

```dart
// platform/network/lib/src/network_config.dart
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
// platform/app_shell/lib/di/network_config_impl.dart
@LazySingleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  NetworkConfigImpl(this._languageStorage);

  final ILanguageStorage _languageStorage;

  /// Null in a build that composes no auth module.
  IAuthSessionGateway? get _session => getItOrNull<IAuthSessionGateway>();

  @override
  String? Function() get getToken => () => _session?.readToken();

  @override
  String? Function() get getLocale =>
      () => _languageStorage.getLanguage().languageCode;

  /// Whether an auth module is composed — without resolving it: resolving
  /// the gateway while `Dio` is being built closes a dependency cycle.
  bool get _hasSession => getIt.isRegistered<IAuthSessionGateway>();

  @override
  Future<String?> Function()? get onRefreshToken =>
      _hasSession ? _refreshSession : null;

  @override
  Future<void> Function()? get onRefreshFailed =>
      _hasSession ? _clearSession : null;
```

> [!IMPORTANT]
> `NetworkConfigImpl` không import module nào. Nó đọc token qua `IAuthSessionGateway`, được resolve bằng `getItOrNull` ngay lúc gọi thay vì inject, nên nó dựng được dù build có module auth hay không, và không thứ tự DI nào làm hỏng được nó. Khi không có gateway nào được đăng ký, `onRefreshToken` trả về null — và `ApiClient` chỉ gắn `RefreshTokenInterceptor` **khi** giá trị đó khác null, nên một build không có auth sẽ không có interceptor refresh, thay vì có một cái không bao giờ thành công. `arch_check` R1 giữ điều đó: nó nằm trong `platform_app_shell`, và package `platform/` không được import module. Xem [`05_di.md`](05_di.md).

---

## 4. Luồng refresh token

`_refreshSession` giao việc cho `IAuthSessionGateway`, do `data_auth` hiện thực: repository refresh và lưu thông tin đăng nhập, còn gateway đọc lại token từ chủ sở hữu. Bản thân config không lưu gì cả:

```dart
// platform/app_shell/lib/di/network_config_impl.dart
Future<String?> _refreshSession() async => await _session?.refreshToken();

// modules/auth/data/lib/src/services/auth_session_gateway_impl.dart
@override
Future<String?> refreshToken() async {
  final result = await _repository.refreshToken();
  if (result.isSuccess) return _local.getUserToken();
  final failure = result.errorOrNull;
  final transient = failure is NetworkFailure ||
      (failure is ServerFailure && (failure.code ?? 500) >= 500);
  if (transient) {
    throw StateError('Session renewal did not reach the server: '
        '${failure?.message}');
  }
  return null;
}
```

### Bị từ chối hay không tới được server

Câu trả lời của gateway quyết định số phận của phiên đăng nhập:

| `refreshToken()` | Nghĩa là | `RefreshTokenHandler` |
| :-- | :-- | :-- |
| một token | đã gia hạn | gửi lại request và mọi request đang chờ nó |
| `null` | server **từ chối** (401/403, mọi 4xx, hoặc một 200 mà envelope báo lỗi — `ErrorCodes.RESPONSE_REJECTED`) | gọi `onRefreshFailed` một lần, reject tất cả |
| ném lỗi | không nhận được câu trả lời (mất mạng, HTTP 5xx thật, bị huỷ) — chỉ những trường hợp này | reject tất cả, **giữ nguyên phiên** |

`onRefreshFailed` chính là `NetworkConfigImpl._clearSession`: gateway xoá thông tin đăng nhập đã lưu, rồi `IAuthSessionState.onSessionLost()` đưa bên sở hữu về trạng thái đăng xuất — đúng thay đổi mà `NavigatorWrapperWidget` lắng nghe để chuyển tới màn đăng nhập. Chỉ xoá storage thì người dùng vẫn ở lại màn hình, "đang đăng nhập", mà không có token.

Một `401` tới *sau* khi refresh đã xong — request được gửi bằng token cũ — không khởi động refresh mới: `RefreshTokenHandler` so header `Authorization` của request với `NetworkConfig.getToken` và, nếu khác nhau, chỉ gửi lại request. Với refresh token xoay vòng, một lần refresh thừa có thể làm mất hiệu lực chính phiên vừa được gia hạn.

### N request 401 đồng thời → chỉ một lần refresh

`RefreshTokenHandler` xếp hàng mọi thứ sau một `Completer`. Request 401 đầu tiên thực hiện refresh; những cái còn lại chờ trên cùng future đó:

```dart
// platform/network/lib/src/handlers/refresh_token_handler.dart
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
// finishes; releasing it earlier would let a concurrent 401 start a
// second, redundant refresh.
return await _retryRequest(err, handler);
```

Body dạng `FormData` được dựng lại trước khi replay, vì stream của form chỉ đọc được một lần.

### Ba lớp chống đệ quy vô hạn

```dart
// platform/network/lib/src/interceptors/refresh_token_interceptor.dart
/// Three guards keep the flow from looping:
/// 1. Requests that opted out of auth
///    ([NetworkConstants.EXTRA_NEED_AUTHENTICATION] `= false`) or out of
///    refresh ([NetworkConstants.EXTRA_CAN_REFRESH_TOKEN] `= false`) are
///    ignored, so the login and refresh calls never trigger a refresh.
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
> Refresh của sample **chính là** một HTTP call qua chính client này (`AuthRemoteDataSource.refreshToken`), nên nó và `login` mang `@Extra({NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false})` (lớp 1); lời gọi refresh còn đặt thêm `EXTRA_CAN_RETRY: false`, vì nó chạy lúc boot và bên trong 401 của request khác nên phải fail nhanh thay vì chờ dialog retry. Khi không có token đã lưu, `AuthRepositoryImpl.refreshToken` trả lời luôn mà không gọi mạng. Thiếu cờ này, một `401` từ chính lời gọi refresh sẽ đi vào `RefreshTokenHandler` trong lúc lần refresh của handler vẫn đang chạy, và chờ chính nó mãi mãi. Endpoint nào của bạn mà `401` mang nghĩa khác "hết phiên" cũng cần cờ này.

---

## 5. SSL pinning

> [!WARNING]
> **Pinning hiện đang TẮT.** `sslPinningHashes` trả về `const []`, và list rỗng nghĩa là pinning bị vô hiệu hoá hoàn toàn. Chừng nào chưa điền vào, app chấp nhận **mọi** certificate mà thiết bị tin tưởng — kể cả cert do proxy chèn vào.

Initializer **không im lặng bỏ qua** chuyện này:

```dart
// platform/common/lib/src/config/app_initializer.dart
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
// platform/app_shell/lib/di/network_binding_module.dart
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

Kiểm tra certificate chỉ bị bỏ qua (phục vụ server tự ký cục bộ) **trong bản debug đã khai báo tường minh flavor `dev`** — `AppConfig.bypassesCertificateValidation`. Mọi trường hợp khác đi qua đường pinning: `staging`, `prod`, bản profile hay release của `dev`, và bản build **thiếu hoặc sai** flavor — được coi như `prod` và ghi log mức ERROR. Đây là cố ý fail closed: trước đây `AppConfig.appFlavor` lùi về `dev`, nên một bản build không có `--flavor` — kể cả release — chấp nhận mọi certificate. Bản thân `appFlavor` (môi trường DI) giờ lùi về `dev` ở bản debug và về `prod` ở các bản còn lại.

---

## 6. Khai API service bằng Retrofit

```dart
// modules/auth/data/lib/src/data_sources/remote/auth_remote_data_source.dart
@RestApi()
abstract class AuthRemoteDataSource {
  factory AuthRemoteDataSource(Dio dio, {String? baseUrl}) =
      _AuthRemoteDataSource;

  /// Authenticates user with provided credentials.
  ///
  /// A `401` here means wrong credentials, not an expired session — so it
  /// must not start a token refresh.
  @POST(AuthApiConstants.LOGIN)
  @Extra({NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false})
  Future<BaseEntity<UserModel>> login(@Body() Map<String, dynamic> loginData);

  /// Refreshes the current authentication token.
  /// … (fails fast: no refresh, no retry dialog)
  @POST(AuthApiConstants.REFRESH_TOKEN)
  @Extra({
    NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false,
    NetworkConstants.EXTRA_CAN_RETRY: false,
  })
  Future<BaseEntity<UserModel>> refreshToken();
}
```

`@Extra` đặt cờ theo từng request mà interceptor đọc (`NetworkConstants` trong `core_network`): `EXTRA_CAN_REFRESH_TOKEN: false` để `401` không kích hoạt refresh token, `EXTRA_CAN_RETRY: false` để timeout không bật dialog retry. Cả hai mặc định là `true` khi không khai.

Các bước: khai abstract class → thêm `part 'x.g.dart';` → chạy `dart run build_runner build --workspace`.

> [!IMPORTANT]
> `AuthRemoteDataSource` **chính là** đường chạy thật: `AuthRepositoryImpl` gọi nó cho login và refresh token, qua `execute()`. Hãy trỏ `AuthApiConstants` vào endpoint thật của bạn, hoặc đổi transport (Firebase, GraphQL) bên trong repository và giữ nguyên hình dạng.

### Endpoint thuộc về package sở hữu

```dart
// modules/auth/data/lib/src/utils/auth_api_constants.dart
class AuthApiConstants {
  AuthApiConstants._();

  static const String LOGIN = '/user/login';
  static const String REFRESH_TOKEN = '/user/refresh-token';
}
```

Hằng số endpoint nằm cùng package sở hữu chúng, không bao giờ ở `core_common` — đúng luật sở hữu như với storage key. Một file endpoint dùng chung sẽ cho phép mọi tầng đọc, và gõ nhầm, route của package khác.

---

## 7. Cấu trúc bao response

`BaseEntity<T>` bao một response chuẩn của server:

```dart
// platform/domain_core/lib/src/entities/base/base_entity.dart
const factory BaseEntity({
  @JsonKey(name: 'statusCode') @Default(200) int statusCode,
  @JsonKey(name: 'data') T? data,
  @JsonKey(name: 'message') String? message,
}) = _BaseEntity<T>;

bool get isSuccess => statusCode == DomainConstants.SUCCESS_STATUS_CODE;
bool get hasError => !isSuccess;
```

`PaginatedEntity<T>` mang theo trang dữ liệu cộng metadata:

```dart
// platform/domain_core/lib/src/entities/base/paginate_entity.dart
typedef BaseEntityPaginate<T> = BaseEntity<PaginatedEntity<T>>;

const factory PaginatedEntity({
  @JsonKey(name: 'items') @Default([]) List<T> data,
  @JsonKey(name: 'meta') @Default(MetaPaginate()) MetaPaginate meta,
}) = _PaginatedEntity<T>;
```

`MetaPaginate` chứa `totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`.

`BaseRequest<T>` là bộ dựng request phân trang:

```dart
// platform/data_core/lib/src/models/base_request.dart
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
- [ ] Login, refresh, và mọi call có `401` không mang nghĩa "hết phiên" thì set `EXTRA_CAN_REFRESH_TOKEN = false`
- [ ] Impl `NetworkConfig` giữ `@LazySingleton` (không bao giờ eager)
- [ ] `sslPinningHashes` đã điền ≥2 pin trước khi phát hành
- [ ] `SslPinningConfig` được bind tường minh trong `@module` — kiểm tra file sinh ra `lib/di/module.module.dart` của `platform_app_shell`
- [ ] Không log nguyên văn bất kỳ thông tin đăng nhập nào

## Xem thêm

- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_network` trong bức tranh chung
- [`05_di.md`](05_di.md) — thứ tự đăng ký và bẫy eager singleton
- [`06_storage.md`](06_storage.md) — nơi token được lưu
- [`02_new_domain_data.md`](02_new_domain_data.md) — repository và cách map `Result<T>`
