import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'home_route_module.dart';

@Singleton(as: HomeNavigator)
class HomeNavigatorImpl implements HomeNavigator {
  @override
  void toHome(BuildContext context) => const HomeRoute().go(context);
}
