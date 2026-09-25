import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../gen/fonts.gen.dart';
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
class ThemeProvider extends ChangeNotifier
    with WidgetsBindingObserver, DisposeGuard {
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

  /// The theme data for the active [themeMode].
  ///
  /// Takes a [BuildContext] because font sizes are scaled through
  /// `context.sp`, the context-aware extension the package recommends.
  ThemeData currentTheme(BuildContext context) {
    switch (themeMode) {
      case ThemeMode.dark:
        return darkTheme(context);
      case ThemeMode.light:
        return lightTheme(context);
      case ThemeMode.system:
        final brightness =
            SchedulerBinding.instance.platformDispatcher.platformBrightness;
        return brightness == Brightness.dark
            ? darkTheme(context)
            : lightTheme(context);
    }
  }

  /// The light theme data.
  ThemeData lightTheme(BuildContext context) =>
      _themeData(context, ThemeMode.light);

  /// The dark theme data.
  ThemeData darkTheme(BuildContext context) =>
      _themeData(context, ThemeMode.dark);

  /// Builds the ThemeData based on the given theme mode.
  ///
  /// This method selects the appropriate theme system and color scheme based on
  /// the theme mode. It also creates a custom text theme with adjusted font sizes
  /// and applies the theme system's colors to the text theme.
  ThemeData _themeData(BuildContext context, ThemeMode mode) {
    final themeSystem = ThemeSystemExtension.withMode(mode);
    final brightness = mode == ThemeMode.dark
        ? Brightness.dark
        : Brightness.light;
    // Every slot built from the palette, so `colorScheme.*` and
    // `context.colors.*` agree — Material's components read the scheme.
    final colorScheme = themeSystem.toColorScheme(brightness);

    // The type scale's sizes. A Material 3 `ThemeData().textTheme` carries
    // colours only — its sizes are merged in later, when MaterialApp
    // localizes the theme — so scaling it read `null` for every style and
    // text was never scaled at all. Starting from the geometry gives
    // [scaleFont] real numbers (the same M3 sizes MaterialApp would add).
    final geometry = Typography.material2021().englishLike;

    // The typeface ships in this package, one file per weight under a
    // single family (see pubspec.yaml), so a style's fontWeight — including
    // a later `copyWith(fontWeight: FontWeight.bold)` — selects the real
    // face. `google_fonts` named one family per weight instead, which left
    // every such copy rendering regular glyphs emboldened by the engine.
    TextTheme applyFont(TextTheme colors) =>
        geometry.merge(colors).apply(fontFamily: FontFamily.plusJakartaSans);

    final defaultTheme = applyFont(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    );

    /// Scales one font size through the context-aware extension.
    ///
    /// `sp`, so type follows the app's `textScaleBounds`: by default it
    /// shrinks below the design width and never grows past it, and a window
    /// class whose `ResponsiveProfile` opts into growth gets bigger type too.
    /// Null-tolerant so the `TextStyle.fontSize` chain stays readable.
    double? scaleFont(double? size) => size == null ? null : context.sp(size);

    /// Scales the font sizes of the text theme to the device's screen size.
    final textTheme = defaultTheme
        .apply(
          bodyColor: themeSystem.textPrimary,
          displayColor: themeSystem.textPrimary,
          decorationColor: themeSystem.textPrimary,
        )
        .copyWith(
          labelSmall: defaultTheme.labelSmall?.copyWith(
            fontSize: scaleFont(defaultTheme.labelSmall?.fontSize),
          ),
          labelMedium: defaultTheme.labelMedium?.copyWith(
            fontSize: scaleFont(defaultTheme.labelMedium?.fontSize),
          ),
          labelLarge: defaultTheme.labelLarge?.copyWith(
            fontSize: scaleFont(defaultTheme.labelLarge?.fontSize),
          ),
          bodySmall: defaultTheme.bodySmall?.copyWith(
            fontSize: scaleFont(defaultTheme.bodySmall?.fontSize),
          ),
          bodyMedium: defaultTheme.bodyMedium?.copyWith(
            fontSize: scaleFont(defaultTheme.bodyMedium?.fontSize),
          ),
          bodyLarge: defaultTheme.bodyLarge?.copyWith(
            fontSize: scaleFont(defaultTheme.bodyLarge?.fontSize),
          ),
          titleSmall: defaultTheme.titleSmall?.copyWith(
            fontSize: scaleFont(defaultTheme.titleSmall?.fontSize),
          ),
          titleMedium: defaultTheme.titleMedium?.copyWith(
            fontSize: scaleFont(defaultTheme.titleMedium?.fontSize),
          ),
          titleLarge: defaultTheme.titleLarge?.copyWith(
            fontSize: scaleFont(defaultTheme.titleLarge?.fontSize),
          ),
          displaySmall: defaultTheme.displaySmall?.copyWith(
            fontSize: scaleFont(defaultTheme.displaySmall?.fontSize),
          ),
          displayMedium: defaultTheme.displayMedium?.copyWith(
            fontSize: scaleFont(defaultTheme.displayMedium?.fontSize),
          ),
          displayLarge: defaultTheme.displayLarge?.copyWith(
            fontSize: scaleFont(defaultTheme.displayLarge?.fontSize),
          ),
          headlineSmall: defaultTheme.headlineSmall?.copyWith(
            fontSize: scaleFont(defaultTheme.headlineSmall?.fontSize),
          ),
          headlineMedium: defaultTheme.headlineMedium?.copyWith(
            fontSize: scaleFont(defaultTheme.headlineMedium?.fontSize),
          ),
          headlineLarge: defaultTheme.headlineLarge?.copyWith(
            fontSize: scaleFont(defaultTheme.headlineLarge?.fontSize),
          ),
        );

    return ThemeData(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,

      /// The Material colour scheme, built from the palette.
      colorScheme: colorScheme,

      /// The side rail tablets and desktops navigate with (see the
      /// dashboard). Left to Material, its selection indicator takes the
      /// scheme's `secondaryContainer` — the stock aqua of
      /// `ColorScheme.light()`, not this palette — while the phone's
      /// bottom bar selects in the brand colour. Both now agree.
      navigationRailTheme: NavigationRailThemeData(
        indicatorColor: themeSystem.primary.withValues(
          alpha: BaseUiConstants.NAV_RAIL_INDICATOR_ALPHA,
        ),
        selectedIconTheme: IconThemeData(color: themeSystem.primary),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: themeSystem.primary,
        ),
      ),

      /// Tooltips stay in the semantics tree — a screen reader reads an
      /// icon-only button's `tooltip` as its label — but a long press or tap
      /// no longer pops the bubble up on touch screens. A mouse hover still
      /// shows it (trigger modes do not apply to mice). Delete this to get
      /// Material's default long-press tooltip back.
      tooltipTheme: const TooltipThemeData(
        triggerMode: TooltipTriggerMode.manual,
      ),

      /// Sets the page transitions theme for the theme.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      /// Extends the theme with the selected theme system.
      extensions: [themeSystem],

      /// Sets the app bar theme for the theme.
      appBarTheme: AppBarTheme(
        /// Sets the background color of the app bar.
        backgroundColor: themeSystem.surface,

        /// Sets the elevation of the app bar when scrolled.
        scrolledUnderElevation:
            BaseUiConstants.APP_BAR_SCROLLED_UNDER_ELEVATION,

        /// Sets the title text style of the app bar.
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: scaleFont(BaseUiConstants.APP_BAR_TITLE_FONT_SIZE),
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

  /// The brightness the app actually renders in: [themeMode], with
  /// [ThemeMode.system] resolved against the platform's current brightness.
  Brightness get effectiveBrightness => switch (themeMode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      SchedulerBinding.instance.platformDispatcher.platformBrightness,
  };

  /// Sets the system UI overlay style based on the current theme mode.
  ///
  /// Resolves [ThemeMode.system] to the platform brightness **first** and
  /// derives both the bar colour and the icon brightness from that one value.
  /// Picking the palette separately — the light one for `system`, whatever
  /// the OS said — painted the navigation bar near-white under white icons
  /// whenever the OS was dark. [didChangePlatformBrightness] calls this
  /// again, so the bars follow the OS while [ThemeMode.system] is active.
  void setSystemTheme() {
    systemUiOverlayStyle = overlayStyleFor(effectiveBrightness);
  }

  /// The status/navigation bar styling for an app rendered in [brightness]:
  /// transparent status bar, navigation bar in that palette's background,
  /// and icons contrasting with it.
  static SystemUiOverlayStyle overlayStyleFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final themeSystem = ThemeSystemExtension.withMode(
      isDark ? ThemeMode.dark : ThemeMode.light,
    );
    // Icons contrast with the bars: light icons on a dark app, and vice versa.
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;
    final base = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return base.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      // iOS: the brightness of the status bar *background*, the opposite of
      // the icons.
      statusBarBrightness: brightness,
      systemNavigationBarColor: themeSystem.background,
      systemNavigationBarIconBrightness: iconBrightness,
    );
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
