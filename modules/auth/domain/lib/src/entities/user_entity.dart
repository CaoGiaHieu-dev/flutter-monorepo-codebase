import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_entity.freezed.dart';

/// SAMPLE — the user as the auth module models it. No `fromJson`: parsing a
/// payload is the data layer's job (`UserModel`).
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();

  const factory UserEntity({required String id, String? email, String? name}) =
      _UserEntity;
}
