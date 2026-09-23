import 'package:flutter/foundation.dart';

import '../utils/responsive_constants.dart';

/// The range a scale factor is allowed to take.
///
/// A scale factor is the ratio between the window and the design artboard on
/// one axis. Left alone, that ratio grows without limit: a 1280-wide desktop
/// window against a 375-wide phone design is 3.4x, so a 20 px app-bar title
/// renders at 68 px and clips. The ratio is the right answer when the window
/// is *smaller* than the design — the design must shrink to fit — and almost
/// never the right answer when it is larger, where the extra space belongs to
/// the layout (more columns, a side rail), not to bigger pixels.
///
/// So the default is [ScaleBounds.downOnly]: shrink freely, never grow.
/// Allow growth explicitly and by a bounded amount, `ScaleBounds(max: 1.25)`,
/// where a design genuinely should fill a larger screen; floor it with [min]
/// where shrinking past a point would stop text being readable or targets
/// being tappable.
///
/// The presets are named `const` constructors, not static instances, and
/// bounds compare by value: `const ScaleBounds.downOnly()` equals
/// `const ScaleBounds(max: 1)` wherever either is written.
@immutable
class ScaleBounds {
  /// Clamps a factor to `[min, max]`.
  ///
  /// [min] must be at least [ResponsiveConstants.MIN_SCALE_FACTOR] and no
  /// greater than [max].
  const ScaleBounds({
    this.min = ResponsiveConstants.MIN_SCALE_FACTOR,
    this.max = ResponsiveConstants.MAX_SCALE_FACTOR,
  }) : assert(
         min >= ResponsiveConstants.MIN_SCALE_FACTOR,
         'A scale factor below zero would mirror the value.',
       ),
       assert(min <= max, 'ScaleBounds.min must not exceed ScaleBounds.max.');

  /// No clamping: the raw window-to-design ratio, however large or small.
  ///
  /// The behaviour before bounds existed. Right for a design drawn for one
  /// device class that must fill every window in proportion — rarely what a
  /// multi-form-factor app wants.
  const ScaleBounds.unbounded()
    : min = ResponsiveConstants.MIN_SCALE_FACTOR,
      max = ResponsiveConstants.MAX_SCALE_FACTOR;

  /// Shrink below the design size, never grow past it. The default.
  ///
  /// A window smaller than the artboard scales the design down to fit; a
  /// larger one draws it 1:1 and leaves the extra space to the layout.
  const ScaleBounds.downOnly()
    : min = ResponsiveConstants.MIN_SCALE_FACTOR,
      max = ResponsiveConstants.DESIGN_SCALE_FACTOR;

  /// Always the design size: no scaling in either direction.
  ///
  /// For a window class whose layout is built to its own measurements — a
  /// desktop profile laid out in real logical pixels — where tracking the
  /// window would only fight the layout.
  const ScaleBounds.fixed()
    : min = ResponsiveConstants.DESIGN_SCALE_FACTOR,
      max = ResponsiveConstants.DESIGN_SCALE_FACTOR;

  /// The smallest factor allowed. `0` lets a value shrink all the way.
  final double min;

  /// The largest factor allowed. [double.infinity] lets a value grow without
  /// limit.
  final double max;

  /// [factor], pulled into `[min, max]`.
  double clamp(double factor) {
    if (factor < min) return min;
    if (factor > max) return max;
    return factor;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScaleBounds && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'ScaleBounds(min: $min, max: $max)';
}
