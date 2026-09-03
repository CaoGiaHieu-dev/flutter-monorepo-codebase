import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'auth_route_module.dart';

@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) {
    const LoginRoute().go(context);
  }

  @override
  void toRegister(BuildContext context) => const RegisterRoute().go(context);

  @override
  void toForgotPassword(BuildContext context) =>
      const ForgotPasswordRoute().go(context);
}
