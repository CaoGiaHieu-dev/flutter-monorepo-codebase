/// Constants owned by the adaptive-layout widgets (`lib/src/adaptive/`).
///
/// Kept apart from `ResponsiveConstants` because they are window-space
/// layout limits, not design values: none of them is ever passed through
/// `context.w` and friends.
class AdaptiveConstants {
  AdaptiveConstants._();

  /// Share of the width the primary pane of an `AdaptiveSplitView` takes
  /// when no fixed width is given.
  ///
  /// 40/60 favours the detail pane, which carries the content being read;
  /// the list beside it needs only enough room to stay scannable.
  static const double SPLIT_PRIMARY_FRACTION = 0.4;

  /// Default thickness of an `AdaptiveSplitView` divider, in logical
  /// pixels: a hairline, as Material draws between panes.
  static const double SPLIT_DIVIDER_EXTENT = 1;

  /// Widest an `AdaptiveContent` lets its child grow, in logical pixels.
  ///
  /// Sized for a comfortable line length (roughly 70–80 characters of body
  /// text) and a form that still reads as one column on a tablet or desktop.
  static const double CONTENT_MAX_WIDTH = 640;
}
