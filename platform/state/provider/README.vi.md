🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# Provider State Management

Micro-core package cung cấp bộ khung chuẩn hóa cho việc quản lý trạng thái UI dựa trên thư viện `provider` và kiến trúc **MVVM (Model-View-ViewModel)**.

Package này loại bỏ các đoạn code lặp lại (boilerplate) trong việc chuyển trạng thái Loading, Success, Error khi gọi UseCase hay thực thi logic bất đồng bộ, giúp cho việc viết UI trở nên Declarative. Barrel của package re-export `package:provider/provider.dart` (`ChangeNotifierProvider`, `Consumer`, `Selector`, `context.read`, …).

---

## 🌟 Tính Năng Cốt Lõi

- **`ViewStateModel<T>`**: UI State bất biến (Freezed) gồm `state` (một `ViewState`), `data` (`T?`) và `message` (`String?`). `ViewState` có 5 biến thể: `initial`, `loading`, `success`, `error({ErrorState? error})`, `loadingMore`.
- **`BaseProvider<T>`**: Lớp Base ViewModel cung cấp sẵn hàm `executeOperation()` giúp tự động hóa việc đổi state quanh một `Result<R>`: loading → gọi UseCase → `success` (kèm data) hoặc `error` (kèm `message` và `ErrorState` tùy chọn).
- **`BaseViewWidget<TProvider, TData>`**: Widget tự động build giao diện dựa trên trạng thái `ViewStateModel` (tự hiển thị loading, nhả data đã khác `null`, hiện giao diện lỗi nếu bạn truyền `onErrorBuilder`).
- **`ProviderStateListener`** / **`MultiProviderStateListener`**: Widget chuyên biệt để hứng các side-effects (như chuyển trang, bật toast thông báo) mà không cần viết StatefulWidget hay Stream thủ công.
- **`LoadMoreMixin` / `LoadMoreListView`**: Quản lý số trang cho danh sách tải thêm, và một list có separator tự thêm ô spinner khi `isLoadingMore` là true.
- **`DefaultLoadingWidget` / `DefaultEmptyWidget`**: Widget mặc định của core cho trạng thái loading / rỗng — core không mượn widget từ `core_ui_kit`.

---

## 🚀 1. Quản lý Tự động hóa qua `executeOperation`

ViewModel không tự viết các câu lệnh đóng mở loading hay map kết quả. Thay vào đó, ViewModel ủy quyền cho hàm `executeOperation`, một phương thức protected của `BaseProvider` (mẫu là `AuthProvider`):

```dart
// modules/auth/feature/lib/src/provider/auth_provider.dart (abridged)
Future<void> login(String email, String password) async {
  // One sign-in at a time: a second submit (the keyboard's Done pressed
  // twice) would race two outcomes.
  if (isLoading) return;
  await executeOperation(
    OperationConfig(
      operation: () =>
          _loginUseCase(LoginParams(email: email, password: password)),
      onSuccess: _authStream.updateAuthStatus,
      onFailure: (failure) => _failures.add(
        mapAuthFailure(failure) == const AuthErrorState.invalidCredentials()
            ? const SessionInvalidCredentialsFailure()
            : SessionServerFailure(code: failure.code),
      ),
      errorStateBuilder: mapAuthFailure,
    ),
  );
}

// …

/// A 401 is a credential problem; every other failure keeps only its code.
/// A network failure has no HTTP status, so it is never read as one, and a
/// 403 is a locked account, not a wrong password.
static AuthErrorState mapAuthFailure(AppFailure<dynamic> failure) {
  return switch (failure) {
    AuthFailure(code: 401) => const AuthErrorState.invalidCredentials(),
    _ => AuthErrorState.failed(code: failure.code),
  };
}
```

`onSuccess` đưa user cho session stream, `onFailure` phát failure cho app shell, còn `errorStateBuilder` map `AppFailure` sang error state của feature mà trang đọc. Câu chặn `if (isLoading) return;` giữ cho lần submit thứ hai không chạy đua với lần đầu.

Hành vi cần biết (`platform/state/provider/lib/src/management/operation_executor.dart`):

- **Loading** → `showLoading` (mặc định `true`) chỉ chuyển sang `loading` khi provider CHƯA có data — đã có data thì UI giữ nguyên, không nháy spinner đè lên.
- **Success** → `ViewState.success()` kèm data. Nếu kiểu kết quả `R` khác kiểu state `T` của provider, truyền `convert:` cho `executeOperation`.
- **Failure** → `ViewState.error(error: errorStateBuilder?.call(failure))`, `message = failure.message` (chẩn đoán tiếng Anh dùng cho log, không phải chữ hiển thị cho người dùng — hãy hiện câu đã dịch, RULE-34). Lần emit này được **ép** (force), nên hai lỗi giống hệt nhau liên tiếp (người dùng bấm Retry khi vẫn offline) vẫn tới được listener.
- **`none` / `cancel`** → không đổi state — kể cả `loading` mà `showLoading` vừa đặt.
- Exception bị ném ra từ `operation` là một bug — bắt exception là việc của `BaseRepository.execute()` ở tầng Data — nhưng nó không bao giờ để màn hình kẹt ở `loading`: executor báo lỗi (`FlutterError.reportError`) rồi chuyển sang `error` qua `ErrorHandler.handleError`, y như một `Result.failure` (kể cả `onFailure` cục bộ / toàn cục), giống cách `emitResult` xử lý với BLoC. Exception không được ném lại.
- `onSuccess` / `onFailure` cục bộ **thay thế** callback toàn cục của `OperationGlobalConfig.instance.setup(...)` cho lần gọi đó; `onStart` / `onFinish` toàn cục luôn chạy.

---

## 🧩 2. Tự Động Hóa Render UI với `BaseViewWidget` & `LoadMoreListView`

Thay vì phải tự viết các khối `if/else` thủ công trong `Consumer` để xử lý các trạng thái `loading`, `error`, `empty` hay `success`, hệ thống đã cung cấp các UI Widget Wrapper chuẩn hóa giúp code giao diện của bạn gọn gàng (Declarative).

#### 2.1 `BaseViewWidget` (Dành cho dữ liệu thông thường)
`BaseViewWidget` dựa trên `Selector` (chỉ rebuild khi `viewState` đổi) và lắng nghe chính xác `ViewStateModel` từ `BaseProvider`.

```dart
BaseViewWidget<ProductProvider, ProductEntity>(
  // Chỉ được gọi với data khác null (success, loadingMore — và error khi
  // không truyền onErrorBuilder).
  builder: (context, product, child) {
    return Text(product.name);
  },

  // (Tùy chọn) Khi Provider chưa chạy lần nào. Không truyền → loadingWidget → DefaultLoadingWidget.
  initialWidget: (context, child) => const ProductPlaceholderWidget(),

  // (Tùy chọn) Khi đang tải. Không truyền → DefaultLoadingWidget.
  loadingWidget: (context, child) => const CircularProgressIndicator(),

  // (Tùy chọn) Khi data == null ngoài lúc initial/loading. Không truyền → DefaultEmptyWidget.
  emptyWidget: (context, child) => Text(context.l10nProduct.productNotFound),

  // (Tùy chọn) Khi lỗi — (context, data cũ, message, child).
  onErrorBuilder: (context, data, message, child) =>
      Text(message ?? context.l10n.somethingWentWrong),
)
```

> Không truyền `onErrorBuilder` thì trạng thái lỗi **không** có UI lỗi tự động: widget vẽ tiếp nhánh bình thường (data cũ qua `builder`, hoặc `emptyWidget` khi chưa có data). Muốn báo lỗi dạng toast/dialog, dùng `ProviderStateListener` (mục 3).

*(Một `BaseViewWidget` lắng nghe một provider. Màn hình kết hợp nhiều provider thì lồng mỗi provider một `BaseViewWidget`, hoặc đọc chúng bằng `context.select`.)*

#### 2.2 Danh sách phân trang: `LoadMoreMixin` + `LoadMoreListView`
Mix `LoadMoreMixin` vào provider để theo dõi `currentPage` / `totalPage` / `isLoadingMore`, giữ trang trong một `BaseProvider<PaginatedEntity<T>>`, và render bằng `LoadMoreListView<P>` bên trong `BaseViewWidget`. List tự thêm một ô spinner sau phần tử cuối khi `isLoadingMore` của provider là true.

```dart
// class UsersProvider extends BaseProvider<PaginatedEntity<UserEntity>>
//     with LoadMoreMixin<UserEntity> { … }
BaseViewWidget<UsersProvider, PaginatedEntity<UserEntity>>(
  builder: (context, page, child) {
    final users = page.data; // List<UserEntity>; phân trang ở page.meta
    if (users.isEmpty) return Text(context.l10nUsers.noUsers);
    return LoadMoreListView<UsersProvider>(
      itemCount: users.length,
      itemBuilder: (context, index) => Text(users[index].name ?? users[index].id),
    );
  },
)
```

---

## 🎧 3. Lắng Nghe Side-effects & Hiển Thị Thông Báo (`ProviderStateListener`)

Khi UI cần phản ứng với sự thay đổi trạng thái của ViewModel (chẳng hạn như bật Dialog, hiện Toast lỗi hoặc chuyển màn hình khi thành công), không sử dụng `StreamSubscription` thủ công trong các `StatefulWidget`.
Hãy dùng **`ProviderStateListener`** (hoặc `MultiProviderStateListener` với danh sách `ProviderStateListenerEntry` khi cần nhiều provider). Provider `P` phải có sẵn phía trên trong cây (listener đọc bằng `context.read<P>()` trong `initState`).

- Callback chỉ chạy khi state **thực sự đổi** (không chạy lại khi rebuild) — **trừ `onError`**: nó chạy cho **mọi** operation thất bại, kể cả khi lỗi y hệt lần trước.
- `listenWhen: (previous, current) => …` lọc thêm; `onStateChanged` chạy trước các callback riêng; ngoài ra có `onLoading`, `onLoadingMore`.

```dart
// modules/auth/feature/lib/src/pages/login_page.dart (abridged)
@override
Widget build(BuildContext context) {
  return ProviderStateListener<AuthProvider, UserEntity>(
    onError: (context, error, _) {
      if (error == const AuthErrorState.invalidCredentials()) {
        _passwordController.clear();
      }
    },
    child: Scaffold(
      // …
                    Selector<AuthProvider, bool>(
                      selector: (_, auth) => auth.isLoading,
                      builder: (context, isLoading, _) =>
                          CustomButton.rectangle(
                            disable: isLoading,
                            onPressed: _submit,
                            // …
                          ),
                    ),
      // …
    ),
  );
}
```

`Selector` chỉ rebuild nút khi `isLoading` đổi. Trang không tự bọc provider: `AuthProvider` toàn cục được `AuthTreeWrapper` gắn một lần.

> Trang này chỉ xóa ô mật khẩu: app shell (`NavigatorWrapperWidget`) **đã** hiện mọi lỗi đăng nhập dưới dạng toast đã dịch, qua `ISessionState`, nên thêm toast ở đây sẽ lặp lại. Muốn toast riêng, gọi `AppOverlay.showToast(content: ...)` với chuỗi đã dịch.

---

## 🔒 4. Quản Lý Lỗi Nghiệp Vụ Chuyên Biệt (Custom Error State)

Mặc định khi gọi API thất bại, tầng Domain trả về một `AppFailure`. Tuy nhiên, tầng UI không nên phụ thuộc cấu trúc bên trong của nó. Việc tạo **Custom Error State** giúp ta định nghĩa chính xác các trường hợp lỗi có thể xảy ra ở Feature đó để xử lý type-safe.

**File `auth_error_state.dart` bằng Freezed** (bản thật: `modules/auth/feature/lib/src/provider/auth_error_state.dart`):
```dart
// modules/auth/feature/lib/src/provider/auth_error_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:provider_state_management/provider_state_management.dart';

part 'auth_error_state.freezed.dart';

/// Why a sign-in failed, as far as the screen words it differently. Carries no
/// text (RULE-34): the shell shows a translated toast for the session failure.
@freezed
abstract class AuthErrorState extends CustomErrorState with _$AuthErrorState {
  const AuthErrorState._();

  const factory AuthErrorState.invalidCredentials() = _InvalidCredentials;

  /// Anything else — offline, a timeout, a 5xx, a locked account. [code] is the
  /// failure's `ErrorCodes` / HTTP status.
  const factory AuthErrorState.failed({int? code}) = _Failed;
}
```

`CustomErrorState` là biến thể `ErrorState.custom()` của `ErrorState` — kế thừa nó là cách một feature gắn lỗi riêng vào `ViewState.error`. *(Sau đó dùng tham số `errorStateBuilder` của `OperationConfig` để map từ `AppFailure` sang `AuthErrorState` như ví dụ ở mục 1 — bản thật là `AuthProvider.mapAuthFailure`.)*

---

## 🔗 5. Liên Kết Phụ Thuộc Giữa Các Provider

Khi `NewsProvider` cần tải lại dữ liệu mỗi khi người dùng đổi ngôn ngữ, hãy tạo lại nó ở tầng Routing, gắn key theo giá trị nó phụ thuộc. `LanguageProvider` thuộc `core_base_ui` và được mount sẵn ở gốc app (`AppMaterialWrapper`), nên feature nào cũng được phép đọc nó:

```dart
// Minh họa: repo này không có NewsRoute hay NewsProvider.
@TypedGoRoute<NewsRoute>(path: NewsPath.NEWS)
class NewsRoute extends GoRouteDataCustom with $NewsRoute {
  const NewsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final languageCode = context.select<LanguageProvider, String>(
      (language) => language.locale.languageCode,
    );
    return ChangeNotifierProvider(
      // Key mới sẽ dispose NewsProvider cũ và tạo instance mới —
      // chỉ khi ngôn ngữ thực sự đổi.
      key: ValueKey(languageCode),
      create: (_) => getIt<NewsProvider>(param1: languageCode),
      child: const NewsPage(),
    );
  }
}
```

> Route chỉ phụ thuộc vào các provider mà feature được phép thấy: của chính nó, hoặc của `core_*`. **Không** đọc `AuthProvider` từ feature khác — import `feature_auth` phá vỡ tính tách rời của module. Trạng thái đăng nhập đi qua `ISessionStatusStream` của `core_di`.

---

## ⚠️ Lưu ý Cực Kỳ Quan Trọng về Vòng Đời

1. **Route-level Auto Dispose**: Feature Providers gắn liền với một màn hình **bắt buộc dùng `@injectable`**, tuyệt đối không được dùng `@singleton` / `@lazySingleton`. (Controller toàn cục như `AuthProvider`, `ThemeProvider`, `LanguageProvider` là ngoại lệ có chủ đích và dùng `@lazySingleton`.)
2. **Khởi tạo ở Router**: Luôn bọc `ChangeNotifierProvider(create: (_) => getIt<XProvider>())` trong hàm `build` của lớp Route (`go_router`) để provider được dispose khi route rời khỏi cây widget. Page không tự bọc thêm một provider nữa.
3. **`initialize()`**: `BaseProvider` gọi `initialize()` trong một microtask sau khi khởi tạo; override nó (gọi `super.initialize()`) cho việc setup bất đồng bộ, và `await provider.ensureInitialized()` khi cần chờ nó xong.
