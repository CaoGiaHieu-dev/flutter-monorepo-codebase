import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// Dio's exceptions reach `ErrorHandler.handleError` through
/// [DioFailureClassifier] — the kernel names no transport type. These are
/// the Dio cases that used to live in `core_common`'s error handler test,
/// unchanged, plus the registration contract.
void main() {
  setUpAll(DioFailureClassifier.ensureRegistered);

  group('ErrorHandler with DioFailureClassifier', () {
    group('handleError with DioException', () {
      test('should map connectionTimeout to NetworkFailure', () {
        final exception = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionTimeout,
        );
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<NetworkFailure<dynamic>>());
        expect(failure.message, equals('Connection timeout'));
        expect(failure.code, equals(1003));
      });

      test('should map badResponse 401 to AuthFailure', () {
        final exception = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 401,
            statusMessage: 'Unauthorized user',
            data: {'message': 'Custom unauthorized message'},
          ),
        );
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<AuthFailure<dynamic>>());
        expect(failure.message, equals('Custom unauthorized message'));
        expect(failure.code, equals(401));
      });

      test('should map badResponse 500 to ServerFailure', () {
        final exception = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 500,
            statusMessage: 'Internal Error',
          ),
        );
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<ServerFailure<dynamic>>());
        expect(failure.message, equals('Internal Error'));
        expect(failure.code, equals(500));
      });
    });

    group('badResponse message extraction', () {
      AppFailure<dynamic> failureFor(Object? data, {String? statusMessage}) {
        return ErrorHandler.handleError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 400,
              statusMessage: statusMessage,
              data: data,
            ),
          ),
        );
      }

      test('joins a list of messages (NestJS validation) one per line', () {
        final failure = failureFor({
          'message': ['email must be an email', 'password is too short'],
          'error': 'Bad Request',
        });
        expect(failure, isA<ServerFailure<dynamic>>());
        expect(failure.code, 400);
        expect(
          failure.message,
          'email must be an email\npassword is too short',
        );
      });

      test('skips empty and null entries of a list', () {
        final failure = failureFor({
          'message': ['', null, 'only this'],
        });
        expect(failure.message, 'only this');
      });

      test('falls back to the status message for an empty list', () {
        final failure = failureFor({
          'message': <String>[],
        }, statusMessage: 'Bad Request');
        expect(failure.message, 'Bad Request');
      });

      test('stringifies a map or a number message', () {
        expect(
          failureFor({
            'message': {'email': 'taken'},
          }).message,
          contains('taken'),
        );
        expect(failureFor({'message': 42}).message, '42');
      });

      test('uses the status message when the body is not a map', () {
        expect(
          failureFor('<html>oops</html>', statusMessage: 'Bad Gateway').message,
          'Bad Gateway',
        );
        expect(
          failureFor(['a', 'b'], statusMessage: 'Bad Request').message,
          'Bad Request',
        );
      });

      test('uses a generic message when nothing usable is present', () {
        expect(failureFor(null).message, 'Server error');
        expect(failureFor({'message': '   '}).message, 'Server error');
      });

      test('a 404 is a ServerFailure carrying the status code', () {
        final failure = ErrorHandler.handleError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/'),
              statusCode: 404,
              data: {'message': 'User not found'},
            ),
          ),
        );
        expect(failure, isA<ServerFailure<dynamic>>());
        expect(failure.code, 404);
        expect(failure.message, 'User not found');
      });
    });

    group('handleError never throws', () {
      test('a badResponse without a response still classifies', () {
        final failure = ErrorHandler.handleError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.badResponse,
          ),
        );
        expect(failure, isA<ServerFailure<dynamic>>());
        expect(failure.message, 'Server error');
      });
    });

    group('registration', () {
      test('registering again replaces instead of stacking', () {
        DioFailureClassifier.ensureRegistered();
        const DioFailureClassifier().register();
        expect(
          ErrorHandler.classifiers.whereType<DioFailureClassifier>(),
          hasLength(1),
        );
      });

      test('ignores anything but a DioException', () {
        const classifier = DioFailureClassifier();
        expect(classifier.classify(const FormatException('x')), isNull);
        expect(classifier.classify(Exception('x')), isNull);
      });

      test('unregistered, a DioException is an unclassified error', () {
        const classifier = DioFailureClassifier();
        addTearDown(DioFailureClassifier.ensureRegistered);
        final seen = <Object>[];
        ErrorHandler.onUnclassifiedError = (error, _) => seen.add(error);
        addTearDown(() => ErrorHandler.onUnclassifiedError = null);

        expect(ErrorHandler.unregisterClassifier(classifier), isTrue);
        final error = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionTimeout,
        );
        final failure = ErrorHandler.handleError(error);

        expect(failure.code, ErrorCodes.UNKNOWN);
        expect(seen, [same(error)]);
      });

      test('a classified DioException is not passed on as unclassified', () {
        final seen = <Object>[];
        ErrorHandler.onUnclassifiedError = (error, _) => seen.add(error);
        addTearDown(() => ErrorHandler.onUnclassifiedError = null);

        ErrorHandler.handleError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
          ),
        );

        expect(seen, isEmpty);
      });
    });
  });
}
