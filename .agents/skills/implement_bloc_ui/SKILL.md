---
name: implement_bloc_ui
description: Guide for UI state management using BLoC (BaseBloc first, optional BlocViewState or custom Freezed state, Freezed events, BlocListener). Use Cubit only when events are unnecessary.
---

# 🧠 Skill: UI State Management with BLoC (Implement BLoC UI)

Use this skill when requested to: "implement UI logic using BLoC", "create a bloc", "listen to bloc state changes to display warnings/dialogs", etc.

## Default choice

- **Default: `BaseBloc` + Freezed `Event`** (event-driven). Follow AGENTS §13 (private event subclasses, `part` / `part of`, async `on<_Event>` handlers).
- **`BaseCubit` only when truly necessary** — e.g. a tiny local UI toggle with no meaningful events, no stream fan-in, and no multi-step workflows. Do **not** default new feature controllers to Cubit.

Reference sample in the template: `modules/home/feature/lib/src/bloc/home_profile_bloc.dart`.

> [!WARNING]
>  **`BaseBloc` and `BaseCubit` are *extension points only*** — they add nothing on top of
> `Bloc` / `Cubit`. The counterpart of Provider's `executeOperation` is **opt-in**: mix in
> `BlocResultMixin<T>` (or `CubitResultMixin<T>`) when the state is `BlocViewState<T>` and call
> `emitResult(emit, () => useCase(params))` — it emits loading (skipped once a success is on
> screen), success (via `convert` when the payload type differs), `error(AppFailure)`, restores
> the previous state on none/cancel, and turns a thrown exception into
> `error(ErrorHandler.handleError(e))`. With a custom Freezed state you still:
> - unwrap `Result<T>` (`success` / `failure` / `none` / `cancel`)
> - map `AppFailure` into your UI state
> - emit the loading state before the async work and a terminal state after
>
> Read `platform/state/bloc/lib/src/result_emitter.dart` before choosing.

---

## 📋 Core Components

### 1. UI State — `BlocViewState<T>` (optional) or a custom Freezed state

> [!IMPORTANT]
> The class is `BlocViewState<T>`, **not** `ViewState`. `provider_state_management` exports
> its own, semantically different `ViewState`; both barrels are public, so sharing the name
> would collide in any file importing both.

`platform/state/bloc/lib/src/bloc_view_state.dart`:

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

How it differs from the Provider `ViewState`:

| | `BlocViewState<T>` (BLoC) | `ViewState` (Provider) |
| :--- | :--- | :--- |
| Generic | yes | no |
| Carries payload | yes — `success(T data)` | no — data lives on `ViewStateModel<T>` |
| `error` argument | `AppFailure` (required) | `ErrorState?` (nullable) |
| `loadingMore` variant | no | yes |

`BlocViewState<T>` is **optional**. For richer screens (forms, wizards, filters + pagination)
declare a Freezed state in the feature and use `BaseBloc<Event, YourState>`.

### 2. BaseBloc + Freezed Events (preferred)

Real sample — `modules/home/feature/lib/src/bloc/home_profile_bloc.dart`:

```dart
import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_di/core_di.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'home_profile_event.dart';
part 'home_profile_bloc.freezed.dart';

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

  Future<void> _onRefreshed(
    _HomeProfileRefreshed event,
    Emitter<BlocViewState<SessionPrincipal?>> emit,
  ) async {
    emit(BlocViewState.success(_sessionStatusStream?.currentUser));
  }

  Future<void> _onAuthStatusChanged(
    _HomeProfileAuthStatusChanged event,
    Emitter<BlocViewState<SessionPrincipal?>> emit,
  ) async {
    emit(BlocViewState.success(event.user));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
```

`home_profile_event.dart` (`part of 'home_profile_bloc.dart';`) — real file:

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

### 3. Unwrapping a `Result<T>` by hand

There is no helper — this is the shape you write in every handler that calls a use case
(the same example as the doc comment in `platform/state/bloc/lib/src/base_bloc.dart`):

```dart
Future<void> _onStarted(
  _Started event,
  Emitter<BlocViewState<Foo>> emit,
) async {
  emit(const BlocViewState.loading());
  final result = await _useCase(const NoParams());
  result.when(
    // `Result.success` carries a nullable payload (`Result.success([T? data])`):
    // decide what "no data" means for this screen instead of forcing it non-null.
    success: (data) => data == null
        ? emit(const BlocViewState.initial())
        : emit(BlocViewState.success(data)),
    failure: (f) => emit(BlocViewState.error(f)),
    none: () => emit(const BlocViewState.initial()),
    cancel: () {},
  );
}
```

`emit(BlocViewState.success(data))` with the nullable `data` does not compile for a
non-nullable `Foo`.

> [!NOTE]
> `Result.none()` and `Result.cancel()` are declared in `domain_core` but no repository in
> the template returns them today. Handle them anyway — `when` is exhaustive.

### 4. Rendering UI: `BlocBuilder` & Pattern Matching

```dart
BlocBuilder<HomeProfileBloc, BlocViewState<SessionPrincipal?>>(
  builder: (context, state) {
    return state.when(
      initial: () => const SizedBox.shrink(),
      loading: () => const Center(child: CircularProgressIndicator()),
      success: (user) => Text(user?.displayName ?? ''),
      error: (failure) => Text(failure.message),
    );
  },
)
```

### 5. Side-effects: `BlocListener`

```dart
BlocListener<HomeProfileBloc, BlocViewState<SessionPrincipal?>>(
  listener: (context, state) {
    state.maybeWhen(
      error: (failure) {
        // `core_ui_kit`'s AppDialog: static, no BuildContext, both strings required.
        AppDialog.showErrorDialog(
          title: context.l10nHome.errorTitle, // your feature's ARB key — never a raw string
          message: failure.message,           // AppFailure.message is a non-null String
        );
      },
      orElse: () {},
    );
  },
  child: const HomePageContent(),
)
```

### 6. Route-level instantiation (auto-dispose)

```dart
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
```

> [!CAUTION]
> The `Page` widget must **not** wrap itself in another `BlocProvider`. Double-wrapping
> creates two controller instances — desynchronised state and a leak.

### 7. When Cubit is acceptable

Only if the flow has **no events worth modelling** (single method, no concurrent intents).
Document why Cubit was chosen in a short comment. Naming stays `_cubit.dart` / `*Cubit`.

### 8. Custom state example (allowed)

```dart
@freezed
abstract class CheckoutState with _$CheckoutState {
  const factory CheckoutState({
    required CartEntity cart,
    @Default(false) bool isSubmitting,
    AppFailure? error,
  }) = _CheckoutState;
}

@injectable
class CheckoutBloc extends BaseBloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc(...) : super(const CheckoutState(cart: CartEntity.empty())) {
    on<_CheckoutSubmitted>(_onSubmitted);
  }
}
```

---

## 🔗 Related

- `docs/{en,vi}/guides/03_state_management.md` — full comparison of both branches
- `implement_provider_ui` — the Provider branch, with `executeOperation`
- `implement_navigation_route` — route-level instantiation
