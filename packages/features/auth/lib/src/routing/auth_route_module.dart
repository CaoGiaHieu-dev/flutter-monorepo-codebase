import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../feature_auth.dart';

part 'auth_route_module.g.dart';

@TypedShellRoute<AuthShellRoute>(
  routes: [
    TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN),
    TypedGoRoute<RegisterRoute>(path: AuthPath.REGISTER),
    TypedGoRoute<ForgotPasswordRoute>(path: AuthPath.FORGOT_PASSWORD),
  ],
)
class AuthShellRoute extends ShellRouteData {
  const AuthShellRoute();

  static final $navigatorKey = NavigatorKeys.authKey;
  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return navigator;
  }
}

class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.authKey;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const LoginPage();
  }
}

class RegisterRoute extends GoRouteDataCustom with $RegisterRoute {
  const RegisterRoute();
  static final $parentNavigatorKey = NavigatorKeys.authKey;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const RegisterPage();
  }
}

class ForgotPasswordRoute extends GoRouteDataCustom with $ForgotPasswordRoute {
  const ForgotPasswordRoute();
  static final $parentNavigatorKey = NavigatorKeys.authKey;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const ForgotPasswordPage();
  }
}
