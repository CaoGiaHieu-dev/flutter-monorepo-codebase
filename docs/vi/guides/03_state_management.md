# Quản lý State

**File này trả lời:** màn hình của tôi nên dùng nhánh state management nào, và viết controller trong nhánh đó ra sao?

**Đọc xong bạn làm được:** chọn Provider hay BLoC một cách có chủ đích, gắn controller qua DI ở tầng route, render các trạng thái, và xử lý side effect — mà không dính những cái bẫy riêng của từng nhánh.

---

## 1. So sánh trung thực

Template này có **hai** nhánh state management. Chúng **không ngang bằng nhau**, và chọn mà không biết điều đó là nguyên nhân bực bội phổ biến nhất.

| | `provider_state_management` | `bloc_state_management` |
|---|---|---|
| Lớp cơ sở | `BaseProvider<T>` | `BaseBloc<Event, State>` / `BaseCubit<State>` |
| Máy móc dùng chung | Đầy đủ: `StateManager`, `OperationExecutor`, `LoadMoreMixin`, `ensureInitialized` | **Không có gì** — lớp cơ sở không thêm gì so với `Bloc` / `Cubit` |
| Bóc tách `Result<T>` | Tự động qua `executeOperation` | **Bạn tự viết, trong TỪNG handler** |
| Map `AppFailure` → lỗi UI | Hook `errorStateBuilder` | **Bạn tự viết, trong TỪNG handler** |
| Trạng thái loading | Tự động set | **Bạn tự emit, trong TỪNG handler** |
| Hook toàn cục | `OperationGlobalConfig` (`onStart`/`onSuccess`/`onFailure`/`onFinish`) | Không có |
| Kiểu state | `ViewStateModel<T>` bọc `ViewState` | `BlocViewState<T>` (tuỳ chọn) hoặc state Freezed tự định nghĩa |
| Side effect khai báo | `ProviderStateListener` / `MultiProviderStateListener` | `BlocListener` (của `flutter_bloc`) |

> [!WARNING]
> `BaseBloc` và `BaseCubit` **chỉ là điểm mở rộng (extension point)**. Hãy đọc chính doc comment của chúng — chúng nói thẳng điều đó. Chúng tồn tại để sau này thêm hành vi dùng chung (logging, analytics, map lỗi mặc định) ở một nơi duy nhất, nhưng **hiện tại không thêm gì cả**. Chọn BLoC nghĩa là bạn tự viết bộ ba bóc-`Result` / map-lỗi / emit-loading trong **mỗi** event handler.

### Chọn thế nào

- **Chọn Provider** khi bạn muốn sự tự động hoá: màn hình CRUD, form, list + detail — bất cứ nơi nào `executeOperation` cắt được boilerplate thật.
- **Chọn BLoC** khi bản thân việc mô hình hoá event mới là giá trị: luồng phức tạp nhiều trigger rời rạc, cần replay/truy vết luồng event, hoặc team đã chuẩn hoá theo BLoC.
- **Đừng** chọn BLoC rồi kỳ vọng có trải nghiệm tương đương `executeOperation`. Chưa có.

Hai nhánh cùng đăng ký trong DI và sống chung được: `feature_auth` dùng Provider, `feature_home` dùng BLoC.

---

## 2. Nhánh Provider

### 2.1 Một controller thật

`packages/features/auth/lib/src/provider/auth_provider.dart`:

```dart
@lazySingleton
class AuthProvider extends BaseProvider<UserEntity> {
  AuthProvider(
    this._loginUseCase,
    this._logoutUseCase,
    this._refreshTokenUseCase,
    this._authStream,
  ) : super();

  final LoginUseCase _loginUseCase;
  final LogoutUseCase _logoutUseCase;
  final RefreshTokenUseCase _refreshTokenUseCase;
  final AuthStatusStreamImpl _authStream;

  bool get isAuthenticated => isSuccess && data != null;

  UserEntity? get currentUser => isAuthenticated ? data : null;

  Future<void> login(String email, String password) async {
    updateState(state: const ViewState.loading());
    await executeOperation(
      OperationConfig(
        operation: () =>
            _loginUseCase(LoginParams(email: email, password: password)),
        onSuccess: (user) async {
          DynamicLogger.log('Login successful for user: ${user?.name}');
        },
        errorStateBuilder: _mapAuthFailure,
      ),
    );
  }
}
```

`AuthProvider` là `@lazySingleton` vì nó là controller **toàn cục** (phiên đăng nhập sống lâu hơn bất kỳ màn hình nào). Controller gắn với một màn hình phải là `@injectable` — xem §4.

### 2.2 `OperationConfig`

`packages/core/provider_state_management/lib/src/management/operation_config.dart`:

```dart
class OperationConfig<R, T> {
  const OperationConfig({
    required this.operation,
    this.onSuccess,
    this.onFailure,
    this.showLoading = true,
    this.errorStateBuilder,
  });

  final FutureOr<Result<R>> Function() operation;
  final FutureOr<void> Function(T? data)? onSuccess;
  final FutureOr<void> Function(AppFailure failure)? onFailure;
  final bool showLoading;
  final ErrorState? Function(AppFailure failure)? errorStateBuilder;
}
```

`executeOperation` chạy trọn luồng: hook toàn cục `onStart` → set loading (nếu đủ điều kiện) → `await operation()` → phân nhánh theo 4 nhánh của `Result` → hook toàn cục `onFinish`.

> [!CAUTION]
> **`showLoading: true` KHÔNG phải lúc nào cũng hiện loading.** Tại `operation_executor.dart:38` điều kiện là:
>
> ```dart
> if (config.showLoading && _stateManager.data == null) {
>   _stateManager.setState(state: const ViewState.loading());
> }
> ```
>
> Khi provider đã có data, những lần gọi sau sẽ **bỏ qua** trạng thái loading. Điều này cố ý cho pull-to-refresh (giữ nội dung cũ thay vì nháy spinner), nhưng **không có cờ nào để ghi đè hành vi đó**. Nếu lần refresh bắt buộc phải hiện spinner, hãy tự gọi `updateState(state: const ViewState.loading())` trước — đúng như `AuthProvider.login` ở trên đang làm.

### 2.3 `ViewState` và `ViewStateModel<T>`

Hai kiểu khác nhau trong `packages/core/provider_state_management/lib/src/base/view_state_model.dart`:

```dart
@freezed
abstract class ViewState with _$ViewState {
  const ViewState._();
  const factory ViewState.initial() = _Initial;
  const factory ViewState.loading() = _Loading;
  const factory ViewState.success() = _Success;
  const factory ViewState.error({ErrorState? error}) = _Error;
  const factory ViewState.loadingMore() = _LoadingMore;
}
```

`ViewState` chỉ là **máy trạng thái — nó không mang data**. Data nằm ở lớp bọc:

```dart
@Freezed(genericArgumentFactories: true)
abstract class ViewStateModel<T> with _$ViewStateModel<T> {
  const factory ViewStateModel({
    @Default(ViewState.initial()) ViewState state,
    T? data,
    String? message,
  }) = _ViewStateModel<T>;
}
```

Vậy `provider.viewState.state` là pha, còn `provider.viewState.data` là dữ liệu. Các getter tiện lợi (`isLoading`, `isSuccess`, `isError`, `isInitial`) có ở cả `ViewState` lẫn `ViewStateModel<T>` (qua extension).

`ErrorState` mở rộng được: feature tự khai union Freezed riêng (ví dụ `AuthErrorState`) rồi map vào qua `errorStateBuilder`.

### 2.4 Render bằng `BaseViewWidget`

`BaseViewWidget<P, T>` select trên `ViewStateModel<T>` của provider và render theo từng pha. Có các biến thể tới `BaseViewWidget6` (sáu provider), cùng `PaginatedViewWidget*` cho `PaginatedEntity<T>`.

```dart
BaseViewWidget<ProfileProvider, UserEntity>(
  builder: (context, user, child) => Text(user.name ?? ''),
  loadingWidget: (context, child) => const MyBrandedSpinner(),
  emptyWidget: (context, child) => const MyEmptyState(),
)
```

> [!WARNING]
> **Bỏ qua `emptyWidget` là bạn nhận màn hình trắng.** Fallback mặc định là `DefaultEmptyWidget`, trả về `SizedBox.shrink()`. Còn `DefaultLoadingWidget` trả về `CircularProgressIndicator.adaptive()`.
>
> Chúng cố ý tối giản: `provider_state_management` là package **core**, mà core tuyệt đối không được phụ thuộc package feature — nên nó không thể dùng widget đã thiết kế trong `core_ui_kit`. Xem `packages/core/provider_state_management/lib/src/base_view/default_state_widgets.dart`. **Hãy luôn truyền `emptyWidget` / `loadingWidget` của riêng bạn trên màn hình người dùng thấy.**

### 2.5 Side effect với `ProviderStateListener`

Dùng listener cho những việc **không phải render** — toast, điều hướng, dialog. Nó tự subscribe trong `initState`, huỷ trong `dispose`, và chỉ bắn khi trạng thái thật sự đổi:

```dart
ProviderStateListener<AuthProvider, UserEntity>(
  listenWhen: (previous, current) =>
      previous.state != current.state && current.isSuccess,
  onError: (context, error, message) {
    if (error is AuthErrorState) {
      error.maybeWhen(
        invalidCredentials: () =>
            AppOverlay.showToast(content: context.l10nAuth.invalid_credentials),
        orElse: () => AppOverlay.showToast(content: message ?? ''),
      );
    }
  },
  onSuccess: (context, data) {
    if (data == null) {
      getItOrNull<AuthNavigator>()?.toLogin(context);
    } else {
      getItOrNull<HomeNavigator>()?.toHome(context);
    }
  },
  child: child,
)
```

Đây là pattern thật lấy từ `app/lib/presentation/widgets/navigator_wrapper_widget.dart` — chú ý nó điều hướng qua **Navigator interface resolve bằng `getItOrNull`**, không bao giờ hardcode path. Xem [`04_routing.md`](04_routing.md).

`MultiProviderStateListener` cho phép lồng nhiều listener mà không tạo kim tự tháp widget.

### 2.6 Khởi tạo bất đồng bộ

Override `initialize()` cho phần setup phải xong trước khi màn hình tin tưởng provider, rồi `await provider.ensureInitialized()`:

```dart
@override
Future<void> initialize() async {
  updateState(state: const ViewState.loading());
  _authSubscription ??= listen(_syncAuthStream);
  await _restoreSession();
  await super.initialize();
}
```

`ensureInitialized()` chỉ resolve sau khi `initialize()` hoàn tất, nên caller không bao giờ chạy đua với phần setup.

---

## 3. Nhánh BLoC

### 3.1 Một BLoC thật

`packages/features/home/lib/src/bloc/home_profile_bloc.dart`:

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<UserEntity?>> {
  HomeProfileBloc(this._authStatusStream)
      : super(const BlocViewState.initial()) {
    on<_HomeProfileStarted>(_onStarted);
    on<_HomeProfileRefreshed>(_onRefreshed);
    on<_HomeProfileAuthStatusChanged>(_onAuthStatusChanged);

    add(const HomeProfileEvent.started());
  }

  final IAuthStatusStream _authStatusStream;
  StreamSubscription<UserEntity?>? _subscription;

  Future<void> _onStarted(
    _HomeProfileStarted event,
    Emitter<BlocViewState<UserEntity?>> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = _authStatusStream.authStatusStream.listen((user) {
      add(HomeProfileEvent.authStatusChanged(user));
    });
    emit(BlocViewState.success(_authStatusStream.currentUser));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
```

Chú ý phần override `close()` để huỷ subscription — vì lớp cơ sở không hỗ trợ gì, dọn dẹp tài nguyên hoàn toàn là trách nhiệm của bạn.

### 3.2 Quy tắc event Freezed

`packages/features/home/lib/src/bloc/home_profile_event.dart`:

```dart
part of 'home_profile_bloc.dart';

@freezed
abstract class HomeProfileEvent with _$HomeProfileEvent {
  const factory HomeProfileEvent.started() = _HomeProfileStarted;
  const factory HomeProfileEvent.refreshed() = _HomeProfileRefreshed;
  const factory HomeProfileEvent.authStatusChanged(UserEntity? user) =
      _HomeProfileAuthStatusChanged;
}
```

Ba quy tắc bắt buộc:

1. **Event subclass phải private** — `_HomeProfileStarted`, không phải `HomeProfileStarted`. Chúng không được lộ ra ngoài package.
2. **Bố cục `part` / `part of`** để BLoC gọi được các subclass private đó:
   ```dart
   part 'home_profile_event.dart';
   part 'home_profile_bloc.freezed.dart';
   ```
3. **Handler nhận `(event, emit)` và phải `async`.**

> [!CAUTION]
> Tuyệt đối không đăng ký closure **đồng bộ** rồi gọi việc bất đồng bộ bên trong:
>
> ```dart
> // SAI — handler kết thúc ngay, emit() bắn quá muộn
> on<HomeEvent>((event, emit) {
>   event.when(started: () => _loadAsync(emit));
> });
> ```
>
> Handler đồng bộ hoàn tất ngay lập tức, nên `emit` sau đó ném lỗi
> `emit was called after an event handler completed normally`.
> Hãy đăng ký tham chiếu tới một method `async` như ở §3.1.

### 3.3 `BlocViewState<T>` — và vì sao phải đổi tên

`packages/core/bloc_state_management/lib/src/bloc_view_state.dart`:

```dart
@freezed
abstract class BlocViewState<T> with _$BlocViewState<T> {
  const BlocViewState._();
  const factory BlocViewState.initial() = _Initial<T>;
  const factory BlocViewState.loading() = _Loading<T>;
  const factory BlocViewState.success(T data) = _Success<T>;
  const factory BlocViewState.error(AppFailure error) = _Error<T>;

  T? get data => mapOrNull(success: (s) => s.data);
}
```

Trước đây nó tên là `ViewState`, trùng tên với kiểu cùng tên của nhánh Provider. Cả hai barrel đều public, nên bất kỳ file nào import cả hai package sẽ **không biên dịch được**. Hai kiểu này thực sự khác nhau:

| | `ViewState` (Provider) | `BlocViewState<T>` |
|---|---|---|
| Generic | Không | Có |
| Số variant | 5 (thêm `loadingMore`) | 4 |
| Mang data | Không — data nằm ở `ViewStateModel<T>` | Có — `success(T data)` |
| Kiểu lỗi | `error({ErrorState? error})`, nullable | `error(AppFailure error)`, bắt buộc |

`BlocViewState` là **tuỳ chọn**. Màn hình có nhu cầu phức tạp hơn nên tự khai state Freezed riêng và dùng `BaseBloc<Event, CustomState>`, giữ các variant trong `_state.dart` theo đúng quy tắc `part`.

### 3.4 Render

```dart
BlocBuilder<HomeProfileBloc, BlocViewState<UserEntity?>>(
  builder: (context, state) => state.when(
    initial: () => const SizedBox.shrink(),
    loading: () => const Center(child: CircularProgressIndicator.adaptive()),
    success: (user) => Text(user?.name ?? ''),
    error: (failure) => Text(failure.message ?? ''),
  ),
)
```

Bắn event bằng `context.read<HomeProfileBloc>().add(const HomeProfileEvent.refreshed())`.

### 3.5 Tự bóc `Result`

Vì không có `executeOperation`, mọi handler gọi use case đều có hình dạng như sau — chính doc comment của `BaseBloc` viết sẵn mẫu này:

```dart
Future<void> _onStarted(
  _Started event,
  Emitter<BlocViewState<Foo>> emit,
) async {
  emit(const BlocViewState.loading());
  final result = await _useCase(const NoParams());
  result.when(
    success: (data) => emit(BlocViewState.success(data)),
    failure: (f) => emit(BlocViewState.error(f)),
    none: () => emit(const BlocViewState.initial()),
    cancel: () {},
  );
}
```

---

## 4. Vòng đời và DI — quy tắc chống rò rỉ bộ nhớ

| Loại controller | Annotation | Vì sao |
|---|---|---|
| VM / BLoC gắn màn hình | `@injectable` (factory) | Mỗi màn hình một instance mới; huỷ khi pop route |
| Controller toàn app | `@lazySingleton` | Sống hết vòng đời process (`AuthProvider`, `ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider`) |

> [!CAUTION]
> **Tuyệt đối không đăng ký controller gắn màn hình là `@singleton` / `@lazySingleton`.** GetIt sẽ giữ instance vĩnh viễn, nên pop màn hình là rò rỉ bộ nhớ và lần vào sau sẽ thấy state cũ.

Controller được khởi tạo **ở route**, không phải trong page. Trích `packages/features/home/lib/src/routing/home_route_module.dart`:

```dart
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      create: (_) => getIt<HomeProfileBloc>(),
      child: const HomePage(),
    );
  }
}
```

> [!CAUTION]
> **Không được bọc hai lần.** Vì route đã cung cấp controller, page **không được** tự bọc thêm `BlocProvider` / `ChangeNotifierProvider`. Làm vậy tạo ra instance thứ hai — page đọc cái này còn event bạn bắn đi cái kia, sinh ra state âm thầm không bao giờ cập nhật, kèm rò rỉ bộ nhớ.

Controller toàn cục như `AuthProvider` là ngoại lệ: route **không** bọc chúng, vì chúng được cung cấp một lần gần gốc app và đọc bằng `Consumer<AuthProvider>` / `context.watch`.

---

## 5. Checklist

- [ ] Đã chọn nhánh có chủ đích, biết rõ BLoC không có `executeOperation`
- [ ] Controller màn hình là `@injectable`, không phải singleton
- [ ] Controller tạo trong `build()` của **route**, page không bọc lại
- [ ] Event BLoC là subclass Freezed private, theo `part` / `part of`
- [ ] Handler BLoC là tham chiếu method `async (event, emit)`
- [ ] `BaseViewWidget` được truyền `emptyWidget` rõ ràng trên màn hình người dùng
- [ ] Side effect nằm trong listener, không nằm trong `build()`
- [ ] Đã huỷ subscription (`close()` cho BLoC, `dispose()` cho Provider)

## Liên quan

- [`04_routing.md`](04_routing.md) — nơi controller được khởi tạo
- [`05_di.md`](05_di.md) — scope, thứ tự module, và các helper resolve
- [`../architecture/02_core.md`](../architecture/02_core.md) — hai package trong bức tranh chung
- [`../reference/01_rules.md`](../reference/01_rules.md) — các luật bắt buộc
