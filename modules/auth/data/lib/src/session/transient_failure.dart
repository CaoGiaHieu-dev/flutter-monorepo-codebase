import 'package:platform_kernel/platform_kernel.dart';

/// Whether [failure] says nothing about the session's validity — the
/// request never got the server's verdict — so the session must be kept.
///
/// Only a failure that never reached a decision counts: no network
/// ([NetworkFailure]), a real HTTP 5xx, or a cancelled request. Every other
/// failure means the server answered and refused — a 401/403, another 4xx,
/// or a 200 whose envelope reports an error (`ErrorCodes.RESPONSE_REJECTED`).
///
/// Shared by the two places that decide whether a user stays signed in:
/// [AuthSessionGatewayImpl.refreshToken] (a `401` mid-session) and
/// `AuthRepositoryImpl.restoreSession` (app start).
bool isTransientFailure(AppFailure<dynamic>? failure) {
  if (failure is NetworkFailure) return true;
  if (failure is! ServerFailure) return false;
  final code = failure.code;
  if (code == null) return false;
  return (code >= 500 && code < 600) || code == ErrorCodes.REQUEST_CANCELLED;
}
