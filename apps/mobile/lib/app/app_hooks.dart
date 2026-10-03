import 'package:platform_app_shell/platform_app_shell.dart';

/// Code this app runs at fixed points of the shell's boot — type
/// `const ShellHooks(` and the IDE lists every hook, each documented with when
/// it runs and what it may not do.
///
/// To report crashes, pass `onError` — e.g.
/// `onError: FirebaseCrashlytics.instance.recordError` once Crashlytics is
/// added to this app — or register an `IErrorReporter` in `lib/app/` and
/// declare `error_reporter: provided` in app_manifest.yaml (RULE-67). Sentry
/// goes in `beforeDependencies`.
const ShellHooks appHooks = ShellHooks();
