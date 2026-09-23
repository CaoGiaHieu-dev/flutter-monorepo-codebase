import 'package:platform_app_shell/platform_app_shell.dart';

import 'di/injection.dart';

/// The whole boot sequence lives in `platform_app_shell`; this app supplies
/// only its own dependency graph, generated from `app_manifest.yaml`.
///
/// To report crashes, pass `onError` — e.g.
/// `onError: FirebaseCrashlytics.instance.recordError` once Crashlytics is
/// added to this app.
void main() => runShellApp(configureDependencies: configureDependencies);
