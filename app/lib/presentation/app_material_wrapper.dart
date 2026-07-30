import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../app.dart';

/// A wrapper around [MaterialApp] and [MaterialApp.router] to avoid code duplication
/// of common configurations like title, debugShowCheckedModeBanner, and showPerformanceOverlay.
///
/// If [useGlobalProviders] is enabled, it automatically injects global providers
/// (AppProvider, ThemeProvider, AuthProvider, DeeplinkProvider) and listens to
/// theme/language changes to update the MaterialApp context dynamically.
class AppMaterialWrapper extends StatelessWidget {
  /// Creates a standard [MaterialApp] wrapper (typically used for Splash screen).
  const AppMaterialWrapper({
    super.key,
    required this.home,
    this.themeMode,
    this.theme,
    this.darkTheme,
    this.locale,
    this.supportedLocales,
    this.builder,
  }) : isRouter = false,
       routeInformationProvider = null,
       routeInformationParser = null,
       routerDelegate = null,
       backButtonDispatcher = null;

  /// Creates a [MaterialApp.router] wrapper (typically used for RootApp).
  const AppMaterialWrapper.router({
    super.key,
    this.themeMode,
    this.theme,
    this.darkTheme,
    this.locale,
    this.supportedLocales,
    this.builder,
    required this.routeInformationProvider,
    required this.routeInformationParser,
    required this.routerDelegate,
    required this.backButtonDispatcher,
  }) : isRouter = true,
       home = null;

  /// Whether this wrapper uses [MaterialApp.router] or a standard [MaterialApp].
  final bool isRouter;

  /// The widget to be displayed as the home screen (for standard [MaterialApp]).
  final Widget? home;

  /// The theme mode preference.
  final ThemeMode? themeMode;

  /// The light theme.
  final ThemeData? theme;

  /// The dark theme.
  final ThemeData? darkTheme;

  /// The locale preference.
  final Locale? locale;

  /// The supported locales.
  final Iterable<Locale>? supportedLocales;

  /// The builder function for wrapping the navigator widget.
  final Widget Function(BuildContext, Widget?)? builder;

  // Router properties
  final RouteInformationProvider? routeInformationProvider;
  final RouteInformationParser<Object>? routeInformationParser;
  final RouterDelegate<Object>? routerDelegate;
  final BackButtonDispatcher? backButtonDispatcher;

  @override
  Widget build(BuildContext context) {
    // Set up global dependency providers and listen to theme/language changes.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: getIt<ThemeProvider>()),
        ChangeNotifierProvider.value(value: getIt<LanguageProvider>()),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, themeProvider, languageProvider, _) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: themeProvider.systemUiOverlayStyle,
            child: TooltipVisibility(
              visible: false,
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: getIt<AppProvider>()),
                  ChangeNotifierProvider.value(value: getIt<AuthProvider>()),
                  ChangeNotifierProvider.value(
                    value: getIt<DeeplinkProvider>(),
                  ),
                ],
                child: _buildMaterialApp(
                  themeMode: themeProvider.themeMode,
                  theme: themeProvider.currentTheme,
                  darkTheme: themeProvider.darkTheme,
                  locale: languageProvider.locale,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMaterialApp({
    ThemeMode? themeMode,
    ThemeData? theme,
    ThemeData? darkTheme,
    Locale? locale,
  }) {
    final title = AppConfig.title;
    const debugShowCheckedModeBanner = false;
    const showPerformanceOverlay = false;
    // Localization configuration
    final delegates = [
      ...getIt.getAll<IFeatureLocalization>().map((e) => e.delegate),
      ...AppLocalizations.localizationsDelegates,
    ];

    if (isRouter) {
      return MaterialApp.router(
        title: title,
        debugShowCheckedModeBanner: debugShowCheckedModeBanner,
        showPerformanceOverlay: showPerformanceOverlay,
        themeMode: themeMode ?? this.themeMode,
        theme: theme ?? this.theme,
        darkTheme: darkTheme ?? this.darkTheme,
        locale: locale ?? this.locale,
        localizationsDelegates: delegates,
        supportedLocales: supportedLocales ?? AppLocalizations.supportedLocales,
        builder: builder,
        routeInformationProvider: routeInformationProvider,
        routeInformationParser: routeInformationParser,
        routerDelegate: routerDelegate,
        backButtonDispatcher: backButtonDispatcher,
        localeResolutionCallback: (deviceLocale, supportedLocales) {
          // Loop through supported locales to find a match
          for (var supportedLocale in supportedLocales) {
            if (supportedLocale.languageCode == deviceLocale?.languageCode) {
              return supportedLocale;
            }
          }
          // Force English (or your first supported locale) if no match is found
          return supportedLocales.first;
        },
      );
    }

    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      showPerformanceOverlay: showPerformanceOverlay,
      home: home,
      themeMode: themeMode ?? this.themeMode,
      theme: theme ?? this.theme,
      darkTheme: darkTheme ?? this.darkTheme,
      locale: locale ?? this.locale,
      localizationsDelegates: delegates,
      supportedLocales: supportedLocales ?? AppLocalizations.supportedLocales,
      builder: builder,
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        // Loop through supported locales to find a match
        for (var supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == deviceLocale?.languageCode) {
            return supportedLocale;
          }
        }
        // Force English (or your first supported locale) if no match is found
        return supportedLocales.first;
      },
    );
  }
}
