import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import '../extensions/extensions.dart';
import '../utils/home_path.dart';
import 'home_route_module.dart';

@LazySingleton(as: IDashboardTabModule)
class HomeDashboardTabModule extends IDashboardTabModule {
  @override
  int get order => 0;

  @override
  String get path => HomePath.HOME;

  @override
  List<RouteBase> get routes => [$homeShellRoute];

  @override
  BottomNavigationBarItem navigationBarItem(BuildContext context) {
    return BottomNavigationBarItem(
      icon: const Icon(Icons.home),
      label: context.l10nHome.tabLabel,
    );
  }
}
