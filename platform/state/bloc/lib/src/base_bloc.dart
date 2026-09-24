import 'package:flutter_bloc/flutter_bloc.dart';
export 'package:flutter_bloc/flutter_bloc.dart';

/// Base class for all Blocs in the application.
///
/// An *extension point*: it adds nothing on top of [Bloc], so shared
/// behaviour (logging, analytics) can later be introduced in one place
/// without touching every feature.
///
/// For a screen whose state is `BlocViewState<T>`, mix in
/// `BlocResultMixin<T>` — the BLoC counterpart of the Provider branch's
/// `executeOperation`. Its `emitResult` emits `loading`, runs the use case,
/// and settles the `Result<T>` (`success` / `failure` / `none` / `cancel`, or
/// a thrown error) into a terminal state:
///
/// ```dart
/// class FooBloc extends BaseBloc<FooEvent, BlocViewState<Foo>>
///     with BlocResultMixin<Foo> {
///   FooBloc(this._useCase) : super(const BlocViewState.initial()) {
///     on<_Started>(_onStarted);
///   }
///
///   final GetFooUseCase _useCase;
///
///   Future<void> _onStarted(_Started event, Emitter<BlocViewState<Foo>> emit) =>
///       emitResult(emit, () => _useCase(const NoParams()));
/// }
/// ```
///
/// A Bloc with its own Freezed state (`BaseBloc<Event, CustomState>`) does
/// not get that helper: it unwraps `Result<T>`, maps `AppFailure` and emits
/// its loading/terminal states by hand.
abstract class BaseBloc<Event, State> extends Bloc<Event, State> {
  BaseBloc(super.initialState);
}
