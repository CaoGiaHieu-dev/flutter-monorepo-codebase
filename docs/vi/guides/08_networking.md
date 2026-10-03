<!-- translated-from: docs/en/guides/08_networking.md@9a3fb93 -->
# Hướng dẫn: Networking

## Mục tiêu

Bạn gọi được một endpoint HTTP mới từ một package data. Bạn khai service bằng Retrofit, đăng ký nó, và bóc response thành `Result`. Bạn cũng học cách cho một request riêng lẻ bỏ qua auth, refresh hay retry, thêm client thứ hai với luật riêng, cắm luồng refresh token, và bật certificate pinning.

## Điều kiện cần

- Một package data — [`02_new_domain_data.md`](02_new_domain_data.md).
- **Chuyện gì diễn ra bên trong client**: chuỗi interceptor và thứ tự của nó, `NetworkConfig` được cung cấp thế nào, luồng refresh token cùng các lớp chống đệ quy, và pinning được cài lúc nào — [`../architecture/02_core.md` § 6](../architecture/02_core.md#6-core_network--http-client).
- Base URL của endpoint trong file env của flavor (`BASE_URL` trong `apps/mobile/env.dev`, …) — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 1. Thêm dependency cho networking

Khai chúng trong `pubspec.yaml` của package data, như `modules/auth/data/pubspec.yaml`. Hãy viết các mục bên thứ ba không kèm version: chúng chỉ nằm trong catalog `pubspec_dependencies.yaml` (RULE-74), và `dart tools/dependency_sync.dart` điền vào mục còn trống.

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

Bản thân `core_network` phụ thuộc `dio` nhưng không phụ thuộc `retrofit`: annotation và generator của Retrofit thuộc về package khai service. Thêm `json_annotation` / `json_serializable` (và `freezed_annotation` / `freezed`) khi model cũng được sinh code. Chạy `dart tools/dependency_sync.dart`, rồi `flutter pub get`.

## 2. Đặt endpoint trong package sở hữu

```dart
// modules/auth/data/lib/src/utils/auth_api_constants.dart
class AuthApiConstants {
  AuthApiConstants._();

  static const String LOGIN = '/user/login';
  static const String REFRESH_TOKEN = '/user/refresh-token';
}
```

Hằng số endpoint nằm cùng package sở hữu chúng, không bao giờ ở `core_common` — đúng luật sở hữu như với storage key (RULE-09). Một file endpoint dùng chung sẽ cho phép mọi tầng đọc, và gõ nhầm, route của package khác.

## 3. Khai service Retrofit

Khai abstract class kèm `part '<file>.g.dart';`:

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

`@Extra` đặt cờ theo từng request mà interceptor đọc (`NetworkConstants` trong `core_network`). `EXTRA_CAN_REFRESH_TOKEN: false` để `401` không kích hoạt refresh token; `EXTRA_CAN_RETRY: false` để timeout không bật dialog retry. Cả hai mặc định là `true` khi không khai (bước 6).

> [!IMPORTANT]
> `AuthRemoteDataSource` **chính là** đường chạy thật: `AuthRepositoryImpl` gọi nó cho login và refresh token, bọc trong `execute()` (RULE-42). Hãy trỏ `AuthApiConstants` vào endpoint thật của bạn, hoặc đổi transport (Firebase, GraphQL) bên trong repository và giữ nguyên hình dạng.

## 4. Đăng ký service qua một `@module`

Lớp Retrofit là một factory constructor, không phải lớp `@injectable`, nên phải đi qua một `@module` trong `lib/di/module.dart` của package, cạnh marker `@InjectableInit.microPackage()`. Bản thật:

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

`Dio` nó nhận là client mặc định của `core_network` — do `NetworkModule` đăng ký (`platform/infra/network/lib/di/network_module.dart`) và đã mang sẵn toàn bộ chuỗi interceptor. Muốn dùng một client có tên (bước 7) thì đặt tên cho tham số:

```dart
@lazySingleton
CatalogRemoteDataSource catalogRemoteDataSource(
  @Named('public_api') Dio dio,
) => CatalogRemoteDataSource(dio);
```

Thiếu `@lazySingleton`, repository inject data source này sẽ hỏng lúc boot với *"… is not registered"*. `flutter analyze` không thấy được lỗi đó: smoke test DI của app thì thấy (RULE-63, [`05_di.md`](05_di.md#8-chẩn-đoán-lỗi-not-registered-lúc-khởi-động)).

## 5. Sinh code

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<module>/data/lib
```

`build_runner` viết `.g.dart` của Retrofit và `module.module.dart` của package. Sau đó barrel generator export các file mới (RULE-75); chỉ cần chạy nó khi một file dưới `lib/` được thêm, đổi tên hay xoá.

## 6. Cho một request riêng bỏ qua auth, refresh hay retry

Cả ba cờ nằm trong `RequestOptions.extra` và mặc định là `true`:

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

| Đặt `false` cho… | Cờ |
|:--|:--|
| Request không được mang token | `EXTRA_NEED_AUTHENTICATION` |
| Login, refresh, và mọi call có `401` không mang nghĩa "hết phiên" | `EXTRA_CAN_REFRESH_TOKEN` |
| Call phải fail nhanh thay vì chờ dialog retry | `EXTRA_CAN_RETRY` |

Với Retrofit, đặt chúng bằng `@Extra({...})`, như bước 3. Vì sao login và refresh cần `EXTRA_CAN_REFRESH_TOKEN: false`: thiếu nó, một `401` từ lời gọi refresh sẽ chờ chính lần refresh đang chờ nó ([`../architecture/02_core.md` § 6](../architecture/02_core.md#ba-lớp-chống-đệ-quy-vô-hạn)).

Hai header đến từ `AuthInterceptor`, không phải từ profile. `Authorization: Bearer <token>` được gắn khi chủ phiên có token, trừ khi request đặt `EXTRA_NEED_AUTHENTICATION: false`. `language` mang mã viết hoa (`EN`, `VI`) của ngôn ngữ mà **app** đã resolve: `NetworkConfigImpl.getLocale` lấy `ILanguageStorage.getLanguage()` — lựa chọn đã lưu, nếu không có thì ngôn ngữ `initial` của profile, nếu không nữa thì ngôn ngữ của thiết bị — và resolve nó qua `LanguageSet` của app (tập mà `LanguageProvider` dùng; `AppLanguages` là cùng thứ đó dựng cho các mặc định của template), nên server chỉ bao giờ thấy một ngôn ngữ mà app có cung cấp. Khi không có mã nào được resolve, interceptor gửi `LocaleProfile.fallback` của profile (mặc định `en`). Tên header là `language` không chuẩn, không phải `Accept-Language`.

## 7. Thêm client thứ hai với luật riêng

`core_network` đăng ký đúng một client — `Dio` mặc định mà mọi Retrofit data source nhận được:

```dart
// platform/infra/network/lib/di/network_module.dart
@module
abstract class NetworkModule {
  @lazySingleton
  Dio dio(ApiClient apiClient) => apiClient.createClient();
}
```

`createClient()` nhận các tham số sau:

| Tham số | Tác dụng |
|---|---|
| `baseUrl` | Ghi đè `EnvConstants.BASE_URL` cho client này |
| `interceptors` | Interceptor bổ sung, gắn **sau** bộ mặc định |
| `useDefaultInterceptors` | `false` sẽ bỏ qua toàn bộ chuỗi mặc định — dùng cho client public/không cần auth |
| `options` | Thay thế hoàn toàn `_defaultOptions` (được `copyWith` nên không làm hỏng state dùng chung) |

Thứ `_defaultOptions` chứa là việc của **app** đặt: timeout connect, receive và send (mỗi loại 20 giây), header thêm và chính sách redirect đến từ `NetworkProfile` của nó (`network:` trong `apps/<id>/lib/app/app_profile.dart`), được đăng ký trước khi graph dựng, nên `Dio` mặc định mang chúng. Một header làm hỏng interceptor auth hoặc làm lộ credential — `authorization`, `cookie`, `set-cookie`, `proxy-authorization`, `content-type` — làm `ApiClient` ném lỗi khi nó được dựng — smoke test DI dựng mọi lazy singleton, nên nó fail ở đó (RULE-66). Base URL vẫn là một define của env (`BASE_URL`, theo từng flavor), và base URL thứ hai là `createClient(baseUrl:)`.

Client thứ hai với luật riêng được đăng ký theo cùng cách, dưới một **tên**, để không thay thế client mặc định. Trong repo không có gì đăng ký nó. Đây là khuôn để chép — ví dụ một API public không có header auth, không refresh, không dialog retry:

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

`getIt<Dio>()` và mọi tham số `Dio` không đặt tên vẫn nhận client mặc định. Chỉ tham số gắn `@Named('public_api')` mới nhận client này (bước 4). Mỗi tên chỉ đăng ký được **một lần** trong container: nếu package thứ hai cũng cần client đó, hãy chuyển phần đăng ký vào `platform/infra/network/lib/di/network_module.dart` thay vì khai hai lần.

## 8. Bóc các lớp bao response

`BaseEntity<T>` bao một response chuẩn của server:

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

`PaginatedEntity<T>` mang theo trang dữ liệu cộng metadata; một endpoint phân trang trả về `BaseEntity<PaginatedEntity<T>>`:

```dart
// platform/layers/domain/lib/src/entities/paginated_entity.dart
const factory PaginatedEntity({
  @JsonKey(name: 'items') @Default([]) List<T> data,
  @JsonKey(name: 'meta') @Default(MetaPaginate()) MetaPaginate meta,
}) = _PaginatedEntity<T>;
```

`MetaPaginate` chứa `totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`.

`BaseRequest<T>` là bộ dựng request phân trang:

```dart
// platform/layers/data/lib/src/models/base_request.dart
const factory BaseRequest({
  @JsonKey(name: 'page') @Default(1) int page,
  @JsonKey(name: 'pageSize') @Default(25) int pageSize,
  @JsonKey(name: 'data') T? data,
}) = _BaseRequest<T>;
```

Repository bóc các lớp bao này thành `Result<T>` qua `execute()` — xem [`02_new_domain_data.md`](02_new_domain_data.md) § 9. Một `200` mà envelope báo lỗi được `successCondition` của `execute` biến thành failure, mang mã `ErrorCodes.RESPONSE_REJECTED`; không có `successCondition` thì response nào không ném lỗi đều là thành công.

### Hiển thị lỗi cho người dùng

`AppFailure.message` là chẩn đoán bằng tiếng Anh (hoặc chính văn bản của server) dành cho log và báo cáo crash; nó không bao giờ lên màn hình (RULE-34). Mọi failure đều mang một `code` ổn định — giá trị `ErrorCodes` cho lỗi transport, HTTP status cho response lỗi — và UI ánh xạ **code** sang một câu đã dịch bằng `AppLocalizations.failureMessage(int? code)` của `core_base_ui`:

```dart
// modules/home/feature/lib/src/pages/home_page.dart
error: (failure) =>
    Text(context.l10n.failureMessage(failure.code)),
```

`DioFailureClassifier` (`core_network`) là cách một `DioException` trở thành `AppFailure` (`ErrorHandler.handleError`, RULE-43); bảng dưới là thứ người dùng đọc được:

| Chuyện gì xảy ra | Failure và `code` | `failureMessage` |
|:--|:--|:--|
| timeout khi connect, send hoặc receive | `NetworkFailure`, `CONNECTION_TIMEOUT` (1003) | `connectionTimedOut` |
| timeout khi transform response | `NetworkFailure`, `TRANSFORM_TIMEOUT` (1008) | `connectionTimedOut` |
| không có kết nối (`connectionError`, một `SocketException`) | `NetworkFailure`, `CONNECTION_ERROR` (1005) / `NO_INTERNET` (1001) | `noInternetConnection` |
| certificate bị từ chối | `NetworkFailure`, `BAD_CERTIFICATE` (1006) | `networkError` |
| lỗi transport khác, request bị huỷ, một `HttpException`, không có status | `NETWORK_UNKNOWN` (1007), `REQUEST_CANCELLED` (1004), `HTTP_ERROR` (1002) | `networkError` |
| response lỗi `5xx` | `ServerFailure`, chính status đó | `serverUnavailable` |
| response lỗi `401` / `403` | `AuthFailure`, chính status đó | `somethingWentWrong` |
| mọi response lỗi khác, một `200` bị từ chối, body rỗng, lỗi không phân loại được, không có code | chính status đó, `RESPONSE_REJECTED` (7001), `EMPTY_RESPONSE` (7002), `UNKNOWN` (9999) | `somethingWentWrong` |

Mọi code từ 1000 tới dưới 2000 đều đọc ra là `networkError` trừ khi một dòng ở trên nêu tên nó. Một feature có thể nói điều cụ thể hơn — sai mật khẩu, không có người dùng — thì tự phân loại failure và dùng ARB của riêng nó (RULE-34); `failureMessage` là phương án dự phòng cho mọi thứ chung chung. Mã nằm trong `ErrorCodes` (`platform/foundation/kernel/lib/src/utils/error_codes.dart`): không bao giờ so với một literal.

## 9. Cắm luồng refresh token

Bạn không tự nối interceptor refresh. `NetworkConfigImpl` cài nó ngay khi có module đăng ký một `ISessionGateway` (ở sample là `AuthSessionGatewayImpl` của `data_auth`, `modules/auth/data/lib/src/session/auth_session_gateway_impl.dart`). Không có gateway nào thì `401` tới thẳng bên gọi, nguyên vẹn.

Để dùng backend của riêng bạn, hãy implement `ISessionGateway` (`platform/foundation/contracts/lib/src/session/i_session_gateway.dart`) trong package data auth của bạn — `readToken()`, `refreshToken()` và `clearSession()`, đăng ký bằng `@LazySingleton(as: ISessionGateway)`. `refreshToken()` của nó phải trả lời theo một trong ba cách, vì câu trả lời quyết định số phận của phiên:

| `refreshToken()` | Nghĩa là | `RefreshTokenHandler` |
| :-- | :-- | :-- |
| một token | đã gia hạn | gửi lại request và mọi request đang chờ nó |
| `null` | server **từ chối** (401/403, mọi 4xx, hoặc một 200 mà envelope báo lỗi — `ErrorCodes.RESPONSE_REJECTED`) | gọi `onRefreshFailed` một lần, reject tất cả |
| ném lỗi | không nhận được câu trả lời (mất mạng, HTTP 5xx thật, bị huỷ) — chỉ những trường hợp này | reject tất cả, **giữ nguyên phiên** |

Sau đó đánh dấu lời gọi login và refresh bằng `EXTRA_CAN_REFRESH_TOKEN: false` (bước 6). Chuyện gì xảy ra sau câu trả lời của bạn — một lần refresh cho N request `401` đồng thời, và ba lớp chống đệ quy — nằm ở [`../architecture/02_core.md` § 6](../architecture/02_core.md#luồng-refresh-token).

## 10. Bật SSL pinning

> [!WARNING]
> **Pinning là quyết định theo từng flavor của app, và template giao nó ở trạng thái "tắt".** `apps/mobile` khai `ssl_pinning: { disabled: "TEMPLATE PLACEHOLDER: no SPKI pins provisioned …" }` cho staging và prod — một quyết định được nêu rõ, được liệt kê trong README của app ở mục *Decisions to revisit before shipping* và được log `WARNING` ở mỗi lần khởi động trên Android hay iOS — nên các bản build đó chấp nhận mọi certificate mà thiết bị tin tưởng, kể cả cert do proxy chèn vào, cho tới khi bạn thay nó bằng pin thật (RULE-48). `apps/admin` không khai gì: không platform nào của nó pin được.

Lấy hash SPKI SHA-256 của từng key:

```sh
openssl s_client -servername <host> -connect <host>:443 </dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

Pin **ít nhất hai** key khác nhau — leaf cộng một key dự phòng — để khi xoay vòng certificate không khoá chết toàn bộ client đã cài. Quyết định nằm trong manifest, theo từng flavor (RULE-48, RULE-80); không sửa gì dưới `platform/`:

```yaml
# apps/<id>/app_manifest.yaml
flavors:
  prod:
    ssl_pinning: { pins: ["<leaf spki sha256 base64>", "<backup spki sha256 base64>"] }
```

Một flavor nhận `pins: [...]` hoặc `disabled: "<reason>"` (lý do không rỗng, không phải `TODO` hay `TBD`), không bao giờ cả hai. `dev` không cần mục nào: nó mặc định là `disabled` với lý do "development flavor: local servers use self-signed certificates". Sau đó `dart tools/composer/composer.dart sync` sinh quyết định vào vùng `facts` của app (`AppFacts.sslPinning`, một `SslPinningPolicy`) và báo cáo trong README, và `composer verify` giữ nó (V1 hình dạng — từ hai pin khác nhau trở lên, mỗi pin là base64 của 32 byte — và V9 một quyết định cho mọi flavor ở nơi một platform đã khai báo pin được, Android hoặc iOS). Không có nguồn pin nào khác và không có gì để đăng ký hay bind: `AppInitializer.initBeforeRunApp` đọc profile, không bao giờ đọc đồ thị, **trước** khi DI bắt đầu, nên một quyết định pin không thể mất vì thiếu đăng ký và không kết nối nào do đồ thị mở ra có thể đi trước nó.

App làm gì với quyết định đó, theo đúng thứ tự `initBeforeRunApp` xét:

| Bản build | Kết quả |
|:--|:--|
| Web | Trình duyệt sở hữu TLS: không cài gì, một dòng `INFO` nói rõ điều đó |
| Bản debug có flavor khai báo là `dev` | Việc kiểm tra certificate bị bỏ qua cho server local (`WARNING`); pin không bao giờ áp dụng |
| Flavor thiếu hoặc không biết | Coi là `prod` cho TLS: việc kiểm tra vẫn bật (`ERROR` nêu cách sửa) |
| Desktop (Windows, macOS, Linux) | Plugin pinning không có implementation: một dòng `INFO`, nền tảng tự kiểm tra |
| Android / iOS, flavor `pins` | Một client pinning với đúng các hash đó trở thành `HttpOverrides` toàn cục |
| Android / iOS, flavor `disabled` | `WARNING` kèm lý do đã khai, traffic **không** được pin |
| Android / iOS, không có quyết định | `ERROR` gắn tag `Security`; kiểm tra boot `P04` từ chối khởi động trước khi tới bước này |

Ở nơi không platform nào đã khai báo pin được (`apps/admin`), `composer verify` từ chối key `ssl_pinning` vì vô dụng và nêu các lối thoát: khai báo android hoặc ios; pin ở nơi app kết nối tới (một gateway hay proxy giữ certificate được pin); hoặc thêm implementation pinning cho desktop trước. Pinning được cài lúc nào, và bản build nào bỏ qua nó: [`../architecture/02_core.md` § 6](../architecture/02_core.md#pinning-được-cài-lúc-nào-và-khi-nào-bị-bỏ-qua).

---

## Kiểm tra

```bash
dart run build_runner build --workspace                  # .g.dart của Retrofit + module.module.dart
flutter analyze                                          # No issues found!
cd platform/infra/network && flutter test                # các test của interceptor
cd apps/mobile && flutter test test/di_smoke_test.dart   # data source của bạn resolve được; DioFailureClassifier đã đăng ký
```

Hãy test repository với một data source giả, như `modules/auth/data/test/` làm, thay vì với server thật. Trên thiết bị, bản debug log mọi request và response qua `LoggingInterceptor` (tag `NetworkConstants.CLIENT_LOG_TAG`), với thông tin đăng nhập đã được che. Quyết định pin hiện trong log gắn tag `Security`: một dòng `ERROR` cho flavor chưa có quyết định, một dòng `WARNING` kèm lý do đã khai cho flavor `disabled`.

Checklist review:

- [ ] Hằng số endpoint nằm trong `utils/` của package data sở hữu, không ở `core_common`
- [ ] Đã khai Retrofit service, thêm `part`, chạy `build_runner`
- [ ] Request không được mang token thì set `EXTRA_NEED_AUTHENTICATION = false`
- [ ] Login, refresh, và mọi call có `401` không mang nghĩa "hết phiên" thì set `EXTRA_CAN_REFRESH_TOKEN = false`
- [ ] Impl `NetworkConfig` giữ `@LazySingleton` (không bao giờ eager, RULE-13)
- [ ] Lỗi hiển thị cho người dùng đi qua `failureMessage(failure.code)`, không bao giờ `failure.message`
- [ ] `flavors.prod.ssl_pinning` (và staging) đã được quyết định trong manifest — ≥2 pin, hoặc `disabled` kèm lý do — trước khi phát hành
- [ ] `composer verify` sạch (V9 giữ quyết định pin) và `cd platform/foundation/common && flutter test test/pin_policy_matrix_test.dart` pass
- [ ] Không log nguyên văn bất kỳ thông tin đăng nhập nào

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `… is not registered` cho data source lúc boot | Lớp Retrofit chưa được đăng ký qua `@module`, hoặc code sinh ra đã cũ | Đăng ký nó (bước 4), rồi chạy `build_runner` (bước 5) |
| Mọi request fail ngay với lỗi kết nối | `BASE_URL` trống trong file env của flavor | Điền `BASE_URL` trong `apps/mobile/env.<flavor>` |
| App treo sau một `401` ở login hay refresh | Lời gọi thiếu `EXTRA_CAN_REFRESH_TOKEN: false`, nên refresh chờ chính nó | Thêm `@Extra` (bước 3 và 6) |
| `401` tới UI dù backend hỗ trợ refresh | Chưa có `ISessionGateway` nào được đăng ký, nên không có interceptor refresh | Implement và đăng ký một gateway (bước 9) |
| Người dùng bị đăng xuất sau một lần mạng chập chờn | `refreshToken()` trả `null` cho một lỗi tạm thời | Ném lỗi khi "không có câu trả lời", chỉ trả `null` khi bị từ chối (bước 9) |
| Server không nhận locale | Server đọc `Accept-Language`; client gửi header không chuẩn `language`, mã viết hoa của một ngôn ngữ mà app có cung cấp | Đọc header `language` ở phía server |
| UI hiện "Something went wrong" cho một lỗi bạn mong là cụ thể | `failureMessage` chỉ ánh xạ các code chung; status hay giá trị `ErrorCodes` đó không nằm trong số nó nêu tên | Phân loại failure trong feature và dùng ARB của riêng nó (bước 8) |
| Log `ERROR`: `SSL pinning has no decision for flavor …` (hoặc boot dừng với `P04`) | Flavor chưa có mục `ssl_pinning` trong manifest, và platform pin được | Khai `pins:` hoặc `disabled` kèm lý do dưới `flavors.<f>.ssl_pinning` rồi chạy `composer sync` (bước 10); V9 từ chối nó ở Gate 0 trước |
| Log `WARNING`: `SSL pinning is disabled for flavor …` | Quyết định của flavor là `disabled` — lý do đã khai nằm trong log | Khai `pins:` (bước 10) khi flavor cần pin |
| `composer verify`: `no declared platform can pin TLS … delete it` | App chỉ khai báo platform web và desktop, những nơi không pin được | Xoá key, hoặc đi theo một trong ba lối thoát mà thông báo liệt kê (bước 10) |
| Log `INFO`: `Web build: the browser validates TLS certificates …` hoặc `SSL pinning is not applicable on <platform> …` | Pinning không thể áp dụng trên platform đó | Không có gì phải sửa; quyết định chỉ được đọc trên Android và iOS |
| Mọi request fail trên một flavor đã pin sau khi certificate của server đổi | Không hash nào được pin là hash của key mới | Hash lại host đang chạy và phát hành một bản pin leaf mới cùng một key dự phòng (bước 10) |
| Hai package đăng ký cùng một client có tên và boot ném lỗi | Mỗi tên chỉ đăng ký được một lần trong container | Chuyển phần đăng ký vào `platform/infra/network/lib/di/network_module.dart` (bước 7) |

## Liên quan

- Luật: RULE-09 (endpoint trong `utils/`), RULE-34 (chuỗi hiển thị cho người dùng được dịch), RULE-41 (data source trả model), RULE-42 (`execute()` và không ném lỗi lên UI), RULE-43 (`ErrorHandler`), RULE-48 (pinning), RULE-63 (smoke test DI), RULE-66 (không log bí mật), RULE-74 (version), RULE-80 (quyết định theo từng app) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 6](../architecture/02_core.md#6-core_network--http-client) — bên trong client
- [`02_new_domain_data.md`](02_new_domain_data.md) — repository và cách map `Result<T>`
- [`05_di.md`](05_di.md) — thứ tự đăng ký và bẫy eager singleton
- [`06_storage.md`](06_storage.md) — nơi token được lưu
