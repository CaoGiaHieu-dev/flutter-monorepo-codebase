import 'package:flutter/widgets.dart';

import 'responsive_metrics.dart';

/// Publishes [ResponsiveMetrics] to the subtree.
///
/// Reading it through [of] registers an `InheritedWidget` dependency, so a
/// widget that scales a value rebuilds when the metrics change — and one that
/// does not, does not. That targeting is the whole point: there is no global
/// instance to read from, so a stale value is not expressible.
class ResponsiveScope extends InheritedWidget {
  const ResponsiveScope({
    required this.metrics,
    required super.child,
    super.key,
  });

  final ResponsiveMetrics metrics;

  /// The metrics for [context], or `null` when no [ResponsiveInit] is above it.
  static ResponsiveMetrics? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResponsiveScope>()?.metrics;

  /// The metrics for [context].
  ///
  /// Throws when no [ResponsiveInit] is above [context]. That is deliberate:
  /// silently falling back to an unscaled number would ship a layout that is
  /// wrong on every device except the design artboard, and nothing would
  /// point at the cause.
  static ResponsiveMetrics of(BuildContext context) {
    final metrics = maybeOf(context);
    assert(
      metrics != null,
      'No ResponsiveInit found above this context.\n'
      'Wrap the app (or the widget under test) in ResponsiveInit before using '
      'context.w/h/r/sp. In tests: ResponsiveInit(designSize: ..., child: ...).',
    );
    return metrics!;
  }

  @override
  bool updateShouldNotify(ResponsiveScope oldWidget) =>
      metrics != oldWidget.metrics;
}
