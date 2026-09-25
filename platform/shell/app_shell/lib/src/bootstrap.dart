import 'dart:async';
import 'dart:io';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'main_scope.dart';
import 'presentation/navigation/app_router.dart';
import 'presentation/root_app.dart';

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
/// The boot sequence itself is identical across apps — DI, then
/// [AppInitializer.initBeforeRunApp] (logger + certificate pinning), then the
/// splash, then [AppInitializer.init], then the router — so it lives here
/// rather than being copied into each `main.dart`, where the copies would
/// drift.
///
/// ## Errors
///
/// Three hooks catch what nothing else did, and all three end in one place
/// (see [installShellErrorHooks]): errors escaping the guarded zone, errors
/// the framework catches ([FlutterError.onError] — build, layout, paint,
/// image decoding) and errors escaping to the engine
/// ([PlatformDispatcher.onError]). Each is still printed to the console as
/// before, then handed to [onError] and to the registered [IErrorReporter],
/// if any, as a fatal error.
///
/// To plug in Crashlytics or Sentry, register an `IErrorReporter` in the app
/// (`getItOrNull`, so none is fine too); [onError] stays for an app that
/// wants the raw callback. Errors thrown by `configureDependencies` itself
/// reach [onError] only — the reporter is not registered yet.
void runShellApp({
  required Future<void> Function() configureDependencies,
  ShellErrorCallback? onError,
}) {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      installShellErrorHooks(onError: onError);
      registerBaseUiLicenses();
      await configureDependencies();

      // Before anything is built. The splash below is already wrapped in every
      // feature's `IAppTreeWrapper`, and a controller created there may open
      // a connection straight away (auth restores the session with a token
      // refresh). Dio keeps the first `HttpClient` it creates, so pinning
      // installed any later — in `initService` — would never reach it.
      AppInitializer.initBeforeRunApp();

      // iOS keeps its native splash for the whole boot, so no Dart splash is
      // built there. `kIsWeb` is checked first because `Platform.isIOS` throws
      // on web.
      final usesDartSplash = kIsWeb || !Platform.isIOS;

      await MainScope(
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
    // Through `FlutterError.reportError`, so a zone error takes the same
    // path as every other: printed, then reported exactly once.
    (error, stack) => FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: _library,
        context: ErrorDescription('while running the app zone'),
      ),
    ),
  );
}

/// Receives every uncaught error once the shell's hooks are installed.
typedef ShellErrorCallback = void Function(Object error, StackTrace stack);

const String _library = 'platform_app_shell';

/// Installs the shell's error hooks. [runShellApp] calls it first thing;
/// exposed for tests.
///
/// - [FlutterError.onError] keeps whatever handler was installed before
///   (by default [FlutterError.presentError], the console dump in debug),
///   then reports.
/// - [PlatformDispatcher.onError] re-raises into [FlutterError.reportError],
///   so it is printed and reported the same way, and returns `true`: the
///   error is handled, the engine need not log it again.
/// - [ErrorHandler.onUnclassifiedError] forwards the handled failures
///   `ErrorHandler` could not classify to the [IErrorReporter] as
///   non-fatal — they usually are bugs, not network weather.
///
/// Reporting means: [onError], then `getItOrNull<IErrorReporter>()`,
/// resolved at the moment of the error so a reporter registered by
/// `configureDependencies` is picked up, and a missing one is not an error.
/// A throwing callback or reporter is swallowed — it is never reported
/// through itself.
@visibleForTesting
void installShellErrorHooks({ShellErrorCallback? onError}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    (previous ?? FlutterError.presentError)(details);
    _report(
      details.exception,
      details.stack ?? StackTrace.current,
      fatal: true,
      reason: details.context?.toDescription(),
      onError: onError,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: _library,
        context: ErrorDescription('while running outside the framework'),
      ),
    );
    return true;
  };

  ErrorHandler.onUnclassifiedError = (error, stack) => _report(
    error,
    stack,
    fatal: false,
    reason: 'ErrorHandler could not classify this exception',
  );
}

/// Guards against a reporter whose own failure would be reported again.
bool _reporting = false;

void _report(
  Object error,
  StackTrace stack, {
  required bool fatal,
  String? reason,
  ShellErrorCallback? onError,
}) {
  if (_reporting) return;
  _reporting = true;
  try {
    try {
      onError?.call(error, stack);
    } catch (_) {
      // The app's callback failed; the reporter below still gets the error.
    }
    final reporter = getItOrNull<IErrorReporter>();
    if (reporter == null) return;
    unawaited(
      reporter
          .recordError(error, stack, fatal: fatal, reason: reason)
          .catchError((Object _) {}),
    );
  } catch (_) {
    // `recordError` threw synchronously: nothing left to report it to.
  } finally {
    _reporting = false;
  }
}
