import 'package:flutter/material.dart';

import '../gen/language/app_localizations.dart';
import '../theme/theme_system_extensions.dart';

/// Extension on [BuildContext] to provide easy access to theme and media query data
extension ContextExtension on BuildContext {
  /// Get the current color scheme
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Localizations
  AppLocalizations get _localizations => AppLocalizations.of(this)!;
  AppLocalizations get l10n => _localizations;
  Locale get locale => Localizations.localeOf(this);

  /// Custom theme extension with additional theme properties
  ThemeSystemExtension get themeExtension =>
      Theme.of(this).extension<ThemeSystemExtension>()!;

  /// Alias for themeExtension to access colors easily (e.g. context.colors.textPrimary)
  ThemeSystemExtension get colors => themeExtension;

  // Color getters for easy access
  Color get primary => colorScheme.primary;
  Color get primaryContainer => colorScheme.primaryContainer;
  Color get secondary => colorScheme.secondary;
  Color get tertiary => colorScheme.tertiary;
  Color get secondaryContainer => colorScheme.secondaryContainer;
  Color get surface => colorScheme.surface;
  Color get error => colorScheme.error;
  Color get onPrimary => colorScheme.onPrimary;
  Color get onSecondary => colorScheme.onSecondary;
  Color get onSurface => colorScheme.onSurface;
  Color get onError => colorScheme.onError;
  Color get dividerColor => Theme.of(this).dividerColor;
  Color get canvasColor => Theme.of(this).canvasColor;

  // Text theme getters
  TextTheme get textTheme => Theme.of(this).textTheme;
  TextStyle get displayLargeStyle => textTheme.displayLarge!;
  TextStyle get displayMediumStyle => textTheme.displayMedium!;
  TextStyle get displaySmallStyle => textTheme.displaySmall!;
  TextStyle get headlineLargeStyle => textTheme.headlineLarge!;
  TextStyle get headlineMediumStyle => textTheme.headlineMedium!;
  TextStyle get headlineSmallStyle => textTheme.headlineSmall!;
  TextStyle get titleLargeStyle => textTheme.titleLarge!;
  TextStyle get titleMediumStyle => textTheme.titleMedium!;
  TextStyle get titleSmallStyle => textTheme.titleSmall!;
  TextStyle get labelLargeStyle => textTheme.labelLarge!;
  TextStyle get labelMediumStyle => textTheme.labelMedium!;
  TextStyle get labelSmallStyle => textTheme.labelSmall!;
  TextStyle get bodyLargeStyle => textTheme.bodyLarge!;
  TextStyle get bodyMediumStyle => textTheme.bodyMedium!;
  TextStyle get bodySmallStyle => textTheme.bodySmall!;

  // Media query getters
  Size get mediaSize => MediaQuery.sizeOf(this);
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  double get width => mediaSize.width;
  double get height => mediaSize.height;
  double get scale => MediaQuery.devicePixelRatioOf(this);
  Orientation get orientation => MediaQuery.orientationOf(this);
  EdgeInsets get padding => MediaQuery.paddingOf(this);

  // Navigation getter
  NavigatorState? get navigator => Navigator.of(this);

  /// Show a snackbar with the given message
  void showSnackBar(String message, {Duration? duration}) {
    hideSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Hide the current snackbar
  void hideSnackBar() {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
  }

  /// Check if the device is in dark mode
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Check if the device is in portrait mode
  bool get isPortrait => orientation == Orientation.portrait;

  /// Check if the device is in landscape mode
  bool get isLandscape => orientation == Orientation.landscape;
}
