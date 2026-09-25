import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:provider_state_management/provider_state_management.dart';

part 'auth_error_state.freezed.dart';

/// Why a sign-in failed, as far as this feature can tell.
///
/// Carries no text: `AppFailure.message` is an English diagnostic, and what
/// the user reads comes from the ARBs — see `SessionFailure`, which the app
/// shell turns into a translated toast.
@freezed
abstract class AuthErrorState extends CustomErrorState with _$AuthErrorState {
  const AuthErrorState._();

  const factory AuthErrorState.invalidCredentials() = _InvalidCredentials;

  const factory AuthErrorState.userNotFound() = _UserNotFound;

  /// Anything else — offline, a timeout, a 5xx, a locked account (403).
  /// [code] is the failure's `ErrorCodes` / HTTP status, which picks the
  /// translated sentence.
  const factory AuthErrorState.failed({int? code}) = _Failed;
}
