🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# Bloc State Management

Micro-core package cung cấp bộ khung quản lý trạng thái UI dựa trên thư viện `flutter_bloc` dành cho các nhóm phát triển yêu thích kiến trúc hướng sự kiện (Event-Driven) và MVI.

Package này tuân thủ nguyên tắc **Idiomatic BLoC** (tối giản, không ép buộc cấu trúc xử lý rườm rà), nhưng cung cấp sẵn một mô hình **UI State Đồng Nhất (Agnostic View State)** để dễ dàng tích hợp và chung sống hòa bình với các mô-đun dùng Provider trong cùng một hệ sinh thái Monorepo.

Barrel `package:bloc_state_management/bloc_state_management.dart` re-export toàn bộ `flutter_bloc` (`Bloc`, `Emitter`, `BlocProvider`, `BlocBuilder`, `BlocListener`, …), nên feature không cần import `flutter_bloc` riêng.

---

## 🌟 Tính Năng Cốt Lõi

- **`BlocViewState<T>`**: State agnostic sẵn có (`initial`, `loading`, `success(T data)`, `error(AppFailure error)`) — **khuyến nghị** cho màn hình đơn giản; **không bắt buộc**. Feature phức tạp có thể dùng Freezed state riêng với `BaseBloc<Event, CustomState>`. Có getter `data` (`T?`, chỉ khác `null` ở `success`).
- **`BaseBloc<Event, State>`**: Base class của Bloc — **lựa chọn mặc định** cho feature dùng BLoC (event-driven).
- **`BaseCubit<State>`**: Chỉ dùng khi luồng thực sự không cần Event (toggle/local UI đơn giản). Không mặc định Cubit cho feature mới.
- **`BlocResultMixin<T>` / `CubitResultMixin<T>`**: `emitResult` — bản tương ứng của `executeOperation` (nhánh Provider) cho màn hình `BlocViewState<T>`: emit `loading`, chạy use case, rồi chốt `Result<T>` (hoặc lỗi bị ném) thành một state cuối.
- **Agnostic & Decoupled**: Hoàn toàn tách biệt khỏi logic của `provider_state_management`. Tên `BlocViewState` (không phải `ViewState`) là có chủ đích: `provider_state_management` export một `ViewState` khác nghĩa, và hai barrel đều public.

> [!IMPORTANT]
> `BaseBloc` và `BaseCubit` vẫn là **điểm mở rộng rỗng** — chúng không thêm gì so với `Bloc` / `Cubit`. Phần xử lý `Result` nằm ở `BlocResultMixin<T>` / `CubitResultMixin<T>` và chỉ áp dụng cho state `BlocViewState<T>`; Bloc dùng state Freezed **riêng** vẫn tự emit loading, tự unwrap `Result<T>` và tự map `AppFailure` (§3). Hai nhánh đã gần nhau hơn nhưng **chưa** ngang bằng: hook `OperationGlobalConfig`, `errorStateBuilder` và `LoadMoreMixin` của nhánh Provider không có bản tương ứng ở BLoC.

---

## 🚀 1. Quản lý Trạng thái UI qua `BlocViewState` (khuyến nghị) hoặc State riêng

**`BlocViewState<T>` không bắt buộc** với BLoC. Đây là state agnostic sẵn có (giống Provider) cho màn hình CRUD / load-success-error đơn giản.

- **Nên dùng `BlocViewState<T>`** khi UI chỉ cần `initial` / `loading` / `success` / `error` quanh một payload `T`.
- **Được phép (và khuyến khích) tự tạo Freezed state riêng** khi feature cần state phức tạp hơn (nhiều field, wizard, form dirty, pagination + filter kết hợp, v.v.). Khi đó `BaseBloc<Event, YourCustomState>` là hợp lệ — chỉ cần giữ Event Freezed private theo AGENTS §13.

Kết hợp Pattern Matching (`when` / `maybeWhen`) trên Freezed state để UI type-safe. Các biến thể của `BlocViewState` là private, nên với nó hãy dùng `when` / `maybeWhen` / `whenOrNull` thay vì `switch`.

**Khai báo Bloc với `BlocViewState` (mẫu đơn giản):**
```dart
import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:domain_auth/domain_auth.dart'; // LoginUseCase, LoginParams, UserEntity
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'login_event.dart'; // LoginEvent, với biến thể private _LoginSubmitted(email, password)
part 'login_bloc.freezed.dart';

@injectable
class LoginBloc extends BaseBloc<LoginEvent, BlocViewState<UserEntity>>
    with BlocResultMixin<UserEntity> {
  LoginBloc(this._loginUseCase) : super(const BlocViewState.initial()) {
    on<_LoginSubmitted>(_onSubmitted);
  }

  final LoginUseCase _loginUseCase;

  Future<void> _onSubmitted(
    _LoginSubmitted event,
    Emitter<BlocViewState<UserEntity>> emit,
  ) => emitResult(
    emit,
    () => _loginUseCase(
      LoginParams(email: event.email, password: event.password),
    ),
  );
}
```

`emitResult` (`lib/src/result_emitter.dart`) emit:

| Kết quả | Emit |
|:--|:--|
| Trước khi gọi | `loading` — trừ khi `showLoading: false`, hoặc đang hiển thị `success` (refresh giữ nguyên nội dung) |
| `Result.success(data)` | `success(data)` — truyền `convert:` khi payload chưa phải `T` |
| `Result.success(null)` | `success(null)` nếu `T` nullable, ngược lại `initial` |
| `Result.failure(f)` | `error(f)` |
| `Result.none` / `.cancel` | state trước lời gọi nếu đã emit `loading` (không bao giờ kẹt ở `loading`), ngược lại không emit gì |
| Thao tác ném exception | `error(ErrorHandler.handleError(e))`, kèm `addError(e)` cho `BlocObserver.onError` |

`onSuccess:` / `onFailure:` chạy sau khi state đã được emit. Khi handler đã xong (bloc đã đóng, hoặc bị transformer `restartable()` thay thế) thì không emit gì thêm. Cubit trộn `CubitResultMixin<T>` và gọi `emitResult(() => ...)`, không cần emitter.

**Vẽ Giao Diện:**
```dart
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, BlocViewState<UserEntity>>(
      builder: (context, state) {
        return state.when(
          initial: () => const MyLoginForm(),
          loading: () => const CircularProgressIndicator(),
          success: (user) => WelcomeWidget(user: user),
          // Map AppFailure sang chuỗi đã dịch bên trong widget — không hardcode chuỗi UI.
          error: (failure) => LoginFailureWidget(failure: failure),
        );
      },
    );
  }
}
```

*(Ghi chú: Khác với `Provider` tự động hiện widget loading ở `BaseViewWidget`, đối với `BLoC` chúng ta sử dụng triết lý "Trực quan 100%" - dev sẽ tự return widget loading ở node `loading` của hàm `when`).*

**State riêng (được phép):** Khi màn hình cần nhiều hơn 4 trạng thái chuẩn, định nghĩa Freezed state trong feature (`part '<name>_state.dart'`) và dùng `BaseBloc<Event, CheckoutState>` — không bắt buộc bọc lại bằng `BlocViewState`.

---

## 🎧 2. Lắng Nghe Side-effects & Hiển Thị Thông Báo (`BlocListener`)

Để bật Dialog, hiện Toast lỗi hoặc chuyển màn hình một lần duy nhất, hãy bọc giao diện của bạn bằng `BlocListener` (thay vì viết stream tay):

```dart
@override
Widget build(BuildContext context) {
  return BlocListener<LoginBloc, BlocViewState<UserEntity>>(
    listener: (context, state) {
      state.maybeWhen(
        success: (user) {
          // Navigator của feature khác: luôn `getItOrNull` (arch_check R8).
          getItOrNull<HomeNavigator>()?.toHome(context);
        },
        error: (failure) {
          AppOverlay.showToast(content: failure.message);
        },
        orElse: () {},
      );
    },
    child: const LoginView(), // phần UI dựng bằng BlocBuilder như trên
  );
}
```

> Đây là mẫu tổng quát. Riêng luồng đăng nhập của template thì **app shell** tự điều hướng khi phiên đăng nhập đổi (`NavigatorWrapperWidget` lắng nghe `IAuthSessionState`), nên màn login thật không tự điều hướng.

---

## 🔒 3. Quản Lý Lỗi Nghiệp Vụ Chuyên Biệt (Custom Error State)

Mặc định, biến số `error` trong `BlocViewState.error(error)` có kiểu là `AppFailure`. `AppFailure` là một `sealed class` (Freezed) trong `domain_core` (`platform/domain_core/lib/src/failures/failures.dart`), nên feature **không thể** `extends` / `implements` nó để thêm lỗi riêng — một `AuthErrorState extends AppFailure` sẽ không compile. Nếu bạn muốn chi tiết hóa lỗi, hãy định nghĩa **Freezed state riêng** cho feature, mang một giá trị lỗi của chính feature, dùng `BaseBloc<Event, CustomState>`, rồi map các biến thể của `AppFailure` sang giá trị đó trong handler:

```dart
// login_state.dart
part of 'login_bloc.dart';

/// Lỗi nghiệp vụ của màn login — giá trị của feature, không phải một AppFailure.
enum LoginError { invalidCredentials, network, unknown }

@freezed
sealed class LoginState with _$LoginState {
  const factory LoginState.initial() = LoginInitial;
  const factory LoginState.loading() = LoginLoading;
  const factory LoginState.success(UserEntity user) = LoginSuccess;
  const factory LoginState.error(LoginError error) = LoginErrorState;
}
```

Sau đó trong Bloc:
```dart
import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:domain_auth/domain_auth.dart'; // LoginUseCase, LoginParams, UserEntity
import 'package:domain_core/domain_core.dart'; // Result, AppFailure và các biến thể
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'login_event.dart';
part 'login_state.dart';
part 'login_bloc.freezed.dart';

@injectable
class LoginBloc extends BaseBloc<LoginEvent, LoginState> {
  LoginBloc(this._loginUseCase) : super(const LoginState.initial()) {
    on<_LoginSubmitted>(_onSubmitted);
  }

  final LoginUseCase _loginUseCase;

  Future<void> _onSubmitted(
    _LoginSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginState.loading());
    final result = await _loginUseCase(
      LoginParams(email: event.email, password: event.password),
    );
    result.when(
      success: (user) => user == null
          ? emit(const LoginState.error(LoginError.unknown))
          : emit(LoginState.success(user)),
      failure: (failure) => emit(LoginState.error(_toLoginError(failure))),
      none: () => emit(const LoginState.initial()),
      cancel: () => emit(const LoginState.initial()),
    );
  }

  /// Map từ biến thể của Domain Failure sang lỗi của feature.
  ///
  /// `ErrorHandler` biến HTTP 401/403 thành `AuthFailure`, lỗi kết nối /
  /// timeout thành `NetworkFailure`.
  static LoginError _toLoginError(AppFailure failure) => switch (failure) {
    AuthFailure() || ValidationFailure() => LoginError.invalidCredentials,
    NetworkFailure() => LoginError.network,
    _ => LoginError.unknown,
  };
}
```

Vẽ giao diện — `LoginState` là `sealed`, nên `switch` được kiểm tra đủ trường hợp lúc compile:
```dart
BlocBuilder<LoginBloc, LoginState>(
  builder: (context, state) => switch (state) {
    LoginInitial() => const MyLoginForm(),
    LoginLoading() => const CircularProgressIndicator(),
    LoginSuccess(:final user) => WelcomeWidget(user: user),
    // LoginErrorWidget map mỗi LoginError sang chuỗi đã dịch của feature.
    LoginErrorState(:final error) => LoginErrorWidget(error: error),
  },
)
```

---

## 🔗 4. Liên Kết Phụ Thuộc Giữa Các Bloc (Giao Tiếp Chéo Hệ Lạ)

Monorepo này là một hệ thống **đa State Management**.
Nếu Feature của bạn dùng **BLoC**, nhưng bạn cần lắng nghe sự thay đổi từ Feature khác dùng **Provider** (hoặc ngược lại).
**TUYỆT ĐỐI KHÔNG** import trực tiếp Bloc hoặc Provider vào code của nhau.
**HÃY SỬ DỤNG Neutral Streams**: một interface trung lập trong `core_di` (ví dụ `IAuthStatusStream`, phơi ra `Stream<AuthPrincipal?>` và `currentUser`), feature sở hữu đăng ký implementation lên GetIt, và `BaseBloc` của bạn chỉ việc lắng nghe Stream đó thay vì lắng nghe Provider.

Mẫu thật: `HomeProfileBloc` (`modules/home/feature/lib/src/bloc/home_profile_bloc.dart`) nhận `IAuthStatusStream?` qua `@factoryParam` — route truyền `getItOrNull<IAuthStatusStream>()`, nên Home vẫn chạy khi app không ghép `feature_auth` — rồi hủy subscription trong `close()`.

*(Xem chi tiết kiến trúc này tại [`docs/vi/guides/10_cross_feature.md`](../../docs/vi/guides/10_cross_feature.md) — Mô hình 3: Agnostic Stream.)*

Nếu chỉ là liên kết Bloc-đến-Bloc cùng Feature, bạn hoàn toàn có thể truyền instance thông qua constructor và dùng `StreamSubscription` lắng nghe bên trong thân Bloc (nhớ `cancel()` trong `close()`).

---

## ⚠️ 5. Lưu ý Cực Kỳ Quan Trọng về Vòng Đời (Route-Level Auto Dispose)

Giống như Provider, các Bloc gắn liền với màn hình phải được giải phóng bộ nhớ khi người dùng rời đi.

1. **Route-level Auto Dispose**: Khai báo Bloc bằng `@injectable`, tuyệt đối không được dùng `@singleton` hoặc `@lazySingleton`.
2. **Khởi tạo ở Router**: Bọc `BlocProvider` trong hàm `build` của lớp Route (`go_router`) ở file `<feature>_route_module.dart`. Page **không** được tự bọc thêm một `BlocProvider` nữa.

Ví dụ thật, `modules/home/feature/lib/src/routing/home_route_module.dart`:

```dart
@TypedGoRoute<HomeRoute>(path: HomePath.HOME)
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      // Auth là tùy chọn: app ghép không có `feature_auth` sẽ không đăng ký
      // IAuthStatusStream, và Home hiện trạng thái chưa đăng nhập.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<IAuthStatusStream>(),
      ),
      child: const HomePage(),
    );
  }
}
```
`BlocProvider` gọi `close()` của Bloc khi chính nó rời khỏi cây widget — route bị pop, hoặc bị thay bằng `go` sang location khác. Push một màn hình khác **lên trên** không đóng Bloc, và một tab của `StatefulShellRoute` (như Home) vẫn sống khi người dùng chuyển tab.
