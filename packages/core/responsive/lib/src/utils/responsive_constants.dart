/// Constants owned by `core_responsive`.
class ResponsiveConstants {
  ResponsiveConstants._();

  /// Floor applied to the screen height when `splitScreenMode` is on.
  ///
  /// In split screen the window can be short enough that height-scaled values
  /// collapse to unreadable sizes. Clamping the *denominator input* keeps
  /// vertical scaling sane instead of letting it track a 300 dp window.
  static const double SPLIT_SCREEN_MIN_HEIGHT = 700;

  /// Design size used when a caller does not supply one: the common 360x690
  /// mobile artboard.
  static const double DEFAULT_DESIGN_WIDTH = 360;
  static const double DEFAULT_DESIGN_HEIGHT = 690;
}
