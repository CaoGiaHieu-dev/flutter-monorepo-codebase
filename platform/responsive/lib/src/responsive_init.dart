import 'package:flutter/widgets.dart';

import 'adaptive/window_size_class.dart';
import 'responsive_metrics.dart';
import 'responsive_scope.dart';
import 'scaling/responsive_profile.dart';
import 'scaling/scale_bounds.dart';
import 'utils/responsive_constants.dart';

/// Installs responsive scaling for the subtree. Mount it once, above
/// `MaterialApp`.
///
/// ```dart
/// ResponsiveInit(
///   designSize: const Size(360, 690),
///   minTextAdapt: true,
///   splitScreenMode: true,
///   // Both default to ScaleBounds.downOnly(): shrink on a window smaller than
///   // the design, draw 1:1 on a larger one. Opt in to bounded growth:
///   scaleBounds: const ScaleBounds(max: 1.25),
///   profiles: const {
///     // Tablets: their own artboard, text allowed to grow a little too.
///     WindowSizeClass.medium: ResponsiveProfile(
///       designSize: Size(600, 960),
///       textScaleBounds: ScaleBounds(max: 1.15),
///     ),
///     // Desktop windows (and anything wider, until it declares its own):
///     // real logical pixels, no scaling in either direction.
///     WindowSizeClass.expanded: ResponsiveProfile(
///       scaleBounds: ScaleBounds.fixed(),
///       textScaleBounds: ScaleBounds.fixed(),
///     ),
///   },
///   child: const RootApp(),
/// )
/// ```
///
/// ## Why this is a `StatelessWidget`
///
/// Screen size already arrives through `MediaQuery`, so tracking it with a
/// `WidgetsBindingObserver` and `setState` would duplicate machinery Flutter
/// runs anyway. [MediaQuery.sizeOf] registers a dependency on the *size
/// aspect* only, so this widget rebuilds on a resize and stays put when
/// anything else in the media query changes — padding, text scale, brightness.
class ResponsiveInit extends StatelessWidget {
  const ResponsiveInit({
    required this.child,
    this.designSize = const Size(
      ResponsiveConstants.DEFAULT_DESIGN_WIDTH,
      ResponsiveConstants.DEFAULT_DESIGN_HEIGHT,
    ),
    this.splitScreenMode = false,
    this.minTextAdapt = false,
    this.fontSizeResolver,
    this.breakpoints = const ResponsiveBreakpoints.material3(),
    this.scaleBounds = const ScaleBounds.downOnly(),
    this.textScaleBounds = const ScaleBounds.downOnly(),
    this.profiles = const <WindowSizeClass, ResponsiveProfile>{},
    super.key,
  });

  /// The base artboard the design was drawn at. See
  /// [ResponsiveMetrics.designSize].
  ///
  /// Both sides must be positive and finite, as must every profile's
  /// [ResponsiveProfile.designSize]; asserted on build.
  final Size designSize;

  /// See [ResponsiveMetrics.splitScreenMode].
  final bool splitScreenMode;

  /// See [ResponsiveMetrics.minTextAdapt].
  final bool minTextAdapt;

  /// See [ResponsiveMetrics.fontSizeResolver]. Not clamped by any bounds.
  final FontSizeResolver? fontSizeResolver;

  /// See [ResponsiveMetrics.breakpoints].
  final ResponsiveBreakpoints breakpoints;

  /// See [ResponsiveMetrics.scaleBounds]. Defaults to
  /// [ScaleBounds.downOnly].
  final ScaleBounds scaleBounds;

  /// See [ResponsiveMetrics.textScaleBounds]. Defaults to
  /// [ScaleBounds.downOnly].
  final ScaleBounds textScaleBounds;

  /// See [ResponsiveMetrics.profiles] and [ResponsiveProfile].
  final Map<WindowSizeClass, ResponsiveProfile> profiles;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Here rather than in the constructor: a `const` constructor cannot read
    // a Size's sides. Every profile is checked, not just the active one, so
    // a bad tablet artboard fails on the phone it is developed on too.
    assert(
      ResponsiveMetrics.isValidDesignSize(designSize),
      'ResponsiveInit.designSize must be positive and finite on both sides, '
      'got $designSize.',
    );
    assert(() {
      for (final MapEntry(key: windowClass, value: profile)
          in profiles.entries) {
        final size = profile.designSize;
        if (size != null && !ResponsiveMetrics.isValidDesignSize(size)) {
          throw AssertionError(
            'The ResponsiveProfile for $windowClass has designSize $size; '
            'both sides must be positive and finite.',
          );
        }
      }
      return true;
    }());
    return ResponsiveScope(
      metrics: ResponsiveMetrics(
        screenSize: MediaQuery.sizeOf(context),
        designSize: designSize,
        splitScreenMode: splitScreenMode,
        minTextAdapt: minTextAdapt,
        fontSizeResolver: fontSizeResolver,
        breakpoints: breakpoints,
        scaleBounds: scaleBounds,
        textScaleBounds: textScaleBounds,
        profiles: profiles,
      ),
      child: child,
    );
  }
}
