import 'package:flutter_bloc/flutter_bloc.dart';
export 'package:flutter_bloc/flutter_bloc.dart';

/// Base class for all Blocs in the application.
///
/// > **Read this before choosing the BLoC branch.**
/// > This class is currently an *extension point only* — it adds nothing on
/// > top of [Bloc]. It exists so shared behaviour (logging, analytics,
/// > default error mapping) can be introduced later in one place without
/// > touching every feature.
///
/// Concretely, the BLoC branch has **no equivalent of the Provider branch's
/// `executeOperation`**. In each event handler you are responsible for:
///
/// - unwrapping `Result<T>` yourself (`success` / `failure` / `none` / `cancel`)
/// - mapping `AppFailure` to whatever your UI state expects
/// - emitting the loading state before the async work and a terminal state after
///
/// ```dart
/// Future<void> _onStarted(
///   _Started event,
///   Emitter<BlocViewState<Foo>> emit,
/// ) async {
///   emit(const BlocViewState.loading());
///   final result = await _useCase(const NoParams());
///   result.when(
///     success: (data) => emit(BlocViewState.success(data)),
///     failure: (f) => emit(BlocViewState.error(f)),
///     none: () => emit(const BlocViewState.initial()),
///     cancel: () {},
///   );
/// }
/// ```
///
/// The Provider branch (`provider_state_management`) wraps all of the above in
/// `executeOperation`. If that automation matters more to you than BLoC's
/// event modelling, prefer that branch — the two are not at parity today.
abstract class BaseBloc<Event, State> extends Bloc<Event, State> {
  BaseBloc(super.initialState);
}
