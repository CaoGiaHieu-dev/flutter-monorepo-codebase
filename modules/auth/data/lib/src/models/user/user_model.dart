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
    @JsonKey(name: 'role', unknownEnumValue: UserRole.unknown) UserRole? role,

    /// Session credential from the login/refresh response.
    ///
    /// Deliberately absent from [UserEntity]: a token is something the
    /// transport hands back, not part of who the user is. It is read once
    /// here, handed to the local data source, and never travels upward.
    @JsonKey(name: 'token') String? token,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  @override
  UserEntity toEntity() {
    return UserEntity(
      id: id,
      email: email,
      name: name,
      role: role,
    );
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      email: entity.email,
      name: entity.name,
      role: entity.role,
    );
  }
}
