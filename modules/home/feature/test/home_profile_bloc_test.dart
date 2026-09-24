import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_di/core_di.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand-written [IAuthStatusStream]: a broadcast controller plus the
/// current user, which is what `feature_auth`'s implementation is.
class _FakeAuthStatusStream implements IAuthStatusStream {
  _FakeAuthStatusStream({this.currentUser});

  final controller = StreamController<AuthPrincipal?>.broadcast();

  @override
  AuthPrincipal? currentUser;

  @override
  Stream<AuthPrincipal?> get authStatusStream => controller.stream;
}

const _ada = AuthPrincipal(id: '1', displayName: 'Ada');
const _grace = AuthPrincipal(id: '2', displayName: 'Grace');

void main() {
  test(
    'with no auth module registered, Home shows the signed-out state',
    () async {
      // The route passes `getItOrNull<IAuthStatusStream>()`, which is null in
      // an app composed without `feature_auth`.
      final bloc = HomeProfileBloc(null);
      addTearDown(bloc.close);

      await expectLater(
        bloc.stream,
        emits(const BlocViewState<AuthPrincipal?>.success(null)),
      );
      expect(bloc.state.data, isNull);
    },
  );

  test('starts from the stream\'s current user', () async {
    final auth = _FakeAuthStatusStream(currentUser: _ada);
    addTearDown(auth.controller.close);
    final bloc = HomeProfileBloc(auth);
    addTearDown(bloc.close);

    await expectLater(
      bloc.stream,
      emits(const BlocViewState<AuthPrincipal?>.success(_ada)),
    );
  });

  test('follows every auth status change, sign-out included', () async {
    final auth = _FakeAuthStatusStream();
    addTearDown(auth.controller.close);
    final bloc = HomeProfileBloc(auth);
    addTearDown(bloc.close);

    final states = <BlocViewState<AuthPrincipal?>>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    auth.controller.add(_grace);
    await pumpEventQueue();
    auth.controller.add(null);
    await pumpEventQueue();

    expect(states.map((s) => s.data?.id), [null, '2', null]);
  });

  test('refreshed re-reads the current user', () async {
    final auth = _FakeAuthStatusStream();
    addTearDown(auth.controller.close);
    final bloc = HomeProfileBloc(auth);
    addTearDown(bloc.close);
    await pumpEventQueue();

    // A broadcast stream does not replay: a change made while nobody was
    // listening is only picked up by re-reading `currentUser`.
    auth.currentUser = _ada;
    bloc.add(const HomeProfileEvent.refreshed());
    await pumpEventQueue();

    expect(bloc.state.data, _ada);
  });

  test('close cancels the auth subscription', () async {
    final auth = _FakeAuthStatusStream();
    addTearDown(auth.controller.close);
    final bloc = HomeProfileBloc(auth);
    await pumpEventQueue();
    expect(auth.controller.hasListener, isTrue);

    await bloc.close();

    expect(auth.controller.hasListener, isFalse);
    // An event after close would throw inside the bloc if the listener
    // survived; with it cancelled this is a no-op.
    auth.controller.add(_grace);
    await pumpEventQueue();
    expect(bloc.isClosed, isTrue);
  });
}
