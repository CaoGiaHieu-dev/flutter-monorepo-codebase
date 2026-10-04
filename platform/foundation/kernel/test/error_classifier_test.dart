import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

class _Grpc implements Exception {
  const _Grpc(this.message);
  final String message;
}

class _Other implements Exception {}

/// Maps [_Grpc] only; everything else is not its to map.
final class _GrpcClassifier implements ErrorClassifier {
  const _GrpcClassifier([this.code = 1010]);

  final int code;

  @override
  AppFailure<dynamic>? classify(Object error) => error is _Grpc
      ? NetworkFailure<dynamic>(message: error.message, code: code)
      : null;
}

/// Claims every error, so a classifier behind it is never asked.
final class _CatchAllClassifier implements ErrorClassifier {
  const _CatchAllClassifier();

  @override
  AppFailure<dynamic>? classify(Object error) =>
      const ServiceFailure<dynamic>(message: 'catch-all', code: 7);
}

final class _ThrowingClassifier implements ErrorClassifier {
  const _ThrowingClassifier();

  @override
  AppFailure<dynamic>? classify(Object error) => throw StateError('broken');
}

/// An `ErrorClassifier` lets a package that owns an error type map it to an
/// `AppFailure` without the kernel naming that type; `ErrorHandler` asks the
/// registered ones in order before its own rules.
void main() {
  tearDown(() {
    ErrorHandler.unregisterClassifier(const _GrpcClassifier());
    ErrorHandler.unregisterClassifier(const _CatchAllClassifier());
    ErrorHandler.unregisterClassifier(const _ThrowingClassifier());
  });

  test('a registered classifier maps the type it owns', () {
    ErrorHandler.registerClassifier(const _GrpcClassifier());

    final failure = ErrorHandler.handleError(const _Grpc('unavailable'));

    expect(failure, isA<NetworkFailure<dynamic>>());
    expect(failure.message, 'unavailable');
    expect(failure.code, 1010);
  });

  test('null passes the error on to the kernel rules', () {
    ErrorHandler.registerClassifier(const _GrpcClassifier());

    final failure = ErrorHandler.handleError(const FormatException('bad'));

    expect(failure, isA<ParseFailure<dynamic>>());
    expect(failure.code, ErrorCodes.INVALID_FORMAT);
  });

  test('an unclaimed error still becomes the unknown failure', () {
    ErrorHandler.registerClassifier(const _GrpcClassifier());

    final failure = ErrorHandler.handleError(_Other());

    expect(failure.code, ErrorCodes.UNKNOWN);
  });

  test('classifiers are asked in registration order, first answer wins', () {
    ErrorHandler.registerClassifier(const _GrpcClassifier());
    ErrorHandler.registerClassifier(const _CatchAllClassifier());

    expect(ErrorHandler.handleError(const _Grpc('x')).code, 1010);
    expect(ErrorHandler.handleError(_Other()).code, 7);
  });

  test('registering the same type again replaces it in place', () {
    ErrorHandler.registerClassifier(const _GrpcClassifier(1));
    ErrorHandler.registerClassifier(const _GrpcClassifier(2));

    expect(ErrorHandler.classifiers.whereType<_GrpcClassifier>(), hasLength(1));
    expect(ErrorHandler.handleError(const _Grpc('x')).code, 2);
  });

  test('unregister removes it and reports whether one was registered', () {
    ErrorHandler.registerClassifier(const _GrpcClassifier());

    expect(ErrorHandler.unregisterClassifier(const _GrpcClassifier()), isTrue);
    expect(ErrorHandler.unregisterClassifier(const _GrpcClassifier()), isFalse);
    expect(
      ErrorHandler.handleError(const _Grpc('x')).code,
      ErrorCodes.UNKNOWN,
    );
  });

  test('a throwing classifier degrades to the unknown failure', () {
    ErrorHandler.registerClassifier(const _ThrowingClassifier());

    final failure = ErrorHandler.handleError(const _Grpc('x'));

    expect(failure.code, ErrorCodes.UNKNOWN);
  });

  test('the classifiers list cannot be modified by a caller', () {
    expect(
      () => ErrorHandler.classifiers.add(const _GrpcClassifier()),
      throwsUnsupportedError,
    );
  });
}
