import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_params.freezed.dart';

@freezed
abstract class LoginParams with _$LoginParams {
  /// Input is validated by the login form before this is built; the params
  /// object itself only carries it.
  const factory LoginParams({required String email, required String password}) =
      _LoginParams;
}
