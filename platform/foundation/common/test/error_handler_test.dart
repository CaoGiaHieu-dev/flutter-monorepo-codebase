import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorHandler', () {
    group('handleError with AppException', () {
      test('should map NetworkException to NetworkFailure', () {
        final exception = const NetworkException('No net', code: 111);
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<NetworkFailure<dynamic>>());
        expect(failure.message, equals('No net'));
        expect(failure.code, equals(111));
      });

      test('should map ServerException to ServerFailure', () {
        final exception = const ServerException(
          'Internal server error',
          code: 500,
        );
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<ServerFailure<dynamic>>());
        expect(failure.message, equals('Internal server error'));
        expect(failure.code, equals(500));
      });

      test('should map AuthException to AuthFailure', () {
        final exception = const AuthException('Unauthorized', code: 401);
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<AuthFailure<dynamic>>());
        expect(failure.message, equals('Unauthorized'));
        expect(failure.code, equals(401));
      });

      test('should map StorageException to StorageFailure', () {
        final exception = const StorageException(
          'Write permission denied',
          code: 2002,
        );
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<StorageFailure<dynamic>>());
        expect(failure.message, equals('Write permission denied'));
        expect(failure.code, equals(2002));
      });

      test('should map ValidationException to ValidationFailure', () {
        final exception = const ValidationException(
          'Invalid input',
          field: 'email',
          code: 3001,
        );
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<ValidationFailure<dynamic>>());
        expect(failure.message, equals('Invalid input'));
        expect((failure as ValidationFailure).field, equals('email'));
        expect(failure.code, equals(3001));
      });
    });

    group('handleError with standard exceptions', () {
      test('should map SocketException to NetworkFailure', () {
        const exception = SocketException('Socket error');
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<NetworkFailure<dynamic>>());
        expect(failure.message, equals('No internet connection'));
        expect(failure.code, equals(1001));
      });

      test('should map FormatException to ParseFailure', () {
        const exception = FormatException('Format error');
        final failure = ErrorHandler.handleError(exception);
        expect(failure, isA<ParseFailure<dynamic>>());
        expect(failure.message, contains('Invalid data format'));
        expect(failure.code, equals(4001));
      });
    });

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
      test('an error whose toString throws degrades to unknown', () {
        final failure = ErrorHandler.handleError(_HostileError());
        expect(failure, isA<ServerFailure<dynamic>>());
        expect(failure.code, 9999);
        expect(failure.message, 'Unknown error occurred');
      });

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

    group('Factory methods helpers', () {
      test('should create AuthFailure via authFailure helper', () {
        final failure = ErrorHandler.authFailure('Custom auth error', 403);
        expect(failure, isA<AuthFailure<dynamic>>());
        expect(failure.message, equals('Custom auth error'));
        expect(failure.code, equals(403));
      });

      test('should create ServerFailure via serverFailure helper', () {
        final failure = ErrorHandler.serverFailure<dynamic>(
          'Custom server error',
          502,
        );
        expect(failure, isA<ServerFailure<dynamic>>());
        expect(failure.message, equals('Custom server error'));
        expect(failure.code, equals(502));
      });

      test('should create StorageFailure via storageFailure helper', () {
        final failure = ErrorHandler.storageFailure(
          'Custom storage error',
          2005,
        );
        expect(failure, isA<StorageFailure<dynamic>>());
        expect(failure.message, equals('Custom storage error'));
        expect(failure.code, equals(2005));
      });
    });
  });
}

/// An error that cannot even describe itself.
class _HostileError {
  @override
  String toString() => throw StateError('toString failed');
}
