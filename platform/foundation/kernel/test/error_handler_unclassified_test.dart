import 'dart:io';

import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

class _Unmapped implements Exception {}

class _HostileError {
  @override
  String toString() => throw StateError('toString failed');
}

/// `ErrorHandler.onUnclassifiedError` — the seam the app shell points at the
/// optional `IErrorReporter` — sees exactly the errors that become the
/// generic "unknown" failure, and cannot break `handleError`.
void main() {
  late List<(Object, StackTrace)> seen;

  setUp(() {
    seen = [];
    ErrorHandler.onUnclassifiedError = (error, stack) =>
        seen.add((error, stack));
  });

  tearDown(() => ErrorHandler.onUnclassifiedError = null);

  test('an unmapped exception is passed on, with its stack trace', () {
    final error = _Unmapped();
    final stack = StackTrace.current;

    final failure = ErrorHandler.handleError(error, stack);

    expect(failure.code, ErrorCodes.UNKNOWN);
    expect(seen, hasLength(1));
    expect(seen.single.$1, same(error));
    expect(seen.single.$2, same(stack));
  });

  test('without a stack trace the current one is supplied', () {
    ErrorHandler.handleError(_Unmapped());

    expect(seen.single.$2, isNotNull);
  });

  test('classified errors are not passed on', () {
    ErrorHandler.handleError(const SocketException('offline'));
    ErrorHandler.handleError(const FormatException('bad json'));
    ErrorHandler.handleError(const NetworkException('No net', code: 1));

    expect(seen, isEmpty);
  });

  test('an error whose toString throws is passed on once', () {
    final error = _HostileError();

    final failure = ErrorHandler.handleError(error);

    expect(failure.code, ErrorCodes.UNKNOWN);
    expect(seen, hasLength(1));
    expect(seen.single.$1, same(error));
  });

  test('a throwing listener cannot make handleError throw', () {
    ErrorHandler.onUnclassifiedError = (_, _) => throw StateError('down');

    expect(
      ErrorHandler.handleError(_Unmapped()).code,
      ErrorCodes.UNKNOWN,
    );
  });
}
