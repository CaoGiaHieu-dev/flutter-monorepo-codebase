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

  /// The scale factor at which a design value is drawn at exactly its design
  /// size — the window matches the artboard on that axis.
  ///
  /// The pivot of every scaling policy: below it values shrink, above it they
  /// grow. `ScaleBounds.downOnly()` caps at it, so a window wider than the
  /// artboard draws the design 1:1 instead of blowing it up.
  static const double DESIGN_SCALE_FACTOR = 1;

  /// The lowest scale factor a `ScaleBounds` may allow: a factor below zero
  /// would mirror a value, which no layout means.
  static const double MIN_SCALE_FACTOR = 0;

  /// The highest scale factor a `ScaleBounds` may allow: no cap at all.
  static const double MAX_SCALE_FACTOR = double.infinity;

  /// Window-width breakpoints, in logical pixels — the Material 3 window
  /// size classes. A window narrower than [BREAKPOINT_MEDIUM] is compact.
  static const double BREAKPOINT_MEDIUM = 600;
  static const double BREAKPOINT_EXPANDED = 840;
  static const double BREAKPOINT_LARGE = 1200;
  static const double BREAKPOINT_EXTRA_LARGE = 1600;

  /// Window-height breakpoints, in logical pixels. A window shorter than
  /// [BREAKPOINT_HEIGHT_MEDIUM] is compact — a phone in landscape, a flip
  /// phone's half-folded top screen.
  static const double BREAKPOINT_HEIGHT_MEDIUM = 480;
  static const double BREAKPOINT_HEIGHT_EXPANDED = 900;
}
