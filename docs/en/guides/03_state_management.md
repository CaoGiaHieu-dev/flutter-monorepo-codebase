# State Management

## Goal

You write a screen controller in either branch — Provider or BLoC. It is created at the route, runs a use case, renders every state and reacts to side effects. At the end you know which traps each branch has and how to avoid them.

## Prerequisites

- A feature package to put the controller in — [`01_new_feature.md`](01_new_feature.md).
- A use case to call — [`02_new_domain_data.md`](02_new_domain_data.md).
- **How the two branches differ**, row by row, and why they are not at parity: [`../architecture/02_core.md` § 10](../architecture/02_core.md#10-state-management--two-branches-not-at-parity). Read it once before you pick.

---

## 1. Choose a branch

- **Pick Provider** when you want the automation: CRUD screens, forms, list + detail, anything where `executeOperation` removes real boilerplate.
- **Pick BLoC** when event modelling itself is the value: complex flows with many discrete triggers, replayable or traceable event streams, or a team that already standardises on BLoC.
- **Do not** pick BLoC expecting all of Provider's machinery. `emitResult` covers the load → settle path of a `BlocViewState<T>` screen. Global hooks, `errorStateBuilder`, `LoadMoreMixin` and `ensureInitialized` have no BLoC counterpart.

Both branches are registered in DI and can coexist in the same app: `feature_auth` uses Provider, `feature_home` uses BLoC. Steps 2–5 are the Provider branch; steps 6–8 are the BLoC branch; step 9 applies to both.

---

## 2. Write a Provider controller

Extend `BaseProvider<T>` and run each use case through `executeOperation`. A real controller, `modules/auth/feature/lib/src/provider/auth_provider.dart`:

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

`AuthProvider` is `@lazySingleton` because it is a **global** controller: session state outlives any one screen. A screen-scoped controller is `@injectable` (step 9).

### Configure the operation

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

`executeOperation` runs the whole flow, in this order:

1. the global `onStart` hook;
2. an optional loading state;
3. `await operation()`;
4. dispatch across the four `Result` branches;
5. the global `onFinish` hook.

### Convert a result of another type — `convert:`

`executeOperation` is generic in the operation's result type `R`, while the provider holds `T`. They can differ: the use case returns a `UserEntity`, the provider shows a `ProfileViewData`. Then pass `convert`. It is a named argument of `executeOperation` itself, not of `OperationConfig`:

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

How the success value becomes the provider's data (`OperationExecutor._handleSuccess`, `operation_executor.dart`):

| Case | Stored as `data` |
|:--|:--|
| `convert` passed | `convert(data)` — always wins, even when `R` already is `T` |
| no `convert`, result is a `T` | the result as-is |
| no `convert`, result is `null` | `null` |
| no `convert`, result is not a `T` | **debug:** an `assert` fails, naming both types. **release:** asserts are stripped, so the state becomes `success` with `data: null` — a screen that silently renders empty |

`onSuccess` receives the **converted** value (`T?`), not the raw `R`. The test `platform/state/provider/test/base_provider_test.dart` (`runConvertedOperation`) covers the path.

> [!CAUTION]
> **`showLoading: true` does not always show loading.** In `OperationExecutor.execute` (`operation_executor.dart`, behind `executeOperation`) the guard is:
>
> ```dart
> if (config.showLoading && _stateManager.data == null) {
>   _stateManager.setState(state: const ViewState.loading());
> }
> ```
>
> Once the provider holds data, later calls **skip** the loading state. That is deliberate for pull-to-refresh: you keep showing stale content instead of flashing a spinner. There is **no flag to override it**. If a refresh must show a spinner, call `updateState(state: const ViewState.loading())` yourself first — exactly what `AuthProvider.login` does above.

## 3. Render the Provider states

### Read the phase and the data

Two distinct types live in `platform/state/provider/lib/src/base/view_state_model.dart`:

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

So `provider.viewState.state` is the phase and `provider.viewState.data` is the payload. The getters `isLoading`, `isSuccess`, `isError` and `isInitial` exist on `ViewState` and, through an extension, on `ViewStateModel<T>`.

### Map a failure to your own error state

`ErrorState` is extensible. A feature declares its own Freezed union and maps into it through `errorStateBuilder`. The union must **extend `CustomErrorState`** — the `ErrorState.custom()` variant, which is what makes it an `ErrorState` at all. Because it extends a class, it needs the private `const X._()` constructor. The real one:

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

`AuthProvider.mapAuthFailure` (`auth_provider.dart`) is the matching `errorStateBuilder`. It turns an `AppFailure` into one of these, or `null` for a generic error.

### Render with `BaseViewWidget`

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
> They are minimal on purpose. `provider_state_management` is a **core** package, and core never depends on a feature package, so it cannot reach the branded widgets in `core_ui_kit`. See `platform/state/provider/lib/src/base_view/default_state_widgets.dart`. **Pass your own `emptyWidget` / `loadingWidget` on any user-facing screen.**

## 4. React to side effects with `ProviderStateListener`

Use a listener for anything that is **not** rendering: toasts, navigation, dialogs. It subscribes in `initState` and cancels in `dispose`. It fires only on real state transitions, with one exception: a **repeated identical error** is passed through.

Why the exception: the provider re-emits an equal error state only for a new failed operation, such as a second wrong password. Each of those must reach `onError`. A `listenWhen` that demands `previous.state != current.state` would filter that repeat back out, so let errors through explicitly:

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

This is an illustrative listener, as a screen inside `feature_auth` would write it. It navigates through **navigator interfaces resolved with `getItOrNull`**, never through a hardcoded path ([`04_routing.md`](04_routing.md)). `AuthNavigator` / `HomeNavigator` come from the `auth_api` / `home_api` packages.

The app shell does the same job without this widget. [`navigator_wrapper_widget.dart`](../../../platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart) may not import `AuthProvider`. It subscribes to `ISessionState.sessionChanges` / `sessionFailures` from `core_di` instead, and navigates to the paths of `ISignInLocation` / `IPostSignInLocation`. It uses no module navigator.

`MultiProviderStateListener` nests several listeners without a pyramid of widgets.

## 5. Run async setup before the screen trusts the provider

Override `initialize()` for setup that must finish first, then `await provider.ensureInitialized()`:

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

## 6. Write a BLoC

Extend `BaseBloc<Event, State>`. A real one, `modules/home/feature/lib/src/bloc/home_profile_bloc.dart`:

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

Note the `close()` override that cancels the subscription. The base class does not help here: resource cleanup is entirely yours.

### Declare the events as private Freezed subclasses

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

Three rules apply (RULE-51, RULE-52):

1. **Event subclasses are private** — `_HomeProfileStarted`, never `HomeProfileStarted`. They must not leak outside the package.
2. **Use the `part` / `part of` layout**, so the BLoC can name those private subclasses:
   ```dart
   part 'home_profile_event.dart';
   part 'home_profile_bloc.freezed.dart';
   ```
3. **Handlers take `(event, emit)` and are `async`.**

> [!CAUTION]
> Never register a **synchronous** closure that starts async work:
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
> Register an `async` method reference instead, as in the BLoC above.

## 7. Settle a use case with `emitResult`

`platform/state/bloc/lib/src/result_emitter.dart` is the BLoC branch's `executeOperation`. Mix `BlocResultMixin<T>` into a Bloc whose state is `BlocViewState<T>`, and hand each handler's `emit` to `emitResult`:

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

A Cubit mixes in `CubitResultMixin<T>` instead and calls `emitResult(() => ...)`. It takes no emitter: it emits through its own `emit`.

What `emitResult` emits, row by row:

| Outcome | Emitted |
|:--|:--|
| Before the call | `loading` — unless `showLoading: false`, or a `success` is already on screen (a refresh keeps the content) |
| `Result.success(data)` | `success(data)`; pass `convert:` when the payload is not already a `T` (without it a mismatched payload is a `StateError`) |
| `Result.success(null)` | `success(null)` when `T` is nullable, otherwise `initial` |
| `Result.failure(f)` | `error(f)` |
| `Result.none` / `Result.cancel` | the state from before the call, if `loading` was emitted — never left stuck on `loading`; otherwise nothing |
| The operation throws | `error(ErrorHandler.handleError(e))`, and `addError(e)` so `BlocObserver.onError` sees the bug |

`onSuccess:` / `onFailure:` run after that state was emitted. Use them for follow-up work (another event, analytics), not for state. Once the handler is done, nothing more is emitted and the callbacks are skipped. "Done" means the bloc closed, or a `restartable()` transformer replaced the handler while the call was pending.

> [!NOTE]
> `emitResult` never emits a `const` state. Inside a generic helper, `const BlocViewState.loading()` is a `BlocViewState<Never>`. `==` treats that as different from the `BlocViewState<T>.loading()` a view or a test expects.

### Unwrap by hand for a custom state

A custom Freezed state (`BaseBloc<Event, CheckoutState>`) gets no helper. Unwrap by hand, and make every branch end in a terminal state:

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

## 8. Render the BLoC state

`BlocViewState<T>` is the optional shared state type, in `platform/state/bloc/lib/src/bloc_view_state.dart`:

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

How it differs from Provider's `ViewState`, and why it has another name: [`../architecture/02_core.md` § 10](../architecture/02_core.md#blocviewstatet). A screen with richer needs declares its own Freezed state and uses `BaseBloc<Event, CustomState>`. Keep its variants in `_state.dart`, under the same `part` rules.

Render it with `BlocBuilder`:

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

Dispatch events with `context.read<HomeProfileBloc>().add(const HomeProfileEvent.refreshed())`.

---

## 9. Register the controller and create it at the route

| Controller kind | Annotation | Why |
|---|---|---|
| Screen-scoped VM / BLoC | `@injectable` (factory) | A fresh instance per screen; disposed when the route pops |
| App-wide controller | `@lazySingleton` | Lives for the process (`AuthProvider`, `ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider`) |

A screen-scoped controller is never a singleton (RULE-10). GetIt would hold it forever: popping the screen leaks it, and the next visit shows stale state.

Create the controller **in the route**, not in the page (RULE-21). From `modules/home/feature/lib/src/routing/home_route_module.dart`:

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
> **Do not double-wrap.** The route already provides the controller, so the page must **not** wrap itself in another `BlocProvider` / `ChangeNotifierProvider`. That creates a second instance: the page reads one while your events go to the other. The state silently never updates, and the first instance leaks.

Global controllers such as `AuthProvider` are the exception. Routes do **not** wrap them: they are provided once near the app root and read with `Consumer<AuthProvider>` / `context.watch`.

---

## Verify

```bash
dart run build_runner build --workspace     # Freezed events/states and the DI registration
flutter analyze                             # No issues found!
cd modules/<name>/feature && flutter test   # All tests passed!
cd apps/mobile && flutter test test/di_smoke_test.dart   # the controller resolves from the real graph
```

Model your tests on the real ones: `modules/auth/feature/test/auth_provider_test.dart` (a provider with hand-written fakes), `modules/home/feature/test/home_profile_bloc_test.dart` (a bloc), and `platform/state/bloc/test/result_emitter_test.dart` (`emitResult`).

Review checklist:

- [ ] Branch chosen deliberately, knowing what BLoC lacks (global hooks, `errorStateBuilder`, pagination)
- [ ] A `BlocViewState<T>` Bloc settles use cases through `emitResult`, not a hand-written `result.when`
- [ ] Screen controller is `@injectable`, not a singleton
- [ ] Controller created in the **route's** `build()`, page does not re-wrap
- [ ] BLoC events are private Freezed subclasses under `part` / `part of`
- [ ] BLoC handlers are `async (event, emit)` method references
- [ ] `BaseViewWidget` given an explicit `emptyWidget` on user-facing screens
- [ ] Side effects live in a listener, not in `build()`
- [ ] Subscriptions cancelled (`close()` for BLoC, `dispose()` for Provider)

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `emit was called after an event handler completed normally` | A sync `on<Event>` closure starts async work | Register an `async (event, emit)` method reference (step 6) |
| The screen is blank after loading | No `emptyWidget`, and the data is `null` | Pass `emptyWidget` to `BaseViewWidget` (step 3) |
| A refresh shows no spinner | `executeOperation` skips loading once data exists | Call `updateState(state: const ViewState.loading())` first (step 2) |
| State never updates on screen | The page wraps a second provider around itself | Remove the page's wrapper; the route provides it (step 9) |
| Stale data when the screen is opened again | The screen controller is a singleton | Make it `@injectable` (step 9) |
| A second identical error shows no toast | `listenWhen` filters equal states | Add `|| current.isError` (step 4) |
| Release build shows an empty success state | The use case returns another type and no `convert:` was passed | Pass `convert:` to `executeOperation` (step 2) |
| A test comparing `BlocViewState` fails although values look equal | A `const` state in generic code is `BlocViewState<Never>` | Write the type argument: `BlocViewState<T>.loading()` (step 7) |

## Related

- Rules: RULE-10 (screen controllers are factories), RULE-11 (constructor injection), RULE-21 (created at the route), RULE-50 (base classes), RULE-51 (private Freezed events), RULE-52 (async handlers), RULE-53 (`emitResult`) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 10](../architecture/02_core.md#10-state-management--two-branches-not-at-parity) — the two branches compared
- [`04_routing.md`](04_routing.md) — where controllers get instantiated
- [`05_di.md`](05_di.md) — scopes, module order, and resolution helpers
