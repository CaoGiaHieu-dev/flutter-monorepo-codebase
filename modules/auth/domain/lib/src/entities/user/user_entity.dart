import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_role.dart';

part 'user_entity.freezed.dart';
part 'user_entity.g.dart';

/// Entity representing a user in the domain layer.
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();

  const factory UserEntity({
    required String id,
    String? email,
    String? name,
    UserRole? role,
    String? bankName,
    String? bankAccount,
    String? fcmToken,
  }) = _UserEntity;

  factory UserEntity.fromJson(Map<String, dynamic> json) =>
      _$UserEntityFromJson(json);
}
