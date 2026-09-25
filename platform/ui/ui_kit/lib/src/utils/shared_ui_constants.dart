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

  /// Default show/hide duration of a dialog raised through `AppOverlay`.
  static const Duration DIALOG_TRANSITION_DURATION = Duration(
    milliseconds: 200,
  );

  /// Default visible duration for a toast raised by `AppOverlay.showToast`.
  static const Duration TOAST_DURATION = Duration(seconds: 3);

  /// Default height of `CustomButton.rectangle`.
  static const double BUTTON_HEIGHT = 48;

  /// Opacity of the ripple and highlight of a transparent `CustomButton`.
  static const double TRANSPARENT_BUTTON_FEEDBACK_ALPHA = 0.12;

  /// Default logo width of `EmptyWidget`.
  static const double EMPTY_WIDGET_WIDTH = 120;

  /// Default logo height of `EmptyWidget`.
  static const double EMPTY_WIDGET_HEIGHT = 60;

  /// Default corner radius of `LoadingWidget`.
  static const double LOADING_WIDGET_RADIUS = 16;

  /// Default side length of `LoadingWidget`.
  static const double LOADING_WIDGET_DIMENSION = 100;

  /// Opacity of the `textPrimary` pill behind a toast.
  static const double TOAST_BACKGROUND_ALPHA = 0.4;

  /// How far `CustomInputField`'s counter is nudged towards the start, and
  /// its default bottom padding (scaled with `w` / `h`).
  static const double INPUT_COUNTER_OFFSET_X = 10;

  /// How far `CustomInputField`'s counter is lifted into the field (scaled
  /// with `h`).
  static const double INPUT_COUNTER_OFFSET_Y = 30;

  /// Stroke width of `CustomCacheNetworkImage`'s loading spinner — the
  /// thin variant Material uses inside small surfaces.
  static const double IMAGE_PROGRESS_STROKE_WIDTH = 2;
}
