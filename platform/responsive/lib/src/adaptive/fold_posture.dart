import 'dart:ui' show DisplayFeature;

/// How a fold or hinge divides the window — the posture a layout reacts to.
///
/// Read it through `context.foldPosture`. It describes the *window*, not the
/// device: a foldable that is closed (running on its cover screen) or opened
/// flat is [flat], exactly like a phone or a tablet, because nothing divides
/// the space the app has.
enum FoldPosture {
  /// Nothing divides the window: a phone, a tablet, a foldable opened flat
  /// or folded shut.
  flat,

  /// A vertical fold or hinge splits the window into a left and a right
  /// half — a book-style foldable (Galaxy Z Fold, Pixel Fold) half opened,
  /// or a dual-screen device spanning both screens. Two panes side by side.
  book,

  /// A horizontal fold splits the window into a top and a bottom half — a
  /// flip phone (Galaxy Z Flip) half folded and stood on a table, or a book
  /// foldable turned sideways. Content above the fold, controls below it.
  tabletop;

  /// The posture a separating [feature] puts the window in, or [flat] when
  /// there is none.
  ///
  /// Orientation comes from the feature's own shape: a fold is reported as
  /// a zero-width (vertical) or zero-height (horizontal) line, and a hinge as
  /// a strip that is far longer than it is thick, so comparing the two sides
  /// needs no window size.
  static FoldPosture of(DisplayFeature? feature) {
    if (feature == null) return flat;
    final bounds = feature.bounds;
    return bounds.height > bounds.width ? book : tabletop;
  }
}
