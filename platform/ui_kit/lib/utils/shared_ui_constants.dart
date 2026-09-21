import 'package:flutter/painting.dart';

/// Timing and overlay constants owned by `core_ui_kit`.
///
/// Package-internal by convention: these are defaults for the reusable
/// widgets in this package. Features that need a different value pass it
/// explicitly through the widget's constructor instead of reading these.
class SharedUiConstants {
  SharedUiConstants._();

  /// Default transition duration for [showDialogBottom].
  static const Duration DIALOG_TRANSITION_DURATION = Duration(
    milliseconds: 200,
  );

  /// Default visible duration for a toast raised by `AppOverlay.showToast`.
  static const Duration TOAST_DURATION = Duration(seconds: 3);

  /// Visible duration for the shorter error toasts raised while picking
  /// or cropping media.
  static const Duration MEDIA_ERROR_TOAST_DURATION = Duration(seconds: 2);

  /// Default scrim colour behind a dialog (50% black).
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);
}
