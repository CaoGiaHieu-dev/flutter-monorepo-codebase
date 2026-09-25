import 'package:platform_kernel/platform_kernel.dart';

import '../gen/language/app_localizations.dart';

/// The user-facing sentence for a failure, chosen by its code.
///
/// `AppFailure.message` is an English diagnostic for logs and never reaches
/// the screen (RULE-34). What the user reads is picked here from the
/// failure's `code` — an [ErrorCodes] value or an HTTP status — so every
/// screen words the same fault the same way, in the user's language:
///
/// ```dart
/// error: (failure) => Text(context.l10n.failureMessage(failure.code)),
/// ```
///
/// Takes the code rather than the `AppFailure` itself: `core_base_ui` is a
/// `ui` package and does not depend on `domain_core` (RULE-01, RULE-02).
/// A feature that can say something more specific (wrong password, unknown
/// user) classifies the failure itself and uses its own ARB; this is the
/// fallback for everything generic.
extension FailureMessageExtension on AppLocalizations {
  String failureMessage(int? code) {
    if (code == null) return somethingWentWrong;
    return switch (code) {
      ErrorCodes.NO_INTERNET ||
      ErrorCodes.CONNECTION_ERROR => noInternetConnection,
      ErrorCodes.CONNECTION_TIMEOUT ||
      ErrorCodes.TRANSFORM_TIMEOUT => connectionTimedOut,
      >= ErrorCodes.NETWORK_ERROR && < ErrorCodes.STORAGE_ERROR => networkError,
      >= 500 && < 600 => serverUnavailable,
      _ => somethingWentWrong,
    };
  }
}
