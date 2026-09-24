import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_di/core_di.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'home_profile_event.dart';
part 'home_profile_bloc.freezed.dart';

/// Sample screen-scoped Bloc for `feature_home` (BLoC is the default SM here).
///
/// Demonstrates template wiring:
/// - `@injectable` factory (not a singleton)
/// - Instantiated at the route via [BlocProvider]
/// - Private Freezed event subclasses + `part` / `part of` (RULE-51)
/// - Uses optional [BlocViewState] for a simple screen; complex features may use
///   a custom Freezed state instead of [BlocViewState]
/// - Listens to [ISessionStatusStream] **when one is registered**. The contract
///   is `core_di`'s, but its only implementer is `feature_auth`, which any app
///   may leave out, so the route
///   passes `getItOrNull<ISessionStatusStream>()` as a factory param and this
///   bloc reads `null` as "signed out". A required constructor dependency
///   would make DI unable to build this bloc at all once auth is removed.
///
/// This is **sample / reference** code — replace with real home business logic.
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
