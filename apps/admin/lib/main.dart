import 'package:platform_app_shell/platform_app_shell.dart';

import 'di/injection.dart';

/// Same shell, same boot, different composition: everything this app is made
/// of is declared in `app_manifest.yaml` and generated into
/// `di/injection.dart`.
void main() => runShellApp(configureDependencies: configureDependencies);
