import 'package:domain_core/domain_core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AuthProvider.mapAuthFailure` must match the failures `ErrorHandler`
/// really produces — HTTP 401/403 as `AuthFailure`, other statuses as
/// `ServerFailure` — or every sign-in error collapses to a server error.
void main() {
  group('AuthProvider.mapAuthFailure', () {
    test('an HTTP 401 (AuthFailure) is invalid credentials', () {
      expect(
        AuthProvider.mapAuthFailure(
          const AuthFailure(message: 'Unauthorized', code: 401),
        ),
        const AuthErrorState.invalidCredentials(),
      );
    });

    test('an HTTP 404 (ServerFailure) is user not found', () {
      expect(
        AuthProvider.mapAuthFailure(
          const ServerFailure(message: 'Not found', code: 404),
        ),
        const AuthErrorState.userNotFound(),
      );
    });

    test('an HTTP 403 is a failure with its code, not wrong credentials', () {
      expect(
        AuthProvider.mapAuthFailure(
          const AuthFailure(message: 'Account locked', code: 403),
        ),
        const AuthErrorState.failed(code: 403),
      );
    });

    test('other server failures keep only their code', () {
      expect(
        AuthProvider.mapAuthFailure(
          const ServerFailure(message: 'Down', code: 503),
        ),
        const AuthErrorState.failed(code: 503),
      );
    });

    test('a network failure is never read as a credential problem', () {
      for (final code in [401, 404, 1005]) {
        expect(
          AuthProvider.mapAuthFailure(
            NetworkFailure(message: 'offline', code: code),
          ),
          AuthErrorState.failed(code: code),
        );
      }
    });
  });
}
