---
name: implement_bloc_ui
description: Guide for UI state management using BLoC (BaseBloc first, optional BlocViewState or custom Freezed state, Freezed events, BlocListener). Use Cubit only when events are unnecessary.
---

# 🧠 Skill: UI State Management with BLoC (Implement BLoC UI)

Use this skill when requested to: "implement UI logic using BLoC", "create a bloc", "listen to bloc state changes to display warnings/dialogs", etc.

## Default choice

- **Default: `BaseBloc` + Freezed `Event`** (event-driven). Follow AGENTS §13 (private event subclasses, `part` / `part of`, async `on<_Event>` handlers).
- **`BaseCubit` only when truly necessary** — e.g. a tiny local UI toggle with no meaningful events, no stream fan-in, and no multi-step workflows. Do **not** default new feature controllers to Cubit.

Reference sample in the template: `packages/features/home/lib/src/bloc/home_profile_bloc.dart`.

> [!WARNING]
> **The BLoC branch is not at parity with the Provider branch.**
> `BaseBloc` and `BaseCubit` are *extension points only* — they add nothing on top of
> `Bloc` / `Cubit`. There is **no equivalent of `executeOperation`**. In every handler you
> must yourself:
> - unwrap `Result<T>` (`success` / `failure` / `none` / `cancel`)
> - map `AppFailure` into your UI state
> - emit the loading state before the async work and a terminal state after
>
> If that automation matters more than BLoC's event modelling, use
> `implement_provider_ui` instead. Read the doc comments on
> `packages/core/bloc_state_management/lib/src/base_bloc.dart` before choosing.

---

## 📋 Core Components

### 1. UI State — `BlocViewState<T>` (optional) or a custom Freezed state

> [!IMPORTANT]
> The class is `BlocViewState<T>`, **not** `ViewState`. It was renamed because
> `provider_state_management` exports its own, semantically different `ViewState`; both
> barrels are public, so sharing the name would collide in any file importing both.

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

Real sample — `packages/features/home/lib/src/bloc/home_profile_bloc.dart`:

```dart
import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'home_profile_event.dart';
part 'home_profile_bloc.freezed.dart';

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

`home_profile_event.dart` (`part of 'home_profile_bloc.dart';`) — real file:

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

### 3. Unwrapping a `Result<T>` by hand

There is no helper — this is the shape you write in every handler that calls a use case:

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

> [!NOTE]
> `Result.none()` and `Result.cancel()` are declared in `domain_core` but no repository in
> the template returns them today. Handle them anyway — `when` is exhaustive.

### 4. Rendering UI: `BlocBuilder` & Pattern Matching

```dart
BlocBuilder<HomeProfileBloc, BlocViewState<UserEntity?>>(
  builder: (context, state) {
    return state.when(
      initial: () => const SizedBox.shrink(),
      loading: () => const Center(child: CircularProgressIndicator()),
      success: (user) => Text(user?.name ?? ''),
      error: (failure) => Text(failure.message),
    );
  },
)
```

### 5. Side-effects: `BlocListener`

```dart
BlocListener<HomeProfileBloc, BlocViewState<UserEntity?>>(
  listener: (context, state) {
    state.maybeWhen(
      error: (failure) {
        AppDialog.showError(context, message: failure.message);
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
    create: (_) => getIt<HomeProfileBloc>(),
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
