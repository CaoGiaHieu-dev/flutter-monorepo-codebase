library dialogs;

import 'package:core_common/core_common.dart';
import 'package:flutter/material.dart';

import 'bottom_wrapper_dialog.dart';
import 'error_dialog.dart';
import 'warning_dialog.dart';

/// A class that provides a set of helper functions for displaying various types of dialogs within the application.
class AppDialog {
  /// Private constructor to prevent instantiation.
  AppDialog._();

  /// Singleton instance of the AppDialog class.
  factory AppDialog() => instance;

  /// Static instance of the AppDialog class.
  static final instance = AppDialog._();

  static void showErrorDialog({
    required String title,
    required String message,
  }) {
    AppDialogController.show(
      identity: title + message,
      builder: (context) {
        return ErrorDialog(title: title, content: message);
      },
    );
  }

  static void showSuccessDialog({
    required String title,
    required String message,
    VoidCallback? onConfirm,
  }) {
    AppDialogController.show(
      identity: title + message,
      builder: (context) {
        return WarningDialog(
          title: title,
          content: message,
          onConfirm: onConfirm,
        );
      },
    );
  }

  static void showInfoDialog({
    required String title,
    required String message,
    VoidCallback? onConfirm,
  }) {
    AppDialogController.show(
      identity: title + message,
      builder: (context) {
        return WarningDialog(
          title: title,
          content: message,
          onConfirm: onConfirm,
        );
      },
    );
  }
}

Future<T?> showDialogBottom<T extends Object?>({
  required BuildContext context,
  required WidgetBuilder builder,
  RouteTransitionsBuilder? customTransition,
  bool barrierDismissible = false,
  Duration transitionDuration = const Duration(milliseconds: 200),
  Color barrierColor = const Color(0x80000000),
  bool customDialog = false,
}) {
  return showGeneralDialog<T>(
    context: context,
    transitionDuration: transitionDuration,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    pageBuilder: (context, anim1, anim2) {
      if (customDialog) return builder.call(context);
      return BottomWrapperDialog(child: builder.call(context));
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return customTransition?.call(context, anim1, anim2, child) ??
          SlideTransition(
            position: Tween(
              begin: const Offset(0, 1),
              end: const Offset(0, 0),
            ).animate(anim1),
            child: child,
          );
    },
  );
}
