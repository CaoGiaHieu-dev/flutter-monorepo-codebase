import 'package:data_auth/data_auth.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit coverage for the DTO ↔ entity mapping the auth repository performs.
///
/// The interesting case is the last one: `token` exists on the model and not
/// on the entity, so mapping must *drop* it. That asymmetry is the boundary
/// this layer is responsible for, and a round-trip test alone would not catch
/// it being re-added to the entity by accident.
void main() {
  group('UserModel (AuthRepository mapping)', () {
    test('toEntity maps identity fields', () {
      const model = UserModel(
        id: 'uid-1',
        email: 'a@b.com',
        name: 'Alice',
        role: 'none',
      );

      final entity = model.toEntity();

      expect(entity.id, 'uid-1');
      expect(entity.email, 'a@b.com');
      expect(entity.name, 'Alice');
      expect(entity.role, UserRole.none);
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

    test('the role\'s wire spelling stays in the model', () {
      expect(
        UserModel.fromJson({'id': '1', 'role': 'owner'}).toEntity().role,
        UserRole.owner,
      );
      expect(
        UserModel.fromJson({'id': '1', 'role': 'admin'}).toEntity().role,
        UserRole.unknown,
        reason: 'a value this app does not know',
      );
      expect(
        UserModel.fromEntity(const UserEntity(id: '1', role: UserRole.owner))
            .toJson()['role'],
        'owner',
      );
    });

    test('the session token stays in the data layer', () {
      const model = UserModel(id: 'uid-4', token: 'secret-jwt');

      // The entity has no `token` field at all, so the only way this can
      // regress is by adding one — which is exactly what should fail here.
      expect(model.token, 'secret-jwt');
      expect(model.toEntity(), const UserEntity(id: 'uid-4'));
    });
  });
}
