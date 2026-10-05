import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

import '../src/provider/auth_provider.dart';
import '../src/session/auth_status_stream_impl.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

/// GetIt resolves the exact registered type, so each extra interface an
/// implementation serves is bound here (RULE-14). A binding matches its
/// target's scope: [AuthProvider] is lazy, so its bindings are too.
@module
abstract class AuthDiModule {
  /// The neutral session stream other features listen to.
  @singleton
  ISessionStatusStream bindISessionStatusStream(AuthStatusStreamImpl impl) =>
      impl;

  /// The shell-facing session view: boot sequencing and the failure channel.
  @lazySingleton
  ISessionState bindISessionState(AuthProvider provider) => provider;

  /// `GoRouter.refreshListenable`: routing reacts to sign-in and sign-out.
  @lazySingleton
  ISessionRefreshListenable bindISessionRefreshListenable(
    AuthProvider provider,
  ) => provider;
}
