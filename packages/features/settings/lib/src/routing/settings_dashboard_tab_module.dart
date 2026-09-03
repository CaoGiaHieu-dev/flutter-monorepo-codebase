import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/extensions.dart';
import '../utils/settings_path.dart';
import 'settings_route_module.dart';

@LazySingleton(as: IDashboardTabModule)
class SettingsDashboardTabModule extends IDashboardTabModule {
  @override
  int get order => 1;

  @override
  String get path => SettingsPath.SETTING;

  @override
  List<RouteBase> get routes => [$settingsRoute];

  @override
  BottomNavigationBarItem navigationBarItem(BuildContext context) {
    return BottomNavigationBarItem(
      icon: const Icon(Icons.settings),
      label: context.l10nSettings.tabLabel,
    );
  }
}
