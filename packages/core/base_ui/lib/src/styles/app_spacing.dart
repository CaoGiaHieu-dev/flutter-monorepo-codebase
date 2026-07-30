import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppSpacing {
  AppSpacing._();

  // Proportional responsive spacing (based on width .w - standard for paddings/margins to maintain aspect ratio)
  static double get xxs => 2.w;
  static double get xs => 4.w;
  static double get sm => 8.w;
  static double get md => 12.w;
  static double get lg => 16.w;
  static double get xl => 24.w;
  static double get xxl => 32.w;
  static double get xxxl => 48.w;
  static double get huge => 64.w;

  // Height-based responsive spacing (based on height .h - useful for vertical gaps / heights)
  static double get xxsH => 2.h;
  static double get xsH => 4.h;
  static double get smH => 8.h;
  static double get mdH => 12.h;
  static double get lgH => 16.h;
  static double get xlH => 24.h;
  static double get xxlH => 32.h;
  static double get xxxlH => 48.h;
  static double get hugeH => 64.h;

  // Raw spacing values (for non-responsive contexts, canvas, or test environments)
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
