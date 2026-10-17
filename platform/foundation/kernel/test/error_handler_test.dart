import 'dart:io';

import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

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

    group('handleError never throws', () {
      test('an error whose toString throws degrades to unknown', () {
        final failure = ErrorHandler.handleError(_HostileError());
        expect(failure, isA<ServerFailure<dynamic>>());
        expect(failure.code, 9999);
        expect(failure.message, 'Unknown error occurred');
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
