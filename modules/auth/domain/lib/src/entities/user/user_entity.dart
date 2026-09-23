import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_role.dart';

part 'user_entity.freezed.dart';
part 'user_entity.g.dart';

/// SAMPLE — the user as the auth module models it.
///
/// Add the fields your product needs; whatever you add here is visible to
/// everything that can see this entity, which is why the cross-module contract carries a narrower
/// `AuthPrincipal` instead of re-exporting this type.
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();

  const factory UserEntity({
    required String id,
    String? email,
    String? name,
    UserRole? role,
  }) = _UserEntity;

  factory UserEntity.fromJson(Map<String, dynamic> json) =>
      _$UserEntityFromJson(json);
}
