import 'package:data_core/data_core.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

@freezed
abstract class UserModel with _$UserModel implements BaseModel<UserEntity> {
  const UserModel._();

  const factory UserModel({
    @JsonKey(name: 'id') required String id,
    @JsonKey(name: 'email') String? email,
    @JsonKey(name: 'name') String? name,

    /// The role as the backend spells it (`customer`, `owner`, `none`).
    ///
    /// Kept as the wire string here and mapped in [toEntity]: the spelling is
    /// the transport's concern, so `domain_auth`'s [UserRole] carries no
    /// JSON annotation.
    @JsonKey(name: 'role') String? role,

    /// Session credential from the login/refresh response.
    ///
    /// Deliberately absent from [UserEntity]: a token is something the
    /// transport hands back, not part of who the user is. It is read once
    /// here, handed to the local data source, and never travels upward.
    @JsonKey(name: 'token') String? token,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  /// The backend's spelling of each [UserRole]. [UserRole.unknown] has none:
  /// it is what an unrecognised value maps to.
  static const Map<UserRole, String> _roleNames = {
    UserRole.customer: 'customer',
    UserRole.owner: 'owner',
    UserRole.none: 'none',
  };

  @override
  UserEntity toEntity() {
    return UserEntity(
      id: id,
      email: email,
      name: name,
      role: role == null ? null : _roleFromName(role!),
    );
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      email: entity.email,
      name: entity.name,
      role: switch (entity.role) {
        null => null,
        final role => _roleNames[role] ?? role.name,
      },
    );
  }

  static UserRole _roleFromName(String name) {
    for (final entry in _roleNames.entries) {
      if (entry.value == name) return entry.key;
    }
    return UserRole.unknown;
  }
}
