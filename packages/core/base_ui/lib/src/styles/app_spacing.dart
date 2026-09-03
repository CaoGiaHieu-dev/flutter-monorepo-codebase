import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';

/// Responsive spacing scale.
///
/// Every accessor takes a [BuildContext] and resolves through `core_responsive`
/// (`context.w` / `context.h`), which scopes rebuilds to the widgets that
/// actually read a value. Taking a context also lines this up with
/// `AppTextStyles`, which has always required one.
///
/// Use [rawXxs] and friends when there is no context to scale against —
/// canvas painting or tests.
class AppSpacing {
  AppSpacing._();

  // Width-proportional spacing — the default for padding and margins, so a
  // layout keeps its aspect ratio across screen widths.
  static double xxs(BuildContext context) => context.w(rawXxs);
  static double xs(BuildContext context) => context.w(rawXs);
  static double sm(BuildContext context) => context.w(rawSm);
  static double md(BuildContext context) => context.w(rawMd);
  static double lg(BuildContext context) => context.w(rawLg);
  static double xl(BuildContext context) => context.w(rawXl);
  static double xxl(BuildContext context) => context.w(rawXxl);
  static double xxxl(BuildContext context) => context.w(rawXxxl);
  static double huge(BuildContext context) => context.w(rawHuge);

  // Height-proportional spacing — for vertical gaps and fixed heights.
  static double xxsH(BuildContext context) => context.h(rawXxs);
  static double xsH(BuildContext context) => context.h(rawXs);
  static double smH(BuildContext context) => context.h(rawSm);
  static double mdH(BuildContext context) => context.h(rawMd);
  static double lgH(BuildContext context) => context.h(rawLg);
  static double xlH(BuildContext context) => context.h(rawXl);
  static double xxlH(BuildContext context) => context.h(rawXxl);
  static double xxxlH(BuildContext context) => context.h(rawXxxl);
  static double hugeH(BuildContext context) => context.h(rawHuge);

  // Design values, unscaled. These are the single source of the numbers above.
  static const double rawXxs = 2;
  static const double rawXs = 4;
  static const double rawSm = 8;
  static const double rawMd = 12;
  static const double rawLg = 16;
  static const double rawXl = 24;
  static const double rawXxl = 32;
  static const double rawXxxl = 48;
  static const double rawHuge = 64;
}
