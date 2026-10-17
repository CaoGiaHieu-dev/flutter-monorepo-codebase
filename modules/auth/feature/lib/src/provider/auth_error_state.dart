import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:provider_state_management/provider_state_management.dart';

part 'auth_error_state.freezed.dart';

/// Why a sign-in failed, as far as the screen words it differently. Carries no
/// text (RULE-34): the shell shows a translated toast for the session failure.
@freezed
abstract class AuthErrorState extends CustomErrorState with _$AuthErrorState {
  const AuthErrorState._();

  const factory AuthErrorState.invalidCredentials() = _InvalidCredentials;

  /// Anything else — offline, a timeout, a 5xx, a locked account. [code] is the
  /// failure's `ErrorCodes` / HTTP status.
  const factory AuthErrorState.failed({int? code}) = _Failed;
}
