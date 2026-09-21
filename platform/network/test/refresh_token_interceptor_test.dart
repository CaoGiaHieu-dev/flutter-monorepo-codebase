import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures which terminal method the interceptor chain ended on, so a test
/// can tell "passed the error through" apart from "handled the refresh".
class _RecordingErrorHandler extends ErrorInterceptorHandler {
  bool rejected = false;
  Response<dynamic>? resolved;

  @override
  void next(DioException err) => rejected = true;

  @override
  void reject(
    DioException err, [
    bool callFollowingErrorInterceptor = false,
  ]) => rejected = true;

  @override
  void resolve(Response<dynamic> response) => resolved = response;
}

DioException _unauthorized({Map<String, dynamic>? extra, String path = '/me'}) {
  final options = RequestOptions(path: path, extra: extra ?? {});
  return DioException(
    requestOptions: options,
    response: Response<dynamic>(requestOptions: options, statusCode: 401),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('RefreshTokenInterceptor', () {
    late int refreshCalls;
    late int failureCalls;

    /// Builds an interceptor whose refresh returns [newToken]; `null` models a
    /// refresh that could not renew the session.
    RefreshTokenInterceptor buildInterceptor({required String? newToken}) {
      return RefreshTokenInterceptor(
        RefreshTokenHandler(
          dio: Dio(),
          onRefreshToken: () async {
            refreshCalls++;
            return newToken;
          },
          onRefreshFailed: () async {
            failureCalls++;
          },
        ),
      );
    }

    setUp(() {
      refreshCalls = 0;
      failureCalls = 0;
    });

    test('ignores errors that are not 401', () async {
      final interceptor = buildInterceptor(newToken: 'fresh');
      final options = RequestOptions(path: '/me');
      final err = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      final handler = _RecordingErrorHandler();

      interceptor.onError(err, handler);

      expect(refreshCalls, 0, reason: 'a 500 must not renew the session');
      expect(handler.rejected, isTrue);
    });

    test('ignores a 401 on a request that opted out of auth', () async {
      final interceptor = buildInterceptor(newToken: 'fresh');
      final handler = _RecordingErrorHandler();

      // This is the guard that keeps the refresh call itself from recursing.
      interceptor.onError(
        _unauthorized(extra: {'needAuthentication': false}),
        handler,
      );

      expect(refreshCalls, 0);
      expect(handler.rejected, isTrue);
    });

    test('does not refresh a request it has already replayed', () async {
      final interceptor = buildInterceptor(newToken: 'fresh');
      final handler = _RecordingErrorHandler();

      interceptor.onError(
        _unauthorized(extra: {'tokenRefreshAttempted': true}),
        handler,
      );

      expect(refreshCalls, 0, reason: 'second 401 must not loop');
      expect(handler.rejected, isTrue);
    });

    test('marks the request before delegating, so the replay cannot loop', () {
      final interceptor = buildInterceptor(newToken: 'fresh');
      final err = _unauthorized();

      interceptor.onError(err, _RecordingErrorHandler());

      expect(err.requestOptions.extra['tokenRefreshAttempted'], isTrue);
    });

    test(
      'rejects and clears the session when refresh yields no token',
      () async {
        final interceptor = buildInterceptor(newToken: null);
        final handler = _RecordingErrorHandler();

        interceptor.onError(_unauthorized(), handler);
        await Future<void>.delayed(Duration.zero);

        expect(refreshCalls, 1);
        expect(failureCalls, 1, reason: 'session must be cleared on failure');
        expect(handler.rejected, isTrue);
      },
    );

    test('a single refresh serves several concurrent 401s', () async {
      final completer = Completer<String?>();
      final interceptor = RefreshTokenInterceptor(
        RefreshTokenHandler(
          dio: Dio(),
          onRefreshToken: () {
            refreshCalls++;
            return completer.future;
          },
          onRefreshFailed: () async => failureCalls++,
        ),
      );

      final handlers = List.generate(3, (_) => _RecordingErrorHandler());
      for (final handler in handlers) {
        interceptor.onError(_unauthorized(), handler);
      }
      await Future<void>.delayed(Duration.zero);

      // The Completer inside RefreshTokenHandler queues the later callers
      // behind the first, so N failing requests cost exactly one refresh.
      expect(refreshCalls, 1);

      completer.complete(null);
      await Future<void>.delayed(Duration.zero);
    });
  });
}
