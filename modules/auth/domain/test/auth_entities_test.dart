import 'package:domain_auth/domain_auth.dart';
import 'package:test/test.dart';

void main() {
  group('LoginParams', () {
    test('equal when email and password match', () {
      const a = LoginParams(email: 'a@b.c', password: 'pw');
      const b = LoginParams(email: 'a@b.c', password: 'pw');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differ when either field differs', () {
      const base = LoginParams(email: 'a@b.c', password: 'pw');

      expect(base, isNot(const LoginParams(email: 'x@b.c', password: 'pw')));
      expect(base, isNot(const LoginParams(email: 'a@b.c', password: 'other')));
    });
  });

  group('UserEntity', () {
    test('only the id is required; the rest default to null', () {
      const user = UserEntity(id: '7');

      expect(user.email, isNull);
      expect(user.name, isNull);
      expect(user.role, isNull);
    });

    test('is a value: same fields are equal, a changed field is not', () {
      const a = UserEntity(id: '1', name: 'Ada', role: UserRole.customer);
      const b = UserEntity(id: '1', name: 'Ada', role: UserRole.customer);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(b.copyWith(role: UserRole.owner)));
    });

    test('copyWith changes only what it is given', () {
      const user = UserEntity(id: '1', email: 'a@b.c', name: 'Ada');

      final renamed = user.copyWith(name: 'Grace');

      expect(renamed.name, 'Grace');
      expect(renamed.id, '1');
      expect(renamed.email, 'a@b.c');
    });
  });

  test('UserRole keeps the four roles the data layer maps onto', () {
    expect(
      UserRole.values.map((r) => r.name),
      ['customer', 'owner', 'none', 'unknown'],
    );
  });
}
