import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider_state_management/provider_state_management.dart';

import 'auth_fakes.dart';

void main() {
  late FakeAuthRepository repository;

  setUp(() => repository = FakeAuthRepository());

  /// Builds the provider and waits for its session restore to finish.
  Future<AuthProvider> buildProvider() async {
    final stream = AuthStatusStreamImpl();
    final provider = AuthProvider(LoginUseCase(repository), repository, stream);
    addTearDown(provider.dispose);
    addTearDown(stream.dispose);
    await provider.ensureInitialized();
    return provider;
  }

  test('a stored session signs the user straight back in', () async {
    repository.refreshResult = const Result.success(ada);

    final provider = await buildProvider();

    expect(provider.hasRestoredSession, isTrue);
    expect(provider.data, ada);
    expect(provider.signedInUser?.displayName, 'Ada');
  });

  test('no session leaves the user signed out, not in error', () async {
    final provider = await buildProvider();

    expect(provider.hasRestoredSession, isTrue);
    expect(provider.isSuccess, isTrue);
    expect(provider.signedInUser, isNull);
  });

  test('login success stores the user and publishes the principal', () async {
    final provider = await buildProvider();
    final published = <SessionPrincipal?>[];
    final sub = provider.sessionChanges.listen(published.add);
    addTearDown(sub.cancel);

    await provider.login('ada@example.com', 'hunter2');
    await pumpEventQueue();

    expect(repository.logins, const [
      LoginParams(email: 'ada@example.com', password: 'hunter2'),
    ]);
    expect(provider.data, ada);
    expect(published.map((p) => p?.id), ['1']);
  });

  test('a 401 is invalid credentials, on both channels', () async {
    repository.loginResult = const Result.failure(
      AuthFailure(message: 'Unauthorized', code: 401),
    );
    final provider = await buildProvider();
    final failures = <SessionFailure>[];
    final sub = provider.sessionFailures.listen(failures.add);
    addTearDown(sub.cancel);

    await provider.login('ada@example.com', 'wrong');
    await pumpEventQueue();

    expect(
      provider.viewState.state,
      const ViewState.error(error: AuthErrorState.invalidCredentials()),
    );
    expect(failures.single, isA<SessionInvalidCredentialsFailure>());
    expect(provider.signedInUser, isNull);
  });

  test('any other failure is published by its code, not its text', () async {
    repository.loginResult = const Result.failure(
      ServerFailure(message: 'Maintenance', code: 503),
    );
    final provider = await buildProvider();
    final failures = <SessionFailure>[];
    final sub = provider.sessionFailures.listen(failures.add);
    addTearDown(sub.cancel);

    await provider.login('ada@example.com', 'x');
    await pumpEventQueue();

    expect(failures.single, isA<SessionServerFailure>());
    expect((failures.single as SessionServerFailure).code, 503);
  });

  test('a second login while the first is pending sends nothing', () async {
    final provider = await buildProvider();
    final pending = Completer<Result<UserEntity>>();
    repository.pendingLogin = pending.future;

    final first = provider.login('ada@example.com', 'hunter2');
    await provider.login('ada@example.com', 'hunter2');
    expect(repository.logins, hasLength(1));

    pending.complete(const Result.success(ada));
    await first;
  });

  test('logout clears the session and signs the user out', () async {
    repository.refreshResult = const Result.success(ada);
    final provider = await buildProvider();

    await provider.logout();

    expect(repository.logouts, 1);
    expect(provider.signedInUser, isNull);
  });

  test('a session lost in the transport tells a signed-in user why', () async {
    repository.refreshResult = const Result.success(ada);
    final provider = await buildProvider();
    final failures = <SessionFailure>[];
    final sub = provider.sessionFailures.listen(failures.add);
    addTearDown(sub.cancel);

    provider.onSessionLost();
    await pumpEventQueue();

    expect(provider.signedInUser, isNull);
    expect(failures.single, isA<SessionExpiredFailure>());

    provider.onSessionLost(); // nobody signed in now: nothing to explain
    await pumpEventQueue();
    expect(failures, hasLength(1));
  });
}
