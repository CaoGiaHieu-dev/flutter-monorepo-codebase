import 'package:auth_api/auth_api.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'auth_route_module.dart';

@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) => const LoginRoute().go(context);
}
