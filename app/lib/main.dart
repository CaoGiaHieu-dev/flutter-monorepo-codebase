import 'dart:async';
import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:feature_splash/feature_splash.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
      // Create an instance of MainScope to manage app initialization and transitions.
      final mainScope = MainScope(
        splashScreen: kIsWeb
            ? const SplashPage()
            : Platform.isIOS
            ? null
            : const SplashPage(),
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
