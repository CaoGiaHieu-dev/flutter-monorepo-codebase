import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

import '../src/provider/auth_provider.dart';
import '../src/services/auth_status_stream_impl.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDiModule {
  /// Neutral auth-state stream other features listen to.
  @singleton
  IAuthStatusStream bindIAuthStatusStream(AuthStatusStreamImpl impl) => impl;

  /// Shell-facing session view: boot sequencing plus the failure channel.
  ///
  /// Lazy on purpose — it binds [AuthProvider], itself a `@lazySingleton`, so
  /// binding eagerly would construct the provider (and its use cases) during
  /// module registration instead of on first use.
  @lazySingleton
  IAuthSessionState bindIAuthSessionState(AuthProvider provider) => provider;

  /// `GoRouter.refreshListenable` source, so routing reacts to sign-in and
  /// sign-out without the shell importing this package.
  @lazySingleton
  IAuthRefreshListenable bindIAuthRefreshListenable(AuthProvider provider) =>
      provider;
}
