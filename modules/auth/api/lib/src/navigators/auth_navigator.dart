import 'package:flutter/widgets.dart';

/// Routes owned by the auth module, for *other features* to reach.
///
/// Part of `auth_api`, the auth module's public surface: a feature that needs
/// to send the user to sign-in (onboarding's "Get started") depends on this
/// package — never on `feature_auth`. The app shell does not use it; it sends
/// signed-out users to the neutral `ISignInLocation` from `core_di`.
///
/// Resolve it with `getItOrNull<AuthNavigator>()` — the implementation lives
/// in `feature_auth`, which is removable, so a build without it must fall
/// through rather than throw. Enforced by `arch_check` rule R8.
abstract class AuthNavigator {
  void toLogin(BuildContext context);
}
