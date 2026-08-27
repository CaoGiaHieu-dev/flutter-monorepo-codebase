import 'package:flutter_bloc/flutter_bloc.dart';

/// Base class for all Cubits in the application.
///
/// > **Read this before choosing the BLoC branch.**
/// > Like [BaseBloc], this is an *extension point only* — it adds nothing on
/// > top of [Cubit]. There is **no equivalent of the Provider branch's
/// > `executeOperation`**: every method must unwrap `Result<T>`, map
/// > `AppFailure`, and emit its own loading/terminal states by hand.
///
/// Per `.agents/AGENTS.md`, prefer [BaseBloc] with Freezed events. Reach for
/// [BaseCubit] only when the screen genuinely has no events worth modelling.
abstract class BaseCubit<State> extends Cubit<State> {
  BaseCubit(super.initialState);
}
