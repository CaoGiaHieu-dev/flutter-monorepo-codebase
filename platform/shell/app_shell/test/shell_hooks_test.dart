import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/boot_harness.dart';
import 'support/profile_fakes.dart';

class _Unmapped implements Exception {}

/// `ShellHooks`: an app's code at fixed points — the two error channels, and
/// before / after the dependency graph.
void main() {
  final harness = BootHarness();
  late FlutterExceptionHandler? savedFlutterOnError;
  late List<FlutterErrorDetails> presented;

  setUp(() {
    harness.setUp();
    savedFlutterOnError = FlutterError.onError;
    presented = [];
    FlutterError.onError = presented.add;
  });

  tearDown(() async {
    FlutterError.onError = savedFlutterOnError;
    await harness.tearDown();
  });

  test('a hook set is const and every hook is optional', () {
    const hooks = ShellHooks();

    expect(hooks.onError, isNull);
    expect(hooks.onNonFatalError, isNull);
    expect(hooks.beforeDependencies, isNull);
    expect(hooks.afterBoot, isNull);
  });

  group('the two error channels', () {
    test('onError is the fatal channel; onNonFatalError is not called', () {
      final fatal = <Object>[];
      final nonFatal = <Object>[];
      installShellErrorHooks(
        onError: (error, _) => fatal.add(error),
        onNonFatalError: (error, _) => nonFatal.add(error),
      );

      FlutterError.reportError(const FlutterErrorDetails(exception: 'boom'));

      expect(fatal, ['boom']);
      expect(nonFatal, isEmpty);
    });

    test('onNonFatalError sees what ErrorHandler cannot classify', () {
      final reporter = FakeReporter();
      getIt.registerSingleton<IErrorReporter>(reporter);
      final fatal = <Object>[];
      final nonFatal = <Object>[];
      installShellErrorHooks(
        onError: (error, _) => fatal.add(error),
        onNonFatalError: (error, _) => nonFatal.add(error),
      );

      final error = _Unmapped();
      ErrorHandler.handleError(error, StackTrace.current);

      expect(nonFatal, [same(error)]);
      expect(fatal, isEmpty, reason: 'a handled failure is not a fatal error');
      expect(presented, isEmpty, reason: 'and is not printed as one');
      // The reporter still gets it, as before.
      expect(reporter.recorded.single.error, same(error));
      expect(reporter.recorded.single.fatal, isFalse);
    });

    test('a throwing onNonFatalError does not break the reporter', () {
      final reporter = FakeReporter();
      getIt.registerSingleton<IErrorReporter>(reporter);
      installShellErrorHooks(
        onNonFatalError: (_, _) => throw StateError('callback'),
      );

      ErrorHandler.handleError(_Unmapped(), StackTrace.current);

      expect(reporter.recorded, hasLength(1));
    });

    test('without onNonFatalError the behaviour is the old one', () {
      final reporter = FakeReporter();
      getIt.registerSingleton<IErrorReporter>(reporter);
      installShellErrorHooks(onError: (_, _) {});

      ErrorHandler.handleError(_Unmapped(), StackTrace.current);

      expect(reporter.recorded, hasLength(1));
    });
  });

  group('through runShellApp', () {
    testWidgets('hooks.onError receives an error from DI', (tester) async {
      final seen = <Object>[];
      final error = StateError('configureDependencies failed');

      runShellApp(
        profile: testProfile(),
        hooks: ShellHooks(onError: (e, _) => seen.add(e)),
        configureDependencies: () async => throw error,
      );
      await pumpUntil(tester, () => seen.isNotEmpty);

      expect(tester.takeException(), same(error));
      expect(seen, [same(error)]);
    });

    testWidgets('the older onError parameter is still honoured', (
      tester,
    ) async {
      final seen = <Object>[];
      final error = StateError('configureDependencies failed');

      runShellApp(
        configureDependencies: () async => throw error,
        onError: (e, _) => seen.add(e),
      );
      await pumpUntil(tester, () => seen.isNotEmpty);

      expect(tester.takeException(), same(error));
      expect(seen, [same(error)]);
    });

    testWidgets('a throwing beforeDependencies reaches onError and stops the '
        'boot before DI', (tester) async {
      final seen = <Object>[];
      var diCalls = 0;
      final error = StateError('Sentry.init failed');

      runShellApp(
        profile: testProfile(),
        hooks: ShellHooks(
          onError: (e, _) => seen.add(e),
          beforeDependencies: (_) async => throw error,
        ),
        configureDependencies: () async => diCalls++,
      );
      await pumpUntil(tester, () => seen.isNotEmpty);

      expect(tester.takeException(), same(error));
      expect(seen, [same(error)]);
      expect(diCalls, 0);
    });

    testWidgets('a throwing afterBoot reaches onError', (tester) async {
      final seen = <Object>[];
      final error = StateError('window plugin failed');

      runShellApp(
        profile: testProfile(
          capabilities: declare(provided: const {'routes'}),
        ),
        hooks: ShellHooks(
          onError: (e, _) => seen.add(e),
          afterBoot: (_) async => throw error,
        ),
        configureDependencies: () async {
          getIt.enableRegisteringMultipleInstancesOfOneType();
          registerRequiredShell();
          getIt.registerSingleton<IFeatureRouteModule>(aRoute());
        },
      );
      await pumpUntil(tester, () => seen.isNotEmpty);

      expect(seen, [same(error)]);
      // The zone reported it through the framework as well.
      tester.takeException();

      await settleAndTearDown(tester);
    });
  });

  group('registered for the graph', () {
    /// Boots a valid app with [hooks]; returns the [ShellHooks] the graph
    /// found in `getIt` while it was being built.
    Future<ShellHooks?> bootWith(WidgetTester tester, ShellHooks hooks) async {
      ShellHooks? seenInDi;
      var diRan = false;

      runShellApp(
        profile: testProfile(),
        hooks: hooks,
        configureDependencies: () async {
          seenInDi = getItOrNull<ShellHooks>();
          getIt.enableRegisteringMultipleInstancesOfOneType();
          registerRequiredShell();
          getIt.registerSingleton<IFeatureRouteModule>(aRoute());
          diRan = true;
        },
      );
      await pumpUntil(tester, () => diRan);
      await settleAndTearDown(tester);
      return seenInDi;
    }

    testWidgets('a class the graph builds reads the app\'s hooks', (
      tester,
    ) async {
      const hooks = ShellHooks(onError: _ignore);

      expect(await bootWith(tester, hooks), same(hooks));
      expect(getIt<ShellHooks>(), same(hooks));
    });

    testWidgets('the default hook set is registered too', (tester) async {
      expect(await bootWith(tester, const ShellHooks()), isNotNull);
    });

    testWidgets('a different set an earlier boot left is replaced', (
      tester,
    ) async {
      const earlier = ShellHooks(onError: _ignore);
      const hooks = ShellHooks(onNonFatalError: _ignore);
      getIt.registerSingleton<ShellHooks>(earlier);

      expect(await bootWith(tester, hooks), same(hooks));
      expect(getIt<ShellHooks>(), same(hooks));
    });

    testWidgets('the same set again is left alone', (tester) async {
      const hooks = ShellHooks(onError: _ignore);
      getIt.registerSingleton<ShellHooks>(hooks);

      expect(await bootWith(tester, hooks), same(hooks));
      expect(getIt.getAll<ShellHooks>(), hasLength(1));
    });
  });
}

void _ignore(Object error, StackTrace stack) {}
