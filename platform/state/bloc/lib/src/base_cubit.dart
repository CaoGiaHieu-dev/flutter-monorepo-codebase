import 'package:flutter_bloc/flutter_bloc.dart';

/// Base class for all Cubits in the application.
///
/// Like [BaseBloc], an *extension point* that adds nothing on top of
/// [Cubit]. A Cubit whose state is `BlocViewState<T>` mixes in
/// `CubitResultMixin<T>` for `emitResult` — the same rules as the Bloc
/// helper, emitting through the Cubit's own `emit`.
///
/// Per RULE-50 (`docs/en/reference/01_rules.md`), prefer [BaseBloc] with Freezed events. Reach for
/// [BaseCubit] only when the screen genuinely has no events worth modelling.
abstract class BaseCubit<State> extends Cubit<State> {
  BaseCubit(super.initialState);
}
