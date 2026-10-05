import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_di/core_di.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'home_profile_event.dart';
part 'home_profile_bloc.freezed.dart';

/// SAMPLE: the **stream-mapping** Bloc. It turns the session stream another
/// module publishes into screen state, so it emits `BlocViewState.success` by
/// hand; a Bloc that loads through a use case settles with `emitResult`
/// instead (RULE-53).
///
/// - `@injectable` factory, created at the route (RULE-10, RULE-21).
/// - Private Freezed events, `part` / `part of` (RULE-51).
/// - [ISessionStatusStream] is optional (its only implementer, `feature_auth`,
///   may be left out of an app), so the route passes
///   `getItOrNull<ISessionStatusStream>()` as a factory param and `null`
///   reads as "signed out".
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

  /// Subscribes once, then shows the current user. A broadcast stream does not
  /// replay, so `refreshed` re-reads `currentUser`.
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
