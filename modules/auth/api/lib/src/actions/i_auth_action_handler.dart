import 'package:flutter/widgets.dart';

/// Auth actions another feature may trigger (settings' logout row).
///
/// Resolve with `getItOrNull<IAuthActionHandler>()` and hide the action when
/// it is null: `feature_auth` implements it and is removable (RULE-12).
abstract class IAuthActionHandler {
  /// Signs the user out; the app shell navigates to sign-in on its own.
  Future<void> logout(BuildContext context);
}
