import 'dart:async';
import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'di/injection.dart';
import 'main_scope.dart';
import 'presentation/navigation/app_router.dart';
import 'presentation/root_app.dart';

void main() {
  // Run the app within a guarded zone to catch and report errors.
  runZonedGuarded(
    () async {
      // Ensure that widget binding is initialized.
      WidgetsFlutterBinding.ensureInitialized();
      // 1. Configure dependency injection first
      await configureDependencies();
      // iOS keeps its native splash for the whole boot, so no Dart splash is
      // built there. `kIsWeb` is checked first because `Platform.isIOS` throws
      // on web.
      final usesDartSplash = kIsWeb || !Platform.isIOS;

      // Create an instance of MainScope to manage app initialization and transitions.
      final mainScope = MainScope(
        // Resolved through `core_di` rather than importing the splash feature:
        // with no implementation registered this stays null and `MainScope`
        // falls back to the native splash.
        splashScreen: usesDartSplash
            ? getItOrNull<IAppSplashScreen>()?.build()
            : null,
        root: const RootApp(),
        initService: () => AppInitializer.init(
          routeObserver: getIt<AppRouter>().routeObserver,
        ),
      );

      // Run the main scope to start the app.
      mainScope.run();
    },
    (error, stack) {
      // Report errors to Firebase Crashlytics in release mode.
      if (kReleaseMode) {
        // FirebaseCrashlytics.instance.recordError(error, stack);
      }

      // Report errors to Flutter's error handling system.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}
