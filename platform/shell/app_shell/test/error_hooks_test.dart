import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

class _Recorded {
  _Recorded(this.error, this.stack, this.fatal, this.reason);

  final Object error;
  final StackTrace? stack;
  final bool fatal;
  final String? reason;
}

class _FakeReporter implements IErrorReporter {
  final recorded = <_Recorded>[];

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) async {
    recorded.add(_Recorded(error, stack, fatal, reason));
  }

  @override
  void log(String message) {}
}

class _ThrowingReporter implements IErrorReporter {
  int calls = 0;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) {
    calls++;
    throw StateError('reporter is down');
  }

  @override
  void log(String message) {}
}

class _Unmapped implements Exception {}

/// `runShellApp` routes every uncaught error — zone, framework, engine —
/// through one hook that still prints it, then hands it to `onError` and to
/// the optional `IErrorReporter`.
void main() {
  late FlutterExceptionHandler? savedFlutterOnError;
  late bool Function(Object, StackTrace)? savedPlatformOnError;
  late List<FlutterErrorDetails> presented;

  setUp(() {
    savedFlutterOnError = FlutterError.onError;
    savedPlatformOnError = PlatformDispatcher.instance.onError;
    presented = [];
    // Stands in for the console dump the hook must keep calling.
    FlutterError.onError = presented.add;
  });

  tearDown(() async {
    FlutterError.onError = savedFlutterOnError;
    PlatformDispatcher.instance.onError = savedPlatformOnError;
    ErrorHandler.onUnclassifiedError = null;
    await getIt.reset();
  });

  test('a framework error is presented, then reported as fatal', () {
    final reporter = _FakeReporter();
    getIt.registerSingleton<IErrorReporter>(reporter);
    final seen = <Object>[];
    installShellErrorHooks(onError: (error, _) => seen.add(error));

    final error = StateError('build failed');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: StackTrace.current,
        context: ErrorDescription('while building Foo'),
      ),
    );

    expect(presented.single.exception, same(error));
    expect(seen, [same(error)]);
    expect(reporter.recorded, hasLength(1));
    expect(reporter.recorded.single.error, same(error));
    expect(reporter.recorded.single.fatal, isTrue);
    expect(reporter.recorded.single.reason, 'while building Foo');
  });

  test('an engine-level error is handled and takes the same path', () {
    final reporter = _FakeReporter();
    getIt.registerSingleton<IErrorReporter>(reporter);
    final seen = <Object>[];
    installShellErrorHooks(onError: (error, _) => seen.add(error));

    final error = StateError('platform channel callback');
    final handled = PlatformDispatcher.instance.onError!(
      error,
      StackTrace.current,
    );

    expect(handled, isTrue);
    expect(presented.single.exception, same(error));
    expect(seen, [same(error)]);
    expect(reporter.recorded.single.fatal, isTrue);
  });

  test('without a reporter the error still reaches onError', () {
    final seen = <Object>[];
    installShellErrorHooks(onError: (error, _) => seen.add(error));

    FlutterError.reportError(const FlutterErrorDetails(exception: 'boom'));

    expect(seen, ['boom']);
    expect(presented, hasLength(1));
  });

  test('a throwing reporter or callback is swallowed, not re-reported', () {
    final reporter = _ThrowingReporter();
    getIt.registerSingleton<IErrorReporter>(reporter);
    installShellErrorHooks(onError: (_, _) => throw StateError('callback'));

    FlutterError.reportError(const FlutterErrorDetails(exception: 'boom'));

    expect(reporter.calls, 1);
    expect(presented, hasLength(1));
  });

  test('an exception ErrorHandler cannot classify is reported non-fatal', () {
    final reporter = _FakeReporter();
    getIt.registerSingleton<IErrorReporter>(reporter);
    final seen = <Object>[];
    installShellErrorHooks(onError: (error, _) => seen.add(error));

    final error = _Unmapped();
    final failure = ErrorHandler.handleError(error, StackTrace.current);

    expect(failure.code, ErrorCodes.UNKNOWN);
    expect(reporter.recorded.single.error, same(error));
    expect(reporter.recorded.single.fatal, isFalse);
    // Handled failures are not uncaught errors: not for `onError`, and not
    // printed as one.
    expect(seen, isEmpty);
    expect(presented, isEmpty);
  });

  test('an expected failure (no connection) is not reported', () {
    final reporter = _FakeReporter();
    getIt.registerSingleton<IErrorReporter>(reporter);
    installShellErrorHooks();

    ErrorHandler.handleError(const SocketException('offline'));

    expect(reporter.recorded, isEmpty);
  });

  testWidgets('runShellApp: an error in the app zone reaches onError once', (
    tester,
  ) async {
    final seen = <Object>[];
    final error = StateError('configureDependencies failed');

    await tester.runAsync(() async {
      runShellApp(
        configureDependencies: () async => throw error,
        onError: (e, _) => seen.add(e),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    // The hook chains to the handler that was installed before it — here
    // the test binding's — so the error is still surfaced to the test.
    expect(tester.takeException(), same(error));
    expect(seen, [same(error)]);
  });
}
