import 'package:flutter/widgets.dart';

/// Routes owned by the auth feature.
///
/// Resolve it with `getItOrNull<AuthNavigator>()` — the implementation lives in
/// `feature_auth`, which is removable, so a build without it must fall through
/// rather than throw. Enforced by `arch_check` rule R8.
abstract class AuthNavigator {
  void toLogin(BuildContext context);
}
