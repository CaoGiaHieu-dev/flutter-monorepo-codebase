import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppRadius {
  AppRadius._();

  static double get xs => 2.r;
  static double get sm => 4.r;
  static double get md => 8.r;
  static double get lg => 12.r;
  static double get xl => 16.r;
  static double get xxl => 24.r;
  static double get circular => 999.r;

  static BorderRadius get xsRadius => BorderRadius.all(Radius.circular(xs));
  static BorderRadius get smRadius => BorderRadius.all(Radius.circular(sm));
  static BorderRadius get mdRadius => BorderRadius.all(Radius.circular(md));
  static BorderRadius get lgRadius => BorderRadius.all(Radius.circular(lg));
  static BorderRadius get xlRadius => BorderRadius.all(Radius.circular(xl));
  static BorderRadius get xxlRadius => BorderRadius.all(Radius.circular(xxl));
  static BorderRadius get circularRadius =>
      BorderRadius.all(Radius.circular(circular));
}
