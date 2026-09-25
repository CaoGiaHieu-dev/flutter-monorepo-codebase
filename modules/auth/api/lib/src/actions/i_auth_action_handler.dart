import 'package:flutter/widgets.dart';

/// Auth actions another feature may trigger without importing `feature_auth`.
///
/// Part of `auth_api`. `feature_settings` offers a logout row through it;
/// `feature_auth` implements it (`AuthActionHandlerImpl`). Resolve it with
/// `getItOrNull<IAuthActionHandler>()` — with no auth module composed the
/// lookup is null and the caller hides the action (`arch_check` R8).
abstract class IAuthActionHandler {
  /// Signs the user out; completes once the stored session is cleared. The
  /// app shell navigates to sign-in on its own — the caller does not.
  Future<void> logout(BuildContext context);
}
