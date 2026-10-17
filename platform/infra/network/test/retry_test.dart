import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records which terminal method an error handler ended on. Overriding all
/// three without calling `super` keeps `isCompleted` false, as it is for a
/// caller still waiting.
class _RecordingErrorHandler extends ErrorInterceptorHandler {
  int passedOn = 0;
  final rejected = <DioException>[];
  Response<dynamic>? resolved;

  @override
  void next(DioException err) => passedOn++;

  @override
  void reject(
    DioException err, [
    bool callFollowingErrorInterceptor = false,
  ]) => rejected.add(err);

  @override
  void resolve(Response<dynamic> response) => resolved = response;
}

/// A transport that answers each request with whatever [respond] returns —
/// or throws — and remembers what it was sent.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  FutureOr<ResponseBody> Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok(RequestOptions options) => ResponseBody.fromString(
  jsonEncode({'path': options.path}),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Never _timeout(RequestOptions options) => throw DioException(
  requestOptions: options,
  type: DioExceptionType.connectionTimeout,
);

DioException _error(
  DioExceptionType type, {
  String path = '/items',
  String method = 'GET',
  Map<String, dynamic>? extra,
}) => DioException(
  requestOptions: RequestOptions(
    path: path,
    method: method,
    baseUrl: 'https://api.test',
    extra: extra ?? {},
  ),
  type: type,
);

/// One dialog request captured from [RetryHandler.onRetryCallback].
typedef _Dialog = ({void Function() onRetry, void Function() onCancel});

/// Lets [RetryInterceptor]'s asynchronous retry decision run to completion.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('RetryHandler.retryWhen', () {
    final handler = RetryHandler(Dio());

    test('retries timeouts and connection errors', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        expect(handler.retryWhen(type), isTrue, reason: '$type');
      }
    });

    test('never retries an HTTP status, a cancel or a bad certificate', () {
      for (final type in [
        DioExceptionType.badResponse,
        DioExceptionType.cancel,
        DioExceptionType.badCertificate,
        DioExceptionType.unknown,
      ]) {
        expect(handler.retryWhen(type), isFalse, reason: '$type');
      }
    });
  });

  group('RetryInterceptor', () {
    late List<DioException> retried;
    late RetryInterceptor interceptor;

    setUp(() {
      retried = [];
      interceptor = RetryInterceptor(
        retryWhen: RetryHandler(Dio()).retryWhen,
        handleRetry: (err, handler) => retried.add(err),
      );
    });

    test('hands a timeout to the retry handler', () async {
      final handler = _RecordingErrorHandler();
      interceptor.onError(
        _error(DioExceptionType.connectionTimeout),
        handler,
      );
      await _settle();

      expect(retried, hasLength(1));
      expect(handler.passedOn, 0, reason: 'the retry handler owns it now');
    });

    test('passes an HTTP error through untouched', () async {
      final handler = _RecordingErrorHandler();
      interceptor.onError(_error(DioExceptionType.badResponse), handler);
      await _settle();

      expect(retried, isEmpty);
      expect(handler.passedOn, 1);
    });

    test('honours canRetry: false on the request', () async {
      final handler = _RecordingErrorHandler();
      interceptor.onError(
        _error(
          DioExceptionType.connectionTimeout,
          extra: {NetworkConstants.EXTRA_CAN_RETRY: false},
        ),
        handler,
      );
      await _settle();

      expect(retried, isEmpty);
      expect(handler.passedOn, 1);
    });

    test(
      'a throwing retryWhen passes the error on instead of escaping',
      () async {
        final throwing = RetryInterceptor(
          retryWhen: (_) => throw StateError('boom'),
          handleRetry: (err, handler) => retried.add(err),
        );
        final handler = _RecordingErrorHandler();
        final errors = <Object>[];
        await runZonedGuarded(() async {
          throwing.onError(_error(DioExceptionType.connectionTimeout), handler);
          await _settle();
        }, (error, _) => errors.add(error));

        expect(errors, isEmpty);
        expect(retried, isEmpty);
        expect(handler.passedOn, 1);
      },
    );

    test('a retryable error with no handleRetry is passed on', () async {
      final noHandler = RetryInterceptor(
        retryWhen: RetryHandler(Dio()).retryWhen,
      );
      final handler = _RecordingErrorHandler();
      noHandler.onError(_error(DioExceptionType.connectionTimeout), handler);
      await _settle();

      expect(handler.passedOn, 1);
    });

    test('without a retryWhen nothing is retried', () async {
      final bare = RetryInterceptor(
        handleRetry: (err, handler) => retried.add(err),
      );
      final handler = _RecordingErrorHandler();
      bare.onError(_error(DioExceptionType.connectionTimeout), handler);
      await _settle();

      expect(retried, isEmpty);
      expect(handler.passedOn, 1);
    });
  });

  group('RetryHandler.handleRetry', () {
    late List<_Dialog> dialogs;
    late _FakeAdapter adapter;
    late RetryHandler retry;

    setUp(() {
      dialogs = [];
      adapter = _FakeAdapter(_ok);
      retry = RetryHandler(
        Dio(BaseOptions(baseUrl: 'https://api.test'))
          ..httpClientAdapter = adapter,
        onRetryCallback: ({required onRetry, required onCancel}) =>
            dialogs.add((onRetry: onRetry, onCancel: onCancel)),
      );
    });

    test('groups concurrent failures behind one dialog', () {
      final a = _RecordingErrorHandler();
      final b = _RecordingErrorHandler();
      retry.handleRetry(
        _error(DioExceptionType.connectionTimeout, path: '/a'),
        a,
      );
      retry.handleRetry(
        _error(DioExceptionType.receiveTimeout, path: '/b'),
        b,
      );

      expect(dialogs, hasLength(1));
    });

    test('cancel rejects every queued caller once', () {
      final a = _RecordingErrorHandler();
      final b = _RecordingErrorHandler();
      final errA = _error(DioExceptionType.connectionTimeout, path: '/a');
      retry.handleRetry(errA, a);
      // The same caller failing again is one entry, not two.
      retry.handleRetry(errA, a);
      retry.handleRetry(_error(DioExceptionType.connectionError), b);

      dialogs.single.onCancel();

      expect(a.rejected, [errA]);
      expect(b.rejected, hasLength(1));
      expect(adapter.requests, isEmpty);
    });

    test(
      'retry replays every queued request, marked canRetry: false',
      () async {
        final a = _RecordingErrorHandler();
        final b = _RecordingErrorHandler();
        retry.handleRetry(
          _error(DioExceptionType.connectionTimeout, path: '/a'),
          a,
        );
        retry.handleRetry(
          _error(DioExceptionType.connectionTimeout, path: '/b'),
          b,
        );

        dialogs.single.onRetry();
        await pumpEventQueue();

        expect(adapter.requests.map((r) => r.path), ['/a', '/b']);
        for (final request in adapter.requests) {
          expect(request.extra[NetworkConstants.EXTRA_CAN_RETRY], isFalse);
        }
        expect(a.resolved?.statusCode, 200);
        expect(b.resolved?.statusCode, 200);
        expect(a.rejected, isEmpty);
      },
    );

    test('a replay that times out again opens a new dialog', () async {
      adapter.respond = _timeout;
      final a = _RecordingErrorHandler();
      retry.handleRetry(_error(DioExceptionType.connectionTimeout), a);

      dialogs.single.onRetry();
      await pumpEventQueue();

      expect(dialogs, hasLength(2), reason: 'the caller is queued again');
      expect(a.rejected, isEmpty);
      expect(a.resolved, isNull);

      dialogs.last.onCancel();
      expect(a.rejected, hasLength(1));
    });

    test('a replay failing otherwise rejects with that failure', () async {
      adapter.respond = (o) => ResponseBody.fromString('nope', 500);
      final a = _RecordingErrorHandler();
      retry.handleRetry(_error(DioExceptionType.connectionTimeout), a);

      dialogs.single.onRetry();
      await pumpEventQueue();

      expect(dialogs, hasLength(1));
      expect(a.rejected.single.type, DioExceptionType.badResponse);
    });

    test('a dialog callback that throws fails the caller and does not wedge '
        'the handler for the next failure', () {
      var calls = 0;
      final shown = <_Dialog>[];
      final fragile = RetryHandler(
        Dio()..httpClientAdapter = adapter,
        onRetryCallback: ({required onRetry, required onCancel}) {
          calls++;
          // The overlay is not built yet on the first failure.
          if (calls == 1) throw StateError('no overlay yet');
          shown.add((onRetry: onRetry, onCancel: onCancel));
        },
      );

      final first = _RecordingErrorHandler();
      final firstError = _error(DioExceptionType.connectionError);
      expect(() => fragile.handleRetry(firstError, first), throwsStateError);
      expect(
        first.rejected,
        [firstError],
        reason:
            'the caller is not left '
            'waiting',
      );

      final second = _RecordingErrorHandler();
      fragile.handleRetry(_error(DioExceptionType.connectionError), second);

      expect(shown, hasLength(1), reason: 'a later failure reaches a prompt');
      shown.single.onCancel();
      expect(second.rejected, hasLength(1));
    });

    group('replaying a request that timed out after it was sent', () {
      DioException timeout(
        String method, {
        DioExceptionType type = DioExceptionType.receiveTimeout,
        Map<String, dynamic>? extra,
      }) => _error(type, method: method, extra: extra);

      test('a POST or PATCH is not replayed: it fails with the timeout, no '
          'dialog', () {
        for (final method in ['POST', 'PATCH', 'post']) {
          for (final type in [
            DioExceptionType.receiveTimeout,
            DioExceptionType.sendTimeout,
          ]) {
            final caller = _RecordingErrorHandler();
            final error = timeout(method, type: type);
            retry.handleRetry(error, caller);

            expect(caller.passedOn, 1, reason: '$method $type');
            expect(caller.rejected, isEmpty);
          }
        }
        expect(dialogs, isEmpty);
      });

      test('a POST that never connected is still replayed', () {
        for (final type in [
          DioExceptionType.connectionTimeout,
          DioExceptionType.connectionError,
        ]) {
          final caller = _RecordingErrorHandler();
          retry.handleRetry(timeout('POST', type: type), caller);
          expect(caller.passedOn, 0, reason: '$type');
        }
        expect(dialogs, hasLength(1));
      });

      test('a POST that opted in with EXTRA_IDEMPOTENT is replayed', () {
        final caller = _RecordingErrorHandler();
        retry.handleRetry(
          timeout('POST', extra: {NetworkConstants.EXTRA_IDEMPOTENT: true}),
          caller,
        );

        expect(caller.passedOn, 0);
        expect(dialogs, hasLength(1));
      });

      test('GET, HEAD, PUT, DELETE and OPTIONS are replayed', () {
        for (final method in ['GET', 'HEAD', 'PUT', 'DELETE', 'OPTIONS']) {
          final caller = _RecordingErrorHandler();
          retry.handleRetry(timeout(method), caller);
          expect(caller.passedOn, 0, reason: method);
        }
        expect(dialogs, hasLength(1), reason: 'one dialog for the batch');
      });
    });

    test('with no dialog callback every request is cancelled', () {
      final silent = RetryHandler(Dio()..httpClientAdapter = adapter);
      final a = _RecordingErrorHandler();
      silent.handleRetry(_error(DioExceptionType.connectionTimeout), a);

      expect(a.rejected, hasLength(1));
      expect(adapter.requests, isEmpty);
    });
  });

  test('wired like ApiClient, concurrent timeouts share one dialog and '
      'both callers get their response after one retry', () async {
    final dialogs = <_Dialog>[];
    final adapter = _FakeAdapter(_timeout);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
    final handler = RetryHandler(
      dio,
      onRetryCallback: ({required onRetry, required onCancel}) =>
          dialogs.add((onRetry: onRetry, onCancel: onCancel)),
    );
    dio.interceptors.add(
      RetryInterceptor(
        retryWhen: handler.retryWhen,
        handleRetry: handler.handleRetry,
      ),
    );

    final first = dio.get<dynamic>('/first');
    final second = dio.get<dynamic>('/second');
    await pumpEventQueue();

    expect(dialogs, hasLength(1));
    adapter.respond = _ok;
    dialogs.single.onRetry();

    final responses = await Future.wait([first, second]);
    expect(
      responses.map((r) => (r.data as Map<String, dynamic>)['path']),
      ['/first', '/second'],
    );
    expect(adapter.requests, hasLength(4), reason: 'two failures, two replays');
  });
}
