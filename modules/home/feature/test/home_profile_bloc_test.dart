import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_di/core_di.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand-written [ISessionStatusStream]: a broadcast controller plus the
/// current user.
class _FakeSessionStream implements ISessionStatusStream {
  final controller = StreamController<SessionPrincipal?>.broadcast();

  Future<void> close() => controller.close();

  @override
  SessionPrincipal? currentUser;

  @override
  Stream<SessionPrincipal?> get sessionStatusStream => controller.stream;
}

const _ada = SessionPrincipal(id: '1', displayName: 'Ada');

void main() {
  test('with no session stream registered, Home is signed out', () async {
    final bloc = HomeProfileBloc(null);
    addTearDown(bloc.close);

    await expectLater(
      bloc.stream,
      emits(const BlocViewState<SessionPrincipal?>.success(null)),
    );
  });

  test('follows the stream, re-reads on refresh, cancels on close', () async {
    final session = _FakeSessionStream();
    addTearDown(session.close);
    final bloc = HomeProfileBloc(session);
    await pumpEventQueue();
    expect(bloc.state.data, isNull);

    session.controller.add(_ada);
    await pumpEventQueue();
    expect(bloc.state.data, _ada);

    // A broadcast stream does not replay: `refreshed` reads `currentUser`.
    session.currentUser = const SessionPrincipal(id: '2');
    bloc.add(const HomeProfileEvent.refreshed());
    await pumpEventQueue();
    expect(bloc.state.data?.id, '2');

    await bloc.close();
    expect(session.controller.hasListener, isFalse);
  });
}
