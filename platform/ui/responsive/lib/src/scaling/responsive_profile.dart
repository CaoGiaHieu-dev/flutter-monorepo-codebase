import 'package:flutter/widgets.dart';

import '../adaptive/window_size_class.dart';
import 'scale_bounds.dart';

/// Scaling settings for one [WindowSizeClass], overriding the top-level
/// values given to `ResponsiveInit`.
///
/// One design size cannot serve every window. A phone artboard stretched to a
/// desktop window scales everything up by the width ratio; capped with
/// [ScaleBounds.downOnly] it stops growing, but it is still a phone design in
/// a desktop window. A profile lets a window class name the artboard it was
/// actually designed at, and how far that class may scale away from it:
///
/// ```dart
/// profiles: const {
///   // Tablets: a tablet artboard, allowed to grow a quarter past it.
///   WindowSizeClass.medium: ResponsiveProfile(
///     designSize: Size(600, 960),
///     scaleBounds: ScaleBounds(max: 1.25),
///     textScaleBounds: ScaleBounds(max: 1.25),
///   ),
///   // Desktop windows: real logical pixels. Against a tall phone artboard
///   // a short laptop window would otherwise shrink every vertical gap.
///   WindowSizeClass.expanded: ResponsiveProfile(
///     scaleBounds: ScaleBounds.fixed(),
///     textScaleBounds: ScaleBounds.fixed(),
///   ),
/// },
/// ```
///
/// Every field is nullable, and `null` means "inherit the top-level value" —
/// so a profile states only what differs for its class.
///
/// ## Which profile applies
///
/// The one keyed by the current window's class; if that class has none, the
/// one keyed by the nearest *smaller* class that has one; if none does, no
/// profile, and the top-level values apply unchanged. See [resolve].
///
/// A profile set at `expanded` therefore also covers `large` and `extraLarge`
/// until one of them declares its own — the way a `min-width` media query
/// cascades. Falling back to a *larger* class instead would hand a narrow
/// window a design drawn for more room than it has.
///
/// ## Continuity at the boundary
///
/// Crossing into a class with its own [designSize] changes the ratio in one
/// step. A [designSize] no wider than the first width of its class (600 for
/// `medium`, 840 for `expanded`, with the Material 3 breakpoints) starts at a
/// ratio of 1 or more, which [ScaleBounds.downOnly] draws 1:1 on both sides
/// of the boundary — so a visible step appears only where bounds allow
/// scaling up. A wider one makes everything shrink the moment the window
/// enters the class.
@immutable
class ResponsiveProfile {
  /// Overrides for one window class. Leave a field `null` to inherit the
  /// top-level value.
  const ResponsiveProfile({
    this.designSize,
    this.scaleBounds,
    this.textScaleBounds,
    this.minTextAdapt,
  });

  /// The artboard this window class was designed at.
  ///
  /// Both sides must be positive and finite
  /// (`ResponsiveMetrics.isValidDesignSize`). A `const` constructor cannot
  /// check that, so `ResponsiveInit` asserts it for every profile when it
  /// builds, and `ResponsiveMetrics` again when the profile is in force.
  final Size? designSize;

  /// The range layout factors may take in this class — `w`, `h`, and the
  /// `r`/`dg`/`dm` factors derived from them.
  final ScaleBounds? scaleBounds;

  /// The range the text factor behind `sp` may take in this class.
  final ScaleBounds? textScaleBounds;

  /// Scale text by the smaller axis in this class — see
  /// `ResponsiveMetrics.minTextAdapt`.
  final bool? minTextAdapt;

  /// The profile that applies to a window of [windowSizeClass], or `null`
  /// when [profiles] has none for it or any smaller class.
  ///
  /// Takes the exact class first, then walks down one class at a time.
  static ResponsiveProfile? resolve(
    Map<WindowSizeClass, ResponsiveProfile> profiles,
    WindowSizeClass windowSizeClass,
  ) {
    if (profiles.isEmpty) return null;
    for (var i = windowSizeClass.index; i >= 0; i--) {
      final profile = profiles[WindowSizeClass.values[i]];
      if (profile != null) return profile;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponsiveProfile &&
          other.designSize == designSize &&
          other.scaleBounds == scaleBounds &&
          other.textScaleBounds == textScaleBounds &&
          other.minTextAdapt == minTextAdapt;

  @override
  int get hashCode =>
      Object.hash(designSize, scaleBounds, textScaleBounds, minTextAdapt);

  @override
  String toString() =>
      'ResponsiveProfile(designSize: $designSize, scaleBounds: $scaleBounds, '
      'textScaleBounds: $textScaleBounds, minTextAdapt: $minTextAdapt)';
}
