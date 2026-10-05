# Guide: Networking

## Goal

You call a new HTTP endpoint from a data package. You declare the service with Retrofit, register it, and unwrap its responses into a `Result`. You also learn to opt a single request out of auth, refresh or retry, to add a second client with its own rules, to plug in token refresh, and to turn on certificate pinning.

## Prerequisites

- A data package — [`02_new_domain_data.md`](02_new_domain_data.md).
- **What happens inside the client**: the interceptor chain and its order, how `NetworkConfig` is supplied, the refresh-token flow and its recursion guards, and when pinning is installed — [`../architecture/02_core.md` § 6](../architecture/02_core.md#6-core_network--http-client).
- The endpoint's base URL in the flavor's env file (`BASE_URL` in `apps/mobile/env.dev`, …) — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 1. Add the network dependencies

Declare them in the data package's `pubspec.yaml`, as `modules/auth/data/pubspec.yaml` does. Write the third-party entries without a version: they live only in the catalog `pubspec_dependencies.yaml` (RULE-74), and `dart tools/dependency_sync.dart` fills in an empty one.

```yaml
dependencies:
  core_network:
    path: ../../../platform/infra/network
  dio:
  retrofit:
  injectable:

dev_dependencies:
  build_runner:
  injectable_generator:
  retrofit_generator:
```

`core_network` itself depends on `dio` but not on `retrofit`: the Retrofit annotations and generator belong to the package that declares the service. Add `json_annotation` / `json_serializable` (and `freezed_annotation` / `freezed`) when the models are generated too. Run `dart tools/dependency_sync.dart`, then `flutter pub get`.

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
  ///
  /// Runs *inside* a refresh, or at boot: a `401` from it reacting with
  /// another refresh would wait on itself forever, and a timeout raising the
  /// retry dialog would block boot on the user's answer. It fails fast
  /// instead, and the caller decides.
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
> `AuthRemoteDataSource` **is** the live path: `AuthRepositoryImpl` calls it for login and token refresh, wrapped in `execute()` (RULE-42). Point `AuthApiConstants` at your real endpoints, or swap the transport (Firebase, GraphQL) inside the repository and keep the shape.

## 4. Register the service through a `@module`

A Retrofit class is a factory constructor, not an `@injectable` class, so it goes through a `@module` in the package's `lib/di/module.dart`, next to the `@InjectableInit.microPackage()` marker. The real one:

```dart
// modules/auth/data/lib/di/module.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../src/data_sources/remote/auth_remote_data_source.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDataDiModule {
  @lazySingleton
  AuthRemoteDataSource authRemoteDataSource(Dio dio) =>
      AuthRemoteDataSource(dio);
}
```

The `Dio` it receives is `core_network`'s default client — registered by `NetworkModule` (`platform/infra/network/lib/di/network_module.dart`) and already carrying the whole interceptor chain. To use a named client (step 7) instead, name the parameter:

```dart
@lazySingleton
CatalogRemoteDataSource catalogRemoteDataSource(
  @Named('public_api') Dio dio,
) => CatalogRemoteDataSource(dio);
```

Without the `@lazySingleton`, the repository that injects the data source fails at boot with *"… is not registered"*. `flutter analyze` cannot see that: the app's DI smoke test does (RULE-63, [`05_di.md`](05_di.md#8-diagnose-not-registered-at-startup)).

## 5. Generate the code

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<module>/data/lib
```

`build_runner` writes Retrofit's `.g.dart` and the package's `module.module.dart`. The barrel generator then exports the new files (RULE-75); it only needs to run when a file under `lib/` was added, renamed or deleted.

## 6. Opt a single request out of auth, refresh or retry

Four flags live in `RequestOptions.extra`; three default to `true` and `EXTRA_IDEMPOTENT` to absent (`false`):

```dart
// platform/infra/network/lib/src/utils/network_constants.dart
/// Set `false` to stop [AuthInterceptor] attaching the bearer token.
static const String EXTRA_NEED_AUTHENTICATION = 'needAuthentication';

/// Set `false` to opt a request out of [RetryInterceptor].
static const String EXTRA_CAN_RETRY = 'canRetry';

/// Set `true` on a `POST` / `PATCH` that is safe to send twice — the server
/// deduplicates it, typically by an idempotency key — so [RetryHandler] may
/// replay it after a send or receive timeout. Without it such a request is
/// never replayed on a timeout: the server may already have processed it.
/// `GET`, `HEAD`, `PUT`, `DELETE` and `OPTIONS` need no flag.
static const String EXTRA_IDEMPOTENT = 'idempotent';

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
| (set `true`, not `false`) A `POST` / `PATCH` the server deduplicates, which may be sent again after a send or receive timeout | `EXTRA_IDEMPOTENT` |

With Retrofit, set them with `@Extra({...})`, as step 3 shows. Why login and refresh need `EXTRA_CAN_REFRESH_TOKEN: false`: without it, a `401` from the refresh call waits on the refresh that is waiting on it ([`../architecture/02_core.md` § 6](../architecture/02_core.md#three-guards-against-infinite-recursion)).

Retrying and idempotency: a request that failed to *connect* never reached the server and is replayed for any method; one that timed out *after* it was sent (send or receive timeout) may already have been processed, so a `POST` or `PATCH` is not replayed — it fails with the timeout — unless it sets `EXTRA_IDEMPOTENT: true`. `GET`, `HEAD`, `PUT`, `DELETE` and `OPTIONS` keep retrying. If the retry prompt cannot be shown (the `onRetryCallback` throws), the queued requests are cancelled and fail with their own errors rather than waiting for a dialog that never came.

Two headers come from `AuthInterceptor`, not from the profile. `Authorization: Bearer <token>` is attached when the session owner has a token, unless the request set `EXTRA_NEED_AUTHENTICATION: false` — and **only to the API host**: the host of `BASE_URL` (compared case-insensitively) or one of `NetworkProfile.authorizedHosts`. A request to any other host — a CDN, a presigned storage URL, a "next page" link a server handed back — leaves without the token and is marked `EXTRA_CAN_REFRESH_TOKEN: false`, so its `401` never starts a token refresh. If your API is split over several sub-domains, list them in `authorizedHosts` ([`13_app_composition.md`](13_app_composition.md) § 4). `language` carries the upper-cased code (`EN`, `VI`) of the language the **app** resolved: `NetworkConfigImpl.getLocale` takes `ILanguageStorage.getLanguage()` — the stored choice, else the profile's `initial` language, else the device's — and resolves it through the app's `LanguageSet` (the set `LanguageProvider` uses; `AppLanguages` is the same thing built for the template's defaults), so the server only ever sees a language the app offers. With no resolved code the interceptor sends the profile's `LocaleProfile.fallback` (`en` by default). The header name is the non-standard `language`, not `Accept-Language`.

## 7. Add a second client with its own rules

`core_network` registers exactly one client — the default `Dio` every Retrofit data source receives:

```dart
// platform/infra/network/lib/di/network_module.dart
@module
abstract class NetworkModule {
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

What `_defaultOptions` holds is the **app's** to set: the connect, receive and send timeouts (20 s each), extra headers, the redirect policy and the extra hosts that may receive the bearer token (`authorizedHosts`) come from its `NetworkProfile` (`network:` in `apps/<id>/lib/app/app_profile.dart`), registered before the graph is built, so the default `Dio` carries them. A header that would defeat the auth interceptors or leak a credential — `authorization`, `cookie`, `set-cookie`, `proxy-authorization`, `content-type` — makes `ApiClient` throw when it is built — the DI smoke test builds every lazy singleton, so it fails there (RULE-66). The base URL stays an env define (`BASE_URL`, per flavor), and a second base URL is `createClient(baseUrl:)`.

A second client with its own rules is registered the same way, under a **name**, so it does not replace the default one. Nothing in the repo registers this. It is the shape to copy — for example, a public API with no auth header, no refresh and no retry dialog:

```dart
// modules/<module>/data/lib/di/module.dart
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@module
abstract class CatalogDataDiModule {
  @Named('public_api')
  @lazySingleton
  Dio publicDio(ApiClient apiClient) => apiClient.createClient(
    useDefaultInterceptors: false,
    interceptors: [LoggingInterceptor(tag: 'PublicAPI')],
  );
}
```

`getIt<Dio>()` and every unnamed `Dio` parameter still get the default client. Only a parameter annotated `@Named('public_api')` gets this one (step 4). A name can be registered **once** per container: if a second package needs the same client, move the registration into `platform/infra/network/lib/di/network_module.dart` rather than declaring it twice.

## 8. Unwrap the response envelopes

`BaseEntity<T>` wraps a standard server response:

```dart
// platform/layers/domain/lib/src/entities/base_entity.dart
const factory BaseEntity({
  @JsonKey(name: 'statusCode') @Default(200) int statusCode,
  @JsonKey(name: 'data') T? data,
  @JsonKey(name: 'message') String? message,
}) = _BaseEntity<T>;

bool get isSuccess =>
    statusCode >= DomainConstants.SUCCESS_STATUS_CODE &&
    statusCode < DomainConstants.SUCCESS_STATUS_CEILING;
bool get hasError => !isSuccess;
```

`isSuccess` is any 2xx (`200` ≤ `statusCode` < `300`): a create answered `201` or an action answered `204` is as successful as a `200`; an envelope reporting a 1xx, 3xx, 4xx or 5xx is `hasError`. An envelope without a `statusCode` defaults to `200`.

`PaginatedEntity<T>` carries the page plus metadata; a paged endpoint returns `BaseEntity<PaginatedEntity<T>>`:

```dart
// platform/layers/domain/lib/src/entities/paginated_entity.dart
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

Repositories unwrap these into `Result<T>` via `execute()` — see [`02_new_domain_data.md`](02_new_domain_data.md) § 9. A `200` whose envelope reports an error is turned into a failure by `execute`'s `successCondition`, coded `ErrorCodes.RESPONSE_REJECTED`; without a `successCondition` a response that did not throw is a success.

### Show a failure to the user

`AppFailure.message` is an English diagnostic (or the server's own text) for logs and crash reports; it never reaches the screen (RULE-34). Every failure carries a stable `code` — an `ErrorCodes` value for a transport failure, the HTTP status for an error response — and the UI maps the **code** to a translated sentence with `AppLocalizations.failureMessage(int? code)` from `core_base_ui`:

```dart
// modules/home/feature/lib/src/pages/home_page.dart
error: (failure) =>
    Text(context.l10n.failureMessage(failure.code)),
```

`DioFailureClassifier` (`core_network`) is how a `DioException` becomes an `AppFailure` (`ErrorHandler.handleError`, RULE-43); the table is what the user then reads:

| What happened | Failure and `code` | `failureMessage` |
|:--|:--|:--|
| connect, send or receive timeout | `NetworkFailure`, `CONNECTION_TIMEOUT` (1003) | `connectionTimedOut` |
| response transform timeout | `NetworkFailure`, `TRANSFORM_TIMEOUT` (1008) | `connectionTimedOut` |
| no connection (`connectionError`, a `SocketException`) | `NetworkFailure`, `CONNECTION_ERROR` (1005) / `NO_INTERNET` (1001) | `noInternetConnection` |
| certificate rejected (`badCertificate`) | `NetworkFailure`, `BAD_CERTIFICATE` (1006) | `networkError` |
| an unknown Dio error caused by a TLS error or a pin mismatch | `ServerFailure`, `BAD_CERTIFICATE` (1006) — not a `NetworkFailure`, so the retry policy does not retry it | `networkError` |
| an unknown Dio error caused by a body that is not valid JSON (a `FormatException`: a maintenance page, a captive portal) | `ParseFailure`, `INVALID_FORMAT` (4001) | `somethingWentWrong` |
| other transport failure, a cancelled request, an `HttpException`, no status | `NETWORK_UNKNOWN` (1007), `REQUEST_CANCELLED` (1004), `HTTP_ERROR` (1002) | `networkError` |
| error response `5xx` | `ServerFailure`, the status | `serverUnavailable` |
| error response `401` / `403` | `AuthFailure`, the status | `somethingWentWrong` |
| any other error response, a rejected `200`, an empty body, an unclassified error, no code | the status, `RESPONSE_REJECTED` (7001), `EMPTY_RESPONSE` (7002), `UNKNOWN` (9999) | `somethingWentWrong` |

The two certificate paths are honest about what Dio reports: a certificate the platform rejects arrives as `DioExceptionType.badCertificate` and stays a `NetworkFailure`; a pin mismatch and a TLS handshake error arrive as `unknown` with the cause attached, and are classified from that cause as a `ServerFailure` — it is not retried (the same certificate will be rejected again), but the handshake failed before any request left the device, so the server gave no verdict: the sample's session gateway treats `NetworkFailure`, a certificate rejection (1006), a real 5xx and a cancelled request as transient and keeps the session. Any code from 1000 up to (not including) 2000 reads as `networkError` unless a row above names it. A feature that can say something more specific — wrong password, unknown user — classifies the failure itself and uses its own ARB (RULE-34); `failureMessage` is the fallback for everything generic. The code lives in `ErrorCodes` (`platform/foundation/kernel/lib/src/utils/error_codes.dart`): never compare against a literal.

### The sample sign-in contract

The sample `feature_auth` signs in against a REST backend that this repository does not ship. `AuthRemoteDataSource` (`modules/auth/data/lib/src/data_sources/remote/auth_remote_data_source.dart`) calls two endpoints, declared in `AuthApiConstants` (`modules/auth/data/lib/src/utils/auth_api_constants.dart`) and appended to `BASE_URL`:

| Call | Request | Response |
|:--|:--|:--|
| Sign in: `POST /user/login` | JSON body `{"email": "<email>", "password": "<password>"}` | the envelope below |
| Renew: `POST /user/refresh-token` | no body; `Authorization: Bearer <stored token>` | the same envelope |

A backend that answers the sign-in call like this lets the sample app sign in:

```json
{
  "statusCode": 200,
  "message": "ok",
  "data": {
    "id": "u_123",
    "email": "ada@example.com",
    "name": "Ada",
    "role": "customer",
    "token": "<access token>"
  }
}
```

The envelope is `BaseEntity<UserModel>` (above) and `data` is `UserModel` (`modules/auth/data/lib/src/models/user_model.dart`):

| Field | Type | What the sample does with it |
|:--|:--|:--|
| `statusCode` | int, optional (default `200`) | must be a 2xx (`isSuccess`); any other value is a rejected response even when the HTTP status is `200` |
| `message` | string, optional | a diagnostic for logs only; the user never reads it (RULE-34) |
| `data.id` | string, **required** | the user's id; a body without it does not parse |
| `data.email`, `data.name` | string, optional | copied to `UserEntity` |
| `data.role` | string, optional | `customer`, `owner` or `none`; any other spelling becomes `UserRole.unknown`; absent stays `null` |
| `data.token` | string, **required on sign-in**, optional on renewal | the session credential: `AuthRepositoryImpl` writes it to secure storage and `AuthInterceptor` sends it as `Authorization: Bearer <token>` on later requests. It never reaches `UserEntity`. Without it a sign-in is rejected; a renewal without it keeps the stored token |

The sign-in counts as a success only when the call did not fail, `statusCode` is a 2xx, `data` is present **and** `data.token` is non-empty (`AuthRepositoryImpl._authenticate`): an envelope without a token is a failure (`RESPONSE_REJECTED`) and stores nothing, because a "signed in" user with no credential could not be restored on the next start. The email is trimmed before it is sent (a trailing space from a keyboard's autocomplete would be another identity); the password is sent as typed. What the user then reads, in the sample's own wording (a toast the app shell shows from `ISessionState.sessionFailures`, not the page):

| The backend answers | Failure | The user reads |
|:--|:--|:--|
| HTTP `401` | `AuthFailure(401)` | "Invalid credentials", and the password field is cleared |
| HTTP `404` | `ServerFailure(404)` | "User not found" |
| HTTP `5xx` | `ServerFailure(status)` | "The server is unavailable right now. Please try again later." |
| HTTP `403`, any other `4xx` | `AuthFailure(403)` / `ServerFailure(status)` | "Something went wrong" |
| HTTP `200` with a `statusCode` outside 2xx, no `data`, or (on sign-in) no `data.token` | `ServerFailure(RESPONSE_REJECTED)` | "Something went wrong" |
| a body that does not parse (no `data.id`, `data` not an object) | `ServerFailure(UNKNOWN)`, also reported to `IErrorReporter` when the app registers one | "Something went wrong" |
| the host cannot be reached | `NetworkFailure(CONNECTION_ERROR)` | the retry dialog first; after **Cancel**, "No internet connection. Check your connection and try again." |
| `BASE_URL` empty (the committed `env.dev`) | `NetworkFailure(NETWORK_UNKNOWN)` | "A network error occurred. Please try again." — the path `/user/login` has no host, so the HTTP client rejects it before any connection is made |

The login call is marked `EXTRA_CAN_REFRESH_TOKEN: false`, so a `401` there is a wrong password, never an expired session (step 6). The renewal runs at app start when a token is stored, and when any other request gets a `401`. A renewal answer without a token (a backend that does not rotate it) keeps the stored token and updates the stored user data; it does not sign the user out. With no stored token the repository answers "signed out" without calling the server. A `401`, `403` or rejected body from `/user/refresh-token` ends the session and clears the stored credentials; a failure that never reached the server keeps it, and the app opens signed in as the user stored at the last sign-in (step 9).

To try the app without writing a backend, run any HTTP server that answers the sign-in call as above and set `BASE_URL` to it in `apps/mobile/env.dev` (`curl -X POST "$BASE_URL/user/login" -H 'Content-Type: application/json' -d '{"email":"ada@example.com","password":"secret1"}'` shows what the app will see). `env.dev` is committed, so put only a URL there, never a credential. The Android emulator reaches the host machine at `10.0.2.2`, not `localhost`, and this repository sets no cleartext-traffic allowance for Android, so a plain `http://` URL is blocked there until you add one — use `https://` or allow it in your app's manifest. There is no mock backend in the repository by design: the template shows the shape and leaves the transport to you. To sign in against a different API, keep `IAuthRepository`, `LoginParams` and `UserEntity` and change what sits behind them: the paths in `AuthApiConstants`, the `@JsonKey` names in `UserModel`, or the whole `AuthRemoteDataSource` ([`02_new_domain_data.md`](02_new_domain_data.md)). `modules/auth/data/test/` tests the repository against a fake data source, so those tests need no server.

## 9. Plug in token refresh

You do not wire the refresh interceptor yourself. `NetworkConfigImpl` installs it as soon as some module registers an `ISessionGateway` (in the sample, `data_auth`'s `AuthSessionGatewayImpl`, `modules/auth/data/lib/src/session/auth_session_gateway_impl.dart`). With none registered, a `401` reaches the caller unchanged.

To use your own backend, implement `ISessionGateway` (`platform/foundation/contracts/lib/src/session/i_session_gateway.dart`) in your auth data package — `readToken()`, `refreshToken()` and `clearSession()`, registered `@LazySingleton(as: ISessionGateway)`. Its `refreshToken()` must answer in one of three ways, because the answer decides what happens to the session:

| `refreshToken()` | Meaning | `RefreshTokenHandler` |
| :-- | :-- | :-- |
| a token | renewed | replays the request and every one waiting on it |
| `null` | the server **refused** (401/403, any 4xx, or a 200 whose envelope reports an error — `ErrorCodes.RESPONSE_REJECTED`) | calls `onRefreshFailed` once, rejects them all |
| throws | never got an answer (no network, a certificate or pin rejection (1006), a real HTTP 5xx, cancelled) — only these | rejects them all, **keeps the session** |

Then mark the login and refresh calls `EXTRA_CAN_REFRESH_TOKEN: false` (step 6). What happens after your answer — one refresh for N concurrent `401`s, and the three recursion guards — is in [`../architecture/02_core.md` § 6](../architecture/02_core.md#the-refresh-token-flow).

## 10. Turn on SSL pinning

> [!WARNING]
> **Pinning is a per-flavor decision of the app, and the template ships it as "off".** `apps/mobile` declares `ssl_pinning: { disabled: "TEMPLATE PLACEHOLDER: no SPKI pins provisioned …" }` for staging and prod — a stated decision, listed in the app's README under *Decisions to revisit before shipping* and logged as a `WARNING` on every Android or iOS start — so those builds accept any certificate the device trusts, including one injected by an intercepting proxy, until you replace it with pins (RULE-48). `apps/admin` declares none: none of its platforms can pin.

Get the SPKI SHA-256 hash of each key:

```sh
openssl s_client -servername <host> -connect <host>:443 </dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

Pin **at least two** distinct keys — the leaf plus a backup — so certificate rotation does not lock every installed client out of the API. The decision lives in the manifest, per flavor (RULE-48, RULE-80); nothing in `platform/` is edited:

```yaml
# apps/<id>/app_manifest.yaml
flavors:
  prod:
    ssl_pinning: { pins: ["<leaf spki sha256 base64>", "<backup spki sha256 base64>"] }
```

A flavor takes `pins: [...]` or `disabled: "<reason>"` (a reason that is not empty, `TODO` or `TBD`), never both. `dev` needs no entry: it defaults to `disabled` with the reason "development flavor: local servers use self-signed certificates". Then `dart tools/composer/composer.dart sync` generates the decision into the app's `facts` region (`AppFacts.sslPinning`, an `SslPinningPolicy`) and its README report, and `composer verify` holds it (V1 the shape — two or more distinct pins, each the base64 of 32 bytes — and V9 a decision for every flavor where a declared platform can pin, Android or iOS). There is no other pin source and nothing to register or bind: `AppInitializer.initBeforeRunApp` reads the profile, never the graph, **before** DI starts, so a pin decision cannot be lost to a missing registration and no connection the graph opens can precede it.

**The pins cover every host the process connects to, not only your API.** The pinning client is installed as the process-wide `HttpOverrides.global`, so an image CDN, a font host, a storage bucket or a third-party SDK endpoint whose certificate does not match one of the pinned keys fails its TLS handshake too. Before you declare `pins:` for a flavor, check every host the app reaches with `dart:io` (the Dio client, `Image.network`, SDKs that use `HttpClient`) and pin keys that cover them, or serve that traffic from a host you pin. A flavor that cannot do either declares `disabled` with its reason.

What the app does with the decision, in the order `initBeforeRunApp` asks:

| Build | Result |
|:--|:--|
| Web | The browser owns TLS: nothing is installed, one `INFO` line says so |
| Debug build whose declared flavor is `dev` | Certificate validation is bypassed for local servers (`WARNING`); pins never apply |
| Missing or unknown flavor | Treated as `prod` for TLS: validation stays on (`ERROR` naming the fix) |
| Desktop (Windows, macOS, Linux) | The pinning plugin has no implementation: one `INFO` line, validation by the platform |
| Android / iOS, flavor `pins` | A pinning client with exactly those hashes becomes the global `HttpOverrides` |
| Android / iOS, flavor `disabled` | `WARNING` with the declared reason, traffic is **not** pinned |
| Android / iOS, no decision | `ERROR` tagged `Security`; boot check `P04` refuses to start before it comes to this |

Where no declared platform can pin (`apps/admin`), `composer verify` refuses an `ssl_pinning` key as dead and names the ways out: declare android or ios; pin where the app connects to (a gateway or proxy that holds the pinned certificate); or add a desktop pinning implementation first. When pinning is installed, and which builds bypass it: [`../architecture/02_core.md` § 6](../architecture/02_core.md#when-pinning-is-installed-and-when-it-is-skipped).

---

## Verify

```bash
dart run build_runner build --workspace                  # Retrofit .g.dart + module.module.dart
flutter analyze                                          # No issues found!
cd platform/infra/network && flutter test                # the interceptor tests
cd platform/foundation/common && flutter test test/ssl_pinning_enforcement_test.dart  # the installed pinning client, pin matching
cd apps/mobile && flutter test test/di_smoke_test.dart   # your data source resolves; DioFailureClassifier is registered
```

Test a repository against a fake data source, as `modules/auth/data/test/` does, rather than against a live server. On a device, a debug build logs every request and response through `LoggingInterceptor` (tag `NetworkConstants.CLIENT_LOG_TAG`), with credentials redacted (headers, body keys that name a credential, URL query values; the FCM token is not logged). The pinning decision shows in the log tagged `Security`: an `ERROR` for a flavor with no decision, a `WARNING` with the declared reason for a `disabled` one.

Review checklist:

- [ ] Endpoint constants live in the owning data package's `utils/`, never in `core_common`
- [ ] Retrofit service declared, `part` added, `build_runner` run
- [ ] Requests that must not carry a token set `EXTRA_NEED_AUTHENTICATION = false`
- [ ] Login, refresh, and any call whose `401` is not "session expired" set `EXTRA_CAN_REFRESH_TOKEN = false`
- [ ] A `POST` / `PATCH` the server deduplicates (an idempotency key) sets `EXTRA_IDEMPOTENT = true`; any other is not replayed after a send or receive timeout
- [ ] `NetworkConfig` impl stays `@LazySingleton` (never eager, RULE-13)
- [ ] A failure shown to the user goes through `failureMessage(failure.code)`, never `failure.message`
- [ ] `flavors.prod.ssl_pinning` (and staging) decided in the manifest — ≥2 pins, or `disabled` with a reason — before shipping
- [ ] `composer verify` is clean (V9 holds the pin decision) and `cd platform/foundation/common && flutter test test/pin_policy_matrix_test.dart` passes
- [ ] Every host the app reaches over `dart:io` (CDN, storage, SDKs) is covered by the pinned keys before a flavor declares `pins:`
- [ ] No credential ever logged verbatim

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `… is not registered` for the data source at boot | The Retrofit class has no `@module` registration, or codegen is stale | Register it (step 4), then `build_runner` (step 5) |
| Every request fails at once with a connection error | `BASE_URL` is empty in the flavor's env file | Set `BASE_URL` in `apps/mobile/env.<flavor>` |
| The app hangs after a `401` on login or refresh | The call lacks `EXTRA_CAN_REFRESH_TOKEN: false`, so the refresh waits on itself | Add the `@Extra` (steps 3 and 6) |
| A `401` reaches the UI although the backend supports refresh | No `ISessionGateway` is registered, so no refresh interceptor is installed | Implement and register one (step 9) |
| The user is signed out after a network blip | `refreshToken()` returned `null` for a transient error | Throw for "no answer" and return `null` only for a refusal (step 9) |
| The server ignores the locale | It reads `Accept-Language`; the client sends the non-standard `language` header, the upper-cased code of a language the app offers | Read `language` on the server |
| The UI shows "Something went wrong" for an error you expected to be specific | `failureMessage` maps only the generic codes; the status or `ErrorCodes` value is not one it names | Classify the failure in the feature and use its own ARB (step 8) |
| `ERROR` log: `SSL pinning has no decision for flavor …` (or boot stops with `P04`) | The flavor has no `ssl_pinning` entry in the manifest, and the platform can pin | Declare `pins:` or `disabled` with a reason under `flavors.<f>.ssl_pinning` and run `composer sync` (step 10); V9 refuses it at Gate 0 first |
| `WARNING` log: `SSL pinning is disabled for flavor …` | The flavor's decision is `disabled` — the declared reason is in the log | Declare `pins:` (step 10) when the flavor should pin |
| `composer verify`: `no declared platform can pin TLS … delete it` | The app declares only web and desktop platforms, which cannot pin | Delete the key, or take one of the three ways out it lists (step 10) |
| `INFO` log: `Web build: the browser validates TLS certificates …` or `SSL pinning is not applicable on <platform> …` | Pinning cannot apply on that platform | Nothing to fix; the decision is only read on Android and iOS |
| Every request fails on a pinned flavor after the server's certificate changed | Neither pinned hash is the new key's | Hash the live host again and ship a release pinning the new leaf and a backup (step 10) |
| Images, fonts or an SDK fail with a TLS error on a flavor that declares `pins:` | The pins apply to every host the process connects to, and that host's certificate matches none of them | Pin keys that cover it, serve it from a pinned host, or declare the flavor `disabled` with a reason (step 10) |
| A `POST` times out and no retry dialog appears | A timed-out `POST` / `PATCH` is not replayed — the server may have processed it | If the server deduplicates it, set `EXTRA_IDEMPOTENT: true` (step 6); otherwise let the user retry deliberately |
| A request to a CDN or presigned URL carries no `Authorization` | The token goes only to the `BASE_URL` host and `NetworkProfile.authorizedHosts` | Add the host to `authorizedHosts` if it is your API (step 6) — never for a third party |
| Two packages register the same named client and boot throws | A name can be registered once per container | Move the registration into `platform/infra/network/lib/di/network_module.dart` (step 7) |

## Related

- Rules: RULE-09 (endpoints in `utils/`), RULE-34 (user-facing strings translated), RULE-41 (data sources return models), RULE-42 (`execute()` and no throw to UI), RULE-43 (`ErrorHandler`), RULE-48 (pinning), RULE-63 (DI smoke test), RULE-66 (never log secrets), RULE-74 (versions), RULE-80 (per-app decisions) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 6](../architecture/02_core.md#6-core_network--http-client) — the client's internals
- [`02_new_domain_data.md`](02_new_domain_data.md) — repository and `Result<T>` mapping
- [`05_di.md`](05_di.md) — registration order and the eager-singleton trap
- [`06_storage.md`](06_storage.md) — where the token is persisted
