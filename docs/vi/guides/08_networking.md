<!-- translated-from: docs/en/guides/08_networking.md@b65f8b3 -->
# Hướng dẫn: Networking

## Mục tiêu

Bạn gọi được một endpoint HTTP mới từ một package data. Bạn khai service bằng Retrofit, đăng ký nó, và bóc response thành `Result`. Bạn cũng học cách cho một request riêng lẻ bỏ qua auth, refresh hay retry, thêm client thứ hai với luật riêng, cắm luồng refresh token, và bật certificate pinning.

## Điều kiện cần

- Một package data — [`02_new_domain_data.md`](02_new_domain_data.md).
- **Chuyện gì diễn ra bên trong client**: chuỗi interceptor và thứ tự của nó, `NetworkConfig` được cung cấp thế nào, luồng refresh token cùng các lớp chống đệ quy, và pinning được cài lúc nào — [`../architecture/02_core.md` § 6](../architecture/02_core.md#6-core_network--http-client).
- Base URL của endpoint trong file env của flavor (`BASE_URL` trong `apps/mobile/env.dev`, …) — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 1. Thêm dependency cho networking

Khai chúng trong `pubspec.yaml` của package data, như `modules/auth/data/pubspec.yaml`. Version lấy từ catalog `pubspec_dependencies.yaml`; sửa xong, `dart tools/dependency_sync.dart` sẽ đồng bộ (RULE-74):

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

Thêm `json_annotation` / `json_serializable` (và `freezed_annotation` / `freezed`) khi model cũng được sinh code. Chạy `flutter pub get`.

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
  /// … (fails fast: no refresh, no retry dialog)
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
> `AuthRemoteDataSource` **chính là** đường chạy thật: `AuthRepositoryImpl` gọi nó cho login và refresh token, qua `execute()`. Hãy trỏ `AuthApiConstants` vào endpoint thật của bạn, hoặc đổi transport (Firebase, GraphQL) bên trong repository và giữ nguyên hình dạng.

## 4. Đăng ký service qua một `@module`

Lớp Retrofit là một factory constructor, không phải lớp `@injectable`, nên phải đi qua một `@module` trong `lib/di/register_module.dart` của package. Bản thật:

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

`Dio` nó nhận là client mặc định của `core_network`, đã mang sẵn toàn bộ chuỗi interceptor. Muốn dùng một client có tên (bước 7) thì đặt tên cho tham số:

   ```dart
   @lazySingleton
   CatalogRemoteDataSource catalogRemoteDataSource(
     @Named('public_api') Dio dio,
   ) => CatalogRemoteDataSource(dio);
   ```

Thiếu `@lazySingleton`, repository inject data source này sẽ hỏng lúc boot với *"… is not registered"*. `flutter analyze` không thấy được lỗi đó (RULE-77).

## 5. Sinh code

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<module>/data/lib
```

`build_runner` viết `.g.dart` của Retrofit và `module.module.dart` của package. Sau đó barrel generator export các file mới (RULE-75).

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

## 7. Thêm client thứ hai với luật riêng

`core_network` đăng ký đúng một client — `Dio` mặc định mà mọi Retrofit data source nhận được:

```dart
// platform/infra/network/lib/di/register_module.dart
@module
abstract class RegisterModule {
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

Client thứ hai với luật riêng được đăng ký theo cùng cách, dưới một **tên**, để không thay thế client mặc định. Trong repo không có gì đăng ký nó. Đây là khuôn để chép — ví dụ một API public không có header auth, không refresh, không dialog retry:

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

`getIt<Dio>()` và mọi tham số `Dio` không đặt tên vẫn nhận client mặc định. Chỉ tham số gắn `@Named('public_api')` mới nhận client này (bước 4). Mỗi tên chỉ đăng ký được **một lần** trong container: nếu package thứ hai cũng cần client đó, hãy chuyển phần đăng ký vào `platform/infra/network/lib/di/register_module.dart` thay vì khai hai lần.

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

`PaginatedEntity<T>` mang theo trang dữ liệu cộng metadata:

```dart
// platform/layers/domain/lib/src/entities/paginated_entity.dart
typedef BaseEntityPaginate<T> = BaseEntity<PaginatedEntity<T>>;

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

Repository bóc các lớp bao này thành `Result<T>` qua `execute()` — xem [`02_new_domain_data.md`](02_new_domain_data.md) § 9.

## 9. Cắm luồng refresh token

Bạn không tự nối interceptor refresh. `NetworkConfigImpl` cài nó ngay khi có module đăng ký một `ISessionGateway` (ở sample là `AuthSessionGatewayImpl` của `data_auth`, `modules/auth/data/lib/src/services/auth_session_gateway_impl.dart`). Không có gateway nào thì `401` tới thẳng bên gọi, nguyên vẹn.

Để dùng backend của riêng bạn, hãy implement `ISessionGateway` (`platform/foundation/contracts/lib/src/session/i_session_gateway.dart`) trong package data auth của bạn. `refreshToken()` của nó phải trả lời theo một trong ba cách, vì câu trả lời quyết định số phận của phiên:

| `refreshToken()` | Nghĩa là | `RefreshTokenHandler` |
| :-- | :-- | :-- |
| một token | đã gia hạn | gửi lại request và mọi request đang chờ nó |
| `null` | server **từ chối** (401/403, mọi 4xx, hoặc một 200 mà envelope báo lỗi — `ErrorCodes.RESPONSE_REJECTED`) | gọi `onRefreshFailed` một lần, reject tất cả |
| ném lỗi | không nhận được câu trả lời (mất mạng, HTTP 5xx thật, bị huỷ) — chỉ những trường hợp này | reject tất cả, **giữ nguyên phiên** |

Sau đó đánh dấu lời gọi login và refresh bằng `EXTRA_CAN_REFRESH_TOKEN: false` (bước 6). Chuyện gì xảy ra sau câu trả lời của bạn — một lần refresh cho N request `401` đồng thời, và ba lớp chống đệ quy — nằm ở [`../architecture/02_core.md` § 6](../architecture/02_core.md#luồng-refresh-token).

## 10. Bật SSL pinning

> [!WARNING]
> **Pinning hiện đang TẮT.** `sslPinningHashes` trả về `const []`, và list rỗng nghĩa là pinning bị vô hiệu hoá hoàn toàn. Chừng nào chưa điền vào, app chấp nhận **mọi** certificate mà thiết bị tin tưởng — kể cả cert do proxy chèn vào.

Lấy hash SPKI SHA-256 của từng key:

```sh
openssl s_client -servername <host> -connect <host>:443 </dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

Pin **ít nhất hai** key — leaf cộng một key dự phòng — để khi xoay vòng certificate không khoá chết toàn bộ client đã cài. Trả chúng về từ `sslPinningHashes` trong `platform/shell/adapters/lib/src/network_config_impl.dart` (RULE-48).

Pinning còn cần `SslPinningConfig` được bind riêng, việc mà `platform/shell/adapters/lib/di/network_binding_module.dart` đã làm (RULE-14). Hãy giữ binding đó: thiếu nó, pinning bị bỏ qua trên mọi flavor, kể cả production ([`../architecture/06_app_shell.md` § 4](../architecture/06_app_shell.md#vì-sao-sslpinningconfig-cần-binding-riêng)). Pinning được cài lúc nào, và bản build nào bỏ qua nó: [`../architecture/02_core.md` § 6](../architecture/02_core.md#pinning-được-cài-lúc-nào-và-khi-nào-bị-bỏ-qua).

---

## Kiểm tra

```bash
dart run build_runner build --workspace                  # .g.dart của Retrofit + module.module.dart
flutter analyze                                          # No issues found!
cd platform/infra/network && flutter test                # các test của interceptor
cd apps/mobile && flutter test test/di_smoke_test.dart   # data source của bạn resolve được; DioFailureClassifier đã đăng ký
```

Hãy test repository với một data source giả, như `modules/auth/data/test/` làm, thay vì với server thật. Trên thiết bị, bản debug log mọi request và response qua `LoggingInterceptor` (tag `NetworkConstants.CLIENT_LOG_TAG`), với thông tin đăng nhập đã được che. Khi pinning tắt hoặc chưa đăng ký, log hiện một dòng `ERROR` gắn tag `Security`.

Checklist review:

- [ ] Hằng số endpoint nằm trong `utils/` của package data sở hữu, không ở `core_common`
- [ ] Đã khai Retrofit service, thêm `part`, chạy `build_runner`
- [ ] Request không được mang token thì set `EXTRA_NEED_AUTHENTICATION = false`
- [ ] Login, refresh, và mọi call có `401` không mang nghĩa "hết phiên" thì set `EXTRA_CAN_REFRESH_TOKEN = false`
- [ ] Impl `NetworkConfig` giữ `@LazySingleton` (không bao giờ eager)
- [ ] `sslPinningHashes` đã điền ≥2 pin trước khi phát hành
- [ ] `SslPinningConfig` được bind tường minh trong `@module` — kiểm tra file sinh ra `lib/di/module.module.dart` của `platform_shell_adapters`
- [ ] Không log nguyên văn bất kỳ thông tin đăng nhập nào

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `… is not registered` cho data source lúc boot | Lớp Retrofit chưa được đăng ký qua `@module`, hoặc code sinh ra đã cũ | Đăng ký nó (bước 4), rồi chạy `build_runner` (bước 5) |
| Mọi request fail ngay với lỗi kết nối | `BASE_URL` trống trong file env của flavor | Điền `BASE_URL` trong `apps/mobile/env.<flavor>` |
| App treo sau một `401` ở login hay refresh | Lời gọi thiếu `EXTRA_CAN_REFRESH_TOKEN: false`, nên refresh chờ chính nó | Thêm `@Extra` (bước 3 và 6) |
| `401` tới UI dù backend hỗ trợ refresh | Chưa có `ISessionGateway` nào được đăng ký, nên không có interceptor refresh | Implement và đăng ký một gateway (bước 9) |
| Người dùng bị đăng xuất sau một lần mạng chập chờn | `refreshToken()` trả `null` cho một lỗi tạm thời | Ném lỗi khi "không có câu trả lời", chỉ trả `null` khi bị từ chối (bước 9) |
| Server không nhận locale | Server đọc `Accept-Language`; client gửi header không chuẩn `language` | Đọc header `language` ở phía server |
| Log `ERROR`: `SSL pinning skipped` | `sslPinningHashes` rỗng, hoặc `SslPinningConfig` chưa được bind | Điền hash và giữ binding (bước 10) |
| Hai package đăng ký cùng một client có tên và boot ném lỗi | Mỗi tên chỉ đăng ký được một lần trong container | Chuyển phần đăng ký vào `platform/infra/network/lib/di/register_module.dart` (bước 7) |

## Liên quan

- Luật: RULE-09 (endpoint trong `utils/`), RULE-14 (interface thứ hai qua `@module`), RULE-41 (data source trả model), RULE-42 (`execute()` và không ném lỗi lên UI), RULE-43 (`ErrorHandler`), RULE-48 (pinning), RULE-66 (không log bí mật) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 6](../architecture/02_core.md#6-core_network--http-client) — bên trong client
- [`02_new_domain_data.md`](02_new_domain_data.md) — repository và cách map `Result<T>`
- [`05_di.md`](05_di.md) — thứ tự đăng ký và bẫy eager singleton
- [`06_storage.md`](06_storage.md) — nơi token được lưu
