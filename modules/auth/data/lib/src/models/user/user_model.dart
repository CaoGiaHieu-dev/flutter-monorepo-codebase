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
    @JsonKey(name: 'bankName') String? bankName,
    @JsonKey(name: 'bankAccount') String? bankAccount,
    @JsonKey(name: 'fcmToken') String? fcmToken,
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
      bankName: bankName,
      bankAccount: bankAccount,
      fcmToken: fcmToken,
    );
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      email: entity.email,
      name: entity.name,
      role: entity.role,
      bankName: entity.bankName,
      bankAccount: entity.bankAccount,
      fcmToken: entity.fcmToken,
    );
  }
}
