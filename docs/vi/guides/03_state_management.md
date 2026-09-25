<!-- translated-from: docs/en/guides/03_state_management.md@b65f8b3 -->
# Quản lý State

## Mục tiêu

Bạn viết được một controller cho màn hình theo một trong hai nhánh — Provider hoặc BLoC. Controller được tạo ở route, chạy use case, render mọi trạng thái và xử lý side effect. Đọc xong, bạn biết mỗi nhánh có bẫy gì và cách tránh.

## Điều kiện cần

- Một feature package để đặt controller — [`01_new_feature.md`](01_new_feature.md).
- Một use case để gọi — [`02_new_domain_data.md`](02_new_domain_data.md).
- **Hai nhánh khác nhau thế nào**, từng dòng một, và vì sao chúng chưa ngang bằng: [`../architecture/02_core.md` § 10](../architecture/02_core.md#10-state-management--hai-nhánh-chưa-ngang-bằng-nhau). Hãy đọc một lần trước khi chọn.

---

## 1. Chọn nhánh

- **Chọn Provider** khi bạn muốn sự tự động hoá: màn hình CRUD, form, list + detail — bất cứ nơi nào `executeOperation` cắt được boilerplate thật.
- **Chọn BLoC** khi bản thân việc mô hình hoá event mới là giá trị: luồng phức tạp nhiều trigger rời rạc, cần replay hay truy vết luồng event, hoặc team đã chuẩn hoá theo BLoC.
- **Đừng** chọn BLoC rồi kỳ vọng có đủ bộ máy của Provider. `emitResult` lo đường tải → chốt kết quả của màn hình `BlocViewState<T>`. Hook toàn cục, `errorStateBuilder`, `LoadMoreMixin` và `ensureInitialized` không có bản tương ứng ở BLoC.

Hai nhánh cùng đăng ký trong DI và sống chung được: `feature_auth` dùng Provider, `feature_home` dùng BLoC. Bước 2–5 là nhánh Provider; bước 6–8 là nhánh BLoC; bước 9 áp dụng cho cả hai.

---

## 2. Viết controller Provider

Kế thừa `BaseProvider<T>` và chạy mỗi use case qua `executeOperation`. Một controller thật, `modules/auth/feature/lib/src/provider/auth_provider.dart`:

```dart
@lazySingleton
class AuthProvider extends BaseProvider<UserEntity>
    implements ISessionState, ISessionRefreshListenable {
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

  Future<void> login(String email, String password) async {
    updateState(state: const ViewState.loading());
    await executeOperation(
      OperationConfig(
        operation: () =>
            _loginUseCase(LoginParams(email: email, password: password)),
        onSuccess: (user) async {
          DynamicLogger.log('Login successful for user: ${user?.name}');
        },
        errorStateBuilder: mapAuthFailure,
      ),
    );
  }
}
```

`AuthProvider` là `@lazySingleton` vì nó là controller **toàn cục**: phiên đăng nhập sống lâu hơn bất kỳ màn hình nào. Controller gắn với một màn hình là `@injectable` (bước 9).

### Cấu hình thao tác

`platform/state/provider/lib/src/management/operation_config.dart`:

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

`executeOperation` chạy trọn luồng, theo thứ tự:

1. hook toàn cục `onStart`;
2. trạng thái loading (nếu đủ điều kiện);
3. `await operation()`;
4. phân nhánh theo 4 nhánh của `Result`;
5. hook toàn cục `onFinish`.

### Đổi kết quả sang kiểu khác — `convert:`

`executeOperation` generic theo kiểu kết quả `R` của operation, còn provider giữ `T`. Hai kiểu có thể khác nhau: use case trả `UserEntity`, provider hiển thị `ProfileViewData`. Khi đó hãy truyền `convert`. Đây là named argument của chính `executeOperation`, không phải của `OperationConfig`:

```dart
// platform/state/provider/lib/src/base/base_provider.dart
Future<void> executeOperation<R>(
  OperationConfig<R, T> config, {
  T? Function(R? data)? convert,
})
```

```dart
class ProfileProvider extends BaseProvider<ProfileViewData> {
  Future<void> load(String id) async {
    await executeOperation(
      OperationConfig(operation: () => _getUserUseCase(GetUserParams(id: id))),
      convert: (user) => user == null ? null : ProfileViewData.fromUser(user),
    );
  }
}
```

Giá trị thành công trở thành `data` của provider thế nào (`OperationExecutor._handleSuccess`, `operation_executor.dart`):

| Trường hợp | Lưu vào `data` |
|:--|:--|
| Có truyền `convert` | `convert(data)` — luôn được ưu tiên, kể cả khi `R` đã là `T` |
| Không `convert`, kết quả là `T` | giữ nguyên kết quả |
| Không `convert`, kết quả là `null` | `null` |
| Không `convert`, kết quả không phải `T` | **debug:** một `assert` fail, nêu tên cả hai kiểu. **release:** assert bị loại bỏ, nên state thành `success` với `data: null` — màn hình lặng lẽ render trống |

`onSuccess` nhận giá trị **đã convert** (`T?`), không phải `R` gốc. Test `platform/state/provider/test/base_provider_test.dart` (`runConvertedOperation`) phủ nhánh này.

> [!CAUTION]
> **`showLoading: true` KHÔNG phải lúc nào cũng hiện loading.** Trong `OperationExecutor.execute` (`operation_executor.dart`, nằm sau `executeOperation`) điều kiện là:
>
> ```dart
> if (config.showLoading && _stateManager.data == null) {
>   _stateManager.setState(state: const ViewState.loading());
> }
> ```
>
> Khi provider đã có data, những lần gọi sau sẽ **bỏ qua** trạng thái loading. Điều này cố ý cho pull-to-refresh: giữ nội dung cũ thay vì nháy spinner. **Không có cờ nào để ghi đè hành vi đó.** Nếu lần refresh bắt buộc phải hiện spinner, hãy tự gọi `updateState(state: const ViewState.loading())` trước — đúng như `AuthProvider.login` ở trên đang làm.

## 3. Render các trạng thái của Provider

### Đọc pha và dữ liệu

Hai kiểu khác nhau nằm trong `platform/state/provider/lib/src/base/view_state_model.dart`:

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

Vậy `provider.viewState.state` là pha, còn `provider.viewState.data` là dữ liệu. Các getter `isLoading`, `isSuccess`, `isError`, `isInitial` có ở `ViewState` và, qua extension, ở cả `ViewStateModel<T>`.

### Map lỗi sang error state của riêng bạn

`ErrorState` mở rộng được. Feature tự khai một union Freezed riêng rồi map vào qua `errorStateBuilder`. Union đó phải **extends `CustomErrorState`** — chính là biến thể `ErrorState.custom()`, thứ khiến nó là một `ErrorState`. Vì kế thừa một class, nó cần constructor private `const X._()`. Bản thật:

```dart
// modules/auth/feature/lib/src/provider/auth_error_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:provider_state_management/provider_state_management.dart';

part 'auth_error_state.freezed.dart';

@freezed
abstract class AuthErrorState extends CustomErrorState with _$AuthErrorState {
  const AuthErrorState._();

  const factory AuthErrorState.invalidCredentials() = _InvalidCredentials;

  const factory AuthErrorState.userNotFound() = _UserNotFound;

  const factory AuthErrorState.serverError({
    required String message,
    int? code,
  }) = _ServerError;
}
```

`AuthProvider.mapAuthFailure` (`auth_provider.dart`) là `errorStateBuilder` tương ứng. Nó đổi một `AppFailure` thành một trong các biến thể này, hoặc `null` cho lỗi chung.

### Render bằng `BaseViewWidget`

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
> Chúng cố ý tối giản. `provider_state_management` là package **core**, mà core không bao giờ phụ thuộc package feature, nên nó không thể dùng widget đã thiết kế trong `core_ui_kit`. Xem `platform/state/provider/lib/src/base_view/default_state_widgets.dart`. **Hãy luôn truyền `emptyWidget` / `loadingWidget` của riêng bạn trên màn hình người dùng thấy.**

## 4. Xử lý side effect bằng `ProviderStateListener`

Dùng listener cho những việc **không phải render**: toast, điều hướng, dialog. Nó tự subscribe trong `initState` và huỷ trong `dispose`. Nó chỉ bắn khi trạng thái thật sự đổi, với một ngoại lệ: **một lỗi lặp lại y hệt** vẫn được cho qua.

Vì sao có ngoại lệ: provider chỉ phát lại một error state bằng nhau khi có một thao tác thất bại mới, chẳng hạn nhập sai mật khẩu lần hai. Mỗi lần như vậy đều phải tới được `onError`. Một `listenWhen` đòi `previous.state != current.state` sẽ lọc lần lặp đó ra, nên hãy cho lỗi đi qua một cách tường minh:

```dart
ProviderStateListener<AuthProvider, UserEntity>(
  // Cả hai trạng thái kết thúc: chỉ lọc `isSuccess` thì
  // `onError` sẽ không bao giờ được gọi. `|| current.isError` giữ lại một
  // lỗi lặp y hệt — listener cho nó qua chính vì lý do này.
  listenWhen: (previous, current) =>
      (previous.state != current.state || current.isError) &&
      (current.isSuccess || current.isError),
  onError: (context, error, message) {
    if (error is AuthErrorState) {
      error.maybeWhen(
        invalidCredentials: () =>
            AppOverlay.showToast(content: context.l10n.invalidCredentials),
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

Đây là listener minh hoạ, đúng như một màn hình trong `feature_auth` sẽ viết. Nó điều hướng qua **navigator interface resolve bằng `getItOrNull`**, không bao giờ qua path hardcode ([`04_routing.md`](04_routing.md)). `AuthNavigator` / `HomeNavigator` đến từ package `auth_api` / `home_api`.

App shell làm cùng việc đó mà không dùng widget này. [`navigator_wrapper_widget.dart`](../../../platform/shell/app_shell/lib/presentation/widgets/navigator_wrapper_widget.dart) không được import `AuthProvider`. Thay vào đó nó lắng nghe `ISessionState.sessionChanges` / `sessionFailures` của `core_di`, và điều hướng tới path của `ISignInLocation` / `IPostSignInLocation`. Nó không dùng navigator của module nào.

`MultiProviderStateListener` cho phép lồng nhiều listener mà không tạo kim tự tháp widget.

## 5. Chạy setup bất đồng bộ trước khi màn hình tin provider

Override `initialize()` cho phần setup phải xong trước, rồi `await provider.ensureInitialized()`:

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

## 6. Viết một BLoC

Kế thừa `BaseBloc<Event, State>`. Một BLoC thật, `modules/home/feature/lib/src/bloc/home_profile_bloc.dart`:

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<SessionPrincipal?>> {
  HomeProfileBloc(@factoryParam this._sessionStatusStream)
    : super(const BlocViewState.initial()) {
    on<_HomeProfileStarted>(_onStarted);
    on<_HomeProfileRefreshed>(_onRefreshed);
    on<_HomeProfileAuthStatusChanged>(_onAuthStatusChanged);

    add(const HomeProfileEvent.started());
  }

  final ISessionStatusStream? _sessionStatusStream;
  StreamSubscription<SessionPrincipal?>? _subscription;

  Future<void> _onStarted(
    _HomeProfileStarted event,
    Emitter<BlocViewState<SessionPrincipal?>> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = _sessionStatusStream?.sessionStatusStream.listen((user) {
      add(HomeProfileEvent.authStatusChanged(user));
    });
    emit(BlocViewState.success(_sessionStatusStream?.currentUser));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
```

Chú ý phần override `close()` để huỷ subscription. Lớp cơ sở không hỗ trợ gì ở đây: dọn dẹp tài nguyên hoàn toàn là việc của bạn.

### Khai event là subclass Freezed private

`modules/home/feature/lib/src/bloc/home_profile_event.dart`:

```dart
part of 'home_profile_bloc.dart';

@freezed
abstract class HomeProfileEvent with _$HomeProfileEvent {
  const factory HomeProfileEvent.started() = _HomeProfileStarted;
  const factory HomeProfileEvent.refreshed() = _HomeProfileRefreshed;
  const factory HomeProfileEvent.authStatusChanged(SessionPrincipal? user) =
      _HomeProfileAuthStatusChanged;
}
```

Ba quy tắc áp dụng (RULE-51, RULE-52):

1. **Event subclass phải private** — `_HomeProfileStarted`, không phải `HomeProfileStarted`. Chúng không được lộ ra ngoài package.
2. **Dùng bố cục `part` / `part of`**, để BLoC gọi được các subclass private đó:
   ```dart
   part 'home_profile_event.dart';
   part 'home_profile_bloc.freezed.dart';
   ```
3. **Handler nhận `(event, emit)` và phải `async`.**

> [!CAUTION]
> Tuyệt đối không đăng ký closure **đồng bộ** rồi khởi động việc bất đồng bộ bên trong:
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
> Hãy đăng ký tham chiếu tới một method `async`, như BLoC ở trên.

## 7. Chốt kết quả use case bằng `emitResult`

`platform/state/bloc/lib/src/result_emitter.dart` là `executeOperation` của nhánh BLoC. Trộn `BlocResultMixin<T>` vào Bloc có state là `BlocViewState<T>`, rồi đưa `emit` của từng handler cho `emitResult`:

```dart
@injectable
class OrdersBloc extends BaseBloc<OrdersEvent, BlocViewState<List<OrderEntity>>>
    with BlocResultMixin<List<OrderEntity>> {
  OrdersBloc(this._getOrders) : super(const BlocViewState.initial()) {
    on<_OrdersRequested>(_onRequested);
  }

  final GetOrdersUseCase _getOrders;

  Future<void> _onRequested(
    _OrdersRequested event,
    Emitter<BlocViewState<List<OrderEntity>>> emit,
  ) => emitResult(emit, () => _getOrders(const NoParams()));
}
```

Cubit thì trộn `CubitResultMixin<T>` và gọi `emitResult(() => ...)`. Nó không nhận emitter: nó emit qua chính `emit` của Cubit.

`emitResult` emit gì, từng trường hợp:

| Kết quả | Emit |
|:--|:--|
| Trước khi gọi | `loading` — trừ khi `showLoading: false`, hoặc đang hiển thị `success` (refresh giữ nguyên nội dung) |
| `Result.success(data)` | `success(data)`; truyền `convert:` khi payload chưa phải `T` (không có `convert` thì payload sai kiểu là `StateError`) |
| `Result.success(null)` | `success(null)` nếu `T` nullable, ngược lại `initial` |
| `Result.failure(f)` | `error(f)` |
| `Result.none` / `Result.cancel` | state trước lời gọi, nếu đã emit `loading` — không bao giờ kẹt ở `loading`; ngược lại không emit gì |
| Thao tác ném exception | `error(ErrorHandler.handleError(e))`, kèm `addError(e)` để `BlocObserver.onError` thấy lỗi |

`onSuccess:` / `onFailure:` chạy sau khi state đã được emit. Dùng chúng cho việc tiếp theo (bắn event khác, analytics), không dùng để đổi state. Khi handler đã xong, sẽ không emit gì thêm và các callback bị bỏ qua. "Đã xong" nghĩa là bloc đã đóng, hoặc transformer `restartable()` đã thay handler này trong lúc lời gọi còn chờ.

> [!NOTE]
> `emitResult` không bao giờ emit state `const`. Trong một helper generic, `const BlocViewState.loading()` là `BlocViewState<Never>`. `==` coi nó khác với `BlocViewState<T>.loading()` mà view hay test mong đợi.

### Tự bóc kết quả khi dùng state tuỳ biến

State Freezed tuỳ biến (`BaseBloc<Event, CheckoutState>`) không có helper. Hãy tự bóc, và cho mọi nhánh kết thúc ở một state cuối:

```dart
Future<void> _onSubmitted(
  _Submitted event,
  Emitter<CheckoutState> emit,
) async {
  final before = state;
  emit(const CheckoutState.submitting());
  final result = await _placeOrder(event.params);
  result.when(
    // `Result.success` mang payload nullable: tự quyết định "không có dữ liệu"
    // nghĩa là gì với màn hình này thay vì ép bằng `!`.
    success: (order) =>
        emit(order == null ? before : CheckoutState.placed(order)),
    failure: (f) => emit(CheckoutState.failed(f)),
    // Không có gì để hiển thị: hoàn tác loading thay vì để spinner quay mãi.
    none: () => emit(before),
    cancel: () => emit(before),
  );
}
```

## 8. Render state của BLoC

`BlocViewState<T>` là kiểu state dùng chung, tuỳ chọn, trong `platform/state/bloc/lib/src/bloc_view_state.dart`:

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

Nó khác `ViewState` của Provider ra sao, và vì sao mang tên khác: [`../architecture/02_core.md` § 10](../architecture/02_core.md#blocviewstatet). Màn hình có nhu cầu phức tạp hơn thì tự khai state Freezed riêng và dùng `BaseBloc<Event, CustomState>`. Giữ các variant trong `_state.dart`, theo đúng quy tắc `part`.

Render bằng `BlocBuilder`:

```dart
BlocBuilder<HomeProfileBloc, BlocViewState<SessionPrincipal?>>(
  builder: (context, state) => state.when(
    initial: () => const SizedBox.shrink(),
    loading: () => const Center(child: CircularProgressIndicator.adaptive()),
    success: (user) => Text(user?.displayName ?? ''),
    error: (failure) => Text(failure.message),
  ),
)
```

Bắn event bằng `context.read<HomeProfileBloc>().add(const HomeProfileEvent.refreshed())`.

---

## 9. Đăng ký controller và tạo nó ở route

| Loại controller | Annotation | Vì sao |
|---|---|---|
| VM / BLoC gắn màn hình | `@injectable` (factory) | Mỗi màn hình một instance mới; huỷ khi pop route |
| Controller toàn app | `@lazySingleton` | Sống hết vòng đời process (`AuthProvider`, `ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider`) |

Controller gắn màn hình không bao giờ là singleton (RULE-10). GetIt sẽ giữ nó vĩnh viễn: pop màn hình là rò rỉ bộ nhớ, và lần vào sau thấy state cũ.

Tạo controller **ở route**, không phải trong page (RULE-21). Trích `modules/home/feature/lib/src/routing/home_route_module.dart`:

```dart
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      // Auth is optional: an app composed without `feature_auth` registers
      // no ISessionStatusStream, and Home then shows the signed-out state.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<ISessionStatusStream>(),
      ),
      child: const HomePage(),
    );
  }
}
```

> [!CAUTION]
> **Không được bọc hai lần.** Route đã cung cấp controller, nên page **không được** tự bọc thêm `BlocProvider` / `ChangeNotifierProvider`. Làm vậy tạo ra instance thứ hai: page đọc cái này còn event bạn bắn đi cái kia. State âm thầm không bao giờ cập nhật, và instance đầu bị rò rỉ.

Controller toàn cục như `AuthProvider` là ngoại lệ. Route **không** bọc chúng: chúng được cung cấp một lần gần gốc app và đọc bằng `Consumer<AuthProvider>` / `context.watch`.

---

## Kiểm tra

```bash
dart run build_runner build --workspace     # event/state Freezed và phần đăng ký DI
flutter analyze                             # No issues found!
cd modules/<name>/feature && flutter test   # All tests passed!
cd apps/mobile && flutter test test/di_smoke_test.dart   # controller resolve được từ graph thật
```

Viết test theo mẫu các test thật: `modules/auth/feature/test/auth_provider_test.dart` (provider với fake viết tay), `modules/home/feature/test/home_profile_bloc_test.dart` (một bloc), và `platform/state/bloc/test/result_emitter_test.dart` (`emitResult`).

Checklist review:

- [ ] Đã chọn nhánh có chủ đích, biết rõ BLoC thiếu gì (hook toàn cục, `errorStateBuilder`, phân trang)
- [ ] Bloc dùng `BlocViewState<T>` chốt use case qua `emitResult`, không tự viết `result.when`
- [ ] Controller màn hình là `@injectable`, không phải singleton
- [ ] Controller tạo trong `build()` của **route**, page không bọc lại
- [ ] Event BLoC là subclass Freezed private, theo `part` / `part of`
- [ ] Handler BLoC là tham chiếu method `async (event, emit)`
- [ ] `BaseViewWidget` được truyền `emptyWidget` rõ ràng trên màn hình người dùng
- [ ] Side effect nằm trong listener, không nằm trong `build()`
- [ ] Đã huỷ subscription (`close()` cho BLoC, `dispose()` cho Provider)

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `emit was called after an event handler completed normally` | Một closure `on<Event>` đồng bộ khởi động việc bất đồng bộ | Đăng ký tham chiếu method `async (event, emit)` (bước 6) |
| Màn hình trắng sau khi tải | Không có `emptyWidget`, và data là `null` | Truyền `emptyWidget` cho `BaseViewWidget` (bước 3) |
| Refresh không hiện spinner | `executeOperation` bỏ qua loading khi đã có data | Gọi `updateState(state: const ViewState.loading())` trước (bước 2) |
| State không bao giờ cập nhật trên màn hình | Page tự bọc thêm một provider thứ hai | Bỏ lớp bọc trong page; route đã cung cấp (bước 9) |
| Dữ liệu cũ khi mở lại màn hình | Controller màn hình là singleton | Đổi sang `@injectable` (bước 9) |
| Lỗi lặp lại y hệt không hiện toast | `listenWhen` lọc bỏ các state bằng nhau | Thêm `|| current.isError` (bước 4) |
| Bản release hiện state success trống | Use case trả kiểu khác và không truyền `convert:` | Truyền `convert:` cho `executeOperation` (bước 2) |
| Test so sánh `BlocViewState` fail dù giá trị trông giống nhau | State `const` trong code generic là `BlocViewState<Never>` | Ghi rõ type argument: `BlocViewState<T>.loading()` (bước 7) |

## Liên quan

- Luật: RULE-10 (controller màn hình là factory), RULE-11 (constructor injection), RULE-21 (tạo ở route), RULE-50 (lớp cơ sở), RULE-51 (event Freezed private), RULE-52 (handler async), RULE-53 (`emitResult`) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 10](../architecture/02_core.md#10-state-management--hai-nhánh-chưa-ngang-bằng-nhau) — so sánh hai nhánh
- [`04_routing.md`](04_routing.md) — nơi controller được khởi tạo
- [`05_di.md`](05_di.md) — scope, thứ tự module, và các helper resolve
