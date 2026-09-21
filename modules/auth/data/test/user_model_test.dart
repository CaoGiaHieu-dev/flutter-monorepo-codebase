import 'package:data_auth/data_auth.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit coverage for the DTO ↔ entity mapping used by [AuthRepositoryImpl].
/// Full Firebase-backed repository methods need integration tests / fakes.
void main() {
  group('UserModel (AuthRepository mapping)', () {
    test('toEntity maps all fields', () {
      const model = UserModel(
        id: 'uid-1',
        email: 'a@b.com',
        name: 'Alice',
        role: UserRole.none,
        bankName: 'ACB',
        bankAccount: '123',
        fcmToken: 'tok',
      );

      final entity = model.toEntity();

      expect(entity.id, 'uid-1');
      expect(entity.email, 'a@b.com');
      expect(entity.name, 'Alice');
      expect(entity.role, UserRole.none);
      expect(entity.bankName, 'ACB');
      expect(entity.bankAccount, '123');
      expect(entity.fcmToken, 'tok');
    });

    test('fromEntity round-trips', () {
      const entity = UserEntity(
        id: 'uid-2',
        email: 'c@d.com',
        name: 'Bob',
        role: UserRole.unknown,
      );

      final model = UserModel.fromEntity(entity);
      expect(model.toEntity(), entity);
    });

    test('fromJson then toEntity', () {
      final model = UserModel.fromJson({
        'id': 'uid-3',
        'email': 'e@f.com',
        'name': 'Carol',
        'role': 'none',
      });

      expect(model.toEntity().email, 'e@f.com');
      expect(model.toEntity().role, UserRole.none);
    });
  });
}
