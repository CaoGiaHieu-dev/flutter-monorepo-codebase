import 'package:home_api/home_api.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'home_route_module.dart';

@LazySingleton(as: HomeNavigator)
class HomeNavigatorImpl implements HomeNavigator {
  @override
  void toHome(BuildContext context) => const HomeRoute().go(context);
}
