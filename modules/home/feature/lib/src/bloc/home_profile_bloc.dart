import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_di/core_di.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'home_profile_event.dart';
part 'home_profile_bloc.freezed.dart';

/// SAMPLE — the **stream-mapping** Bloc: it turns a stream another module
/// publishes into screen state. There is no use case and no `Result` here,
/// so it emits `BlocViewState.success` by hand; a Bloc that loads through a
/// use case mixes in `BlocResultMixin` and settles with `emitResult` instead
/// (what the module generator's BLoC template does — RULE-53).
///
/// Demonstrates template wiring:
/// - `@injectable` factory (not a singleton)
/// - Instantiated at the route via [BlocProvider]
/// - Private Freezed event subclasses + `part` / `part of` (RULE-51)
/// - Listens to [ISessionStatusStream] **when one is registered**. The contract
///   is `core_di`'s, but its only implementer is `feature_auth`, which any app
///   may leave out, so the route passes
///   `getItOrNull<ISessionStatusStream>()` as a factory param and this bloc
///   reads `null` as "signed out". A required constructor dependency would
///   make DI unable to build this bloc at all once auth is removed.
///
/// This is **sample / reference** code — replace with real home business logic.
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<SessionPrincipal?>> {
  HomeProfileBloc(@factoryParam this._sessionStatusStream)
    : super(const BlocViewState.initial()) {
    // `started` and `refreshed` do the same thing: read the current user.
    on<_HomeProfileStarted>(_onLoad);
    on<_HomeProfileRefreshed>(_onLoad);
    on<_HomeProfileAuthStatusChanged>(_onAuthStatusChanged);

    add(const HomeProfileEvent.started());
  }

  final ISessionStatusStream? _sessionStatusStream;
  StreamSubscription<SessionPrincipal?>? _subscription;

  /// Subscribes to session changes once, then shows the current user.
  ///
  /// A broadcast stream does not replay, so a change made while nobody was
  /// listening is only picked up by re-reading `currentUser` — which is what
  /// `refreshed` is for.
  Future<void> _onLoad(
    HomeProfileEvent event,
    Emitter<BlocViewState<SessionPrincipal?>> emit,
  ) async {
    _subscription ??= _sessionStatusStream?.sessionStatusStream.listen(
      (user) => add(HomeProfileEvent.authStatusChanged(user)),
    );
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
