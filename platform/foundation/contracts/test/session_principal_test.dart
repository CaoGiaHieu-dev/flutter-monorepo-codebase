import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionPrincipal', () {
    test('principals with the same fields are equal and hash alike', () {
      const a = SessionPrincipal(
        id: '1',
        displayName: 'Ada',
        email: 'ada@example.com',
        roles: {'owner', 'admin'},
      );
      const b = SessionPrincipal(
        id: '1',
        displayName: 'Ada',
        email: 'ada@example.com',
        roles: {'admin', 'owner'},
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('role order is irrelevant, role membership is not', () {
      const base = SessionPrincipal(id: '1', roles: {'owner', 'admin'});

      expect(base, const SessionPrincipal(id: '1', roles: {'admin', 'owner'}));
      expect(base, isNot(const SessionPrincipal(id: '1', roles: {'owner'})));
      expect(
        base,
        isNot(const SessionPrincipal(id: '1', roles: {'owner', 'guest'})),
      );
    });

    test('every field takes part in equality', () {
      const base = SessionPrincipal(
        id: '1',
        displayName: 'Ada',
        email: 'ada@example.com',
      );

      expect(
        base,
        isNot(
          const SessionPrincipal(
            id: '2',
            displayName: 'Ada',
            email: 'ada@example.com',
          ),
        ),
      );
      expect(
        base,
        isNot(
          const SessionPrincipal(
            id: '1',
            displayName: 'Grace',
            email: 'ada@example.com',
          ),
        ),
      );
      expect(
        base,
        isNot(
          const SessionPrincipal(
            id: '1',
            displayName: 'Ada',
            email: 'other@example.com',
          ),
        ),
      );
    });

    test(
      'a stream de-duplicating on equality drops an unchanged principal',
      () {
        const first = SessionPrincipal(id: '1', roles: {'owner'});
        const same = SessionPrincipal(id: '1', roles: {'owner'});

        final seen = <SessionPrincipal>{}
          ..add(first)
          ..add(same);

        expect(seen, hasLength(1));
      },
    );

    test('hasRole is true only for a role the principal holds', () {
      const principal = SessionPrincipal(id: '1', roles: {'owner'});

      expect(principal.hasRole('owner'), isTrue);
      expect(principal.hasRole('admin'), isFalse);
    });

    test('roles default to none and the optional fields to null', () {
      const principal = SessionPrincipal(id: '1');

      expect(principal.roles, isEmpty);
      expect(principal.hasRole('owner'), isFalse);
      expect(principal.displayName, isNull);
      expect(principal.email, isNull);
    });

    test('toString names the id but never leaks the email', () {
      const principal = SessionPrincipal(
        id: '42',
        displayName: 'Ada',
        email: 'ada@example.com',
      );

      expect(principal.toString(), contains('42'));
      expect(principal.toString(), isNot(contains('ada@example.com')));
    });
  });

  group('SessionFailure', () {
    // The exhaustive switch the shell writes: this file stops compiling if a
    // variant is added without the shell learning to translate it.
    String describe(SessionFailure failure) => switch (failure) {
      SessionInvalidCredentialsFailure() => 'credentials',
      SessionUserNotFoundFailure() => 'not-found',
      SessionServerFailure(:final code) => 'server:$code',
      SessionExpiredFailure() => 'expired',
      SessionUnknownFailure() => 'unknown',
    };

    test('each variant is told apart by the exhaustive switch', () {
      expect(describe(const SessionInvalidCredentialsFailure()), 'credentials');
      expect(describe(const SessionUserNotFoundFailure()), 'not-found');
      expect(describe(const SessionExpiredFailure()), 'expired');
      expect(describe(const SessionUnknownFailure()), 'unknown');
    });

    test('a server failure carries its code, or none', () {
      expect(describe(const SessionServerFailure(code: 503)), 'server:503');
      expect(describe(const SessionServerFailure()), 'server:null');
    });
  });
}
