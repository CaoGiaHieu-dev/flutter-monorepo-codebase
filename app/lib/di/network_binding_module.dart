import 'package:core_common/core_common.dart';
import 'package:core_network/core_network.dart';
import 'package:injectable/injectable.dart';

/// Re-exposes the registered [NetworkConfig] under its [SslPinningConfig]
/// supertype.
///
/// GetIt resolves by the exact type a binding was registered under — it does
/// **not** walk the supertype chain. `NetworkConfigImpl` is registered as
/// `NetworkConfig`, so `getItOrNull<SslPinningConfig>()` (called by
/// `AppInitializer._setupHttpOverrides`) returned `null` and certificate
/// pinning was silently skipped on staging and production.
///
/// Binding through a module — the same dual-registration pattern used for
/// `IAuthStatusStream` in `feature_auth` — keeps a single instance behind both
/// types. The parameter is typed as [NetworkConfig] (which `implements
/// SslPinningConfig`), so the upcast is checked by the compiler and no `as`
/// cast is needed.
@module
abstract class NetworkBindingModule {
  @lazySingleton
  SslPinningConfig bindSslPinningConfig(NetworkConfig config) => config;
}
