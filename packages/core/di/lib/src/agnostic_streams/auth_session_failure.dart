/// Neutral, already-classified description of a failed session operation.
///
/// The app shell shows a toast when sign-in fails, but it must not learn the
/// auth feature's error types to do so. Previously the shell type-checked
/// `AuthErrorState` — a `feature_auth` class — which is why deleting that
/// package broke the shell at compile time.
///
/// The owning feature does the classification (it is the only layer that knows
/// what a `401` means for its backend) and publishes one of these. The shell
/// only maps the variant to a globally translated string from `core_base_ui`.
///
/// ## Why a plain `sealed class` and not Freezed
///
/// `core_di` is a contract-only package with no code generation of its own;
/// pulling in a Freezed `part` here would mean every consumer waits on
/// `build_runner` for what is a four-variant tag. Dart 3 `sealed` gives the
/// exhaustive `switch` that matters, with zero generated files.
///
/// ```dart
/// final message = switch (failure) {
///   AuthInvalidCredentialsFailure() => l10n.invalid_credentials,
///   AuthUserNotFoundFailure()       => l10n.user_not_found,
///   AuthServerFailure(:final message) => message,
///   AuthUnknownFailure()            => l10n.something_went_wrong,
/// };
/// ```
sealed class AuthSessionFailure {
  const AuthSessionFailure();
}

/// The supplied credentials were rejected.
final class AuthInvalidCredentialsFailure extends AuthSessionFailure {
  const AuthInvalidCredentialsFailure();
}

/// No account matches the supplied identifier.
final class AuthUserNotFoundFailure extends AuthSessionFailure {
  const AuthUserNotFoundFailure();
}

/// The backend reported a failure and provided a displayable reason.
final class AuthServerFailure extends AuthSessionFailure {
  const AuthServerFailure({required this.message, this.code});

  /// Message already fit to show to a user; the feature decides its wording.
  final String message;

  /// Transport or application status code, when the feature knows one.
  final int? code;
}

/// Anything the owning feature could not classify further.
final class AuthUnknownFailure extends AuthSessionFailure {
  const AuthUnknownFailure();
}
