/// Magic values owned exclusively by `core_base_ui`'s own behaviour.
///
/// These are NOT design tokens — the shared spacing / radius / typography
/// scale lives in `src/styles/` (`AppSpacing`, `AppRadius`, `AppTextStyles`,
/// …) and stays there because features consume it as public API. This class
/// only collects the loose numbers that used to sit inline inside this
/// package's extensions and theme builder.
///
/// Values are stored **unscaled**; the call site applies the ScreenUtil
/// extension (`.h` / `.r` / `.sp`) so scaling stays visible where it happens.
class BaseUiConstants {
  BaseUiConstants._();

  // ---------------------------------------------------------------------------
  // Snackbar (context_extension.dart)
  // ---------------------------------------------------------------------------

  /// Default visible duration for `BuildContext.showSnackBar`.
  static const Duration SNACK_BAR_DURATION = Duration(seconds: 3);

  // ---------------------------------------------------------------------------
  // Dropdown menu (key_extension.dart)
  // ---------------------------------------------------------------------------

  /// Vertical offset applied to the dropdown anchor rect (scaled with `.h`).
  static const double DROPDOWN_VERTICAL_OFFSET = -4;

  /// Corner radius of the dropdown surface (scaled with `.r`).
  static const double DROPDOWN_BORDER_RADIUS = 8;

  /// Border thickness of the dropdown surface (scaled with `.r`).
  static const double DROPDOWN_BORDER_WIDTH = 1;

  /// Height of a single dropdown row (scaled with `.h`).
  static const double DROPDOWN_ITEM_HEIGHT = 48;

  /// Dropdown max height as a fraction of the screen's longest side.
  static const int DROPDOWN_MAX_HEIGHT_DIVISOR = 3;

  // ---------------------------------------------------------------------------
  // Theme builder (theme_provider.dart)
  // ---------------------------------------------------------------------------

  /// Font size of the app bar title (scaled with `.sp`).
  static const double APP_BAR_TITLE_FONT_SIZE = 16;

  /// App bar elevation once content scrolls under it — flat by design.
  static const double APP_BAR_SCROLLED_UNDER_ELEVATION = 0.0;
}
