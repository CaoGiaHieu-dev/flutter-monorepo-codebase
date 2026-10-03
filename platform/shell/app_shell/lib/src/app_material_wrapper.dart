import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

import 'provider/deeplink_provider.dart';

/// A wrapper around [MaterialApp] and [MaterialApp.router] to avoid code duplication
/// of common configurations like title, debugShowCheckedModeBanner, and showPerformanceOverlay.
///
/// If [useGlobalProviders] is enabled, it automatically injects the app-shell
/// providers (ThemeProvider, LanguageProvider, DeeplinkProvider)
/// and listens to theme/language changes to update the MaterialApp context
/// dynamically.
///
/// Feature-owned controllers are *not* named here. Each feature contributes its
/// own [IAppTreeWrapper], collected with `getAllOrEmpty`, so this file imports
/// no feature package and a build missing any of them still compiles.
class AppMaterialWrapper extends StatelessWidget {
  /// Creates a standard [MaterialApp] wrapper (typically used for Splash screen).
  const AppMaterialWrapper({
    super.key,
    required this.home,
    this.builder,
    this.display = const DisplayProfile(),
  }) : isRouter = false,
       routeInformationProvider = null,
       routeInformationParser = null,
       routerDelegate = null,
       backButtonDispatcher = null;

  /// Creates a [MaterialApp.router] wrapper (typically used for RootApp).
  const AppMaterialWrapper.router({
    super.key,
    this.builder,
    required this.routeInformationProvider,
    required this.routeInformationParser,
    required this.routerDelegate,
    required this.backButtonDispatcher,
    this.display = const DisplayProfile(),
  }) : isRouter = true,
       home = null;

  /// Whether this wrapper uses [MaterialApp.router] or a standard [MaterialApp].
  final bool isRouter;

  /// The app's display settings; [DisplayProfile.textScaleMax] is the OS
  /// font-size cap.
  final DisplayProfile display;

  /// The widget to be displayed as the home screen (for standard [MaterialApp]).
  final Widget? home;

  /// The builder function for wrapping the navigator widget.
  ///
  /// Whatever it returns is wrapped in the app's text-scale cap — see
  /// [_textScaleBuilder].
  final Widget Function(BuildContext, Widget?)? builder;

  /// Honours the user's OS font size up to [DisplayProfile.textScaleMax]
  /// (200 % unless the app allows more), around [builder]'s output — so the
  /// splash, every page and every overlay the builder installs (toasts,
  /// dialogs) share one cap.
  ///
  /// 200 % is the "resize text up to 200%" of WCAG 2.2 SC 1.4.4 and the top of
  /// Android 14's font-size slider; iOS accessibility sizes go past 3x, where
  /// a phone screen holds a handful of words per line. Below the cap the
  /// user's setting passes through untouched — non-linear scalers included —
  /// and nothing clamps the lower end, so a smaller-than-default setting is
  /// respected too.
  ///
  /// It does not compound with `core_responsive`: `context.sp` sizes a
  /// `TextStyle` for the window and never reads the text scaler, which
  /// `Text` applies on top, once, when it lays out.
  Widget _textScaleBuilder(BuildContext context, Widget? child) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: display.textScaleMax,
      child: builder?.call(context, child) ?? child ?? const SizedBox.shrink(),
    );
  }

  // Router properties
  final RouteInformationProvider? routeInformationProvider;
  final RouteInformationParser<Object>? routeInformationParser;
  final RouterDelegate<Object>? routerDelegate;
  final BackButtonDispatcher? backButtonDispatcher;

  /// Folds every feature-contributed [IAppTreeWrapper] around [child].
  ///
  /// Lowest `order` is applied first, so it ends up innermost — closest to the
  /// app — which is what a wrapper needs when it must read a value another one
  /// provides. No registrations simply returns [child] untouched.
  Widget _wrapWithFeatureTrees(BuildContext context, Widget child) {
    final wrappers = getAllOrEmpty<IAppTreeWrapper>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return wrappers.fold(
      child,
      (wrapped, wrapper) => wrapper.wrap(context, wrapped),
    );
  }

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
          // No `TooltipVisibility(visible: false)` here: it removed every
          // tooltip from the semantics tree too, leaving icon-only buttons
          // unlabelled for screen readers. The theme's `tooltipTheme` stops
          // the long-press popup instead and keeps the label.
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: themeProvider.systemUiOverlayStyle,
            child: ChangeNotifierProvider.value(
              value: getIt<DeeplinkProvider>(),
              child: _wrapWithFeatureTrees(
                context,
                _buildMaterialApp(
                  themeMode: themeProvider.themeMode,
                  theme: themeProvider.currentTheme(context),
                  darkTheme: themeProvider.darkTheme(context),
                  locale: languageProvider.locale,
                  languages: languageProvider.languageSet,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMaterialApp({
    required ThemeMode themeMode,
    required ThemeData theme,
    required ThemeData darkTheme,
    required Locale locale,
    required LanguageSet languages,
  }) {
    final title = AppConfig.title;
    const debugShowCheckedModeBanner = false;
    const showPerformanceOverlay = false;
    // Localization configuration
    // `getAllOrEmpty`, not `getIt.getAll`: the latter throws when no feature
    // registers `IFeatureLocalization`. Every feature package is removable, so
    // an app built without any of them must still resolve its delegates —
    // falling back to the global `core_base_ui` ones.
    final delegates = [
      ...getAllOrEmpty<IFeatureLocalization>().map((e) => e.delegate),
      ...AppLocalizations.localizationsDelegates,
    ];
    final supportedLocales = languages.supported;

    if (isRouter) {
      return MaterialApp.router(
        title: title,
        debugShowCheckedModeBanner: debugShowCheckedModeBanner,
        showPerformanceOverlay: showPerformanceOverlay,
        themeMode: themeMode,
        theme: theme,
        darkTheme: darkTheme,
        locale: locale,
        localizationsDelegates: delegates,
        supportedLocales: supportedLocales,
        builder: _textScaleBuilder,
        routeInformationProvider: routeInformationProvider,
        routeInformationParser: routeInformationParser,
        routerDelegate: routerDelegate,
        backButtonDispatcher: backButtonDispatcher,
        localeResolutionCallback: (deviceLocale, _) =>
            languages.resolve(deviceLocale),
      );
    }

    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      showPerformanceOverlay: showPerformanceOverlay,
      home: home,
      themeMode: themeMode,
      theme: theme,
      darkTheme: darkTheme,
      locale: locale,
      localizationsDelegates: delegates,
      supportedLocales: supportedLocales,
      builder: _textScaleBuilder,
      localeResolutionCallback: (deviceLocale, _) =>
          languages.resolve(deviceLocale),
    );
  }
}
