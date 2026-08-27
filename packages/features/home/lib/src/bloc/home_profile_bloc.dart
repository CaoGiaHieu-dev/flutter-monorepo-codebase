import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'home_profile_event.dart';
part 'home_profile_bloc.freezed.dart';

/// Sample screen-scoped Bloc for `feature_home` (BLoC is the default SM here).
///
/// Demonstrates template wiring:
/// - `@injectable` factory (not a singleton)
/// - Instantiated at the route via [BlocProvider]
/// - Private Freezed event subclasses + `part` / `part of` (AGENTS §13)
/// - Uses optional [BlocViewState] for a simple screen; complex features may use
///   a custom Freezed state instead of [BlocViewState]
/// - Listens to [IAuthStatusStream]
///
/// This is **sample / reference** code — replace with real home business logic.
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

  Future<void> _onRefreshed(
    _HomeProfileRefreshed event,
    Emitter<BlocViewState<UserEntity?>> emit,
  ) async {
    emit(BlocViewState.success(_authStatusStream.currentUser));
  }

  Future<void> _onAuthStatusChanged(
    _HomeProfileAuthStatusChanged event,
    Emitter<BlocViewState<UserEntity?>> emit,
  ) async {
    emit(BlocViewState.success(event.user));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
