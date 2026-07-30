import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

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
