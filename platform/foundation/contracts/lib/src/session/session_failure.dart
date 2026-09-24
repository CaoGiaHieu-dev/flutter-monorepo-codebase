/// Neutral, already-classified description of a failed session operation.
///
/// The app shell shows a toast when sign-in fails, but it must not learn the
/// session owner's error types to do so. Previously the shell type-checked
/// `AuthErrorState` — a `feature_auth` class — which is why deleting that
/// package broke the shell at compile time.
///
/// The module that owns the session does the classification (it is the only
/// layer that knows what a `401` means for its backend) and publishes one of
/// these. The shell only maps the variant to a globally translated string
/// from `core_base_ui`.
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
///   SessionInvalidCredentialsFailure() => l10n.invalidCredentials,
///   SessionUserNotFoundFailure()       => l10n.userNotFound,
///   SessionServerFailure(:final message) => message,
///   SessionUnknownFailure()            => l10n.somethingWentWrong,
/// };
/// ```
sealed class SessionFailure {
  const SessionFailure();
}

/// The supplied credentials were rejected.
final class SessionInvalidCredentialsFailure extends SessionFailure {
  const SessionInvalidCredentialsFailure();
}

/// No account matches the supplied identifier.
final class SessionUserNotFoundFailure extends SessionFailure {
  const SessionUserNotFoundFailure();
}

/// The backend reported a failure and provided a displayable reason.
final class SessionServerFailure extends SessionFailure {
  const SessionServerFailure({required this.message, this.code});

  /// Message already fit to show to a user; the owning module decides its
  /// wording.
  final String message;

  /// Transport or application status code, when the owner knows one.
  final int? code;
}

/// Anything the owning module could not classify further.
final class SessionUnknownFailure extends SessionFailure {
  const SessionUnknownFailure();
}
