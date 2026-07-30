import 'package:flutter/widgets.dart';

abstract class AuthNavigator {
  void toLogin(BuildContext context);
  void toRegister(BuildContext context);
  void toForgotPassword(BuildContext context);
}
