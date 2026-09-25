import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/l10n_settings_extension.dart';
import '../utils/settings_path.dart';
import 'settings_route_module.dart';

/// SAMPLE — a second destination, showing that `order` is what fixes the
/// sequence rather than registration order or DI declaration order.
@LazySingleton(as: INavDestinationModule)
class SettingsNavDestination extends INavDestinationModule {
  @override
  int get order => 1;

  @override
  String get path => SettingsPath.SETTINGS;

  @override
  List<RouteBase> get routes => [$settingsRoute];

  @override
  NavDestination destination(BuildContext context) => NavDestination(
    label: context.l10nSettings.tabLabel,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  );
}
