/// Presentation constants owned by the app shell.
class AppShellUiConstants {
  AppShellUiConstants._();

  /// The largest OS text scale the app honours, applied by `RootApp` with
  /// `MediaQuery.withClampedTextScaling`.
  ///
  /// 2.0 is the "resize text up to 200%" of WCAG 2.2 SC 1.4.4 and the top of
  /// Android 14's font-size slider; iOS accessibility sizes go past 3x, where
  /// a phone screen holds a handful of words per line. Below this cap the
  /// user's setting passes through untouched — non-linear scalers included —
  /// and nothing clamps the lower end, so a smaller-than-default setting is
  /// respected too.
  static const double MAX_TEXT_SCALE_FACTOR = 2.0;
}
