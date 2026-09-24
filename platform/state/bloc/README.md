🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# Bloc State Management

A micro-core package providing a UI state-management skeleton built on `flutter_bloc`, for teams that prefer an event-driven (MVI-style) architecture.

The package follows **idiomatic BLoC** (minimal, no forced ceremony), but ships a ready-made **agnostic view state** so BLoC modules integrate with — and coexist peacefully alongside — Provider modules in the same monorepo.

The barrel `package:bloc_state_management/bloc_state_management.dart` re-exports all of `flutter_bloc` (`Bloc`, `Emitter`, `BlocProvider`, `BlocBuilder`, `BlocListener`, …), so a feature does not import `flutter_bloc` separately.

---

## 🌟 Core Features

- **`BlocViewState<T>`**: A ready-made agnostic state (`initial`, `loading`, `success(T data)`, `error(AppFailure error)`) — **recommended** for simple screens; **not mandatory**. A complex feature may use its own Freezed state with `BaseBloc<Event, CustomState>`. Has a `data` getter (`T?`, non-null only in `success`).
- **`BaseBloc<Event, State>`**: The Bloc base class — **the default choice** for a BLoC (event-driven) feature.
- **`BaseCubit<State>`**: Only when the flow genuinely needs no events (a toggle, simple local UI). Do not default to Cubit for a new feature.
- **`BlocResultMixin<T>` / `CubitResultMixin<T>`**: `emitResult` — the BLoC counterpart of the Provider branch's `executeOperation` for a `BlocViewState<T>` screen: emits `loading`, runs the use case, and settles its `Result<T>` (or a thrown error) into a terminal state.
- **Agnostic & decoupled**: Fully independent of `provider_state_management`'s logic. The name `BlocViewState` (not `ViewState`) is deliberate: `provider_state_management` exports a `ViewState` that means something different, and both barrels are public.

> [!IMPORTANT]
> `BaseBloc` and `BaseCubit` are still **empty extension points** — they add nothing on top of `Bloc` / `Cubit`. The `Result` handling lives in `BlocResultMixin<T>` / `CubitResultMixin<T>` and covers a `BlocViewState<T>` state only; a Bloc with its **own** Freezed state still emits loading, unwraps `Result<T>` and maps `AppFailure` by hand (§3). The branches are closer than they were, **not** at parity: the Provider branch's `OperationGlobalConfig` hooks, `errorStateBuilder` and `LoadMoreMixin` have no BLoC counterpart.

---

## 🚀 1. Managing UI State with `BlocViewState` (recommended) or a Custom State

**`BlocViewState<T>` is not mandatory** for BLoC. It is a ready-made agnostic state (like Provider's) for simple CRUD / load-success-error screens.

- **Use `BlocViewState<T>`** when the UI only needs `initial` / `loading` / `success` / `error` around a payload `T`.
- **You may (and are encouraged to) define your own Freezed state** when the feature needs richer state (many fields, a wizard, a dirty form, pagination combined with filters, etc.). `BaseBloc<Event, YourCustomState>` is then perfectly valid — just keep the Freezed events private per AGENTS §13.

Combine it with pattern matching (`when` / `maybeWhen`) on the Freezed state for a type-safe UI. `BlocViewState`'s variants are private, so use `when` / `maybeWhen` / `whenOrNull` on it rather than a `switch`.

**Declaring a Bloc with `BlocViewState` (simple example):**
```dart
import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:domain_auth/domain_auth.dart'; // LoginUseCase, LoginParams, UserEntity
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'login_event.dart'; // LoginEvent, with a private _LoginSubmitted(email, password) variant
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

`emitResult` (`lib/src/result_emitter.dart`) emits:

| Outcome | Emitted |
|:--|:--|
| Before the call | `loading` — unless `showLoading: false`, or a `success` is already on screen (a refresh keeps the content) |
| `Result.success(data)` | `success(data)` — pass `convert:` when the payload is not already a `T` |
| `Result.success(null)` | `success(null)` for a nullable `T`, otherwise `initial` |
| `Result.failure(f)` | `error(f)` |
| `Result.none` / `.cancel` | the state before the call when `loading` was emitted (never stuck on `loading`), otherwise nothing |
| The operation throws | `error(ErrorHandler.handleError(e))`, plus `addError(e)` for `BlocObserver.onError` |

`onSuccess:` / `onFailure:` run after the state is emitted. Nothing is emitted once the handler is done (bloc closed, or replaced by a `restartable()` transformer). A Cubit mixes in `CubitResultMixin<T>` and calls `emitResult(() => ...)` without an emitter.

**Rendering the UI:**
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
          // Map the AppFailure to a translated string inside the widget —
          // never hardcode UI strings.
          error: (failure) => LoginFailureWidget(failure: failure),
        );
      },
    );
  }
}
```

*(Note: unlike Provider, whose `BaseViewWidget` shows a loading widget for you, BLoC follows a "100% explicit" philosophy — you return the loading widget yourself in the `loading` branch of `when`.)*

**Custom state (allowed):** When a screen needs more than the 4 standard states, define a Freezed state in the feature (`part '<name>_state.dart'`) and use `BaseBloc<Event, CheckoutState>` — there is no need to wrap it in `BlocViewState`.

---

## 🎧 2. Listening for Side-effects & Showing Notifications (`BlocListener`)

To open a dialog, show an error toast or navigate exactly once, wrap your UI in a `BlocListener` (instead of hand-writing a stream subscription):

```dart
@override
Widget build(BuildContext context) {
  return BlocListener<LoginBloc, BlocViewState<UserEntity>>(
    listener: (context, state) {
      state.maybeWhen(
        success: (user) {
          // Another feature's navigator: always `getItOrNull` (arch_check R8).
          getItOrNull<HomeNavigator>()?.toHome(context);
        },
        error: (failure) {
          AppOverlay.showToast(content: failure.message);
        },
        orElse: () {},
      );
    },
    child: const LoginView(), // the UI, built with a BlocBuilder as above
  );
}
```

> This is the general pattern. For this template's own sign-in flow the **app shell** navigates when the session changes (`NavigatorWrapperWidget` listens to `IAuthSessionState`), so the real login screen does not navigate itself.

---

## 🔒 3. Feature-Specific Business Errors (Custom Error State)

By default, `error` in `BlocViewState.error(error)` is an `AppFailure`. `AppFailure` is a Freezed `sealed class` in `domain_core` (`platform/layers/domain/lib/src/failures/failures.dart`), so a feature **cannot** `extends` / `implements` it to add its own errors — an `AuthErrorState extends AppFailure` does not compile. To refine errors, define the feature's **own Freezed state** carrying a feature-owned error value, use `BaseBloc<Event, CustomState>`, and map the `AppFailure` variants to that value in the handler:

```dart
// login_state.dart
part of 'login_bloc.dart';

/// The login screen's business errors — a feature value, not an AppFailure.
enum LoginError { invalidCredentials, network, unknown }

@freezed
sealed class LoginState with _$LoginState {
  const factory LoginState.initial() = LoginInitial;
  const factory LoginState.loading() = LoginLoading;
  const factory LoginState.success(UserEntity user) = LoginSuccess;
  const factory LoginState.error(LoginError error) = LoginErrorState;
}
```

Then in the Bloc:
```dart
import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:domain_auth/domain_auth.dart'; // LoginUseCase, LoginParams, UserEntity
import 'package:domain_core/domain_core.dart'; // Result, AppFailure and its variants
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

  /// Maps a Domain failure variant to the feature's error.
  ///
  /// `ErrorHandler` turns HTTP 401/403 into an `AuthFailure` and a
  /// connection error / timeout into a `NetworkFailure`.
  static LoginError _toLoginError(AppFailure failure) => switch (failure) {
    AuthFailure() || ValidationFailure() => LoginError.invalidCredentials,
    NetworkFailure() => LoginError.network,
    _ => LoginError.unknown,
  };
}
```

Rendering — `LoginState` is `sealed`, so the `switch` is checked for exhaustiveness at compile time:
```dart
BlocBuilder<LoginBloc, LoginState>(
  builder: (context, state) => switch (state) {
    LoginInitial() => const MyLoginForm(),
    LoginLoading() => const CircularProgressIndicator(),
    LoginSuccess(:final user) => WelcomeWidget(user: user),
    // LoginErrorWidget maps each LoginError to the feature's translated string.
    LoginErrorState(:final error) => LoginErrorWidget(error: error),
  },
)
```

---

## 🔗 4. Dependencies Between Blocs (Cross-Paradigm Communication)

This monorepo runs **more than one state-management library**.
Say your feature uses **BLoC**, but needs to react to changes in another feature that uses **Provider** (or the other way round).
**NEVER** import one's Bloc or Provider directly into the other's code.
**USE neutral streams**: a neutral interface in `core_di` (for example `IAuthStatusStream`, exposing a `Stream<AuthPrincipal?>` and `currentUser`), whose implementation the owning feature registers in GetIt; your `BaseBloc` listens to that stream instead of to a Provider.

The real example: `HomeProfileBloc` (`modules/home/feature/lib/src/bloc/home_profile_bloc.dart`) takes an `IAuthStatusStream?` through `@factoryParam` — the route passes `getItOrNull<IAuthStatusStream>()`, so Home still works in an app composed without `feature_auth` — and cancels its subscription in `close()`.

*(See the full architecture in [`docs/en/guides/10_cross_feature.md`](../../../docs/en/guides/10_cross_feature.md) — Model 3: Agnostic Stream.)*

For Bloc-to-Bloc links inside the same feature, you can simply pass the instance through the constructor and listen with a `StreamSubscription` inside the Bloc (cancel it in `close()`).

---

## ⚠️ 5. Critical Lifecycle Note (Route-Level Auto Dispose)

As with Provider, a Bloc tied to a screen must be released when the user leaves it.

1. **Route-level auto dispose**: Register the Bloc with `@injectable` — never `@singleton` or `@lazySingleton`.
2. **Create it in the router**: Wrap `BlocProvider` in the `build` method of the route class (`go_router`) in `<feature>_route_module.dart`. The page must **not** wrap itself in a second `BlocProvider`.

The real example, `modules/home/feature/lib/src/routing/home_route_module.dart`:

```dart
@TypedGoRoute<HomeRoute>(path: HomePath.HOME)
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
`BlocProvider` calls the Bloc's `close()` when it leaves the widget tree itself — the route is popped, or replaced by a `go` to another location. Pushing another screen **on top** does not close it, and a `StatefulShellRoute` tab (like Home) stays alive while the user switches tabs.
