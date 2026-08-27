import 'package:core_common/core_common.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/pages.dart';
import '../utils/settings_path.dart';

part 'settings_route_module.g.dart';

@TypedGoRoute<SettingsRoute>(path: SettingsPath.SETTING)
class SettingsRoute extends GoRouteDataCustom with $SettingsRoute {
  const SettingsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const SettingsPage();
  }
}
