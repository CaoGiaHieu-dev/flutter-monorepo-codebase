# Hướng dẫn: Giao tiếp giữa các feature

File này trả lời câu hỏi **"feature A cần thứ gì đó từ feature B — làm sao mà không import nó?"**.
Các package feature không bao giờ được import lẫn nhau — không có ngoại lệ; widget dùng chung lấy từ package core `core_ui_kit` — nên mọi
tương tác đều đi qua một hợp đồng do package *trung lập* nắm giữ.

Đọc xong bạn sẽ biết chọn mô hình nào trong sáu mô hình, và nối dây thế nào để xoá feature nào đi
thì app vẫn chạy.

---

## Luật gốc

```
feature_a  ──✗──>  feature_b        cấm tuyệt đối
feature_a  ──✓──>  b_api            hợp đồng module B dành cho feature khác nằm ở đây
feature_b  ──✓──>  b_api            B implement và đăng ký theo chúng
ai cũng    ──✓──>  core_di          hợp đồng trung lập với sản phẩm (session, location, routing)
```

Một hợp đồng nằm ở một trong hai chỗ trung lập. **Package API của module B** (`modules/<b>/api`,
`b_api`) chứa những gì tồn tại để *feature khác chạm tới B* — navigator, action handler, một
widget builder (`auth_api`, `home_api` trong các sample); nó chỉ phụ thuộc foundation và
Flutter, và feature của B implement nó. **`core_di`**, DI Hub, chỉ chứa thứ trung lập với sản
phẩm — thứ mà chính platform cần, đặt tên theo nhu cầu đó (phiên đăng nhập, vị trí đăng nhập /
sau đăng nhập, routing), không bao giờ theo module cung cấp nó. Dù ở đâu, cả hai phía đều phụ
thuộc hợp đồng, không phía nào phụ thuộc phía kia. Chính điều đó làm cho feature có thể gỡ ra
được; `arch_check` R3 giữ các luật của package API.

---

## Bảng quyết định

| Tôi cần… | Dùng | Mô hình |
| :-- | :-- | :-- |
| Chạy cùng một thao tác nghiệp vụ với feature khác | **UseCase** dùng chung từ `domain_*` | 1 |
| Đọc/ghi storage, gọi API, ghi log | **Core service** (`core_storage`, `core_network`…) | 2 |
| Phản ứng liên tục theo state của feature khác (login/logout…) | **Agnostic stream** — trên `core_di` khi trung lập với sản phẩm (session), còn lại ở `<id>_api` của module sở hữu | 3 |
| Lưu một tuỳ chọn UI thuần (theme, ngôn ngữ) | **Bỏ qua Domain** qua interface storage ở `core_di` | 4 |
| Nhúng widget mà chỉ feature khác dựng được | **Widget builder interface** trong `<id>_api` của module sở hữu | 5 |
| Kích hoạt một hành động UI một-lần do feature khác sở hữu (logout…) | **Action handler** trong `<id>_api` của module sở hữu | 6 |
| Chỉ đơn giản là điều hướng sang màn của feature khác | **Navigator interface** trong `<id>_api` của module sở hữu — xem [`04_routing.md`](04_routing.md) | — |

---

## Mô hình 1 — UseCase Domain dùng chung

**Dùng khi** hai feature thực hiện cùng một thao tác nghiệp vụ.
**Không dùng khi** thứ bạn cần là state UI chứ không phải logic nghiệp vụ.

Cả hai feature inject cùng một use case từ package domain. Không bên nào biết bên kia tồn tại:

```dart
// Trong controller của bất kỳ feature nào
class CheckoutProvider extends BaseProvider<PaymentEntity> {
  CheckoutProvider(this._loginUseCase);

  final LoginUseCase _loginUseCase;
}
```

Use case nằm ở `domain_auth`; cả `feature_auth` và `feature_checkout` đều phụ thuộc `domain_auth`,
không bao giờ phụ thuộc lẫn nhau. Đây là mô hình rẻ nhất — hãy cân nhắc nó trước tiên.

---

## Mô hình 2 — Core Service

**Dùng khi** năng lực cần dùng là hạ tầng, không phải logic nghiệp vụ.
**Không dùng khi** hành vi đó thuộc về một feature cụ thể.

Inject thẳng `StorageManager`, `Dio`, `IDatabaseHandle<TDb>`… từ package `core_*` tương ứng. Không có gì
dính tới feature cụ thể, nên cũng chẳng có ràng buộc nào để phá.

Xem [`06_storage.md`](06_storage.md), [`08_networking.md`](08_networking.md),
[`07_database.md`](07_database.md).

---

## Mô hình 3 — Agnostic Stream (đăng ký kép)

**Dùng khi** feature A phải phản ứng *liên tục* theo state do feature B sở hữu — và hai bên có thể
dùng thư viện state-management khác nhau.
**Không dùng khi** bạn cần một hành động một-lần (dùng mô hình 6) hay chỉ đọc một giá trị (mô hình 4).

Đây là pattern quan trọng nhất trong codebase. `feature_auth` dùng Provider; `feature_home` dùng
BLoC. Không bên nào được import bên kia, và cũng không nên biết bên kia xài công cụ state gì.

### Bước 1 — interface trung lập ở `core_di`

Code thật từ
[`platform/foundation/contracts/lib/src/session/i_session_status_stream.dart`](../../../platform/foundation/contracts/lib/src/session/i_session_status_stream.dart):

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

Hai quyết định thiết kế đáng hiểu rõ:

**Vì sao là `SessionPrincipal` chứ không phải `UserEntity`.** Hợp đồng ở `core_di` không được gọi
tên một kiểu thuộc package `domain_*` (`.agents/AGENTS.md` §8.4): import đó khiến mọi bên tiêu thụ
phụ thuộc `domain_auth` ngay lúc biên dịch, và `getItOrNull` không gỡ được điều đó. Vì vậy `core_di`
sở hữu một value type nhỏ,
[`SessionPrincipal`](../../../platform/foundation/contracts/lib/src/session/session_principal.dart), và feature
auth thu hẹp entity của mình về kiểu đó tại ranh giới (`toPrincipal` ở bước 2). Hợp đồng cố ý nhỏ
hơn entity — bên tiêu thụ chỉ hỏi *ai đang đăng nhập* sẽ không bao giờ thấy phần còn lại.

**Vì sao có `currentUser` bên cạnh stream.** `sessionStatusStream` là stream *broadcast*: nó không
phát lại giá trị cuối cho listener mới. Một bên đăng ký sau khi đã đăng nhập sẽ "mù" cho tới lần
thay đổi kế tiếp, nên nó đọc `currentUser` để lấy state tại thời điểm đăng ký.

### Bước 2 — implementation cụ thể trong feature sở hữu

Code thật từ
[`modules/auth/feature/lib/src/services/auth_status_stream_impl.dart`](../../../modules/auth/feature/lib/src/services/auth_status_stream_impl.dart):

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

### Bước 3 — bind interface về đúng instance đó

Code thật từ
[`modules/auth/feature/lib/di/module.dart`](../../../modules/auth/feature/lib/di/module.dart):

```dart
@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDiModule {
  @singleton
  ISessionStatusStream bindISessionStatusStream(AuthStatusStreamImpl impl) => impl;
}
```

**Vì sao phải đăng ký hai lần.** Class cụ thể được đăng ký để `feature_auth` inject thẳng
`AuthStatusStreamImpl` và gọi method ghi `updateAuthStatus` — không cần tra `getIt`, không cần ép
kiểu `as`. Phần bind `@module` sau đó lộ *cùng một instance* dưới dạng interface chỉ-đọc cho mọi
bên khác. Bên sở hữu ghi, bên tiêu thụ đọc.

### Bước 4 — tiêu thụ từ feature khác

Code thật từ
[`modules/home/feature/lib/src/bloc/home_profile_bloc.dart`](../../../modules/home/feature/lib/src/bloc/home_profile_bloc.dart):

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

`feature_home` chỉ phụ thuộc `core_di` — không phụ thuộc `feature_auth`, và cũng không phụ thuộc `domain_auth`: hợp đồng mang `SessionPrincipal`, kiểu do chính `core_di` sở hữu, nên không có package domain nào đi qua ranh giới.

Stream này **tuỳ chọn** có chủ đích. `ISessionStatusStream` do `feature_auth` đăng ký, và một app có thể không ghép nó, nên bloc nhận nó qua `@factoryParam` và route cung cấp — code thật từ [`modules/home/feature/lib/src/routing/home_route_module.dart`](../../../modules/home/feature/lib/src/routing/home_route_module.dart):

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

---

## Mô hình 4 — Bỏ qua Domain cho state UI thuần

**Dùng khi** giá trị là tuỳ chọn UI không bao giờ rời khỏi máy — theme mode, locale.
**Không dùng khi** giá trị mang ý nghĩa nghiệp vụ hoặc được gửi lên server.

Chuỗi này bỏ qua hẳn tầng domain:

```
ThemeProvider  →  IThemeStorage (core_di)  →  ThemeStorageImpl (app shell)  →  StorageValue
```

Interface — code thật từ
[`platform/foundation/contracts/lib/src/theme/i_theme_storage.dart`](../../../platform/foundation/contracts/lib/src/theme/i_theme_storage.dart):

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

**Vì sao ở đây phải bỏ qua Domain.** Một use case sẽ phải nhận và trả `ThemeMode`, vốn là kiểu của
`package:flutter/material.dart`. Tầng domain là Dart thuần và **không thể import Flutter**, nên đưa
theme đi qua nó là bất khả thi về mặt cấu trúc — đây là ràng buộc cứng, không phải đường tắt.

Implementation nằm ở app shell (`platform/shell/adapters/lib/src/theme_storage_impl.dart`) vì đó là nơi provider của
`core_base_ui` và cơ chế của `core_storage` gặp nhau mà không tạo thành vòng phụ thuộc.


---

## Mô hình 5 — Widget Builder interface

**Dùng khi** feature A phải render một widget mà chỉ feature B biết cách dựng nội dung.
**Không dùng khi** widget đó là UI dùng chung — thứ đó thuộc về `core_ui_kit`.

Khai hợp đồng builder trong package API của module sở hữu (feature A thêm `profile_api` vào
`dependencies:` của nó):

```dart
// modules/profile/api/lib/src/builders/i_profile_card_builder.dart
import 'package:flutter/widgets.dart';

abstract class IProfileCardBuilder {
  Widget build(BuildContext context, {required String userId});
}
```

Cài đặt nó trong feature sở hữu và đăng ký bằng `@Injectable(as: IProfileCardBuilder)`. Bên tiêu
thụ phân giải theo kiểu phòng thủ để app vẫn sống khi feature đó bị gỡ:

```dart
final builder = getItOrNull<IProfileCardBuilder>();
return builder?.build(context, userId: id) ?? const SizedBox.shrink();
```

---

## Mô hình 6 — Action Handler

**Dùng khi** feature A phải kích hoạt một hành động một-lần gắn với UI do feature B sở hữu —
logout là ví dụ kinh điển.
**Không dùng cho** điều hướng thuần (dùng Navigator interface) hay logic domain (dùng UseCase).

Interface — code thật từ package API của module auth,
[`modules/auth/api/lib/src/actions/i_auth_action_handler.dart`](../../../modules/auth/api/lib/src/actions/i_auth_action_handler.dart)
(`feature_settings` phụ thuộc `auth_api`, không bao giờ phụ thuộc `feature_auth`):

```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  void logout(BuildContext context);
}
```

Implementation — code thật từ
[`modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart`](../../../modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart):

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

`feature_settings` gọi `getItOrNull<IAuthActionHandler>()?.logout(context)` — nó không hề biết
logout là một lời gọi Provider, cũng không biết `AuthProvider` tồn tại.

Các handler nằm trong thư mục `handlers/` của feature sở hữu và đặt tên `*ActionHandlerImpl`.

---

## Fallback an toàn — luật khiến feature gỡ được

Mọi bên tiêu thụ một hợp đồng cross-feature đều phải chịu được việc hợp đồng đó **không tồn tại**.
App shell đã làm đúng như vậy cho routing:

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

`getIt<T>()` **ném lỗi** khi không có gì được đăng ký. Mỗi lời gọi `getIt<T>()` trần trỏ tới một
kiểu do feature sở hữu là một cú crash đang chờ tới ngày feature đó bị xoá.

```dart
// Tốt — suy giảm êm ái
getItOrNull<IAuthActionHandler>()?.logout(context);

// Tốt — lùi về chính widget của nhánh thay vì crash
// (platform/shell/app_shell/lib/presentation/navigation/app_router.dart)
builder: (context, state, navigationShell) {
  return getItOrNull<DashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      navigationShell;
},
```

Bản thân `navigationShell` là widget hiển thị nhánh hiện tại, nên một app không compose
`feature_dashboard` vẫn render các destination — chỉ là không có chrome. Một `SizedBox` rỗng ở đây
sẽ mở app đó trên một màn hình trống.

> [!NOTE]
> Việc `apps/mobile/lib/di/injection.dart` gọi tên các package feature là tham chiếu cứng có chủ đích duy
> nhất của composition root — nơi lắp ráp buộc phải biết nó lắp cái gì. Không file nào khác trong
> app import module (R10), và shell dùng chung ở `platform/shell/app_shell/` thì không thể (R1); tất cả phần còn lại chạm tới feature qua hợp đồng ở
> `core_di` cùng fallback `getAllOrEmpty` / `getItOrNull`. Các import `core_ui_kit` trong shell
> không phải ngoại lệ — đó là package core, không phải feature gỡ được.
>
> Kiểm chứng bằng `grep -rn "package:feature_" apps/mobile/lib --include="*.dart"` — mọi kết quả đều phải
> nằm trong `injection.dart` hoặc file sinh ra `injection.config.dart`.

---

## Anti-pattern

| Đừng | Vì sao | Thay bằng |
| :-- | :-- | :-- |
| `import 'package:feature_b/...'` từ feature A | Trói cứng hai feature; không feature nào gỡ được | Hợp đồng trong `b_api` (hoặc hợp đồng trung lập ở `core_di`) |
| Hợp đồng riêng của một module (`AuthNavigator`) đặt trong `core_di` | Platform khi đó gọi tên một module sản phẩm, và giữ một hợp đồng chết khi module bị gỡ | `<id>_api` của module sở hữu |
| Lộ `Bloc` hay `ChangeNotifier` ra ngoài feature | Ép feature kia phải theo thư viện state của bạn | Mô hình 3 — neutral stream |
| `getIt<KiểuDoFeatureSởHữu>()` | Ném lỗi khi feature đó bị gỡ | `getItOrNull<T>()` + fallback |
| Dùng Action Handler để điều hướng | Sai công cụ; mất type-safe route | Navigator interface |
| Đặt logic nghiệp vụ dùng chung vào `core_ui_kit` | Đó là package UI | Một UseCase ở domain |
| Hợp đồng `core_di` gọi tên entity của `domain_*` | Mọi bên tiêu thụ phải phụ thuộc package domain đó; trái AGENTS.md §8.4 | Value type do hợp đồng sở hữu (`SessionPrincipal`) |

---

## Liên quan

- [`04_routing.md`](04_routing.md) — Navigator interface và hợp đồng route
- [`05_di.md`](05_di.md) — phạm vi đăng ký, bind `@module`, thứ tự nạp
- [`03_state_management.md`](03_state_management.md) — Provider và BLoC
- [`../architecture/05_features.md`](../architecture/05_features.md) — luật ranh giới feature
- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_di` dùng để làm gì
