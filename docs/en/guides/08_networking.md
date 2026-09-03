# Guide: Networking

**What this answers:** how an HTTP request leaves this app — which interceptors touch it, how an expired session is renewed, and what is (and is not) protecting the connection.

**After reading you can:** declare a new API service, opt a request out of auth or retry, wire the refresh-token flow, and turn on certificate pinning correctly.

---

## 1. `ApiClient` — the Dio factory

`core_network` never hard-codes credentials or UI. It takes everything through `NetworkConfig` (§3), which the app shell implements.

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

`createClient()` parameters:

| Parameter | Effect |
|---|---|
| `baseUrl` | Overrides `EnvConstants.BASE_URL` for this client |
| `interceptors` | Extra interceptors appended **after** the defaults |
| `useDefaultInterceptors` | `false` skips the whole default chain — use for a public/unauthenticated client |
| `options` | Replaces `_defaultOptions` wholesale (it is `copyWith`-ed, so shared state is not mutated) |

A second client with its own rules is registered through a DI module, e.g. a public API client with `useDefaultInterceptors: false`.

---

## 2. The interceptor chain

Dio runs interceptors in the order they were added — for `onRequest` **and** for `onError`. The real order in `createClient()` is:

```
1. AuthInterceptor            → attaches Authorization + language headers
2. RefreshTokenInterceptor    → catches 401, renews the session, replays  (only if configured)
3. RetryInterceptor           → catches timeout / connection errors
4. LoggingInterceptor         → structured logs (debug builds only)
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

Auth runs first so the token is attached before anything else; refresh sits ahead of retry so a 401 is *renewed* rather than replayed with the same dead token.

### Per-request opt-outs

Both flags live in `RequestOptions.extra` and default to `true`:

```dart
// packages/core/network/lib/src/utils/network_constants.dart
/// Set `false` to stop [AuthInterceptor] attaching the bearer token.
static const String EXTRA_NEED_AUTHENTICATION = 'needAuthentication';

/// Set `false` to opt a request out of [RetryInterceptor].
static const String EXTRA_CAN_RETRY = 'canRetry';
```

### `AuthInterceptor`

Adds an upper-cased `language` header (falling back to the device locale, then to `vi`), and the bearer token when the request wants auth:

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
> The language header key is the non-standard `'language'`, not `Accept-Language`. Match it on the server side.

### `RetryInterceptor`

Only transport failures qualify — **not** HTTP status codes:

```dart
// packages/core/network/lib/src/handlers/retry_handler.dart
bool retryWhen(DioExceptionType type) {
  return type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.connectionError ||
      type == DioExceptionType.connectionTimeout;
}
```

Concurrent failures are collected into one queue and a **single** retry dialog is raised through `NetworkConfig.onRetryCallback`. If no callback is supplied, every queued request is cancelled instead of hanging.

### `LoggingInterceptor`

All three hooks are behind `kDebugMode`, and credential headers are masked even in debug:

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

## 3. `NetworkConfig` — the app shell supplies the details

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

The two refresh getters default to `null`, so in an app with no refresh endpoint a `401` reaches the caller untouched.

The implementation delegates each value to whoever actually owns it, rather than reading storage itself:

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
> `NetworkConfigImpl` is `@LazySingleton`, not `@Singleton`. It depends on `AuthLocalDataSource`, which lives in `data_auth` — a module initialised *after* the app-local DI block. An eager singleton would resolve during `configureDependencies()` and throw "not registered". `flutter analyze` cannot catch this; verify against generated `app/lib/di/injection.config.dart`. See [`05_di.md`](05_di.md).

---

## 4. Refresh-token flow

`_refreshSession` runs the domain use case, then re-reads the token from its owner — the config never persists anything itself:

```dart
// app/lib/di/network_config_impl.dart
Future<String?> _refreshSession() async {
  final result = await _refreshTokenUseCase(const NoParams());
  if (!result.isSuccess) return null;

  return _authLocalDataSource.getUserToken();
}
```

### One refresh for N concurrent 401s

`RefreshTokenHandler` serialises everything behind a `Completer`. The first 401 performs the refresh; the rest wait on the same future:

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

The retry is `await`-ed deliberately:

```dart
// `await` keeps the refresh lock (`_completer`) held until the retry
// finishes; without it the `finally` below clears the lock early and a
// concurrent 401 would start a second, redundant refresh.
return await _retryRequest(err, handler);
```

`FormData` bodies are rebuilt before replay, because a form stream can only be consumed once.

### Three guards against infinite recursion

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

Guard 2 is subtle — the flag is set **before** handing over, because the replay goes back through this same interceptor:

```dart
// Mark the options *before* handing over: `RefreshTokenHandler` replays
// this same RequestOptions through `dio.fetch`, which re-enters this
// interceptor. The flag makes that second pass fall through to `super`.
err.requestOptions.extra[NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] = true;
```

> [!NOTE]
> If your refresh endpoint is itself an HTTP call through this client, set `extra[EXTRA_NEED_AUTHENTICATION] = false` on it (guard 1). The current implementation calls Firebase directly, so this does not apply here.

---

## 5. SSL pinning

> [!WARNING]
> **Pinning is currently OFF.** `sslPinningHashes` returns `const []`, and an empty list disables pinning entirely. Until you fill it in, the app accepts any certificate the device trusts — including one injected by an intercepting proxy.

The initializer refuses to fail silently about it:

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

### The registration trap

`NetworkConfig implements SslPinningConfig`, but registering the impl `as: NetworkConfig` does **not** make it resolvable as `SslPinningConfig` — GetIt matches the exact registered type. Without a second binding, `getItOrNull<SslPinningConfig>()` returns `null` and pinning is skipped on every flavour, production included. The binding that prevents it:

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

The parameter is typed `NetworkConfig`, so the upcast is compiler-checked — no `as` cast.

### Getting a pin

```sh
openssl s_client -servername <host> -connect <host>:443 </dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

Pin **at least two** keys — the leaf plus a backup — so certificate rotation does not lock every installed client out of the API.

`dev` bypasses certificate validation entirely (for local self-signed servers); `staging` and `prod` go through the pinning path.

---

## 6. Declaring an API service with Retrofit

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

Steps: declare the abstract class → `part 'x.g.dart';` → run `dart run build_runner build -d --workspace`.

> [!IMPORTANT]
> `AuthRemoteDataSource` is a **reference sample, not the live path**. `AuthRepositoryImpl` talks to the Firebase SDK directly and never calls this class. Keep it as a template for a REST backend; do not assume auth traffic flows through it.

### Endpoints belong to the owning package

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

Endpoint constants live with the package that owns them, never in `core_common` — the same ownership rule as storage keys. A shared endpoint file would let every layer read, and mistype, another package's routes.

---

## 7. Response envelopes

`BaseEntity<T>` wraps a standard server response:

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

`PaginatedEntity<T>` carries the page plus metadata:

```dart
// packages/domain/core/lib/src/entities/base/paginate_entity.dart
typedef BaseEntityPaginate<T> = BaseEntity<PaginatedEntity<T>>;

const factory PaginatedEntity({
  @JsonKey(name: 'items') @Default([]) List<T> data,
  @JsonKey(name: 'meta') @Default(MetaPaginate()) MetaPaginate meta,
}) = _PaginatedEntity<T>;
```

`MetaPaginate` holds `totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`.

`BaseRequest<T>` is the paging request builder:

```dart
// packages/data/core/lib/src/models/base_request.dart
const factory BaseRequest({
  @JsonKey(name: 'page') @Default(1) int page,
  @JsonKey(name: 'pageSize') @Default(25) int pageSize,
  @JsonKey(name: 'data') T? data,
}) = _BaseRequest<T>;
```

Repositories unwrap these into `Result<T>` via `execute()` — see [`02_new_domain_data.md`](02_new_domain_data.md).

---

## 8. Checklist

- [ ] Endpoint constants live in the owning data package's `utils/`, never in `core_common`
- [ ] Retrofit service declared, `part` added, `build_runner` run
- [ ] Requests that must not carry a token set `EXTRA_NEED_AUTHENTICATION = false`
- [ ] `NetworkConfig` impl stays `@LazySingleton` (never eager)
- [ ] `sslPinningHashes` populated with ≥2 pins before shipping
- [ ] `SslPinningConfig` bound explicitly in a `@module` — check `injection.config.dart`
- [ ] No credential ever logged verbatim

## See also

- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_network` in context
- [`05_di.md`](05_di.md) — registration order and the eager-singleton trap
- [`06_storage.md`](06_storage.md) — where the token is persisted
- [`02_new_domain_data.md`](02_new_domain_data.md) — repository and `Result<T>` mapping
