import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'boot/boot_error_app.dart';
import 'composition/composition_check.dart';
import 'main_scope.dart';
import 'navigation/app_router.dart';
import 'root_app.dart';
import 'shell_hooks.dart';

/// Boots an app built on this shell.
///
/// Every app's `main.dart` is one call to this, passing what the app *is* —
/// its [profile], whose facts are generated from `app_manifest.yaml` — the
/// code it runs at fixed points ([hooks]) and the `configureDependencies`
/// generated for it from the same manifest:
///
/// ```dart
/// void main() => runShellApp(
///   profile: appProfile,
///   hooks: appHooks,
///   configureDependencies: configureDependencies,
/// );
/// ```
///
/// The boot sequence itself is identical across apps — [profile] checks,
/// DI, then [AppInitializer.initBeforeRunApp] (logger + certificate
/// pinning), then the splash, then [AppInitializer.init], then the router —
/// so it lives here rather than being copied into each `main.dart`, where the
/// copies would drift.
///
/// ## The app profile
///
/// The [profile] is required: an app that does not say where it runs and what
/// it provides is the problem the declaration exists to remove. The shell does
/// three things with it:
///
/// 1. **Before DI**, [AppProfile.validate] runs for the platform
///    (`resolveAppPlatform`) and flavor this build is. A problem — an
///    undeclared platform or flavor, a required `--dart-define` that is
///    empty, a missing pin decision — stops the boot at [runBootError]'s
///    screen, and `configureDependencies` is never called. Starting on a
///    platform the manifest does not declare used to be a blank window with
///    no error. `--dart-define=ALLOW_UNDECLARED_PLATFORM=true` turns the
///    undeclared-platform problem into a logged warning, for a developer's
///    quick look.
/// 2. The profile and its sections are registered ([registerAppProfile]),
///    and so are the [hooks] (`getItOrNull<ShellHooks>()`), still before DI,
///    so anything built while the graph initialises can read them.
/// 3. **After DI**, [checkAppContract] holds the app's `capabilities:`
///    declaration to what the graph registered ([handleCompositionReport]).
///    In a dev or staging flavor, or a debug or profile build, a mismatch
///    stops the boot with the same screen; in a production release it is
///    logged and reported as a non-fatal error and the app starts anyway — a
///    removed module must still run (RULE-05). An app's DI smoke test should
///    call [checkAppContract] on the graph it boots, so CI finds the mismatch
///    before a release does.
///
/// The Dart splash is chosen by the platform's declared `splash`
/// (`platforms.<p>.splash` in the manifest), not by a fork on the operating
/// system.
///
/// ## Hooks
///
/// [hooks] carries an app's code for fixed points: the two error channels
/// ([ShellHooks.onError], [ShellHooks.onNonFatalError]),
/// [ShellHooks.beforeDependencies] and [ShellHooks.afterBoot]. The last two
/// receive an [AppRuntime].
///
/// ## Errors
///
/// Three hooks catch what nothing else did, and all three end in one place
/// (see [installShellErrorHooks]): errors escaping the guarded zone, errors
/// the framework catches ([FlutterError.onError] — build, layout, paint,
/// image decoding) and errors escaping to the engine
/// ([PlatformDispatcher.onError]). Each is still printed to the console as
/// before, then handed to the fatal error hook and to the registered
/// [IErrorReporter], if any, as a fatal error.
///
/// To plug in Crashlytics or Sentry, register an `IErrorReporter` in the app
/// (`getItOrNull`, so none is fine too); the fatal hook stays for an app that
/// wants the raw callback — [ShellHooks.onError]. Errors thrown by
/// `configureDependencies` itself reach the fatal hook only — the reporter is
/// not registered yet.
void runShellApp({
  required AppProfile profile,
  required Future<void> Function() configureDependencies,
  ShellHooks hooks = const ShellHooks(),
}) {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      installShellErrorHooks(
        onError: hooks.onError,
        onNonFatalError: hooks.onNonFatalError,
      );
      registerBaseUiLicenses();

      final runtime = AppRuntime(
        profile: profile,
        flavor: AppConfig.appFlavor,
        platform: resolveAppPlatform(),
        isDebug: kDebugMode,
      );

      final problems = validateBoot(runtime);
      if (problems.isNotEmpty) {
        runBootError(problems, detailed: showsBootDiagnostics(runtime.flavor));
        return;
      }

      // Before DI: an eager singleton built while the graph initialises can
      // inject a section, and nothing registered later can shadow it.
      registerAppProfile(profile, platform: runtime.platform);
      _registerHooks(hooks);
      await hooks.beforeDependencies?.call(runtime);

      await configureDependencies();

      final report = checkAppContract(
        runtime.profile,
        flavor: runtime.flavor,
        platform: runtime.platform,
      );
      final goesOn = handleCompositionReport(
        report,
        onNonFatalError: hooks.onNonFatalError,
      );
      if (!goesOn) return;

      // Before anything is built. The splash below is already wrapped in every
      // feature's `IAppTreeWrapper`, and a controller created there may open
      // a connection straight away (auth restores the session with a token
      // refresh). Dio keeps the first `HttpClient` it creates, so pinning
      // installed any later — in `initService` — would never reach it.
      AppInitializer.initBeforeRunApp(
        profile: profile,
        platform: runtime.platform,
        flavor: runtime.flavor,
      );

      // The platform's declared `splash` decides — iOS keeps its native splash
      // for the whole boot by default, so no Dart splash is built there.
      final usesDartSplash =
          (profile.facts.platformFor(runtime.platform) ??
                  const PlatformFacts.today())
              .splash ==
          SplashMode.dart;

      await MainScope(
        // Resolved through `core_di` rather than importing the splash feature:
        // with no implementation registered this stays null and `MainScope`
        // falls back to the native splash.
        splashScreen: usesDartSplash
            ? getItOrNull<IAppSplashScreen>()?.build()
            : null,
        root: const RootApp(),
        initService: () async {
          await AppInitializer.init(
            routeObserver: getIt<AppRouter>().routeObserver,
            profile: profile,
            platform: runtime.platform,
            flavor: runtime.flavor,
          );
          await hooks.afterBoot?.call(runtime);
        },
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

/// What stops [runtime]'s app before dependency injection starts: the
/// problems [AppProfile.validate] finds for the platform and flavor this
/// build is.
///
/// Required `--dart-define`s are checked in a non-debug build only — a plain
/// `flutter run` of a debug build need not pass the env file.
///
/// With [allowUndeclaredPlatform] (the `ALLOW_UNDECLARED_PLATFORM` define by
/// default) an undeclared platform (`P01`) is logged as a warning instead.
@visibleForTesting
List<ProfileProblem> validateBoot(
  AppRuntime runtime, {
  bool allowUndeclaredPlatform = ProfileConstants.ALLOW_UNDECLARED_PLATFORM,
}) {
  final problems = runtime.profile.validate(
    platform: runtime.platform,
    flavor: runtime.flavor,
    checkEnv: !runtime.isDebug,
  );
  if (!allowUndeclaredPlatform) return problems;

  for (final problem in problems.where((p) => p.code == _undeclaredPlatform)) {
    DynamicLogger.log(
      '${problem.description}\nALLOW_UNDECLARED_PLATFORM is set, so the boot '
      'continues with the template defaults for this platform.\n'
      '${problem.action}',
      tag: 'Boot',
      level: LogLevel.WARNING,
    );
  }
  return problems.where((p) => p.code != _undeclaredPlatform).toList();
}

/// The problem code of a platform the manifest does not declare.
const String _undeclaredPlatform = 'P01';

/// Whether a boot that finds a problem stops and shows the full diagnostics:
/// in a debug or profile build, or a flavor that is not production.
///
/// A production release instead shows a generic message when the problem
/// leaves it no choice (an undeclared platform), and logs and carries on when
/// the app can still run (a composition mismatch after DI) — it never locks
/// users out over a declaration that is out of date.
@visibleForTesting
bool showsBootDiagnostics(Flavor flavor, {bool isRelease = kReleaseMode}) =>
    !isRelease || flavor != Flavor.prod;

/// What the boot does with what [checkAppContract] found after DI — and
/// whether it goes on (`true`) or stops (`false`).
///
/// - A clean [report]: goes on, silently.
/// - Where diagnostics are shown ([showsBootDiagnostics]): the boot stops at
///   [runBootError]'s screen with every problem.
/// - A production release: goes on. It never locks users out of a build whose
///   only fault is a declaration out of date, so the report is logged to
///   `DynamicLogger` as an ERROR and handed, as a non-fatal error, to
///   [onNonFatalError] and the registered `IErrorReporter`.
///
/// [isRelease] stands in for `kReleaseMode`, a compile-time constant that a
/// test cannot flip.
@visibleForTesting
bool handleCompositionReport(
  CompositionReport report, {
  ShellErrorCallback? onNonFatalError,
  bool isRelease = kReleaseMode,
}) {
  if (report.isClean) return true;

  if (showsBootDiagnostics(report.flavor, isRelease: isRelease)) {
    runBootError(report.problems, detailed: true);
    return false;
  }

  DynamicLogger.log(report.explain(), tag: 'Boot', level: LogLevel.ERROR);
  _report(
    StateError(report.explain()),
    StackTrace.current,
    fatal: false,
    reason: 'the app composition does not match its declaration',
    onError: onNonFatalError,
  );
  return true;
}

/// Binds [hooks] under its exact type before DI, so a class the graph builds
/// can read them with `getItOrNull<ShellHooks>()`.
///
/// Idempotent, like [registerAppProfile]: the same set again changes nothing,
/// and a different one replaces the earlier registration — a harness that
/// boots several apps in one process starts each from its own hooks.
void _registerHooks(ShellHooks hooks) {
  if (getIt.isRegistered<ShellHooks>()) {
    if (identical(getIt<ShellHooks>(), hooks)) return;
    getIt.unregister<ShellHooks>();
  }
  getIt.registerSingleton<ShellHooks>(hooks);
}

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
/// Reporting means: the callback — [onError] for the fatal channel,
/// [onNonFatalError] for the unclassified failures — then
/// `getItOrNull<IErrorReporter>()`, resolved at the moment of the error so a
/// reporter registered by `configureDependencies` is picked up, and a missing
/// one is not an error. A throwing callback or reporter is swallowed — it is
/// never reported through itself.
@visibleForTesting
void installShellErrorHooks({
  ShellErrorCallback? onError,
  ShellErrorCallback? onNonFatalError,
}) {
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
    onError: onNonFatalError,
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
