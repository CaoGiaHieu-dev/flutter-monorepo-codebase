# Bloc State Management

Micro-core package cung cấp bộ khung quản lý trạng thái UI dựa trên thư viện `flutter_bloc` dành cho các nhóm phát triển yêu thích kiến trúc hướng sự kiện (Event-Driven) và MVI.

Package này tuân thủ nguyên tắc **Idiomatic BLoC** (tối giản, không ép buộc cấu trúc xử lý rườm rà), nhưng cung cấp sẵn một mô hình **UI State Đồng Nhất (Agnostic View State)** để dễ dàng tích hợp và chung sống hòa bình với các mô-đun dùng Provider trong cùng một hệ sinh thái Monorepo.

---

## 🌟 Tính Năng Cốt Lõi

- **`ViewState<T>`**: State agnostic sẵn có (`initial`, `loading`, `success`, `error`) — **khuyến nghị** cho màn hình đơn giản; **không bắt buộc**. Feature phức tạp có thể dùng Freezed state riêng với `BaseBloc<Event, CustomState>`.
- **`BaseBloc<Event, State>`**: Base class của Bloc — **lựa chọn mặc định** cho feature dùng BLoC (event-driven).
- **`BaseCubit<State>`**: Chỉ dùng khi luồng thực sự không cần Event (toggle/local UI đơn giản). Không mặc định Cubit cho feature mới.
- **Agnostic & Decoupled**: Hoàn toàn tách biệt khỏi logic của `provider_state_management`.

---

## 🚀 1. Quản lý Trạng thái UI qua `ViewState` (khuyến nghị) hoặc State riêng

**`ViewState<T>` không bắt buộc** với BLoC. Đây là state agnostic sẵn có (giống Provider) cho màn hình CRUD / load-success-error đơn giản.

- **Nên dùng `ViewState<T>`** khi UI chỉ cần `initial` / `loading` / `success` / `error` quanh một payload `T`.
- **Được phép (và khuyến khích) tự tạo Freezed state riêng** khi feature cần state phức tạp hơn (nhiều field, wizard, form dirty, pagination + filter kết hợp, v.v.). Khi đó `BaseBloc<Event, YourCustomState>` là hợp lệ — chỉ cần giữ Event Freezed private theo AGENTS §13.

Kết hợp Pattern Matching (`when` / `maybeWhen`) trên Freezed state để UI type-safe.

**Khai báo Bloc với `ViewState` (mẫu đơn giản):**
```dart
import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:domain/domain.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'login_event.dart';
part 'login_bloc.freezed.dart';

@injectable
class LoginBloc extends BaseBloc<LoginEvent, ViewState<UserEntity>> {
  LoginBloc(this._loginUseCase) : super(const ViewState.initial()) {
    on<_LoginSubmitted>(_onSubmitted);
  }

  final LoginUseCase _loginUseCase;

  Future<void> _onSubmitted(
    _LoginSubmitted event,
    Emitter<ViewState<UserEntity>> emit,
  ) async {
    emit(const ViewState.loading());
    final result = await _loginUseCase(
      LoginParams(email: event.email, password: event.password),
    );
    result.when(
      success: (user) => emit(ViewState.success(user!)),
      failure: (appFailure) => emit(ViewState.error(appFailure)),
      none: () {},
      cancel: () {},
    );
  }
}
```

**Vẽ Giao Diện:**
```dart
class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, ViewState<UserEntity>>(
      builder: (context, state) {
        return state.when(
          initial: () => MyLoginForm(),
          loading: () => const CircularProgressIndicator(),
          success: (user) => Text('Xin chào ${user.name}'),
          error: (failure) => Text('Đăng nhập lỗi: $failure'),
        );
      },
    );
  }
}
```

*(Ghi chú: Khác với `Provider` tự động bọc thẻ `loading` ở BaseViewWidget, đối với `BLoC` chúng ta sử dụng triết lý "Trực quan 100%" - dev sẽ tự return `CircularProgressIndicator` ở node `loading` của hàm `when`).*

**State riêng (được phép):** Khi màn hình cần nhiều hơn 4 trạng thái chuẩn, định nghĩa Freezed state trong feature (`part '_state.dart'`) và dùng `BaseBloc<Event, CheckoutState>` — không bắt buộc bọc lại bằng `ViewState`.

---

## 🎧 2. Lắng Nghe Side-effects & Hiển Thị Thông Báo (`BlocListener`)

Để bật Dialog, hiện Toast lỗi hoặc chuyển màn hình một lần duy nhất, hãy bọc giao diện của bạn bằng `BlocListener` (thay vì viết stream tay):

```dart
@override
Widget build(BuildContext context) {
  return BlocListener<LoginBloc, ViewState<UserEntity>>(
    listener: (context, state) {
      state.maybeWhen(
        success: (user) {
          getIt<AuthNavigator>().toHome();
        },
        error: (failure) {
          AppOverlay.showToast(content: failure.message);
        },
        orElse: () {},
      );
    },
    child: BlocBuilder<LoginBloc, ViewState<UserEntity>>(
      // UI building...
    ),
  );
}
```

---

## 🔒 3. Quản Lý Lỗi Nghiệp Vụ Chuyên Biệt (Custom Error State)

Mặc định, biến số `error` trong `ViewState.error(error)` có kiểu là `AppFailure`. Nếu bạn muốn chi tiết hóa lỗi, hãy định nghĩa Custom Error State cho feature của mình:

```dart
import 'package:core_common/core_common.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_error_state.freezed.dart';

@freezed
abstract class AuthErrorState extends AppFailure with _$AuthErrorState {
  const AuthErrorState._();

  const factory AuthErrorState.invalidCredentials() = _InvalidCredentials;
  const factory AuthErrorState.userNotFound() = _UserNotFound;
}
```

Sau đó trong Bloc:
```dart
      failure: (appFailure) {
        // Map từ Domain Failure sang AuthErrorState
        final customError = appFailure.whenOrNull(
          network: (...) => const AuthErrorState.userNotFound(),
        ) ?? const AuthErrorState.invalidCredentials();
        
        emit(ViewState.error(customError));
      },
```

---

## 🔗 4. Liên Kết Phụ Thuộc Giữa Các Bloc (Giao Tiếp Chéo Hệ Lạ)

Monorepo này là một hệ thống **đa State Management**. 
Nếu Feature của bạn dùng **BLoC**, nhưng bạn cần lắng nghe sự thay đổi từ Feature khác dùng **Provider** (hoặc ngược lại).
**TUYỆT ĐỐI KHÔNG** import trực tiếp Bloc hoặc Provider vào code của nhau.
**HÃY SỬ DỤNG Neutral Streams**: Đăng ký một Dart `Stream` thuần túy lên GetIt (DI Hub), sau đó `BaseBloc` của bạn chỉ việc lắng nghe Stream đó thay vì lắng nghe Provider.

*(Xem chi tiết kiến trúc này tại tài liệu `docs/04_presentation_layer.md` - Mục 3: Giao Tiếp Chéo Hệ Lạ).*

Nếu chỉ là liên kết Bloc-đến-Bloc cùng Feature, bạn hoàn toàn có thể truyền instance thông qua constructor và dùng `StreamSubscription` lắng nghe bên trong thân Bloc.

---

## ⚠️ 5. Lưu ý Cực Kỳ Quan Trọng về Vòng Đời (Route-Level Auto Dispose)

Giống như Provider, các Bloc gắn liền với màn hình phải được giải phóng bộ nhớ khi người dùng rời đi.

1. **Route-level Auto Dispose**: Khai báo Bloc bằng `@injectable`, tuyệt đối không được dùng `@singleton` hoặc `@lazySingleton`.
2. **Khởi tạo ở Router**: Bọc `BlocProvider` trong hàm `build` của lớp Route (`go_router`) ở file `route_module.dart`:

```dart
@TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      create: (context) => getIt<LoginBloc>(), // Injectable sẽ tạo instance mới
      child: const LoginPage(),
    );
  }
}
```
Khi người dùng chuyển sang màn hình khác, `BlocProvider` sẽ tự động gọi hàm `close()` của `LoginBloc` để xóa sổ nó khỏi RAM.
