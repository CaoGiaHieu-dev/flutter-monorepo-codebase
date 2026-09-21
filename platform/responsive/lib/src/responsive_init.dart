import 'package:flutter/widgets.dart';

import 'responsive_metrics.dart';
import 'responsive_scope.dart';
import 'utils/responsive_constants.dart';

/// Installs responsive scaling for the subtree. Mount it once, above
/// `MaterialApp`.
///
/// ```dart
/// ResponsiveInit(
///   designSize: const Size(360, 690),
///   minTextAdapt: true,
///   splitScreenMode: true,
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
    super.key,
  });

  /// The artboard the design was drawn at.
  final Size designSize;

  /// See [ResponsiveMetrics.splitScreenMode].
  final bool splitScreenMode;

  /// See [ResponsiveMetrics.minTextAdapt].
  final bool minTextAdapt;

  /// See [ResponsiveMetrics.fontSizeResolver].
  final FontSizeResolver? fontSizeResolver;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ResponsiveScope(
      metrics: ResponsiveMetrics(
        screenSize: MediaQuery.sizeOf(context),
        designSize: designSize,
        splitScreenMode: splitScreenMode,
        minTextAdapt: minTextAdapt,
        fontSizeResolver: fontSizeResolver,
      ),
      child: child,
    );
  }
}
