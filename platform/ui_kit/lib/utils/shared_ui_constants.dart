import 'package:flutter/painting.dart';

/// Timing, overlay and default-size constants owned by `core_ui_kit`.
///
/// Package-internal by convention: these are defaults for the reusable
/// widgets in this package. Features that need a different value pass it
/// explicitly through the widget's constructor instead of reading these.
///
/// Sizes are **design pixels**: a widget scales its own default through
/// `core_responsive` (`context.w/h/r`) when the caller passes nothing. A value
/// the caller passes is already scaled and used as-is.
class SharedUiConstants {
  SharedUiConstants._();

  /// Default transition duration for [showDialogBottom].
  static const Duration DIALOG_TRANSITION_DURATION = Duration(
    milliseconds: 200,
  );

  /// Default visible duration for a toast raised by `AppOverlay.showToast`.
  static const Duration TOAST_DURATION = Duration(seconds: 3);

  /// Default scrim colour behind a dialog (50% black).
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);

  /// Default height of a rectangle, outlined or drop-down `CustomButton`.
  static const double BUTTON_HEIGHT = 48;

  /// Default corner radius of a rectangle, options or drop-down button.
  static const double BUTTON_RADIUS = 8;

  /// Default corner radius of an outlined button.
  static const double OUTLINED_BUTTON_RADIUS = 30;

  /// Default minimum width of an outlined button.
  static const double OUTLINED_BUTTON_MIN_WIDTH = 54;

  /// Default diameter of a circle button.
  static const double CIRCLE_BUTTON_DIAMETER = 48;

  /// Default height and minimum width of an options button.
  static const double OPTIONS_BUTTON_SIZE = 40;

  /// Default maximum width of a drop-down button.
  static const double DROPDOWN_BUTTON_MAX_WIDTH = 125;

  /// Default horizontal padding inside a drop-down button.
  static const double DROPDOWN_BUTTON_PADDING_HORIZONTAL = 12;

  /// Default vertical padding inside a drop-down button.
  static const double DROPDOWN_BUTTON_PADDING_VERTICAL = 8;

  /// Default logo width of `EmptyWidget`.
  static const double EMPTY_WIDGET_WIDTH = 120;

  /// Default logo height of `EmptyWidget`.
  static const double EMPTY_WIDGET_HEIGHT = 60;

  /// Default corner radius of `LoadingWidget`.
  static const double LOADING_WIDGET_RADIUS = 16;

  /// Default side length of `LoadingWidget`.
  static const double LOADING_WIDGET_DIMENSION = 100;

  /// Dash and gap length of `DotDivider`.
  static const double DOT_DIVIDER_DASH_LENGTH = 2;
}
