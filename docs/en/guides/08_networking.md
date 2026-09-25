# Guide: Networking

## Goal

You call a new HTTP endpoint from a data package. You declare the service with Retrofit, register it, and unwrap its responses into a `Result`. You also learn to opt a single request out of auth, refresh or retry, to add a second client with its own rules, to plug in token refresh, and to turn on certificate pinning.

## Prerequisites

- A data package — [`02_new_domain_data.md`](02_new_domain_data.md).
- **What happens inside the client**: the interceptor chain and its order, how `NetworkConfig` is supplied, the refresh-token flow and its recursion guards, and when pinning is installed — [`../architecture/02_core.md` § 6](../architecture/02_core.md#6-core_network--http-client).
- The endpoint's base URL in the flavor's env file (`BASE_URL` in `apps/mobile/env.dev`, …) — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 1. Add the network dependencies

Declare them in the data package's `pubspec.yaml`, as `modules/auth/data/pubspec.yaml` does. Versions come from the catalog `pubspec_dependencies.yaml`; after editing, `dart tools/dependency_sync.dart` aligns them (RULE-74):

   ```yaml
   dependencies:
     core_network:
       path: ../../../platform/infra/network
     dio: "^5.11.0"
     retrofit: "^4.10.0"
     injectable: ^3.0.0

   dev_dependencies:
     build_runner: "^2.16.0"
     injectable_generator: "^3.1.3"
     retrofit_generator: "^10.2.8"
   ```

Add `json_annotation` / `json_serializable` (and `freezed_annotation` / `freezed`) when the models are generated too. Run `flutter pub get`.

## 2. Put the endpoints in the owning package

```dart
// modules/auth/data/lib/src/utils/auth_api_constants.dart
class AuthApiConstants {
  AuthApiConstants._();

  static const String LOGIN = '/user/login';
  static const String REFRESH_TOKEN = '/user/refresh-token';
}
```

Endpoint constants live with the package that owns them, never in `core_common` — the same ownership rule as storage keys (RULE-09). A shared endpoint file would let every layer read, and mistype, another package's routes.

## 3. Declare the Retrofit service

Declare the abstract class with `part '<file>.g.dart';`:

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

`@Extra` sets per-request flags the interceptors read (`NetworkConstants` in `core_network`). `EXTRA_CAN_REFRESH_TOKEN: false` keeps a `401` from starting a token refresh; `EXTRA_CAN_RETRY: false` keeps a timeout from raising the retry dialog. Both default to `true` when absent (step 6).

> [!IMPORTANT]
> `AuthRemoteDataSource` **is** the live path: `AuthRepositoryImpl` calls it for login and token refresh, through `execute()`. Point `AuthApiConstants` at your real endpoints, or swap the transport (Firebase, GraphQL) inside the repository and keep the shape.

## 4. Register the service through a `@module`

A Retrofit class is a factory constructor, not an `@injectable` class, so it goes through a `@module` in the package's `lib/di/register_module.dart`. The real one:

   ```dart
   // modules/auth/data/lib/di/register_module.dart
   import 'package:dio/dio.dart';
   import 'package:injectable/injectable.dart';

   import '../src/data_sources/remote/auth_remote_data_source.dart';

   @module
   abstract class RegisterModule {
     @lazySingleton
     AuthRemoteDataSource authRemoteDataSource(Dio dio) =>
         AuthRemoteDataSource(dio);
   }
   ```

The `Dio` it receives is `core_network`'s default client, already carrying the whole interceptor chain. To use a named client (step 7) instead, name the parameter:

   ```dart
   @lazySingleton
   CatalogRemoteDataSource catalogRemoteDataSource(
     @Named('public_api') Dio dio,
   ) => CatalogRemoteDataSource(dio);
   ```

Without the `@lazySingleton`, the repository that injects the data source fails at boot with *"… is not registered"*. `flutter analyze` cannot see that (RULE-77).

## 5. Generate the code

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<module>/data/lib
```

`build_runner` writes Retrofit's `.g.dart` and the package's `module.module.dart`. The barrel generator then exports the new files (RULE-75).

## 6. Opt a single request out of auth, refresh or retry

All three flags live in `RequestOptions.extra` and default to `true`:

```dart
// platform/infra/network/lib/src/utils/network_constants.dart
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

| Set to `false` on… | Flag |
|:--|:--|
| A request that must not carry a token | `EXTRA_NEED_AUTHENTICATION` |
| Login, refresh, and any call whose `401` is not "session expired" | `EXTRA_CAN_REFRESH_TOKEN` |
| A call that must fail fast rather than wait on the retry dialog | `EXTRA_CAN_RETRY` |

With Retrofit, set them with `@Extra({...})`, as step 3 shows. Why login and refresh need `EXTRA_CAN_REFRESH_TOKEN: false`: without it, a `401` from the refresh call waits on the refresh that is waiting on it ([`../architecture/02_core.md` § 6](../architecture/02_core.md#three-guards-against-infinite-recursion)).

## 7. Add a second client with its own rules

`core_network` registers exactly one client — the default `Dio` every Retrofit data source receives:

```dart
// platform/infra/network/lib/di/register_module.dart
@module
abstract class RegisterModule {
  @lazySingleton
  Dio dio(ApiClient apiClient) => apiClient.createClient();
}
```

`createClient()` takes these parameters:

| Parameter | Effect |
|---|---|
| `baseUrl` | Overrides `EnvConstants.BASE_URL` for this client |
| `interceptors` | Extra interceptors appended **after** the defaults |
| `useDefaultInterceptors` | `false` skips the whole default chain — use for a public/unauthenticated client |
| `options` | Replaces `_defaultOptions` wholesale (it is `copyWith`-ed, so shared state is not mutated) |

A second client with its own rules is registered the same way, under a **name**, so it does not replace the default one. Nothing in the repo registers this. It is the shape to copy — for example, a public API with no auth header, no refresh and no retry dialog:

```dart
// modules/<module>/data/lib/di/register_module.dart
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@module
abstract class RegisterModule {
  @Named('public_api')
  @lazySingleton
  Dio publicDio(ApiClient apiClient) => apiClient.createClient(
    useDefaultInterceptors: false,
    interceptors: [LoggingInterceptor(tag: 'PublicAPI')],
  );
}
```

`getIt<Dio>()` and every unnamed `Dio` parameter still get the default client. Only a parameter annotated `@Named('public_api')` gets this one (step 4). A name can be registered **once** per container: if a second package needs the same client, move the registration into `platform/infra/network/lib/di/register_module.dart` rather than declaring it twice.

## 8. Unwrap the response envelopes

`BaseEntity<T>` wraps a standard server response:

```dart
// platform/layers/domain/lib/src/entities/base_entity.dart
const factory BaseEntity({
  @JsonKey(name: 'statusCode') @Default(200) int statusCode,
  @JsonKey(name: 'data') T? data,
  @JsonKey(name: 'message') String? message,
}) = _BaseEntity<T>;

bool get isSuccess => statusCode == DomainConstants.SUCCESS_STATUS_CODE;
bool get hasError => !isSuccess;
```

`PaginatedEntity<T>` carries the page plus metadata:

```dart
// platform/layers/domain/lib/src/entities/paginated_entity.dart
typedef BaseEntityPaginate<T> = BaseEntity<PaginatedEntity<T>>;

const factory PaginatedEntity({
  @JsonKey(name: 'items') @Default([]) List<T> data,
  @JsonKey(name: 'meta') @Default(MetaPaginate()) MetaPaginate meta,
}) = _PaginatedEntity<T>;
```

`MetaPaginate` holds `totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`.

`BaseRequest<T>` is the paging request builder:

```dart
// platform/layers/data/lib/src/models/base_request.dart
const factory BaseRequest({
  @JsonKey(name: 'page') @Default(1) int page,
  @JsonKey(name: 'pageSize') @Default(25) int pageSize,
  @JsonKey(name: 'data') T? data,
}) = _BaseRequest<T>;
```

Repositories unwrap these into `Result<T>` via `execute()` — see [`02_new_domain_data.md`](02_new_domain_data.md) § 9.

## 9. Plug in token refresh

You do not wire the refresh interceptor yourself. `NetworkConfigImpl` installs it as soon as some module registers an `ISessionGateway` (in the sample, `data_auth`'s `AuthSessionGatewayImpl`, `modules/auth/data/lib/src/services/auth_session_gateway_impl.dart`). With none registered, a `401` reaches the caller unchanged.

To use your own backend, implement `ISessionGateway` (`platform/foundation/contracts/lib/src/session/i_session_gateway.dart`) in your auth data package. Its `refreshToken()` must answer in one of three ways, because the answer decides what happens to the session:

| `refreshToken()` | Meaning | `RefreshTokenHandler` |
| :-- | :-- | :-- |
| a token | renewed | replays the request and every one waiting on it |
| `null` | the server **refused** (401/403, any 4xx, or a 200 whose envelope reports an error — `ErrorCodes.RESPONSE_REJECTED`) | calls `onRefreshFailed` once, rejects them all |
| throws | never got an answer (no network, a real HTTP 5xx, cancelled) — only these | rejects them all, **keeps the session** |

Then mark the login and refresh calls `EXTRA_CAN_REFRESH_TOKEN: false` (step 6). What happens after your answer — one refresh for N concurrent `401`s, and the three recursion guards — is in [`../architecture/02_core.md` § 6](../architecture/02_core.md#the-refresh-token-flow).

## 10. Turn on SSL pinning

> [!WARNING]
> **Pinning is currently OFF.** `sslPinningHashes` returns `const []`, and an empty list disables pinning entirely. Until you fill it in, the app accepts any certificate the device trusts — including one injected by an intercepting proxy.

Get the SPKI SHA-256 hash of each key:

```sh
openssl s_client -servername <host> -connect <host>:443 </dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

Pin **at least two** keys — the leaf plus a backup — so certificate rotation does not lock every installed client out of the API. Return them from `sslPinningHashes` in `platform/shell/adapters/lib/src/network_config_impl.dart` (RULE-48).

Pinning also needs `SslPinningConfig` bound in its own right, which `platform/shell/adapters/lib/di/network_binding_module.dart` already does (RULE-14). Keep that binding: without it pinning is skipped on every flavor, production included ([`../architecture/06_app_shell.md` § 4](../architecture/06_app_shell.md#why-sslpinningconfig-needs-a-separate-binding)). When pinning is installed, and which builds bypass it: [`../architecture/02_core.md` § 6](../architecture/02_core.md#when-pinning-is-installed-and-when-it-is-skipped).

---

## Verify

```bash
dart run build_runner build --workspace                  # Retrofit .g.dart + module.module.dart
flutter analyze                                          # No issues found!
cd platform/infra/network && flutter test                # the interceptor tests
cd apps/mobile && flutter test test/di_smoke_test.dart   # your data source resolves; DioFailureClassifier is registered
```

Test a repository against a fake data source, as `modules/auth/data/test/` does, rather than against a live server. On a device, a debug build logs every request and response through `LoggingInterceptor` (tag `NetworkConstants.CLIENT_LOG_TAG`), with credentials redacted. When pinning is off or unregistered, the log shows an `ERROR` tagged `Security`.

Review checklist:

- [ ] Endpoint constants live in the owning data package's `utils/`, never in `core_common`
- [ ] Retrofit service declared, `part` added, `build_runner` run
- [ ] Requests that must not carry a token set `EXTRA_NEED_AUTHENTICATION = false`
- [ ] Login, refresh, and any call whose `401` is not "session expired" set `EXTRA_CAN_REFRESH_TOKEN = false`
- [ ] `NetworkConfig` impl stays `@LazySingleton` (never eager)
- [ ] `sslPinningHashes` populated with ≥2 pins before shipping
- [ ] `SslPinningConfig` bound explicitly in a `@module` — check `platform_shell_adapters`' generated `lib/di/module.module.dart`
- [ ] No credential ever logged verbatim

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `… is not registered` for the data source at boot | The Retrofit class has no `@module` registration, or codegen is stale | Register it (step 4), then `build_runner` (step 5) |
| Every request fails at once with a connection error | `BASE_URL` is empty in the flavor's env file | Set `BASE_URL` in `apps/mobile/env.<flavor>` |
| The app hangs after a `401` on login or refresh | The call lacks `EXTRA_CAN_REFRESH_TOKEN: false`, so the refresh waits on itself | Add the `@Extra` (steps 3 and 6) |
| A `401` reaches the UI although the backend supports refresh | No `ISessionGateway` is registered, so no refresh interceptor is installed | Implement and register one (step 9) |
| The user is signed out after a network blip | `refreshToken()` returned `null` for a transient error | Throw for "no answer" and return `null` only for a refusal (step 9) |
| The server ignores the locale | It reads `Accept-Language`; the client sends the non-standard `language` header | Read `language` on the server |
| `ERROR` log: `SSL pinning skipped` | `sslPinningHashes` is empty, or `SslPinningConfig` is not bound | Fill the hashes and keep the binding (step 10) |
| Two packages register the same named client and boot throws | A name can be registered once per container | Move the registration into `platform/infra/network/lib/di/register_module.dart` (step 7) |

## Related

- Rules: RULE-09 (endpoints in `utils/`), RULE-14 (second interface via `@module`), RULE-41 (data sources return models), RULE-42 (`execute()` and no throw to UI), RULE-43 (`ErrorHandler`), RULE-48 (pinning), RULE-66 (never log secrets) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 6](../architecture/02_core.md#6-core_network--http-client) — the client's internals
- [`02_new_domain_data.md`](02_new_domain_data.md) — repository and `Result<T>` mapping
- [`05_di.md`](05_di.md) — registration order and the eager-singleton trap
- [`06_storage.md`](06_storage.md) — where the token is persisted
