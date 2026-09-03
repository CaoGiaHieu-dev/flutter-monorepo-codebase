import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'utils/responsive_constants.dart';

/// Resolves a font size from the design value and the current [metrics].
///
/// Return the size in logical pixels. Supplied to [ResponsiveInit] when the
/// default text scaling is not what the design calls for.
typedef FontSizeResolver =
    double Function(num fontSize, ResponsiveMetrics metrics);

/// An immutable snapshot of everything needed to scale a design value to the
/// current screen.
///
/// Deliberately a plain value object: it holds no widget, no context and no
/// global state, so it is trivially testable and its equality drives
/// [ResponsiveScope.updateShouldNotify] exactly.
@immutable
class ResponsiveMetrics {
  const ResponsiveMetrics({
    required this.screenSize,
    required this.designSize,
    this.splitScreenMode = false,
    this.minTextAdapt = false,
    this.fontSizeResolver,
  });

  /// The current window size in logical pixels.
  final Size screenSize;

  /// The artboard size the design was drawn at, in logical pixels.
  final Size designSize;

  /// Clamp the height used for vertical scaling to
  /// [ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT].
  final bool splitScreenMode;

  /// Scale text by the smaller of the two axes rather than by width.
  ///
  /// Prevents text from ballooning on wide, short windows.
  final bool minTextAdapt;

  /// Overrides the default text scaling entirely when supplied.
  final FontSizeResolver? fontSizeResolver;

  /// Horizontal ratio between the real screen and the design artboard.
  double get scaleWidth => screenSize.width / designSize.width;

  /// Vertical ratio, honouring [splitScreenMode].
  double get scaleHeight {
    final height = splitScreenMode
        ? math.max(screenSize.height, ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT)
        : screenSize.height;
    return height / designSize.height;
  }

  /// Ratio applied to text when no [fontSizeResolver] is supplied.
  double get scaleText =>
      minTextAdapt ? math.min(scaleWidth, scaleHeight) : scaleWidth;

  /// Scales a width. Also the right choice for anything that must stay square.
  double width(num value) => value * scaleWidth;

  /// Scales a height — vertical gaps, row heights.
  double height(num value) => value * scaleHeight;

  /// Scales by the smaller axis. Use for radii, borders and strokes, which
  /// look wrong if they stretch with only one dimension.
  double radius(num value) => value * math.min(scaleWidth, scaleHeight);

  /// Scales by both axes at once.
  double diagonal(num value) => value * scaleWidth * scaleHeight;

  /// Scales by the larger axis.
  double diameter(num value) => value * math.max(scaleWidth, scaleHeight);

  /// Scales a font size.
  double sp(num value) =>
      fontSizeResolver?.call(value, this) ?? value * scaleText;

  /// [sp] capped at the design value, so text never grows past what the
  /// designer drew — only shrinks on smaller screens.
  double spMin(num value) => math.min(value.toDouble(), sp(value));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResponsiveMetrics &&
        other.screenSize == screenSize &&
        other.designSize == designSize &&
        other.splitScreenMode == splitScreenMode &&
        other.minTextAdapt == minTextAdapt &&
        other.fontSizeResolver == fontSizeResolver;
  }

  @override
  int get hashCode => Object.hash(
    screenSize,
    designSize,
    splitScreenMode,
    minTextAdapt,
    fontSizeResolver,
  );

  @override
  String toString() =>
      'ResponsiveMetrics(screen: $screenSize, design: $designSize, '
      'splitScreenMode: $splitScreenMode, minTextAdapt: $minTextAdapt)';
}
