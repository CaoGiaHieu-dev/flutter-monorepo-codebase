import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/extensions.dart';
import '../utils/home_path.dart';
import 'home_route_module.dart';

/// SAMPLE — a module contributing one primary navigation destination.
///
/// It describes the destination ([NavDestination]) rather than building a
/// widget, so the same module works in an app that renders a bottom bar, a
/// rail or a sidebar.
@LazySingleton(as: INavDestinationModule)
class HomeNavDestination extends INavDestinationModule {
  @override
  int get order => 0;

  @override
  String get path => HomePath.HOME;

  @override
  List<RouteBase> get routes => [$homeShellRoute];

  @override
  NavDestination destination(BuildContext context) => NavDestination(
    label: context.l10nHome.tabLabel,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  );
}
