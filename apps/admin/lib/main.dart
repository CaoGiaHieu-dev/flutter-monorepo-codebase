import 'package:platform_app_shell/platform_app_shell.dart';

import 'app/app_hooks.dart';
import 'app/app_profile.dart';
import 'di/injection.dart';

/// Same shell, same boot, different composition: everything this app is made
/// of is declared in `app_manifest.yaml` and generated into
/// `app/app_profile.dart` (what it is) and `di/injection.dart` (what it
/// composes).
void main() => runShellApp(
  profile: appProfile,
  hooks: appHooks,
  configureDependencies: configureDependencies,
);
