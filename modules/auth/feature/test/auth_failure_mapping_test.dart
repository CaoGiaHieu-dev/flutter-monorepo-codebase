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

    test('an HTTP 403 keeps the backend message as a server error', () {
      expect(
        AuthProvider.mapAuthFailure(
          const AuthFailure(message: 'Account locked', code: 403),
        ),
        const AuthErrorState.serverError(message: 'Account locked', code: 403),
      );
    });

    test('other server failures surface their message', () {
      expect(
        AuthProvider.mapAuthFailure(
          const ServerFailure(message: 'Down', code: 503),
        ),
        const AuthErrorState.serverError(message: 'Down', code: 503),
      );
    });

    test('a network failure is never read as a credential problem', () {
      for (final code in [401, 404, 1005]) {
        expect(
          AuthProvider.mapAuthFailure(
            NetworkFailure(message: 'offline', code: code),
          ),
          AuthErrorState.serverError(message: 'offline', code: code),
        );
      }
    });
  });
}
