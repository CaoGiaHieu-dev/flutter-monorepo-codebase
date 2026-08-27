import 'package:flutter/material.dart';
import 'package:flutter_screenutil_plus/flutter_screenutil_plus.dart';

/// Responsive corner-radius scale.
///
/// Mirrors [AppSpacing]: every accessor takes a [BuildContext] and resolves
/// through `context.r`. See `AppSpacing` for the rationale.
///
/// Use [rawXs] and friends where no context is available.
class AppRadius {
  AppRadius._();

  static double xs(BuildContext context) => context.r(rawXs);
  static double sm(BuildContext context) => context.r(rawSm);
  static double md(BuildContext context) => context.r(rawMd);
  static double lg(BuildContext context) => context.r(rawLg);
  static double xl(BuildContext context) => context.r(rawXl);
  static double xxl(BuildContext context) => context.r(rawXxl);
  static double circular(BuildContext context) => context.r(rawCircular);

  static BorderRadius xsRadius(BuildContext context) =>
      BorderRadius.all(Radius.circular(xs(context)));
  static BorderRadius smRadius(BuildContext context) =>
      BorderRadius.all(Radius.circular(sm(context)));
  static BorderRadius mdRadius(BuildContext context) =>
      BorderRadius.all(Radius.circular(md(context)));
  static BorderRadius lgRadius(BuildContext context) =>
      BorderRadius.all(Radius.circular(lg(context)));
  static BorderRadius xlRadius(BuildContext context) =>
      BorderRadius.all(Radius.circular(xl(context)));
  static BorderRadius xxlRadius(BuildContext context) =>
      BorderRadius.all(Radius.circular(xxl(context)));
  static BorderRadius circularRadius(BuildContext context) =>
      BorderRadius.all(Radius.circular(circular(context)));

  // Design values, unscaled. Single source of the numbers above.
  static const double rawXs = 2;
  static const double rawSm = 4;
  static const double rawMd = 8;
  static const double rawLg = 12;
  static const double rawXl = 16;
  static const double rawXxl = 24;
  static const double rawCircular = 999;
}
