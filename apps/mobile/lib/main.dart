import 'package:platform_app_shell/platform_app_shell.dart';

import 'app/app_hooks.dart';
import 'app/app_profile.dart';
import 'di/injection.dart';

/// The whole boot sequence lives in `platform_app_shell`; this app supplies
/// what it is (`appProfile`, generated facts from `app_manifest.yaml`), the
/// code it runs at fixed points (`appHooks`) and its dependency graph
/// (`configureDependencies`, generated from the same manifest).
void main() => runShellApp(
  profile: appProfile,
  hooks: appHooks,
  configureDependencies: configureDependencies,
);
