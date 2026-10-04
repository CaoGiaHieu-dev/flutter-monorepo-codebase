import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/boot_harness.dart';
import 'support/profile_fakes.dart';
import 'support/shell_fakes.dart';

class _Splash implements IAppSplashScreen {
  @override
  Widget build() => const Text('SPLASH');
}

/// A session owner whose first restore the test finishes by hand.
class _Session implements ISessionState {
  final restore = Completer<void>();

  @override
  Future<void> ensureInitialized() => restore.future;

  @override
  bool get hasRestoredSession => restore.isCompleted;

  @override
  SessionPrincipal? get signedInUser => null;

  @override
  Stream<SessionPrincipal?> get sessionChanges => const Stream.empty();

  @override
  Stream<SessionFailure> get sessionFailures => const Stream.empty();

  @override
  void onSessionLost() {}
}

class _Gateway implements ISessionGateway {
  @override
  String? readToken() => null;

  @override
  Future<String?> refreshToken() async => null;

  @override
  Future<void> clearSession() async {}
}

class _Refresh extends ChangeNotifier implements ISessionRefreshListenable {}

/// A boot that *throws* — `configureDependencies`, an initializer, an app
/// hook — used to leave a frozen splash or a blank window; it now ends on the
/// boot error screen, still reported, with a retry that starts the boot over.
void main() {
  final harness = BootHarness();
  late FlutterExceptionHandler? savedFlutterOnError;
  late List<FlutterErrorDetails> presented;

  setUp(() {
    harness.setUp();
    presented = [];
  });
  tearDown(harness.tearDown);

  /// A `testWidgets` whose reported errors are collected in [presented]
  /// instead of failing the test by themselves: these tests assert on them.
  /// The binding installs its own `FlutterError.onError` when the test body
  /// starts, so the stand-in for the console dump goes in there.
  void bootTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      savedFlutterOnError = FlutterError.onError;
      FlutterError.onError = presented.add;
      addTearDown(() => FlutterError.onError = savedFlutterOnError);
      await body(tester);
    });
  }

  Future<void> graph({bool splash = false}) async {
    getIt.enableRegisteringMultipleInstancesOfOneType();
    registerRequiredShell();
    getIt.registerSingleton<IFeatureRouteModule>(aRoute());
    if (splash) getIt.registerSingleton<IAppSplashScreen>(_Splash());
  }

  group('configureDependencies throws', () {
    bootTest('the error screen replaces a blank window, the error is '
        'reported, and Retry boots the app', (tester) async {
      final errors = <Object>[];
      var attempts = 0;

      runShellApp(
        profile: testProfile(),
        hooks: ShellHooks(onError: (error, _) => errors.add(error)),
        configureDependencies: () async {
          attempts++;
          if (attempts == 1) throw StateError('disk full');
          await graph();
        },
      );
      await pumpUntil(
        tester,
        () => find.byType(BootErrorApp).evaluate().isNotEmpty,
      );

      expect(find.byType(BootErrorApp), findsOneWidget);
      expect(find.textContaining('[B01]'), findsOneWidget);
      expect(find.textContaining('disk full'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());

      await tester.tap(find.text('Retry'));
      await pumpUntil(tester, () => find.byType(RootApp).evaluate().isNotEmpty);

      expect(attempts, 2);
      expect(find.byType(BootErrorApp), findsNothing);
      expect(find.byType(RootApp), findsOneWidget);
      expect(errors, hasLength(1), reason: 'the retry succeeded');

      await settleAndTearDown(tester);
    });

    bootTest('a retry that fails again shows the screen again, and each '
        'failure is reported', (tester) async {
      final errors = <Object>[];
      var attempts = 0;

      runShellApp(
        profile: testProfile(),
        hooks: ShellHooks(onError: (error, _) => errors.add(error)),
        configureDependencies: () async {
          attempts++;
          throw StateError('still broken $attempts');
        },
      );
      await pumpUntil(
        tester,
        () => find.textContaining('still broken 1').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Retry'));
      await pumpUntil(
        tester,
        () => find.textContaining('still broken 2').evaluate().isNotEmpty,
      );

      expect(find.byType(BootErrorApp), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(errors, hasLength(2));
    });

    bootTest('a failing beforeDependencies hook is caught the same way', (
      tester,
    ) async {
      runShellApp(
        profile: testProfile(),
        hooks: ShellHooks(
          beforeDependencies: (_) async => throw StateError('hook bug'),
        ),
        configureDependencies: graph,
      );
      await pumpUntil(
        tester,
        () => find.byType(BootErrorApp).evaluate().isNotEmpty,
      );

      expect(find.textContaining('hook bug'), findsOneWidget);
    });
  });

  group('initialisation throws after DI', () {
    bootTest('an afterBoot hook that throws replaces the Dart splash', (
      tester,
    ) async {
      final errors = <Object>[];

      runShellApp(
        profile: testProfile(
          capabilities: declare(provided: const {'routes', 'splash'}),
        ),
        hooks: ShellHooks(
          onError: (error, _) => errors.add(error),
          afterBoot: (_) async => throw StateError('hook bug'),
        ),
        configureDependencies: () => graph(splash: true),
      );
      await pumpUntil(
        tester,
        () => find.byType(BootErrorApp).evaluate().isNotEmpty,
      );

      expect(find.byType(BootErrorApp), findsOneWidget);
      expect(find.text('SPLASH'), findsNothing);
      expect(find.byType(RootApp), findsNothing);
      expect(errors.single, isA<StateError>());
    });

    bootTest('with the native splash preserved the error still reaches '
        'the screen', (tester) async {
      debugAppPlatformOverride = AppPlatform.ios;
      final errors = <Object>[];

      runShellApp(
        profile: testProfile(),
        hooks: ShellHooks(
          onError: (error, _) => errors.add(error),
          afterBoot: (_) async => throw StateError('hook bug'),
        ),
        configureDependencies: graph,
      );
      await pumpUntil(
        tester,
        () => find.byType(BootErrorApp).evaluate().isNotEmpty,
      );

      expect(find.textContaining('hook bug'), findsOneWidget);
      expect(errors.single, isA<StateError>());
    });
  });

  group('the screen', () {
    const problem = ProfileProblem(
      code: bootFailureCode,
      description: 'The app failed while starting: secret internals',
      action: 'Fix the cause and retry.',
    );

    testWidgets('a production release shows a generic message and a Retry, '
        'never the error', (tester) async {
      await tester.pumpWidget(
        BootErrorApp(
          problems: const [problem],
          detailed: false,
          onRetry: () async {},
        ),
      );
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('secret internals'), findsNothing);
      expect(find.textContaining(bootFailureCode), findsNothing);
    });

    testWidgets('no onRetry (a wrong declaration) means no Retry button', (
      tester,
    ) async {
      await tester.pumpWidget(
        const BootErrorApp(problems: [problem], detailed: true),
      );
      await tester.pump();

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a second tap while the boot restarts does not start a '
        'second boot', (tester) async {
      var retries = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        BootErrorApp(
          problems: const [problem],
          detailed: true,
          onRetry: () {
            retries++;
            return pending.future;
          },
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.tap(find.text('Retry'), warnIfMissed: false);
      await tester.pump();

      expect(retries, 1);
      pending.complete();
    });
  });

  group('awaitSessionRestore', () {
    test('without a session owner there is nothing to wait for', () async {
      await awaitSessionRestore(null, timeout: const Duration(seconds: 1));
    });

    test('returns only after the restore has finished', () async {
      final session = _Session();
      var done = false;
      final waiting = awaitSessionRestore(
        session,
        timeout: const Duration(seconds: 5),
      ).then((_) => done = true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(done, isFalse, reason: 'the restore is still pending');

      session.restore.complete();
      await waiting;
      expect(done, isTrue);
    });

    test('a restore that never lands does not hold the boot past the '
        'timeout', () async {
      final started = Stopwatch()..start();

      await awaitSessionRestore(
        _Session(),
        timeout: const Duration(milliseconds: 50),
      );

      expect(started.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('the splash waits for the session restore', () {
    bootTest('the router is not shown until the session has restored', (
      tester,
    ) async {
      final session = _Session();
      var reachedRestoreWait = false;

      runShellApp(
        hooks: ShellHooks(afterBoot: (_) async => reachedRestoreWait = true),
        profile: testProfile(
          capabilities: declare(
            provided: const {
              'routes',
              'splash',
              'session_state',
              'session_gateway',
              'session_refresh',
              'sign_in',
            },
          ),
        ),
        configureDependencies: () async {
          await graph(splash: true);
          getIt
            ..registerSingleton<ISessionState>(session)
            ..registerSingleton<ISessionGateway>(_Gateway())
            ..registerSingleton<ISessionRefreshListenable>(_Refresh())
            ..registerSingleton<ISignInLocation>(FakeSignInLocation('/login'));
        },
      );
      // Everything before the session wait has run: only the restore is
      // pending, and the boot is not allowed past it.
      await pumpUntil(tester, () => reachedRestoreWait);
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });

      expect(reachedRestoreWait, isTrue);
      expect(find.text('SPLASH'), findsOneWidget);
      expect(find.byType(RootApp), findsNothing);

      session.restore.complete();
      await pumpUntil(tester, () => find.byType(RootApp).evaluate().isNotEmpty);

      expect(find.byType(RootApp), findsOneWidget);

      await settleAndTearDown(tester);
    });
  });
}
