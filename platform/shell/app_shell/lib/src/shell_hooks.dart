import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Receives every uncaught error once the shell's hooks are installed.
typedef ShellErrorCallback = void Function(Object error, StackTrace stack);

/// Code an app runs at fixed points of the shell's boot — all optional, all
/// `const`, found by autocomplete on `const ShellHooks(`.
///
/// The app's `lib/app/app_hooks.dart` holds one `const ShellHooks appHooks`
/// and `main.dart` passes it to `runShellApp`. A hook is *code*: data that
/// fits the manifest (platforms, flavors, capabilities) or the profile
/// (tuning) belongs there instead, where a gate can read it.
///
/// A hook that throws is reported through the error hooks like any other
/// error in the app zone, and stops the boot at the point it ran.
final class ShellHooks {
  const ShellHooks({
    this.onError,
    this.onNonFatalError,
    this.beforeDependencies,
    this.afterBoot,
    this.navigatorObservers,
    this.redirect,
    this.configureWindow,
  });

  /// The fatal-error channel: every error that escapes the guarded zone,
  /// reaches the framework (`FlutterError.onError`) or reaches the engine
  /// (`PlatformDispatcher.onError`). Each is still printed, then handed here
  /// and to the registered `IErrorReporter`.
  ///
  /// A top-level function tear-off is `const`, so
  /// `ShellHooks(onError: reportFatal)` stays a constant.
  final ShellErrorCallback? onError;

  /// The non-fatal channel: failures `ErrorHandler.handleError` could not
  /// classify (`ErrorHandler.onUnclassifiedError`). Today only an
  /// `IErrorReporter` sees these; they are usually bugs rather than network
  /// weather, and are never printed as uncaught errors.
  final ShellErrorCallback? onNonFatalError;

  /// Runs after the error hooks are installed and the app profile is
  /// registered, before dependency injection starts — the slot for
  /// `Sentry.init`, `Firebase.initializeApp` or any setup the graph itself
  /// needs in place.
  ///
  /// May not resolve anything from the DI graph: it does not exist yet.
  final Future<void> Function(AppRuntime runtime)? beforeDependencies;

  /// Runs after dependency injection and the shell's own initialisation,
  /// before the first frame of the app.
  ///
  /// Everything the graph registered can be resolved here. Keep it short: the
  /// splash stays up until it completes.
  final Future<void> Function(AppRuntime runtime)? afterBoot;

  /// Extra observers for the router's navigators — screen analytics, a
  /// breadcrumb trail for the crash reporter.
  ///
  /// Called once, when the router is built (after dependency injection), with
  /// the [AppRuntime]. They are added beside the shell's own route observer,
  /// which they never replace, and go_router forwards them to every nested
  /// navigator, so one observer sees the whole app.
  final List<NavigatorObserver> Function(AppRuntime runtime)?
  navigatorObservers;

  /// One app-wide route guard, run before any route's own redirect — the slot
  /// for a maintenance page or a forced-update screen.
  ///
  /// Return a location to redirect to, or `null` to let the navigation
  /// through. It runs on every navigation and whenever the session changes,
  /// so it must be quick and must not redirect to a location that redirects
  /// back. Sign-in and sign-out navigation is the shell's own
  /// (`ISignInLocation`, `IPostSignInLocation`); this is not the place to
  /// reimplement it.
  final FutureOr<String?> Function(BuildContext context, GoRouterState state)?
  redirect;

  /// Applies the window the manifest declares for a desktop platform
  /// (`platforms.<p>.window`: its initial and minimum size).
  ///
  /// Runs once during boot, after the shell's own initialisation and before
  /// [afterBoot]. The shell brings no window-management plugin — the app
  /// brings one (`window_manager`, say) and calls it here. A platform that
  /// declares a `window` while the app passes no hook is a boot problem
  /// (`P05`), never a silent no-op; a platform that declares none never calls
  /// this.
  final Future<void> Function(AppRuntime runtime, WindowFacts window)?
  configureWindow;
}
