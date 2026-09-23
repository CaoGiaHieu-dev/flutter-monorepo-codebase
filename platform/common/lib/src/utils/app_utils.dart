import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:material_ui/material_ui.dart';

/// Small app-wide helpers with no better home.
class AppUtils {
  AppUtils._();

  /// The internet connection checker instance.
  static final internetConnection = InternetConnection();

  /// Unfocuses the keyboard if it is currently focused.
  static void unfocusKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}
