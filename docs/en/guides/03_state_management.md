# State Management

**This guide answers:** which state-management branch should I use for a screen, and how do I write a controller in it?

**After reading you can:** pick Provider or BLoC deliberately, wire a controller through DI at route level, render its states, and react to side effects — without hitting the traps each branch has.

---

## 1. The honest comparison

This template ships **two** state-management branches. They now share the core of the job — run a use case, show loading, settle its `Result` — but they are **still not at parity**, and picking one without knowing where they differ is the most common source of frustration.

| | `provider_state_management` | `bloc_state_management` |
|---|---|---|
| Base class | `BaseProvider<T>` | `BaseBloc<Event, State>` / `BaseCubit<State>` |
| Lines of shared machinery | Full: `StateManager`, `OperationExecutor`, `LoadMoreMixin`, `ensureInitialized` | `BlocResultMixin` / `CubitResultMixin` (`emitResult`) — nothing else; the base classes add nothing over `Bloc` / `Cubit` |
| `Result<T>` unwrapping | Automatic via `executeOperation` | Automatic via `emitResult` **for a `BlocViewState<T>` screen**; by hand for a custom state |
| `AppFailure` → UI error mapping | `errorStateBuilder` hook | None — `error(AppFailure)` carries it as-is; map it in the view, or by hand into a custom state |
| Loading state | Set automatically (skipped once data is loaded) | `emitResult` emits it (skipped while a `success` is on screen) |
| An operation that **throws** | Propagates — the repository's `execute()` is what turns exceptions into `Result.failure` | `emitResult` catches it: `ErrorHandler.handleError` → `error(...)`, and the raw error goes to `addError` (`BlocObserver.onError`) |
| Global hooks | `OperationGlobalConfig` (`onStart`/`onSuccess`/`onFailure`/`onFinish`) | None |
| Pagination | `LoadMoreMixin` | None |
| State type | `ViewStateModel<T>` wrapping `ViewState` | `BlocViewState<T>` (optional) or your own Freezed state |
| Declarative side effects | `ProviderStateListener` / `MultiProviderStateListener` | `BlocListener` (from `flutter_bloc`) |

> [!WARNING]
> `BaseBloc` and `BaseCubit` are still **extension points only** — they add nothing over `Bloc` / `Cubit`. The `Result` unwrap / loading emit lives in a separate mixin, `BlocResultMixin<T>` (or `CubitResultMixin<T>`), and only for a screen whose state is `BlocViewState<T>` (§3.5). A Bloc with its own Freezed state writes that trio by hand in each handler, and neither branch-B mixin offers global hooks, an `errorStateBuilder` or pagination.

### Choosing

- **Pick Provider** when you want the automation: CRUD screens, forms, list + detail, anything where `executeOperation` removes real boilerplate.
- **Pick BLoC** when event modelling itself is the value: complex flows with many discrete triggers, replayable/traceable event streams, or when the team already standardises on BLoC.
- **Do not** pick BLoC expecting all of Provider's machinery. `emitResult` covers the load → settle path of a `BlocViewState<T>` screen; global hooks, `errorStateBuilder`, `LoadMoreMixin` and `ensureInitialized` have no BLoC counterpart.

Both branches are registered in DI and can coexist in the same app — `feature_auth` uses Provider, `feature_home` uses BLoC.

---

## 2. The Provider branch

### 2.1 A real controller

`modules/auth/feature/lib/src/provider/auth_provider.dart`:

```dart
@lazySingleton
class AuthProvider extends BaseProvider<UserEntity>
    implements IAuthSessionState, IAuthRefreshListenable {
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

Note `AuthProvider` is `@lazySingleton` because it is a **global** controller (session state outlives any one screen). A screen-scoped controller must be `@injectable` — see §4.

### 2.2 `OperationConfig`

`platform/provider_state_management/lib/src/management/operation_config.dart`:

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

`executeOperation` runs the whole flow: global `onStart` hook → optional loading state → `await operation()` → dispatch across the four `Result` branches → global `onFinish` hook.

#### When the use case returns something else — `convert:`

`executeOperation` is generic in the operation's result type `R`; the provider holds `T`. When they differ — the use case returns a `UserEntity`, the provider shows a `ProfileViewData` — pass `convert`, a named argument of `executeOperation` itself (not of `OperationConfig`):

```dart
// platform/provider_state_management/lib/src/base/base_provider.dart
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

How the success value becomes the provider's data (`OperationExecutor._handleSuccess`, `operation_executor.dart`):

| Case | Stored as `data` |
|:--|:--|
| `convert` passed | `convert(data)` — always wins, even when `R` already is `T` |
| no `convert`, result is a `T` | the result as-is |
| no `convert`, result is `null` | `null` |
| no `convert`, result is not a `T` | **debug:** an `assert` fails, naming both types. **release:** asserts are stripped, so the state becomes `success` with `data: null` — a screen that silently renders empty |

`onSuccess` receives the **converted** value (`T?`), not the raw `R`. The test `platform/provider_state_management/test/base_provider_test.dart` (`runConvertedOperation`) covers the path.

> [!CAUTION]
> **`showLoading: true` does not always show loading.** In `OperationExecutor.execute` (`operation_executor.dart`, behind `executeOperation`) the guard is:
>
> ```dart
> if (config.showLoading && _stateManager.data == null) {
>   _stateManager.setState(state: const ViewState.loading());
> }
> ```
>
> Once the provider holds data, subsequent calls **skip** the loading state. That is deliberate for pull-to-refresh (you keep showing stale content instead of flashing a spinner), but there is **no flag to override it**. If a refresh must show a spinner, call `updateState(state: const ViewState.loading())` yourself first — which is exactly what `AuthProvider.login` does above.

### 2.3 `ViewState` vs `ViewStateModel<T>`

Two distinct types in `platform/provider_state_management/lib/src/base/view_state_model.dart`:

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

`ViewState` is the **state machine only — it carries no data**. The data lives on the wrapper:

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

So `provider.viewState.state` is the phase and `provider.viewState.data` is the payload. Convenience getters (`isLoading`, `isSuccess`, `isError`, `isInitial`) are exposed both on `ViewState` and, via extension, on `ViewStateModel<T>`.

`ErrorState` is extensible: a feature declares its own Freezed union and maps into it through `errorStateBuilder`. The union must **extend `IErrorState`** — the `ErrorState.custom()` variant, which is what makes it an `ErrorState` at all — and, because it extends a class, needs the private `const X._()` constructor. The real one:

```dart
// modules/auth/feature/lib/src/provider/auth_error_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:provider_state_management/provider_state_management.dart';

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

`AuthProvider.mapAuthFailure` (`auth_provider.dart`) is the matching `errorStateBuilder`: it turns an `AppFailure` into one of these, or `null` for a generic error.

### 2.4 Rendering with `BaseViewWidget`

`BaseViewWidget<P, T>` selects on the provider's `ViewStateModel<T>` and renders per phase. Variants exist up to `BaseViewWidget6` (six providers), plus `PaginatedViewWidget*` for `PaginatedEntity<T>`.

```dart
BaseViewWidget<ProfileProvider, UserEntity>(
  builder: (context, user, child) => Text(user.name ?? ''),
  loadingWidget: (context, child) => const MyBrandedSpinner(),
  emptyWidget: (context, child) => const MyEmptyState(),
)
```

> [!WARNING]
> **Omit `emptyWidget` and you get a blank screen.** The built-in fallback is `DefaultEmptyWidget`, which returns `SizedBox.shrink()`. Its sibling `DefaultLoadingWidget` returns a `CircularProgressIndicator.adaptive()`.
>
> They are intentionally minimal: `provider_state_management` is a **core** package, and core must never depend on a feature package — so it cannot reach for the branded widgets in `core_ui_kit`. See `platform/provider_state_management/lib/src/base_view/default_state_widgets.dart`. **Pass your own `emptyWidget` / `loadingWidget` on any user-facing screen.**

### 2.5 Side effects with `ProviderStateListener`

Use a listener for things that are **not** rendering — toasts, navigation, dialogs. It subscribes in `initState`, cancels in `dispose`, and only fires on real state transitions — with one exception: a **repeated identical error** is passed through. The provider re-emits an equal error state only for a new failed operation (a second wrong password), and each of those must reach `onError`. A `listenWhen` that demands `previous.state != current.state` would filter that repeat straight back out, so let errors through explicitly:

```dart
ProviderStateListener<AuthProvider, UserEntity>(
  // Both terminal states: filtering on `isSuccess` alone would mean
  // `onError` never fires. `|| current.isError` keeps a repeated identical
  // error — the listener passes it through for exactly this reason.
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

An illustrative listener, as a screen inside `feature_auth` would write it — note it navigates through **Navigator interfaces resolved with `getItOrNull`**, never by hardcoding a path. See [`04_routing.md`](04_routing.md). The app shell does the same job without this widget: [`navigator_wrapper_widget.dart`](../../../platform/app_shell/lib/presentation/widgets/navigator_wrapper_widget.dart) may not import `AuthProvider`, so it subscribes to `IAuthSessionState.sessionChanges` / `sessionFailures` from `core_di` instead.

`MultiProviderStateListener` nests several listeners without a pyramid of widgets.

### 2.6 Async init

Override `initialize()` for setup that must finish before the screen trusts the provider, then `await provider.ensureInitialized()`:

```dart
@override
Future<void> initialize() async {
  updateState(state: const ViewState.loading());
  _authSubscription ??= listen(_syncAuthStream);
  await _restoreSession();
  await super.initialize();
}
```

`ensureInitialized()` resolves only after `initialize()` completes, so callers never race the setup.

---

## 3. The BLoC branch

### 3.1 A real BLoC

`modules/home/feature/lib/src/bloc/home_profile_bloc.dart`:

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<AuthPrincipal?>> {
  HomeProfileBloc(@factoryParam this._authStatusStream)
    : super(const BlocViewState.initial()) {
    on<_HomeProfileStarted>(_onStarted);
    on<_HomeProfileRefreshed>(_onRefreshed);
    on<_HomeProfileAuthStatusChanged>(_onAuthStatusChanged);

    add(const HomeProfileEvent.started());
  }

  final IAuthStatusStream? _authStatusStream;
  StreamSubscription<AuthPrincipal?>? _subscription;

  Future<void> _onStarted(
    _HomeProfileStarted event,
    Emitter<BlocViewState<AuthPrincipal?>> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = _authStatusStream?.authStatusStream.listen((user) {
      add(HomeProfileEvent.authStatusChanged(user));
    });
    emit(BlocViewState.success(_authStatusStream?.currentUser));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
```

Note the `close()` override cancelling the subscription — with no base-class help, resource cleanup is entirely your responsibility.

### 3.2 Freezed event rules

`modules/home/feature/lib/src/bloc/home_profile_event.dart`:

```dart
part of 'home_profile_bloc.dart';

@freezed
abstract class HomeProfileEvent with _$HomeProfileEvent {
  const factory HomeProfileEvent.started() = _HomeProfileStarted;
  const factory HomeProfileEvent.refreshed() = _HomeProfileRefreshed;
  const factory HomeProfileEvent.authStatusChanged(AuthPrincipal? user) =
      _HomeProfileAuthStatusChanged;
}
```

Three non-negotiable rules:

1. **Event subclasses are private** — `_HomeProfileStarted`, never `HomeProfileStarted`. They must not leak outside the package.
2. **`part` / `part of` layout** so the BLoC can name those private subclasses:
   ```dart
   part 'home_profile_event.dart';
   part 'home_profile_bloc.freezed.dart';
   ```
3. **Handlers take `(event, emit)` and are `async`.**

> [!CAUTION]
> Never register a **synchronous** closure that kicks off async work:
>
> ```dart
> // WRONG — the handler returns immediately, then emit() fires too late
> on<HomeEvent>((event, emit) {
>   event.when(started: () => _loadAsync(emit));
> });
> ```
>
> The sync handler completes at once, so the later `emit` throws
> `emit was called after an event handler completed normally`.
> Register an `async` method reference instead, as in §3.1.

### 3.3 `BlocViewState<T>`

`platform/bloc_state_management/lib/src/bloc_view_state.dart`:

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

The name avoids a collision with the Provider branch's `ViewState`. Both barrels are public, so a file importing both packages must not meet two types with the same name. The two are genuinely different:

| | Provider `ViewState` | `BlocViewState<T>` |
|---|---|---|
| Generic | No | Yes |
| Variants | 5 (adds `loadingMore`) | 4 |
| Carries data | No — data sits on `ViewStateModel<T>` | Yes — `success(T data)` |
| Error payload | `error({ErrorState? error})`, nullable | `error(AppFailure error)`, required |

`BlocViewState` is **optional**. A screen with richer needs should declare its own Freezed state and use `BaseBloc<Event, CustomState>`, keeping variants in `_state.dart` under the same `part` rules.

### 3.4 Rendering

```dart
BlocBuilder<HomeProfileBloc, BlocViewState<AuthPrincipal?>>(
  builder: (context, state) => state.when(
    initial: () => const SizedBox.shrink(),
    loading: () => const Center(child: CircularProgressIndicator.adaptive()),
    success: (user) => Text(user?.displayName ?? ''),
    error: (failure) => Text(failure.message),
  ),
)
```

Dispatch events with `context.read<HomeProfileBloc>().add(const HomeProfileEvent.refreshed())`.

### 3.5 Unwrapping `Result` — `emitResult`

`platform/bloc_state_management/lib/src/result_emitter.dart` is the BLoC branch's `executeOperation`. Mix `BlocResultMixin<T>` into a Bloc whose state is `BlocViewState<T>` and hand each handler's `emit` to `emitResult`:

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

A Cubit mixes in `CubitResultMixin<T>` instead and calls `emitResult(() => ...)` — no emitter, it emits through its own `emit`.

What `emitResult` emits, row by row:

| Outcome | Emitted |
|:--|:--|
| Before the call | `loading` — unless `showLoading: false`, or a `success` is already on screen (a refresh keeps the content) |
| `Result.success(data)` | `success(data)`; pass `convert:` when the payload is not already a `T` (without it a mismatched payload is a `StateError`) |
| `Result.success(null)` | `success(null)` when `T` is nullable, otherwise `initial` |
| `Result.failure(f)` | `error(f)` |
| `Result.none` / `Result.cancel` | the state from before the call, if `loading` was emitted — never left stuck on `loading`; otherwise nothing |
| The operation throws | `error(ErrorHandler.handleError(e))`, and `addError(e)` so `BlocObserver.onError` sees the bug |

`onSuccess:` / `onFailure:` run after that state was emitted — for follow-up work (another event, analytics), not for state. Once the handler is done — the bloc closed, or a `restartable()` transformer replaced it while the call was pending — nothing more is emitted and the callbacks are skipped.

> [!NOTE]
> `emitResult` never emits a `const` state: inside a generic helper `const BlocViewState.loading()` is a `BlocViewState<Never>`, which `==` treats as different from the `BlocViewState<T>.loading()` a view or a test expects.

**A custom Freezed state** (`BaseBloc<Event, CheckoutState>`) gets no helper — unwrap by hand, and make every branch end in a terminal state:

```dart
Future<void> _onSubmitted(
  _Submitted event,
  Emitter<CheckoutState> emit,
) async {
  final before = state;
  emit(const CheckoutState.submitting());
  final result = await _placeOrder(event.params);
  result.when(
    // `Result.success` carries a nullable payload: decide what "no data"
    // means for this screen instead of forcing it with `!`.
    success: (order) =>
        emit(order == null ? before : CheckoutState.placed(order)),
    failure: (f) => emit(CheckoutState.failed(f)),
    // Nothing to show: undo the loading state rather than leave the spinner.
    none: () => emit(before),
    cancel: () => emit(before),
  );
}
```

---

## 4. Lifecycle and DI — the rule that prevents leaks

| Controller kind | Annotation | Why |
|---|---|---|
| Screen-scoped VM / BLoC | `@injectable` (factory) | A fresh instance per screen; disposed when the route pops |
| App-wide controller | `@lazySingleton` | Lives for the process (`AuthProvider`, `ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider`) |

> [!CAUTION]
> **Never register a screen-scoped controller as `@singleton` / `@lazySingleton`.** GetIt would hold the instance forever, so popping the screen leaks it and the next visit shows stale state.

Controllers are instantiated **at the route**, not inside the page. From `modules/home/feature/lib/src/routing/home_route_module.dart`:

```dart
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      // Auth is optional: an app composed without `feature_auth` registers
      // no IAuthStatusStream, and Home then shows the signed-out state.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<IAuthStatusStream>(),
      ),
      child: const HomePage(),
    );
  }
}
```

> [!CAUTION]
> **Do not double-wrap.** Because the route already provides the controller, the page must **not** wrap itself in another `BlocProvider` / `ChangeNotifierProvider`. Doing so creates a second instance — the page reads one while your events go to the other, producing state that silently never updates, plus a leak.

Global controllers such as `AuthProvider` are the exception: routes do **not** wrap them, because they are provided once near the app root and read with `Consumer<AuthProvider>` / `context.watch`.

---

## 5. Checklist

- [ ] Branch chosen deliberately, knowing what BLoC lacks (global hooks, `errorStateBuilder`, pagination)
- [ ] A `BlocViewState<T>` Bloc settles use cases through `emitResult`, not a hand-written `result.when`
- [ ] Screen controller is `@injectable`, not a singleton
- [ ] Controller created in the **route's** `build()`, page does not re-wrap
- [ ] BLoC events are private Freezed subclasses under `part` / `part of`
- [ ] BLoC handlers are `async (event, emit)` method references
- [ ] `BaseViewWidget` given an explicit `emptyWidget` on user-facing screens
- [ ] Side effects live in a listener, not in `build()`
- [ ] Subscriptions cancelled (`close()` for BLoC, `dispose()` for Provider)

## Related

- [`04_routing.md`](04_routing.md) — where controllers get instantiated
- [`05_di.md`](05_di.md) — scopes, module order, and resolution helpers
- [`../architecture/02_core.md`](../architecture/02_core.md) — both packages in context
- [`../reference/01_rules.md`](../reference/01_rules.md) — the enforced rules
