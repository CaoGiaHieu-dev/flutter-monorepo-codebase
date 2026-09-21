import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_params.freezed.dart';
part 'login_params.g.dart';

@freezed
abstract class LoginParams with _$LoginParams {
  /// Creates LoginParams with validation
  ///
  /// Throws ArgumentError if validation fails
  const factory LoginParams({required String email, required String password}) =
      _LoginParams;

  factory LoginParams.fromJson(Map<String, dynamic> json) =>
      _$LoginParamsFromJson(json);
}
