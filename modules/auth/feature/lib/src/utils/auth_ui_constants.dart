/// Layout numbers of the auth screens, unscaled.
///
/// The widgets scale them through `context` (`context.r`) where they are
/// used, so changing a size is one edit here — RULE-33.
class AuthUiConstants {
  AuthUiConstants._();

  /// Side of the square badge behind the header's lock icon (scaled with `r`).
  static const double HEADER_BADGE_SIZE = 96;

  /// Size of the header's lock icon (scaled with `r`).
  static const double HEADER_ICON_SIZE = 44;

  /// Border width of a focused form field (scaled with `r`).
  static const double FOCUSED_BORDER_WIDTH = 2;

  /// Side of the spinner that replaces the submit label (scaled with `r`).
  static const double SUBMIT_SPINNER_SIZE = 20;

  /// Stroke of that spinner (scaled with `r`).
  static const double SUBMIT_SPINNER_STROKE = 2;
}
