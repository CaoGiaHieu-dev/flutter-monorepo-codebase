import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_route_module.dart';

@Singleton(as: SettingsNavigator)
class SettingsNavigatorImpl implements SettingsNavigator {
  @override
  void toSettings(BuildContext context) => const SettingsRoute().go(context);
}
