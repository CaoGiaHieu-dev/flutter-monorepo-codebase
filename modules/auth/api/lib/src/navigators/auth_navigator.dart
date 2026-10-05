import 'package:flutter/widgets.dart';

/// Routes owned by auth, for other features (onboarding's "Get started").
///
/// Resolve with `getItOrNull<AuthNavigator>()` — `feature_auth` implements it
/// and is removable (RULE-12). The shell uses `ISignInLocation`, not this.
abstract class AuthNavigator {
  void toLogin(BuildContext context);
}
