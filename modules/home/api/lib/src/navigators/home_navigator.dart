import 'package:flutter/widgets.dart';

/// Routes owned by the home module, for *other features* to reach.
///
/// Part of `home_api`, the home module's public surface. The app shell does
/// not use it: after sign-in it goes to the neutral `IPostSignInLocation`
/// from `core_di`. Resolve it with `getItOrNull<HomeNavigator>()` — the
/// implementation lives in `feature_home`, which is removable (`arch_check`
/// R8).
abstract class HomeNavigator {
  void toHome(BuildContext context);
}
