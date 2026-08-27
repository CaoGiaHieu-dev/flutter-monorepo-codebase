import 'package:core_di/core_di.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:injectable/injectable.dart';

import '../utils/base_ui_constants.dart';
import 'theme_system_extensions.dart';

/// ThemeProvider class manages the app's theme and system UI overlay style.
///
/// This class is responsible for:
/// - Providing access to the current theme mode.
/// - Setting the theme mode based on user preference.
/// - Managing the system UI overlay style based on the theme mode.
/// - Building the light and dark themes.
/// - Reacting to OS-level Dark/Light changes while [ThemeMode.system] is active.
@lazySingleton
class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  final IThemeStorage _themeStorage;

  /// Constructor for ThemeProvider.
  ThemeProvider(this._themeStorage);

  /// Current theme mode.
  ///
  /// Defaults to [ThemeMode.system]; [initialize] immediately replaces this
  /// with the persisted preference before the provider is handed to callers.
  ThemeMode _themeMode = ThemeMode.system;

  /// Getter for the current theme mode.
  ThemeMode get themeMode => _themeMode;

  /// Setter for the theme mode.
  ///
  /// Updates the theme mode and sets the system theme.
  /// Also persists the theme mode to secure storage.
  set themeMode(ThemeMode value) {
    if (_themeMode == value) return;
    _themeMode = value;

    setSystemTheme();
    _themeStorage.saveThemeMode(value);

    notifyListeners();
  }

  /// Current system UI overlay style.
  SystemUiOverlayStyle _systemUiOverlayStyle = SystemUiOverlayStyle.dark;

  /// Getter for the system UI overlay style.
  SystemUiOverlayStyle get systemUiOverlayStyle => _systemUiOverlayStyle;

  /// Setter for the system UI overlay style.
  ///
  /// Updates the system UI overlay style and notifies listeners.
  set systemUiOverlayStyle(SystemUiOverlayStyle value) {
    if (_systemUiOverlayStyle == value) return;
    _systemUiOverlayStyle = value;
    notifyListeners();
  }

  /// Getter for the current theme data based on the theme mode.
  ThemeData get currentTheme {
    switch (themeMode) {
      case ThemeMode.dark:
        return darkTheme;
      case ThemeMode.light:
        return lightTheme;
      case ThemeMode.system:
        final brightness =
            SchedulerBinding.instance.platformDispatcher.platformBrightness;
        return brightness == Brightness.dark ? darkTheme : lightTheme;
    }
  }

  /// Getter for the light theme data.
  ThemeData get lightTheme => _themeData(ThemeMode.light);

  /// Getter for the dark theme data.
  ThemeData get darkTheme => _themeData(ThemeMode.dark);

  /// Builds the ThemeData based on the given theme mode.
  ///
  /// This method selects the appropriate theme system and color scheme based on
  /// the theme mode. It also creates a custom text theme with adjusted font sizes
  /// and applies the theme system's colors to the text theme.
  ThemeData _themeData(ThemeMode mode) {
    final themeSystem = ThemeSystemExtension.withMode(mode);
    final colorScheme = switch (mode) {
      ThemeMode.dark => const ColorScheme.dark(),
      ThemeMode.light => const ColorScheme.light(),
      ThemeMode.system => ColorScheme.fromSwatch(),
    };

    final defaultTheme = switch (mode) {
      ThemeMode.dark => GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme,
      ),
      ThemeMode.light => GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme,
      ),
      ThemeMode.system => GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.from(colorScheme: colorScheme).textTheme,
      ),
    };

    /// Scales the font sizes of the text theme.
    ///
    /// This method adjusts the font sizes of the text theme based on the device's
    /// screen size.
    final textTheme = defaultTheme
        .apply(
          bodyColor: themeSystem.textPrimary,
          displayColor: themeSystem.textPrimary,
          decorationColor: themeSystem.textPrimary,
        )
        .copyWith(
          labelSmall: defaultTheme.labelSmall?.copyWith(
            fontSize: defaultTheme.labelSmall?.fontSize?.sp,
          ),
          labelMedium: defaultTheme.labelMedium?.copyWith(
            fontSize: defaultTheme.labelMedium?.fontSize?.sp,
          ),
          labelLarge: defaultTheme.labelLarge?.copyWith(
            fontSize: defaultTheme.labelLarge?.fontSize?.sp,
          ),
          bodySmall: defaultTheme.bodySmall?.copyWith(
            fontSize: defaultTheme.bodySmall?.fontSize?.sp,
          ),
          bodyMedium: defaultTheme.bodyMedium?.copyWith(
            fontSize: defaultTheme.bodyMedium?.fontSize?.sp,
          ),
          bodyLarge: defaultTheme.bodyLarge?.copyWith(
            fontSize: defaultTheme.bodyLarge?.fontSize?.sp,
          ),
          titleSmall: defaultTheme.titleSmall?.copyWith(
            fontSize: defaultTheme.titleSmall?.fontSize?.sp,
          ),
          titleMedium: defaultTheme.titleMedium?.copyWith(
            fontSize: defaultTheme.titleMedium?.fontSize?.sp,
          ),
          titleLarge: defaultTheme.titleLarge?.copyWith(
            fontSize: defaultTheme.titleLarge?.fontSize?.sp,
          ),
          displaySmall: defaultTheme.displaySmall?.copyWith(
            fontSize: defaultTheme.displaySmall?.fontSize?.sp,
          ),
          displayMedium: defaultTheme.displayMedium?.copyWith(
            fontSize: defaultTheme.displayMedium?.fontSize?.sp,
          ),
          displayLarge: defaultTheme.displayLarge?.copyWith(
            fontSize: defaultTheme.displayLarge?.fontSize?.sp,
          ),
          headlineSmall: defaultTheme.headlineSmall?.copyWith(
            fontSize: defaultTheme.headlineSmall?.fontSize?.sp,
          ),
          headlineMedium: defaultTheme.headlineMedium?.copyWith(
            fontSize: defaultTheme.headlineMedium?.fontSize?.sp,
          ),
          headlineLarge: defaultTheme.headlineLarge?.copyWith(
            fontSize: defaultTheme.headlineLarge?.fontSize?.sp,
          ),
        );

    return ThemeData(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,

      /// Sets the color scheme for the theme.
      colorScheme: colorScheme.copyWith(
        primary: themeSystem.primary,
        surface: themeSystem.surface,
      ),

      /// Sets the page transitions theme for the theme.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      /// Extends the theme with the selected theme system.
      extensions: [ThemeSystemExtension.withMode(mode)],

      /// Sets the app bar theme for the theme.
      appBarTheme: AppBarTheme(
        /// Sets the background color of the app bar.
        backgroundColor: themeSystem.surface,

        /// Sets the elevation of the app bar when scrolled.
        scrolledUnderElevation:
            BaseUiConstants.APP_BAR_SCROLLED_UNDER_ELEVATION,

        /// Sets the title text style of the app bar.
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: BaseUiConstants.APP_BAR_TITLE_FONT_SIZE.sp,
          fontWeight: FontWeight.bold,
        ),

        /// Centers the app bar title.
        centerTitle: true,
      ),

      /// Sets the primary color for the theme.
      primaryColor: themeSystem.primary,

      /// Sets the brightness for the theme.
      brightness: colorScheme.brightness,

      /// Sets the background color for the scaffold.
      scaffoldBackgroundColor: themeSystem.background,

      /// Sets the Cupertino override theme for the theme.
      cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
        textTheme: CupertinoTextThemeData(
          /// Sets the text style for the date picker.
          dateTimePickerTextStyle: textTheme.titleMedium,

          /// Sets the text style for the picker.
          pickerTextStyle: textTheme.bodyMedium,
        ),
      ),

      /// Sets the divider color for the theme.
      dividerColor: themeSystem.divider,

      /// Sets the text theme for the theme.
      textTheme: textTheme,
    );
  }

  /// Guards against registering the platform observer twice if [initialize]
  /// is ever invoked more than once (e.g. a DI reset in tests).
  bool _isObservingPlatform = false;

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    // Load theme mode.
    _themeMode = _themeStorage.getThemeMode();
    setSystemTheme();

    // ThemeMode.system resolves against the OS brightness, which can change
    // while the app is running. Without this observer the app would keep
    // rendering the brightness captured at the last rebuild.
    if (!_isObservingPlatform) {
      WidgetsBinding.instance.addObserver(this);
      _isObservingPlatform = true;
    }
  }

  /// Called by the framework when the OS switches between Light and Dark.
  ///
  /// Only [ThemeMode.system] derives its appearance from the platform, so an
  /// explicit light/dark choice is left untouched — no wasted rebuild.
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (_themeMode != ThemeMode.system) return;

    // Refresh the status/navigation bar styling for the new brightness…
    setSystemTheme();
    // …and rebuild consumers, because `currentTheme` now resolves differently.
    notifyListeners();
  }

  /// Detaches the platform-brightness observer and releases the notifier.
  ///
  /// Marked `@disposeMethod` so GetIt calls it when the container is reset —
  /// without it a `resetDependencies()` in tests would leave every previous
  /// instance registered as a [WidgetsBindingObserver], accumulating across
  /// resets. In a running app this never fires: the singleton lives for the
  /// whole process.
  @disposeMethod
  @override
  void dispose() {
    if (_isObservingPlatform) {
      WidgetsBinding.instance.removeObserver(this);
      _isObservingPlatform = false;
    }
    super.dispose();
  }

  /// Sets the system UI overlay style based on the current theme mode.
  ///
  /// This method adjusts the system UI overlay style (status bar and navigation
  /// bar colors) based on the current theme mode.
  void setSystemTheme() {
    final themeSystem = ThemeSystemExtension.withMode(
      themeMode == ThemeMode.system ? ThemeMode.light : themeMode,
    );

    systemUiOverlayStyle = switch (themeMode) {
      ThemeMode.system =>
        SchedulerBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemNavigationBarColor: themeSystem.background,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: themeSystem.background,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
      ThemeMode.light => SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: themeSystem.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      ThemeMode.dark => SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: themeSystem.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    };
  }

  void toggleTheme() {
    switch (themeMode) {
      case ThemeMode.system:
        themeMode = ThemeMode.light;
        break;
      case ThemeMode.light:
        themeMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        themeMode = ThemeMode.system;
        break;
    }
  }
}
