<!-- translated-from: docs/en/guides/10_cross_feature.md@b65f8b3 -->
# Hướng dẫn: Giao tiếp giữa các feature

## Mục tiêu

Feature A cần thứ gì đó từ feature B, nhưng không được import nó (RULE-04). Bạn chọn đúng một trong sáu mô hình được phép (RULE-25) và nối dây sao cho xoá feature nào đi thì app vẫn chạy.

## Điều kiện cần

- **Vì sao hợp đồng nằm ở chỗ nó nằm** — trong package API của module B, hoặc ở `core_di` khi trung lập với sản phẩm — và các anti-pattern cần từ chối: [`../architecture/05_features.md` § 9](../architecture/05_features.md#9-giao-tiếp-giữa-các-feature--vì-sao-có-hình-dạng-này).
- Hai feature cần nối với nhau — [`01_new_feature.md`](01_new_feature.md). Module chưa có package API thì cần tạo một cái: [`12_module_isolation.md` § 4](12_module_isolation.md#4-tạo-package-api-cho-module).

---

## 1. Chọn mô hình

| Tôi cần… | Dùng | Mô hình |
| :-- | :-- | :-- |
| Chạy cùng một thao tác nghiệp vụ với feature khác | **UseCase** dùng chung từ `domain_*` | 1 |
| Đọc/ghi storage, gọi API, ghi log | **Core service** (`core_storage`, `core_network`…) | 2 |
| Phản ứng liên tục theo state của feature khác (login/logout…) | **Agnostic stream** — trên `core_di` khi trung lập với sản phẩm (session), còn lại ở `<id>_api` của module sở hữu | 3 |
| Lưu một tuỳ chọn UI thuần (theme, ngôn ngữ) | **Bỏ qua Domain** qua interface storage ở `core_di` | 4 |
| Nhúng widget mà chỉ feature khác dựng được | **Widget builder interface** trong `<id>_api` của module sở hữu | 5 |
| Kích hoạt một hành động UI một-lần do feature khác sở hữu (logout…) | **Action handler** trong `<id>_api` của module sở hữu | 6 |
| Chỉ đơn giản là điều hướng sang màn của feature khác | **Navigator interface** trong `<id>_api` của module sở hữu — xem [`04_routing.md`](04_routing.md) | — |

Hãy nghĩ tới mô hình 1 trước: nó rẻ nhất.

## 2. Dùng chung thao tác nghiệp vụ qua một use case (mô hình 1)

**Dùng khi** hai feature thực hiện cùng một thao tác nghiệp vụ. **Không dùng khi** thứ bạn cần là state UI chứ không phải logic nghiệp vụ.

Cả hai feature inject cùng một use case từ package domain. Không bên nào biết bên kia tồn tại:

```dart
// Trong controller của bất kỳ feature nào
class CheckoutProvider extends BaseProvider<PaymentEntity> {
  CheckoutProvider(this._loginUseCase);

  final LoginUseCase _loginUseCase;
}
```

Use case nằm ở `domain_auth`. Cả `feature_auth` và `feature_checkout` đều phụ thuộc `domain_auth`, không bao giờ phụ thuộc nhau.

## 3. Dùng một core service (mô hình 2)

**Dùng khi** năng lực cần dùng là hạ tầng, không phải logic nghiệp vụ. **Không dùng khi** hành vi đó thuộc về một feature cụ thể.

Inject thẳng `StorageManager`, `Dio`, `IDatabaseHandle<TDb>`… từ package `core_*` tương ứng. Không có gì đặc thù feature ở đây, nên không có ràng buộc nào để phá. Xem [`06_storage.md`](06_storage.md), [`08_networking.md`](08_networking.md), [`07_database.md`](07_database.md).

## 4. Chia sẻ state liên tục qua agnostic stream (mô hình 3)

**Dùng khi** feature A phải phản ứng *liên tục* theo state do feature B sở hữu — và hai bên có thể dùng thư viện state management khác nhau. **Không dùng khi** bạn cần một hành động một-lần (mô hình 6) hay chỉ đọc một giá trị (mô hình 4).

Đây là pattern quan trọng nhất trong codebase. `feature_auth` dùng Provider; `feature_home` dùng BLoC. Không bên nào được import bên kia, và cũng không nên biết bên kia xài công cụ state gì (RULE-54).

### Khai interface trung lập ở `core_di`

Code thật từ [`platform/foundation/contracts/lib/src/session/i_session_status_stream.dart`](../../../platform/foundation/contracts/lib/src/session/i_session_status_stream.dart):

```dart
abstract class ISessionStatusStream {
  /// Emits on every session change; `null` means signed out.
  Stream<SessionPrincipal?> get sessionStatusStream;

  /// The currently signed-in principal, or `null` when signed out.
  ///
  /// Read this for the state at subscription time — [sessionStatusStream] is a
  /// broadcast stream and does not replay its last value to new listeners.
  SessionPrincipal? get currentUser;
}
```

Hợp đồng mang [`SessionPrincipal`](../../../platform/foundation/contracts/lib/src/session/session_principal.dart), một value type do `core_di` sở hữu, không bao giờ là entity của `domain_*` (RULE-08). `currentUser` tồn tại vì stream broadcast không phát lại giá trị cuối. Cả hai quyết định được giải thích ở [`../architecture/05_features.md` § 9](../architecture/05_features.md#9-giao-tiếp-giữa-các-feature--vì-sao-có-hình-dạng-này).

### Implement trong feature sở hữu

Code thật từ [`modules/auth/feature/lib/src/services/auth_status_stream_impl.dart`](../../../modules/auth/feature/lib/src/services/auth_status_stream_impl.dart):

```dart
/// Implementation of [ISessionStatusStream] provided by `feature_auth`.
@singleton
class AuthStatusStreamImpl implements ISessionStatusStream {
  final _controller = StreamController<SessionPrincipal?>.broadcast();
  SessionPrincipal? _currentUser;

  @override
  Stream<SessionPrincipal?> get sessionStatusStream => _controller.stream;

  @override
  SessionPrincipal? get currentUser => _currentUser;

  /// Called by `feature_auth` when the session settles.
  void updateAuthStatus(UserEntity? user) {
    final principal = toPrincipal(user);
    _currentUser = principal;
    _controller.add(principal);
  }

  /// The one place `UserEntity` is narrowed for the outside world.
  static SessionPrincipal? toPrincipal(UserEntity? user) {
    if (user == null) return null;
    return SessionPrincipal(
      id: user.id,
      displayName: user.name,
      email: user.email,
      roles: {if (user.role != null) user.role!.name},
    );
  }
}
```

### Bind interface về đúng instance đó

Code thật từ [`modules/auth/feature/lib/di/module.dart`](../../../modules/auth/feature/lib/di/module.dart):

```dart
@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDiModule {
  @singleton
  ISessionStatusStream bindISessionStatusStream(AuthStatusStreamImpl impl) => impl;
}
```

Bên sở hữu inject `AuthStatusStreamImpl` và ghi qua `updateAuthStatus`. Mọi bên khác đọc đúng instance đó qua interface chỉ-đọc (RULE-14).

### Tiêu thụ từ feature khác

Code thật từ [`modules/home/feature/lib/src/bloc/home_profile_bloc.dart`](../../../modules/home/feature/lib/src/bloc/home_profile_bloc.dart):

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<SessionPrincipal?>> {
  HomeProfileBloc(@factoryParam this._sessionStatusStream)
    : super(const BlocViewState.initial()) {
    // …
  }

  final ISessionStatusStream? _sessionStatusStream;
  StreamSubscription<SessionPrincipal?>? _subscription;
```

`feature_home` chỉ phụ thuộc `core_di` — không phụ thuộc `feature_auth`, và cũng không phụ thuộc `domain_auth`. Hợp đồng mang `SessionPrincipal`, kiểu do chính `core_di` sở hữu, nên không có package domain nào đi qua ranh giới.

Stream này **tuỳ chọn** có chủ đích. `ISessionStatusStream` do `feature_auth` đăng ký, và một app có thể không ghép nó. Vì vậy bloc nhận nó qua `@factoryParam`, và route cung cấp — code thật từ [`modules/home/feature/lib/src/routing/home_route_module.dart`](../../../modules/home/feature/lib/src/routing/home_route_module.dart):

```dart
    return BlocProvider(
      // Auth is optional: an app composed without `feature_auth` registers
      // no ISessionStatusStream, and Home then shows the signed-out state.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<ISessionStatusStream>(),
      ),
      child: const HomePage(),
    );
```

Một tham số constructor bắt buộc cũng compile được y như vậy — nhưng rồi DI sẽ không dựng nổi `HomeProfileBloc` trong bản build không có auth. Constructor vẫn nhận dependency của nó (không lookup trong business logic); chỉ việc lookup *tuỳ chọn* chuyển lên route.

> [!CAUTION]
> Luôn huỷ subscription trong `close()` / `dispose()`. Stream broadcast sẽ vô tư giữ sống một
> controller đã bị huỷ.

## 5. Lưu tuỳ chọn UI mà không qua Domain (mô hình 4)

**Dùng khi** giá trị là tuỳ chọn UI không bao giờ rời khỏi máy — theme mode, locale. **Không dùng khi** giá trị mang ý nghĩa nghiệp vụ hoặc được gửi lên server.

Chuỗi này bỏ qua hẳn tầng domain, vì Domain không thể import `ThemeMode` của Flutter (RULE-03):

```
ThemeProvider  →  IThemeStorage (core_di)  →  ThemeStorageImpl (app shell)  →  StorageValue
```

Interface — code thật từ [`platform/foundation/contracts/lib/src/i_theme_storage.dart`](../../../platform/foundation/contracts/lib/src/i_theme_storage.dart):

```dart
import 'package:material_ui/material_ui.dart';

/// Interface for theme storage, decoupling ThemeProvider from the actual storage implementation.
abstract class IThemeStorage {
  /// Gets the current ThemeMode from storage.
  ThemeMode getThemeMode();

  /// Saves the given ThemeMode to storage.
  void saveThemeMode(ThemeMode mode);
}
```

Implementation nằm ở shell adapters, `platform/shell/adapters/lib/src/theme_storage_impl.dart`. Cách viết một cái tương tự: [`06_storage.md` § 9](06_storage.md#9-chia-sẻ-giá-trị-qua-ranh-giới-package).

## 6. Nhúng widget do feature khác dựng (mô hình 5)

**Dùng khi** feature A phải render một widget mà chỉ feature B biết cách dựng nội dung. **Không dùng khi** widget đó là UI dùng chung — thứ đó thuộc về `core_ui_kit`.

Khai hợp đồng builder trong package API của module sở hữu (feature A thêm `profile_api` vào `dependencies:` của nó):

```dart
// modules/profile/api/lib/src/builders/i_profile_card_builder.dart
import 'package:flutter/widgets.dart';

abstract class IProfileCardBuilder {
  Widget build(BuildContext context, {required String userId});
}
```

Implement nó trong feature sở hữu và đăng ký bằng `@Injectable(as: IProfileCardBuilder)`. Bên tiêu thụ resolve một cách phòng thủ, để app sống sót khi feature bị gỡ:

```dart
final builder = getItOrNull<IProfileCardBuilder>();
return builder?.build(context, userId: id) ?? const SizedBox.shrink();
```

## 7. Kích hoạt hành động UI của feature khác (mô hình 6)

**Dùng khi** feature A phải kích hoạt một hành động một-lần gắn với UI do feature B sở hữu — logout là ví dụ điển hình. **Không dùng cho** điều hướng thuần (dùng Navigator interface) hay logic domain (dùng UseCase).

Interface — code thật từ package API của module auth, [`modules/auth/api/lib/src/actions/i_auth_action_handler.dart`](../../../modules/auth/api/lib/src/actions/i_auth_action_handler.dart) (`feature_settings` phụ thuộc `auth_api`, không bao giờ phụ thuộc `feature_auth`):

```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  void logout(BuildContext context);
}
```

Implementation — code thật từ [`modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart`](../../../modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart):

```dart
import 'package:auth_api/auth_api.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';

@Injectable(as: IAuthActionHandler)
class AuthActionHandlerImpl implements IAuthActionHandler {
  @override
  void logout(BuildContext context) {
    context.read<AuthProvider>().logout();
  }
}
```

`feature_settings` gọi `getItOrNull<IAuthActionHandler>()?.logout(context)`. Nó không hề biết logout là một lời gọi Provider, hay `AuthProvider` có tồn tại.

Các handler nằm trong thư mục `handlers/` của feature sở hữu và đặt tên `*ActionHandlerImpl` (RULE-78).

## 8. Cho mọi lời tra cứu sống sót khi bên sở hữu bị gỡ

Mọi bên tiêu thụ một hợp đồng cross-feature đều phải chịu được việc hợp đồng đó **không tồn tại** (RULE-12). App shell đã làm đúng như vậy cho routing:

```dart
// platform/shell/app_shell/lib/presentation/navigation/app_router.dart
List<RouteBase> get _featureRoutes {
  return [
    for (final module in getAllOrEmpty<IFeatureRouteModule>())
      ...module.routes,
  ];
}
```

Áp dụng đúng kỷ luật đó ở mọi nơi:

| Tình huống | Dùng | Không dùng |
| :-- | :-- | :-- |
| Không hoặc nhiều implementation | `getAllOrEmpty<T>()` | `getIt.getAll<T>()` |
| Một implementation tuỳ chọn | `getItOrNull<T>()` + fallback | `getIt<T>()` |

`getIt<T>()` **ném lỗi** khi không có gì được đăng ký. Mỗi lời gọi `getIt<T>()` trần trỏ tới một kiểu do feature sở hữu là một lần crash chờ sẵn cho ngày feature đó bị xoá.

```dart
// Tốt — suy giảm êm ái
getItOrNull<IAuthActionHandler>()?.logout(context);

// Tốt — lùi về chính widget của nhánh thay vì crash
// (platform/shell/app_shell/lib/presentation/navigation/app_router.dart)
builder: (context, state, navigationShell) {
  return getItOrNull<IDashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      navigationShell;
},
```

Bản thân `navigationShell` là widget hiển thị nhánh hiện tại. Vì vậy một app không compose `feature_dashboard` vẫn render các destination — chỉ là không có chrome. Một `SizedBox` rỗng ở đây sẽ mở app đó ra một màn hình trắng.

> [!NOTE]
> Việc `apps/mobile/lib/di/injection.dart` gọi tên các package feature là tham chiếu cứng có chủ đích duy
> nhất của composition root — nơi lắp ráp buộc phải biết nó lắp cái gì. Không file nào khác trong
> app import module (R10), và shell dùng chung ở `platform/shell/app_shell/` thì không thể (R1); tất cả phần còn lại chạm tới feature qua hợp đồng ở
> `core_di` cùng fallback `getAllOrEmpty` / `getItOrNull`. Các import `core_ui_kit` trong shell
> không phải ngoại lệ — đó là package core, không phải feature gỡ được.

---

## Kiểm tra

```bash
dart tools/arch_check/check.dart     # ✅ … R3 (import feature/API), R8 (tra cứu tuỳ chọn), R10 (import trong app)
grep -rn "package:feature_" apps/mobile/lib --include="*.dart"   # chỉ có kết quả trong injection.dart / injection.config.dart
cd apps/mobile && flutter test test/di_smoke_test.dart            # hợp đồng resolve được từ graph thật
```

Sau đó chứng minh việc gỡ hoạt động: bỏ module sở hữu khỏi một manifest bằng `dart tools/sample_cleanup/remove_sample.dart <bundle>` (chạy thử, với module mẫu) hoặc sửa manifest trên một nhánh nháp, rồi chạy `flutter analyze` cùng smoke test. Bên tiêu thụ vẫn phải compile và khởi động được.

Checklist review:

- [ ] Không có `import 'package:feature_*'` từ một feature khác
- [ ] Hợp đồng nằm trong `<id>_api` của bên sở hữu (hoặc ở `core_di` nếu trung lập với sản phẩm), không bao giờ gọi tên entity của `domain_*`
- [ ] State do bên sở hữu ghi, bên tiêu thụ đọc được phơi ra dạng stream trung lập, không phải Bloc hay `ChangeNotifier`
- [ ] Mọi bên tiêu thụ resolve bằng `getItOrNull` / `getAllOrEmpty` và có fallback
- [ ] Subscription được huỷ trong `close()` / `dispose()`
- [ ] Action handler nằm trong `handlers/` với tên `*ActionHandlerImpl`; điều hướng dùng navigator, không dùng handler

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `arch_check` R3 fail vì một import feature | Feature A import feature B hoặc `data_*` | Phụ thuộc `b_api` (hoặc hợp đồng ở `core_di`) thay vào đó (bước 1) |
| `arch_check` R8 fail | Hợp đồng do module sở hữu được resolve bằng `getIt` / `getAll` bên ngoài module đó | Dùng `getItOrNull` / `getAllOrEmpty` kèm fallback (bước 8) |
| App crash lúc boot sau khi gỡ một feature | Một `getIt<T>()` trần hoặc một tham số constructor bắt buộc cần kiểu đã bị gỡ | Resolve nó một cách tuỳ chọn, ở route, dưới dạng factory param (bước 4) |
| Bên tiêu thụ không thấy state cho tới lần thay đổi kế tiếp | Nó đăng ký vào stream broadcast sau sự kiện cuối | Đọc `currentUser` trước, rồi mới lắng nghe (bước 4) |
| Mọi bên tiêu thụ giờ phụ thuộc `domain_auth` | Hợp đồng `core_di` gọi tên một entity domain | Cho hợp đồng một value type riêng, như `SessionPrincipal` (bước 4) |
| Màn hình đã huỷ vẫn tiếp tục phản ứng | Subscription chưa bao giờ được huỷ | Huỷ nó trong `close()` / `dispose()` (bước 4) |

## Liên quan

- Luật: RULE-04 (không import feature → feature), RULE-08 (`core_di` trung lập với sản phẩm), RULE-12 (tra cứu tuỳ chọn), RULE-25 (sáu mô hình), RULE-54 (state qua stream trung lập) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/05_features.md` § 9](../architecture/05_features.md#9-giao-tiếp-giữa-các-feature--vì-sao-có-hình-dạng-này) — vì sao hợp đồng có hình dạng này, và các anti-pattern
- [`04_routing.md`](04_routing.md) — Navigator interface và hợp đồng route
- [`05_di.md`](05_di.md) — phạm vi đăng ký, bind `@module`, thứ tự nạp
- [`03_state_management.md`](03_state_management.md) — Provider và BLoC
- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_di` dùng để làm gì
