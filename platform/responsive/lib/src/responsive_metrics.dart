import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'adaptive/window_size_class.dart';
import 'scaling/responsive_profile.dart';
import 'scaling/scale_bounds.dart';
import 'utils/responsive_constants.dart';

/// Resolves a font size from the design value and the current [metrics].
///
/// Return the size in logical pixels. Supplied to [ResponsiveInit] when the
/// default text scaling is not what the design calls for.
///
/// The result is used as-is: neither [ResponsiveMetrics.textScaleBounds] nor
/// a profile's bounds clamp it. A resolver *is* a text scaling policy, and
/// clamping it afterwards would silently second-guess the one the caller
/// wrote. Read [ResponsiveMetrics.effectiveTextScaleBounds] inside the
/// resolver to honour the bounds.
typedef FontSizeResolver = double Function(
  num fontSize,
  ResponsiveMetrics metrics,
);

/// An immutable snapshot of everything needed to scale a design value to the
/// current screen.
///
/// Deliberately a plain value object: it holds no widget, no context and no
/// global state, so it is trivially testable and its equality drives
/// [ResponsiveScope.updateShouldNotify] exactly.
///
/// ## Scaling policy
///
/// Each axis starts as the raw ratio between the window and the design
/// artboard, then is clamped by a [ScaleBounds]: layout factors by
/// [scaleBounds], the text factor by [textScaleBounds]. Both default to
/// [ScaleBounds.downOnly] — shrink to fit a window smaller than the design,
/// draw 1:1 in a larger one — because an unbounded ratio turns a phone design
/// on a 1280-wide window into 3.4x everything. Growth is opt-in and bounded:
/// `ScaleBounds(max: 1.25)`.
///
/// [profiles] then let each [WindowSizeClass] swap in its own artboard,
/// bounds and [minTextAdapt]; the resolved values are exposed as
/// [activeProfile], [effectiveDesignSize], [effectiveScaleBounds],
/// [effectiveTextScaleBounds] and [effectiveMinTextAdapt], and those are what
/// the scaling uses.
@immutable
class ResponsiveMetrics {
  /// Treat [profiles] as immutable once passed — equality reads it, so a map
  /// mutated afterwards would make two snapshots compare wrong. A `const`
  /// map literal is the natural fit.
  const ResponsiveMetrics({
    required this.screenSize,
    required this.designSize,
    this.splitScreenMode = false,
    this.minTextAdapt = false,
    this.fontSizeResolver,
    this.breakpoints = const ResponsiveBreakpoints.material3(),
    this.scaleBounds = const ScaleBounds.downOnly(),
    this.textScaleBounds = const ScaleBounds.downOnly(),
    this.profiles = const <WindowSizeClass, ResponsiveProfile>{},
  });

  /// The current window size in logical pixels.
  final Size screenSize;

  /// The base artboard the design was drawn at, in logical pixels — the one
  /// every window class uses unless its profile names another.
  ///
  /// Scaling reads [effectiveDesignSize], not this.
  final Size designSize;

  /// Clamp the height used for vertical scaling to
  /// [ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT].
  final bool splitScreenMode;

  /// Scale text by the smaller of the two axes rather than by width.
  ///
  /// Prevents text from ballooning on wide, short windows. A profile may
  /// override it — see [effectiveMinTextAdapt].
  final bool minTextAdapt;

  /// Overrides the default text scaling entirely when supplied.
  ///
  /// Its result is not clamped by any [ScaleBounds] — see [FontSizeResolver].
  final FontSizeResolver? fontSizeResolver;

  /// Where the window size classes begin.
  final ResponsiveBreakpoints breakpoints;

  /// The range the layout factors — [scaleWidth], [scaleHeight], and the
  /// [radius], [diagonal] and [diameter] built from them — may take.
  ///
  /// Defaults to [ScaleBounds.downOnly]. A profile may override it — see
  /// [effectiveScaleBounds].
  final ScaleBounds scaleBounds;

  /// The range the text factor [scaleText], behind [sp], may take.
  ///
  /// Separate from [scaleBounds] because text and layout fail differently: a
  /// tablet can afford wider gutters long before it can afford bigger body
  /// text. Defaults to [ScaleBounds.downOnly]. A profile may override it —
  /// see [effectiveTextScaleBounds].
  final ScaleBounds textScaleBounds;

  /// Per-window-class overrides of [designSize], [scaleBounds],
  /// [textScaleBounds] and [minTextAdapt].
  ///
  /// See [ResponsiveProfile] for how the applicable one is chosen.
  final Map<WindowSizeClass, ResponsiveProfile> profiles;

  /// The width class of the current window.
  WindowSizeClass get windowSizeClass => breakpoints.classify(screenSize.width);

  /// The height class of the current window.
  WindowHeightClass get windowHeightClass =>
      breakpoints.classifyHeight(screenSize.height);

  /// Whether the window is wider than it is tall.
  ///
  /// Measured from [screenSize] — the window, not the device — with the same
  /// rule as [MediaQueryData.orientation]: a square window is portrait.
  Orientation get orientation => screenSize.width > screenSize.height
      ? Orientation.landscape
      : Orientation.portrait;

  /// Whether [orientation] is [Orientation.landscape].
  bool get isLandscape => orientation == Orientation.landscape;

  /// The profile that applies to [windowSizeClass], or `null` when none does.
  ///
  /// See [ResponsiveProfile.resolve].
  ResponsiveProfile? get activeProfile =>
      ResponsiveProfile.resolve(profiles, windowSizeClass);

  /// The artboard scaling measures against: the [activeProfile]'s, else
  /// [designSize].
  Size get effectiveDesignSize => activeProfile?.designSize ?? designSize;

  /// The layout bounds in force: the [activeProfile]'s, else [scaleBounds].
  ScaleBounds get effectiveScaleBounds =>
      activeProfile?.scaleBounds ?? scaleBounds;

  /// The text bounds in force: the [activeProfile]'s, else [textScaleBounds].
  ScaleBounds get effectiveTextScaleBounds =>
      activeProfile?.textScaleBounds ?? textScaleBounds;

  /// Whether text scales by the smaller axis: the [activeProfile]'s setting,
  /// else [minTextAdapt].
  bool get effectiveMinTextAdapt => activeProfile?.minTextAdapt ?? minTextAdapt;

  /// The raw horizontal ratio, before any bounds.
  double _widthRatio(Size design) => screenSize.width / design.width;

  /// The raw vertical ratio, before any bounds, honouring [splitScreenMode].
  double _heightRatio(Size design) {
    final height = splitScreenMode
        ? math.max(
            screenSize.height,
            ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT,
          )
        : screenSize.height;
    return height / design.height;
  }

  /// Horizontal factor: the window-to-artboard width ratio, clamped by
  /// [effectiveScaleBounds].
  double get scaleWidth =>
      effectiveScaleBounds.clamp(_widthRatio(effectiveDesignSize));

  /// Vertical factor: the height ratio, honouring [splitScreenMode], clamped
  /// by [effectiveScaleBounds].
  double get scaleHeight =>
      effectiveScaleBounds.clamp(_heightRatio(effectiveDesignSize));

  /// Ratio applied to text when no [fontSizeResolver] is supplied: the width
  /// ratio — or the smaller axis under [effectiveMinTextAdapt] — clamped by
  /// [effectiveTextScaleBounds].
  ///
  /// Computed from the raw ratios, not from [scaleWidth]/[scaleHeight], so
  /// text and layout bounds stay independent: text may grow where layout may
  /// not, and the other way round.
  double get scaleText {
    final design = effectiveDesignSize;
    final width = _widthRatio(design);
    final ratio = effectiveMinTextAdapt
        ? math.min(width, _heightRatio(design))
        : width;
    return effectiveTextScaleBounds.clamp(ratio);
  }

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

  /// Scales a font size: [scaleText], or [fontSizeResolver] when supplied.
  double sp(num value) =>
      fontSizeResolver?.call(value, this) ?? value * scaleText;

  /// [sp] capped at the design value, so text never grows past what the
  /// designer drew — only shrinks on smaller screens.
  ///
  /// Under the default [ScaleBounds.downOnly] text bounds this equals [sp].
  /// It earns its place where the bounds do not: a profile that lets text
  /// grow (`textScaleBounds: ScaleBounds(max: 1.25)`), or a
  /// [fontSizeResolver], whose result no bounds clamp. Use it for text that
  /// must stay at the design size even there.
  double spMin(num value) => math.min(value.toDouble(), sp(value));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResponsiveMetrics &&
        other.screenSize == screenSize &&
        other.designSize == designSize &&
        other.splitScreenMode == splitScreenMode &&
        other.minTextAdapt == minTextAdapt &&
        other.fontSizeResolver == fontSizeResolver &&
        other.breakpoints == breakpoints &&
        other.scaleBounds == scaleBounds &&
        other.textScaleBounds == textScaleBounds &&
        mapEquals(other.profiles, profiles);
  }

  @override
  int get hashCode => Object.hash(
    screenSize,
    designSize,
    splitScreenMode,
    minTextAdapt,
    fontSizeResolver,
    breakpoints,
    scaleBounds,
    textScaleBounds,
    // Order-independent, like [mapEquals]: two maps with the same entries
    // must hash alike whatever order they were written in.
    Object.hashAllUnordered(
      profiles.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'ResponsiveMetrics(screen: $screenSize, design: $designSize, '
      'splitScreenMode: $splitScreenMode, minTextAdapt: $minTextAdapt, '
      'scaleBounds: $scaleBounds, textScaleBounds: $textScaleBounds, '
      'profiles: $profiles)';
}
