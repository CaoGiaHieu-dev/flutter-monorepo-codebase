import 'package:domain_core/domain_core.dart';
import 'package:test/test.dart';

/// `AppFailure` is compared by value all over the presentation layer —
/// `AuthProvider.mapAuthFailure` switches on its variant and code, and tests
/// match on it with `==`. A change to its Freezed shape breaks all of that
/// without failing analysis.
void main() {
  group('equality', () {
    test('same variant, message and code are equal', () {
      expect(
        const NetworkFailure<dynamic>(message: 'offline', code: 1005),
        const NetworkFailure<dynamic>(message: 'offline', code: 1005),
      );
      expect(
        const AppFailure<dynamic>.auth(message: 'no', code: 401).hashCode,
        const AuthFailure<dynamic>(message: 'no', code: 401).hashCode,
      );
    });

    test('a different code or message is not equal', () {
      const base = ServerFailure<dynamic>(message: 'down', code: 503);
      expect(base, isNot(const ServerFailure<dynamic>(message: 'down')));
      expect(
        base,
        isNot(const ServerFailure<dynamic>(message: 'up', code: 503)),
      );
    });

    test('the same fields under a different variant are not equal', () {
      expect(
        const AuthFailure<dynamic>(message: 'x', code: 401),
        isNot(const ServerFailure<dynamic>(message: 'x', code: 401)),
      );
    });

    test('validation failures compare their field too', () {
      expect(
        const ValidationFailure<dynamic>(message: 'bad', field: 'email'),
        isNot(const ValidationFailure<dynamic>(message: 'bad', field: 'name')),
      );
    });
  });

  test('every variant maps to its own branch', () {
    final failures = <AppFailure<dynamic>>[
      const AppFailure.network(message: 'm'),
      const AppFailure.server(message: 'm'),
      const AppFailure.auth(message: 'm'),
      const AppFailure.storage(message: 'm'),
      const AppFailure.validation(message: 'm'),
      const AppFailure.parse(message: 'm'),
      const AppFailure.cache(message: 'm'),
      const AppFailure.service(message: 'm'),
    ];
    final names = failures
        .map(
          (f) => switch (f) {
            NetworkFailure() => 'network',
            ServerFailure() => 'server',
            AuthFailure() => 'auth',
            StorageFailure() => 'storage',
            ValidationFailure() => 'validation',
            ParseFailure() => 'parse',
            CacheFailure() => 'cache',
            ServiceFailure() => 'service',
          },
        )
        .toList();
    expect(names, [
      'network',
      'server',
      'auth',
      'storage',
      'validation',
      'parse',
      'cache',
      'service',
    ]);
  });

  test('copyWith keeps the variant', () {
    const original = AuthFailure<dynamic>(message: 'expired', code: 401);
    final copy = original.copyWith(message: 'renewed');
    expect(copy, isA<AuthFailure<dynamic>>());
    expect(copy.message, 'renewed');
    expect(copy.code, 401);
  });

  test('round-trips through JSON', () {
    const original = ServerFailure<String>(
      message: 'down',
      code: 503,
      data: 'detail',
    );
    final json = original.toJson((d) => d);
    final decoded = AppFailure<String>.fromJson(json, (o) => o as String);
    expect(decoded, original);
  });
}
