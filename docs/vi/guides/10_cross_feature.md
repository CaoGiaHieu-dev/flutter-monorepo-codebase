# Hướng dẫn: Giao tiếp giữa các feature

File này trả lời câu hỏi **"feature A cần thứ gì đó từ feature B — làm sao mà không import nó?"**.
Các package feature không bao giờ được import lẫn nhau — không có ngoại lệ, vì widget dùng chung nay lấy từ package core `core_ui_kit` — nên mọi
tương tác đều đi qua một hợp đồng do package *trung lập* nắm giữ.

Đọc xong bạn sẽ biết chọn mô hình nào trong sáu mô hình, và nối dây thế nào để xoá feature nào đi
thì app vẫn chạy.

---

## Luật gốc

```
feature_a  ──✗──>  feature_b        cấm tuyệt đối
feature_a  ──✓──>  core_di          hợp đồng nằm ở đây
feature_b  ──✓──>  core_di          implementation đăng ký theo hợp đồng đó
```

`core_di` là **DI Hub**: nó chứa interface, không chứa logic. Cả hai phía đều phụ thuộc nó, không
phía nào phụ thuộc phía kia. Chính điều đó làm cho feature có thể gỡ ra được.

---

## Bảng quyết định

| Tôi cần… | Dùng | Mô hình |
| :-- | :-- | :-- |
| Chạy cùng một thao tác nghiệp vụ với feature khác | **UseCase** dùng chung từ `domain_*` | 1 |
| Đọc/ghi storage, gọi API, ghi log | **Core service** (`core_storage`, `core_network`…) | 2 |
| Phản ứng liên tục theo state của feature khác (login/logout…) | **Agnostic stream** trên `core_di` | 3 |
| Lưu một tuỳ chọn UI thuần (theme, ngôn ngữ) | **Bỏ qua Domain** qua interface storage ở `core_di` | 4 |
| Nhúng widget mà chỉ feature khác dựng được | **Widget builder interface** trên `core_di` | 5 |
| Kích hoạt một hành động UI một-lần do feature khác sở hữu (logout…) | **Action handler** trên `core_di` | 6 |
| Chỉ đơn giản là điều hướng sang màn của feature khác | **Navigator interface** — xem [`04_routing.md`](04_routing.md) | — |

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

Inject thẳng `StorageManager`, `Dio`, `AppDatabase`… từ package `core_*` tương ứng. Không có gì
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
[`packages/core/di/lib/src/agnostic_streams/i_auth_status_stream.dart`](../../../packages/core/di/lib/src/agnostic_streams/i_auth_status_stream.dart):

```dart
abstract class IAuthStatusStream {
  /// Emits on every authentication state change; `null` means signed out.
  Stream<UserEntity?> get authStatusStream;

  /// The currently signed-in user, or `null` when signed out.
  UserEntity? get currentUser;
}
```

Hai quyết định thiết kế đáng hiểu rõ:

**Vì sao dùng `UserEntity` cụ thể chứ không phải generic `<T>`.** Bên tiêu thụ giữ được type safety
đầy đủ, không phải ép kiểu. Theo `.agents/AGENTS.md` §8.4, khi một neutral stream mang domain
entity thì interface ở `core_di` **bắt buộc** gọi tên kiểu đó tường minh thay vì lùi về `<T>` — và
`core_di` được *cho phép tường minh* phụ thuộc các micro-package `domain_*` để làm việc đó.
`core_di` là DI Hub chứ không phải business logic, nên điều này không biến nó thành tầng domain.

**Vì sao có `currentUser` bên cạnh stream.** `authStatusStream` là stream *broadcast*: nó không
phát lại giá trị cuối cho listener mới. Một bên đăng ký sau khi đã đăng nhập sẽ "mù" cho tới lần
thay đổi kế tiếp, nên nó đọc `currentUser` để lấy state tại thời điểm đăng ký.

### Bước 2 — implementation cụ thể trong feature sở hữu

Code thật từ
[`packages/features/auth/lib/src/services/auth_status_stream_impl.dart`](../../../packages/features/auth/lib/src/services/auth_status_stream_impl.dart):

```dart
/// Implementation of [IAuthStatusStream] provided by `feature_auth`.
@singleton
class AuthStatusStreamImpl implements IAuthStatusStream {
  final _controller = StreamController<UserEntity?>.broadcast();
  UserEntity? _currentUser;

  @override
  Stream<UserEntity?> get authStatusStream => _controller.stream;

  @override
  UserEntity? get currentUser => _currentUser;

  /// Internal method used by `feature_auth` to update the state.
  void updateAuthStatus(UserEntity? user) {
    _currentUser = user;
    _controller.add(user);
  }
}
```

### Bước 3 — bind interface về đúng instance đó

Code thật từ
[`packages/features/auth/lib/di/module.dart`](../../../packages/features/auth/lib/di/module.dart):

```dart
@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDiModule {
  @singleton
  IAuthStatusStream bindIAuthStatusStream(AuthStatusStreamImpl impl) => impl;
}
```

**Vì sao phải đăng ký hai lần.** Class cụ thể được đăng ký để `feature_auth` inject thẳng
`AuthStatusStreamImpl` và gọi method ghi `updateAuthStatus` — không cần tra `getIt`, không cần ép
kiểu `as`. Phần bind `@module` sau đó lộ *cùng một instance* dưới dạng interface chỉ-đọc cho mọi
bên khác. Bên sở hữu ghi, bên tiêu thụ đọc.

### Bước 4 — tiêu thụ từ feature khác

Code thật từ
[`packages/features/home/lib/src/bloc/home_profile_bloc.dart`](../../../packages/features/home/lib/src/bloc/home_profile_bloc.dart):

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<UserEntity?>> {
  HomeProfileBloc(this._authStatusStream)
    : super(const BlocViewState.initial()) {
    // …
  }

  final IAuthStatusStream _authStatusStream;
  StreamSubscription<UserEntity?>? _subscription;
```

`feature_home` phụ thuộc `core_di` và `domain_auth` — không bao giờ phụ thuộc `feature_auth`.

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
[`packages/core/di/lib/src/theme/i_theme_storage.dart`](../../../packages/core/di/lib/src/theme/i_theme_storage.dart):

```dart
import 'package:flutter/material.dart';

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

Implementation nằm ở app shell (`app/lib/di/theme_storage_impl.dart`) vì đó là nơi provider của
`core_base_ui` và cơ chế của `core_storage` gặp nhau mà không tạo thành vòng phụ thuộc.

> [!NOTE]
> `domain_language` có tồn tại và có định nghĩa use case ngôn ngữ, nhưng UI Settings **không** dùng
> chúng — nó dùng `LanguageProvider` qua đường bypass này, đúng vì lý do nêu trên.
> `domain_language` được giữ như tài liệu tham khảo cho trường hợp locale lấy từ API sau này, không
> phải code đang chạy.

---

## Mô hình 5 — Widget Builder interface

**Dùng khi** feature A phải render một widget mà chỉ feature B biết cách dựng nội dung.
**Không dùng khi** widget đó là UI dùng chung — thứ đó thuộc về `core_ui_kit`.

Khai hợp đồng builder ở `core_di`:

```dart
// packages/core/di/lib/src/builders/i_profile_card_builder.dart
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

Interface — code thật từ
[`packages/core/di/lib/src/actions/i_auth_action_handler.dart`](../../../packages/core/di/lib/src/actions/i_auth_action_handler.dart):

```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  void logout(BuildContext context);
}
```

Implementation — code thật từ
[`packages/features/auth/lib/src/handlers/auth_action_handler_impl.dart`](../../../packages/features/auth/lib/src/handlers/auth_action_handler_impl.dart):

```dart
import 'package:core_di/core_di.dart';
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
// app/lib/presentation/navigation/app_router.dart
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

// Tốt — không render gì thay vì crash
getItOrNull<DashboardRouteModule>()?.builder(context, state, shell)
    ?? const SizedBox.shrink();
```

> [!NOTE]
> Việc `app/lib/di/injection.dart` gọi tên các package feature là tham chiếu cứng có chủ đích duy
> nhất của composition root — nơi lắp ráp buộc phải biết nó lắp cái gì. Một số file trong shell vẫn
> còn import trực tiếp `feature_auth` / `feature_splash` / `core_ui_kit`; chúng đã được ghi chú
> tại chỗ và là phần việc còn lại trước khi mọi feature gỡ được hoàn toàn.

---

## Anti-pattern

| Đừng | Vì sao | Thay bằng |
| :-- | :-- | :-- |
| `import 'package:feature_b/...'` từ feature A | Trói cứng hai feature; không feature nào gỡ được | Hợp đồng ở `core_di` |
| Lộ `Bloc` hay `ChangeNotifier` ra ngoài feature | Ép feature kia phải theo thư viện state của bạn | Mô hình 3 — neutral stream |
| `getIt<KiểuDoFeatureSởHữu>()` | Ném lỗi khi feature đó bị gỡ | `getItOrNull<T>()` + fallback |
| Dùng Action Handler để điều hướng | Sai công cụ; mất type-safe route | Navigator interface |
| Đặt logic nghiệp vụ dùng chung vào `core_ui_kit` | Đó là package UI | Một UseCase ở domain |
| Dùng generic `<T>` cho stream mang domain entity | Mất type safety, trái AGENTS.md §8.4 | Gọi tên kiểu entity |

---

## Liên quan

- [`04_routing.md`](04_routing.md) — Navigator interface và hợp đồng route
- [`05_di.md`](05_di.md) — phạm vi đăng ký, bind `@module`, thứ tự nạp
- [`03_state_management.md`](03_state_management.md) — Provider và BLoC
- [`../architecture/05_features.md`](../architecture/05_features.md) — luật ranh giới feature
- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_di` dùng để làm gì
