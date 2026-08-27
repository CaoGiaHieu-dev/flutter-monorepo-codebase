# State Management

**This guide answers:** which state-management branch should I use for a screen, and how do I write a controller in it?

**After reading you can:** pick Provider or BLoC deliberately, wire a controller through DI at route level, render its states, and react to side effects — without hitting the traps each branch has.

---

## 1. The honest comparison

This template ships **two** state-management branches. They are **not at parity**, and picking one without knowing that is the most common source of frustration.

| | `provider_state_management` | `bloc_state_management` |
|---|---|---|
| Base class | `BaseProvider<T>` | `BaseBloc<Event, State>` / `BaseCubit<State>` |
| Lines of shared machinery | Full: `StateManager`, `OperationExecutor`, `LoadMoreMixin`, `ensureInitialized` | **None** — the base classes add nothing over `Bloc` / `Cubit` |
| `Result<T>` unwrapping | Automatic via `executeOperation` | **You write it, in every handler** |
| `AppFailure` → UI error mapping | `errorStateBuilder` hook | **You write it, in every handler** |
| Loading state | Set automatically | **You emit it, in every handler** |
| Global hooks | `OperationGlobalConfig` (`onStart`/`onSuccess`/`onFailure`/`onFinish`) | None |
| State type | `ViewStateModel<T>` wrapping `ViewState` | `BlocViewState<T>` (optional) or your own Freezed state |
| Declarative side effects | `ProviderStateListener` / `MultiProviderStateListener` | `BlocListener` (from `flutter_bloc`) |

> [!WARNING]
> `BaseBloc` and `BaseCubit` are **extension points only**. Read their own doc comments — they say so explicitly. They exist so shared behaviour (logging, analytics, default error mapping) can be added later in one place, but **today they add nothing**. Choosing BLoC means writing the `Result` unwrap / failure-map / loading-emit trio by hand in **each** event handler.

### Choosing

- **Pick Provider** when you want the automation: CRUD screens, forms, list + detail, anything where `executeOperation` removes real boilerplate.
- **Pick BLoC** when event modelling itself is the value: complex flows with many discrete triggers, replayable/traceable event streams, or when the team already standardises on BLoC.
- **Do not** pick BLoC expecting `executeOperation`-equivalent ergonomics. It is not there yet.

Both branches are registered in DI and can coexist in the same app — `feature_auth` uses Provider, `feature_home` uses BLoC.

---

## 2. The Provider branch

### 2.1 A real controller

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

Note `AuthProvider` is `@lazySingleton` because it is a **global** controller (session state outlives any one screen). A screen-scoped controller must be `@injectable` — see §4.

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

`executeOperation` runs the whole flow: global `onStart` hook → optional loading state → `await operation()` → dispatch across the four `Result` branches → global `onFinish` hook.

> [!CAUTION]
> **`showLoading: true` does not always show loading.** In `operation_executor.dart:38` the guard is:
>
> ```dart
> if (config.showLoading && _stateManager.data == null) {
>   _stateManager.setState(state: const ViewState.loading());
> }
> ```
>
> Once the provider holds data, subsequent calls **skip** the loading state. That is deliberate for pull-to-refresh (you keep showing stale content instead of flashing a spinner), but there is **no flag to override it**. If a refresh must show a spinner, call `updateState(state: const ViewState.loading())` yourself first — which is exactly what `AuthProvider.login` does above.

### 2.3 `ViewState` vs `ViewStateModel<T>`

Two distinct types in `packages/core/provider_state_management/lib/src/base/view_state_model.dart`:

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

`ErrorState` is extensible: features declare their own Freezed union (e.g. `AuthErrorState`) and map into it through `errorStateBuilder`.

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
> They are intentionally minimal: `provider_state_management` is a **core** package, and core must never depend on a feature package — so it cannot reach for the branded widgets in `core_ui_kit`. See `packages/core/provider_state_management/lib/src/base_view/default_state_widgets.dart`. **Pass your own `emptyWidget` / `loadingWidget` on any user-facing screen.**

### 2.5 Side effects with `ProviderStateListener`

Use a listener for things that are **not** rendering — toasts, navigation, dialogs. It subscribes in `initState`, cancels in `dispose`, and only fires on real state transitions:

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

That is the real pattern from `app/lib/presentation/widgets/navigator_wrapper_widget.dart` — note it navigates through **Navigator interfaces resolved with `getItOrNull`**, never by hardcoding a path. See [`04_routing.md`](04_routing.md).

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

Note the `close()` override cancelling the subscription — with no base-class help, resource cleanup is entirely your responsibility.

### 3.2 Freezed event rules

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

### 3.3 `BlocViewState<T>` — and why it was renamed

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

It used to be called `ViewState`, colliding with the Provider branch's type of the same name. Both barrels are public, so any file importing both packages would have failed to compile. The two are genuinely different:

| | Provider `ViewState` | `BlocViewState<T>` |
|---|---|---|
| Generic | No | Yes |
| Variants | 5 (adds `loadingMore`) | 4 |
| Carries data | No — data sits on `ViewStateModel<T>` | Yes — `success(T data)` |
| Error payload | `error({ErrorState? error})`, nullable | `error(AppFailure error)`, required |

`BlocViewState` is **optional**. A screen with richer needs should declare its own Freezed state and use `BaseBloc<Event, CustomState>`, keeping variants in `_state.dart` under the same `part` rules.

### 3.4 Rendering

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

Dispatch events with `context.read<HomeProfileBloc>().add(const HomeProfileEvent.refreshed())`.

### 3.5 Unwrapping `Result` by hand

Since there is no `executeOperation`, every handler that calls a use case looks like this — the pattern is spelled out in `BaseBloc`'s own doc comment:

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

## 4. Lifecycle and DI — the rule that prevents leaks

| Controller kind | Annotation | Why |
|---|---|---|
| Screen-scoped VM / BLoC | `@injectable` (factory) | A fresh instance per screen; disposed when the route pops |
| App-wide controller | `@lazySingleton` | Lives for the process (`AuthProvider`, `ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider`) |

> [!CAUTION]
> **Never register a screen-scoped controller as `@singleton` / `@lazySingleton`.** GetIt would hold the instance forever, so popping the screen leaks it and the next visit shows stale state.

Controllers are instantiated **at the route**, not inside the page. From `packages/features/home/lib/src/routing/home_route_module.dart`:

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
> **Do not double-wrap.** Because the route already provides the controller, the page must **not** wrap itself in another `BlocProvider` / `ChangeNotifierProvider`. Doing so creates a second instance — the page reads one while your events go to the other, producing state that silently never updates, plus a leak.

Global controllers such as `AuthProvider` are the exception: routes do **not** wrap them, because they are provided once near the app root and read with `Consumer<AuthProvider>` / `context.watch`.

---

## 5. Checklist

- [ ] Branch chosen deliberately, knowing BLoC has no `executeOperation`
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
