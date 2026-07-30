---
name: implement_bloc_ui
description: Guide for UI state management using BLoC (BaseBloc first, optional ViewState or custom Freezed state, Freezed events, BlocListener). Use Cubit only when events are unnecessary.
---

# 🧠 Skill: UI State Management with BLoC (Implement BLoC UI)

Use this skill when requested to: "implement UI logic using BLoC", "create a bloc", "listen to bloc state changes to display warnings/dialogs", etc.

## Default choice

- **Default: `BaseBloc` + Freezed `Event`** (event-driven). Follow AGENTS §13 (private event subclasses, `part` / `part of`, async `on<_Event>` handlers).
- **`BaseCubit` only when truly necessary** — e.g. a tiny local UI toggle with no meaningful events, no stream fan-in, and no multi-step workflows. Do **not** default new feature controllers to Cubit.

Reference sample in the template: `packages/features/home/lib/src/bloc/home_profile_bloc.dart`.

---

## 📋 Core Components

### 1. UI State — `ViewState<T>` (recommended) or custom Freezed state
- **`ViewState<T>` is not mandatory** for BLoC. Prefer it for simple load/success/error screens (`initial`, `loading`, `success`, `error`).
- For features that need richer UI state (forms, wizards, filters + pagination, multi-step flows), **define a Freezed state class in the feature** and use `BaseBloc<Event, YourState>`.
- Keep Event subclasses private (`part` / `part of`) per AGENTS §13 either way.

### 2. BaseBloc + Freezed Events (preferred)
```dart
import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:domain_*/domain_*.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'profile_event.dart';
part 'profile_bloc.freezed.dart';

@injectable
class ProfileBloc extends BaseBloc<ProfileEvent, ViewState<UserEntity>> {
  ProfileBloc(this._getProfileUseCase) : super(const ViewState.initial()) {
    on<_ProfileStarted>(_onStarted);
  }

  final GetProfileUseCase _getProfileUseCase;

  Future<void> _onStarted(
    _ProfileStarted event,
    Emitter<ViewState<UserEntity>> emit,
  ) async {
    emit(const ViewState.loading());
    final result = await _getProfileUseCase();
    result.when(
      success: (user) => emit(ViewState.success(user!)),
      failure: (appFailure) => emit(ViewState.error(appFailure)),
      none: () {},
      cancel: () {},
    );
  }
}
```

`profile_event.dart` (`part of 'profile_bloc.dart';`):
```dart
@freezed
abstract class ProfileEvent with _$ProfileEvent {
  const factory ProfileEvent.started() = _ProfileStarted;
}
```

### 3. Rendering UI: `BlocBuilder` & Pattern Matching
```dart
BlocBuilder<ProfileBloc, ViewState<UserEntity>>(
  builder: (context, state) {
    return state.when(
      initial: () => const SizedBox.shrink(),
      loading: () => const Center(child: CircularProgressIndicator()),
      success: (user) => Text(user.name ?? ''),
      error: (failure) => Text(failure.message),
    );
  },
)
```

### 4. Side-effects: `BlocListener`
```dart
BlocListener<ProfileBloc, ViewState<UserEntity>>(
  listener: (context, state) {
    state.maybeWhen(
      error: (failure) {
        AppDialog.showError(context, message: failure.message);
      },
      orElse: () {},
    );
  },
  child: const ProfilePageContent(),
)
```

### 5. Route-level instantiation (auto-dispose)
```dart
@override
Widget build(BuildContext context, GoRouterState state) {
  return BlocProvider(
    create: (_) => getIt<ProfileBloc>(),
    child: const ProfilePage(),
  );
}
```

### 6. When Cubit is acceptable
Only if the flow has **no events worth modeling** (single method, no concurrent intents). Prefer documenting why Cubit was chosen in a short comment. Naming remains `_cubit.dart` / `*Cubit` per AGENTS when used.

### 7. Custom state example (allowed)
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
