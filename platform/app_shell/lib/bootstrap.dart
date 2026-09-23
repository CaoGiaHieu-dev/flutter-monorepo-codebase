import 'dart:async';
import 'dart:io';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'main_scope.dart';
import 'presentation/presentation.dart';

/// Boots an app built on this shell.
///
/// Every app's `main.dart` is one call to this, passing the
/// `configureDependencies` generated for that app from its
/// `app_manifest.yaml`:
///
/// ```dart
/// void main() => runShellApp(configureDependencies: configureDependencies);
/// ```
///
/// The boot sequence itself is identical across apps — DI, then the splash,
/// then [AppInitializer], then the router — so it lives here rather than being
/// copied into each `main.dart`, where the copies would drift.
///
/// [onError] receives every error escaping the guarded zone before it is
/// forwarded to [FlutterError.reportError]; wire a crash reporter there.
void runShellApp({
  required Future<void> Function() configureDependencies,
  void Function(Object error, StackTrace stack)? onError,
}) {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      registerBaseUiLicenses();
      await configureDependencies();

      // iOS keeps its native splash for the whole boot, so no Dart splash is
      // built there. `kIsWeb` is checked first because `Platform.isIOS` throws
      // on web.
      final usesDartSplash = kIsWeb || !Platform.isIOS;

      MainScope(
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
      ).run();
    },
    (error, stack) {
      onError?.call(error, stack);
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}
