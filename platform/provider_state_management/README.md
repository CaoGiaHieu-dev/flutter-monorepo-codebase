# Provider State Management

Micro-core package cung cấp bộ khung chuẩn hóa cho việc quản lý trạng thái UI dựa trên thư viện `provider` và kiến trúc **MVVM (Model-View-ViewModel)**. 

Package này loại bỏ hoàn toàn các đoạn code lặp lại (boilerplate) trong việc xử lý trạng thái Loading, Success, Error khi gọi API hay thực thi logic bất đồng bộ, giúp cho việc viết UI trở nên Declarative và an toàn tuyệt đối.

---

## 🌟 Tính Năng Cốt Lõi

- **`ViewStateModel<T>`**: Cấu trúc UI State bất biến (Freezed) chuẩn hóa với các trạng thái `initial`, `loading`, `success`, `error`.
- **`BaseProvider<T>`**: Lớp Base ViewModel cung cấp sẵn hàm `executeOperation()` giúp tự động hóa quá trình đổi state, gọi UseCase, và try-catch lỗi.
- **`BaseViewWidget<TProvider, TData>`**: Widget tự động build giao diện dựa trên trạng thái `ViewStateModel` (tự hiển thị loading, nhả data sạch, hiện giao diện lỗi).
- **`ProviderStateListener`**: Widget chuyên biệt để hứng các side-effects (như chuyển trang, bật toast thông báo) một lần duy nhất mà không cần viết StatefulWidget hay Stream thủ công.
- **`PaginatedViewWidget`**: Phiên bản mở rộng của BaseViewWidget dành riêng cho dữ liệu phân trang.
- **Hỗ Trợ Multi-Providers**: Các Proxy và ViewWidget từ 1 đến 6 Providers cùng lúc (ví dụ: `BaseViewWidget2`, `BaseProxyWidget3`).

---

## 🚀 1. Quản lý Tự động hóa qua `executeOperation`

ViewModel không được viết thủ công các câu lệnh dọn dẹp biến, đóng mở loading, hay try-catch. Thay vào đó, ViewModel ủy quyền toàn bộ tiến trình cho hàm `executeOperation` tích hợp sẵn trong `BaseProvider`:

```dart
import 'package:provider_state_management/provider_state_management.dart';
import 'package:domain/domain.dart';
import 'package:injectable/injectable.dart';

@injectable
class LoginProvider extends BaseProvider<UserEntity> {
  final LoginUseCase _loginUseCase;

  LoginProvider(this._loginUseCase);

  Future<void> login(String email, String password) async {
    // Tự động hóa: Cập nhật ViewState sang loading khi data rỗng, kích hoạt UseCase, bắt lỗi tự động
    await executeOperation(
      OperationConfig(
        operation: () => _loginUseCase(LoginParams(email: email, password: password)),
        showLoading: true, // Tự động chuyển ViewState sang loading đè lên toàn màn hình
        onSuccess: (user) async {
          // Xử lý khi thành công (ví dụ: Lưu token)
        },
        errorStateBuilder: (failure) {
          // (Tùy chọn) Tự động map lỗi từ nghiệp vụ (Domain) sang lỗi giao diện (Custom Error State)
          return failure.whenOrNull(
            server: (message, code, data) => AuthErrorState.serverError(message: message, code: code),
            network: (message, code, data) => const AuthErrorState.userNotFound(),
          );
        },
      ),
    );
  }
}
```

---

## 🧩 2. Tự Động Hóa Render UI với `BaseViewWidget` & `PaginatedViewWidget`

Thay vì phải tự viết các khối `if/else` thủ công trong `Consumer` để xử lý các trạng thái `loading`, `error`, `empty` hay `success`, hệ thống đã cung cấp các UI Widget Wrapper chuẩn hóa giúp code giao diện của bạn cực kỳ gọn gàng (Declarative).

#### 2.1 `BaseViewWidget` (Dành cho dữ liệu thông thường)
`BaseViewWidget` kế thừa sức mạnh của `Selector` (giúp tối ưu hóa render) và tự động lắng nghe chính xác `ViewStateModel` từ `BaseProvider`.

```dart
BaseViewWidget<ProductProvider, ProductEntity>(
  // Hàm này CHỈ ĐƯỢC GỌI khi API đã chạy thành công và có dữ liệu (data != null)
  builder: (context, product, child) {
    return Text('Tên sản phẩm: ${product.name}');
  },
  
  // (Tùy chọn) Giao diện khi Provider chưa chạy API lần nào
  initialWidget: (context, child) => const Text('Vui lòng tải dữ liệu...'),
  
  // (Tùy chọn) Giao diện khi API đang tải. Nếu không truyền, hệ thống hiện LoadingWidget() mặc định
  loadingWidget: (context, child) => const CircularProgressIndicator(),
  
  // (Tùy chọn) Giao diện khi API chạy thành công nhưng dữ liệu trả về null
  emptyWidget: (context, child) => const Text('Sản phẩm không tồn tại'),
  
  // (Tùy chọn) Giao diện tùy chỉnh khi lỗi. Nếu không truyền, hệ thống sẽ hiển thị lỗi tự động
  onErrorBuilder: (context, data, message, child) => Text('Lỗi: $message'),
)
```

*(Lưu ý: Hệ thống hỗ trợ lắng nghe lên tới 6 Providers cùng lúc thông qua `BaseViewWidget2` đến `BaseViewWidget6`)*

#### 2.2 `PaginatedViewWidget` (Dành cho Danh sách có phân trang)
Được thiết kế chuyên biệt để làm việc với `PaginatedEntity<T>` (kiểu danh sách chia trang trả về từ tầng Domain). Logic xác định màn hình `empty` (trống) thông minh hơn: Nó sẽ tự động trích xuất kiểm tra mảng bên trong (`data.data.isEmpty`). Nếu Server trả về HTTP 200 nhưng danh sách rỗng `[]`, màn hình Empty sẽ tự động được kích hoạt.

```dart
PaginatedViewWidget<UsersProvider, UserEntity>(
  builder: (context, paginatedData, child) {
    final usersList = paginatedData.data; // List<UserEntity>
    return ListView.builder(
      itemCount: usersList.length,
      itemBuilder: (context, index) => Text(usersList[index].name),
    );
  },
  emptyWidget: (context, child) => const Text('Không có người dùng nào trong hệ thống'),
)
```

---

## 🎧 3. Lắng Nghe Side-effects & Hiển Thị Thông Báo (`ProviderStateListener`)

Khi UI cần phản ứng với sự thay đổi trạng thái của ViewModel chỉ một lần (chẳng hạn như bật Dialog, hiện Toast lỗi hoặc chuyển màn hình khi thành công), tuyệt đối không được sử dụng `StreamSubscription` thủ công trong các `StatefulWidget`.
Bắt buộc sử dụng **`ProviderStateListener`**:

```dart
@override
Widget build(BuildContext context) {
  return ProviderStateListener<AuthProvider, UserEntity>(
    // Bắt và hiển thị thông báo lỗi nghiệp vụ chuyên biệt
    onError: (context, error, message) {
      if (error is AuthErrorState) {
        error.maybeWhen(
          invalidCredentials: () => AppOverlay.showToast(content: 'Sai tài khoản hoặc mật khẩu'),
          serverError: (serverMessage, code) => AppOverlay.showToast(content: serverMessage),
          orElse: () => AppOverlay.showToast(content: message ?? 'Đăng nhập thất bại'),
        );
      } else {
        AppOverlay.showToast(content: message ?? 'Đã xảy ra lỗi hệ thống');
      }
    },
    // Kích hoạt khi thành công
    onSuccess: (context, user) {
      getIt<AuthNavigator>().toHome();
    },
    child: Scaffold(
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return MyLoginForm(
            isLoading: authProvider.isLoading,
            onSubmit: () => authProvider.login(email, pass),
          );
        },
      ),
    ),
  );
}
```

---

## 🔒 4. Quản Lý Lỗi Nghiệp Vụ Chuyên Biệt (Custom Error State)

Mặc định khi gọi API thất bại, tầng Domain trả về `Failure`. Tuy nhiên, tầng UI không nên biết cấu trúc bên trong `Failure`. Việc tạo **Custom Error State** giúp ta định nghĩa chính xác các trường hợp lỗi có thể xảy ra ở Feature đó để xử lý type-safe.

**Tạo file `auth_error_state.dart` bằng Freezed:**
```dart
import 'package:provider_state_management/provider_state_management.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_error_state.freezed.dart';

@freezed
abstract class AuthErrorState extends IErrorState with _$AuthErrorState {
  const AuthErrorState._();

  const factory AuthErrorState.invalidCredentials() = _InvalidCredentials;
  const factory AuthErrorState.userNotFound() = _UserNotFound;
  const factory AuthErrorState.serverError({
    required String message,
    int? code,
  }) = _ServerError;
}
```

*(Sau đó dùng tham số `errorStateBuilder` của hàm `executeOperation` để map từ `Failure` sang `AuthErrorState` như ví dụ ở mục 1).*

---

## 🔗 5. Liên Kết Phụ Thuộc Giữa Các Provider (`BaseProxyWidget`)

Khi `CartProvider` cần biết thông tin tài khoản đăng nhập từ `AuthProvider` để tải giỏ hàng, hãy dùng `BaseProxyWidget` (hoặc `BaseProxyWidget2`, `BaseProxyWidget3`) ở tầng Routing:

```dart
@TypedGoRoute<CartRoute>(path: CartPath.CART)
class CartRoute extends GoRouteDataCustom with $CartRoute {
  const CartRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BaseProxyWidget<AuthProvider, CartProvider>(
      // Khởi tạo CartProvider phụ thuộc vào AuthProvider, bọc trọn CartPage ở tầng routing
      create: (context, authProvider) => getIt<CartProvider>(
        param1: authProvider.currentUser?.id, 
      ),
      // Chỉ cập nhật hoặc tái tạo CartProvider khi ID người dùng của AuthProvider thay đổi
      updateWhen: (authPrevious, cartCurrent) {
        return authPrevious.currentUser?.id != cartCurrent.userId;
      },
      child: const CartPage(),
    );
  }
}
```

---

## ⚠️ Lưu ý Cực Kỳ Quan Trọng về Vòng Đời

1. **Route-level Auto Dispose**: Feature Providers gắn liền với một màn hình **bắt buộc dùng `@injectable`**, tuyệt đối không được dùng `@singleton`.
2. **Khởi tạo ở Router**: Luôn luôn bọc `ChangeNotifierProvider` hoặc `BaseProxyWidget` trong hàm `build` của lớp Route (`go_router`) để đảm bảo Auto-Dispose khi chuyển màn hình. Không gọi Provider ở trong logic khởi tạo Component bên trong.
