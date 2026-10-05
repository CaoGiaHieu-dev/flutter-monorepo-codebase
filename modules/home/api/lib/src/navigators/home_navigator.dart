import 'package:flutter/widgets.dart';

/// Routes the home module owns, for *other features* to reach. Resolve it with
/// `getItOrNull<HomeNavigator>()`; `feature_home` implements it. The app shell
/// uses `IPostSignInLocation` from `core_di` instead.
abstract class HomeNavigator {
  void toHome(BuildContext context);
}
