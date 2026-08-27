import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:core_ui_kit/dialogs/app_overlay.dart';
import 'package:flutter/material.dart';

import 'app_material_wrapper.dart';
import 'navigation/app_router.dart';

/// Root application widget that sets up the main app structure
///
/// This widget serves as the entry point for the Flutter application and
/// is responsible for setting up the core application infrastructure including:
/// - Provider dependency injection
/// - Theme management
/// - Localization support
/// - Navigation routing
/// - Global app configuration
///
/// The widget follows Clean Architecture principles by separating concerns
/// and providing a clean interface between the presentation layer and
/// the underlying app infrastructure.
///
/// Key responsibilities:
/// - Initialize global providers (AppProvider, ThemeProvider, DeeplinkProvider)
/// - Configure MaterialApp with routing, theming, and localization
/// - Set up global gesture handling and UI overlays
/// - Provide consistent app-wide behavior and styling
///
/// Example usage:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // Initialize dependencies
///   await setupDependencies();
///
///   runApp(const RootApp());
/// }
/// ```
class RootApp extends StatelessWidget {
  /// Creates the root application widget
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppMaterialWrapper.router(
      supportedLocales: AppLocalizations.supportedLocales,

      // Navigation configuration using GoRouter
      routeInformationProvider:
          getIt<AppRouter>().router.routeInformationProvider,
      routeInformationParser: getIt<AppRouter>().router.routeInformationParser,
      routerDelegate: getIt<AppRouter>().router.routerDelegate,
      backButtonDispatcher: getIt<AppRouter>().router.backButtonDispatcher,

      // Global app builder for consistent behavior
      builder: (context, child) {
        return Overlay.wrap(
          child: AppOverlayInitializer(
            child: AppDialogControllerInitializer(
              child: GestureDetector(
                // Global tap handler to unfocus keyboard when tapping outside input fields
                onTap: AppUtils.unfocusKeyboard,
                child: MediaQuery.withNoTextScaling(
                  // Disable text scaling to maintain consistent UI layout
                  child: child!,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
