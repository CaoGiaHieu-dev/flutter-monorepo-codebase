import 'package:material_ui/material_ui.dart';

/// The type scale, read from the active theme.
///
/// `ThemeProvider` sizes every style through `context.sp` and colours it from
/// the palette, so these are ready to use; adjust one with `copyWith`.
class AppTextStyles {
  AppTextStyles._();

  static TextTheme _textTheme(BuildContext context) =>
      Theme.of(context).textTheme;

  static TextStyle titleLargeStyle(BuildContext context) =>
      _textTheme(context).titleLarge!;
  static TextStyle titleMediumStyle(BuildContext context) =>
      _textTheme(context).titleMedium!;
  static TextStyle titleSmallStyle(BuildContext context) =>
      _textTheme(context).titleSmall!;
  static TextStyle bodyLargeStyle(BuildContext context) =>
      _textTheme(context).bodyLarge!;
  static TextStyle bodyMediumStyle(BuildContext context) =>
      _textTheme(context).bodyMedium!;
  static TextStyle bodySmallStyle(BuildContext context) =>
      _textTheme(context).bodySmall!;
  static TextStyle labelLargeStyle(BuildContext context) =>
      _textTheme(context).labelLarge!;
  static TextStyle labelMediumStyle(BuildContext context) =>
      _textTheme(context).labelMedium!;
  static TextStyle labelSmallStyle(BuildContext context) =>
      _textTheme(context).labelSmall!;
  static TextStyle displayLargeStyle(BuildContext context) =>
      _textTheme(context).displayLarge!;
  static TextStyle displayMediumStyle(BuildContext context) =>
      _textTheme(context).displayMedium!;
  static TextStyle displaySmallStyle(BuildContext context) =>
      _textTheme(context).displaySmall!;
  static TextStyle headlineLargeStyle(BuildContext context) =>
      _textTheme(context).headlineLarge!;
  static TextStyle headlineMediumStyle(BuildContext context) =>
      _textTheme(context).headlineMedium!;
  static TextStyle headlineSmallStyle(BuildContext context) =>
      _textTheme(context).headlineSmall!;
}
