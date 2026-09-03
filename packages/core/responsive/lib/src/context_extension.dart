import 'package:flutter/widgets.dart';

import 'responsive_metrics.dart';
import 'responsive_scope.dart';

/// Scaling entry points, all routed through [BuildContext].
///
/// There is intentionally no `16.w`-style extension on `num`. A number has no
/// context, so such an extension can only read a global — and a widget that
/// reads a global never learns that the metrics changed. Requiring the context
/// makes the correct thing the only thing you can write.
///
/// Inside an `async` method, read the value *before* the first `await` and
/// pass the result on; do not hold the context across the gap.
extension ResponsiveContext on BuildContext {
  /// The metrics in scope. Throws if no `ResponsiveInit` is above this context.
  ResponsiveMetrics get responsive => ResponsiveScope.of(this);

  /// Scales a width. Also correct for anything that must stay square.
  double w(num value) => responsive.width(value);

  /// Scales a height — vertical gaps, row heights.
  double h(num value) => responsive.height(value);

  /// Scales by the smaller axis: radii, borders, strokes.
  double r(num value) => responsive.radius(value);

  /// Scales a font size.
  double sp(num value) => responsive.sp(value);

  /// [sp] capped at the design value — text shrinks but never grows.
  double spMin(num value) => responsive.spMin(value);

  /// Scales by both axes at once.
  double dg(num value) => responsive.diagonal(value);

  /// Scales by the larger axis.
  double dm(num value) => responsive.diameter(value);

  /// Scaled [EdgeInsets].
  ///
  /// Each axis is scaled by the axis it belongs to — horizontal padding by
  /// width, vertical by height — so padding keeps its proportions instead of
  /// tracking a single dimension. `all` therefore also uses [w], which is what
  /// makes it a drop-in for `EdgeInsets.all(context.w(x))`.
  EdgeInsets edgeInsets({
    num? all,
    num? horizontal,
    num? vertical,
    num? left,
    num? top,
    num? right,
    num? bottom,
  }) {
    if (all != null) {
      final v = w(all);
      return EdgeInsets.all(v);
    }
    return EdgeInsets.only(
      left: w(left ?? horizontal ?? 0),
      right: w(right ?? horizontal ?? 0),
      top: h(top ?? vertical ?? 0),
      bottom: h(bottom ?? vertical ?? 0),
    );
  }

  /// Scaled [BorderRadius]. Radii use the smaller axis — see [r].
  BorderRadius borderRadius({
    num? all,
    num? topLeft,
    num? topRight,
    num? bottomLeft,
    num? bottomRight,
  }) {
    if (all != null) return BorderRadius.circular(r(all));
    return BorderRadius.only(
      topLeft: Radius.circular(r(topLeft ?? 0)),
      topRight: Radius.circular(r(topRight ?? 0)),
      bottomLeft: Radius.circular(r(bottomLeft ?? 0)),
      bottomRight: Radius.circular(r(bottomRight ?? 0)),
    );
  }

  /// A vertical gap of [value] design pixels.
  SizedBox verticalSpace(num value) => SizedBox(height: h(value));

  /// A horizontal gap of [value] design pixels.
  SizedBox horizontalSpace(num value) => SizedBox(width: w(value));
}
