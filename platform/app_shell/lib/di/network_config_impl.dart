import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

/// Concrete implementation of NetworkConfig for the main application shell.
///
/// This fulfills dependencies of core_network using core_base_ui for retry
/// overlay dialogs, without creating circular package dependencies.
///
/// Credentials are never read from a shared storage object — this delegates
/// to the actual owners of each value ([IAuthSessionGateway] for the session,
/// [ILanguageStorage] for the locale) so no cross-domain storage key leaks.
///
/// **This file imports no module.** It used to pull `AuthLocalDataSource` and
/// `RefreshTokenUseCase` straight out of `data_auth` / `domain_auth`, which
/// meant a build without the auth module did not compile — the composition
/// root was the one place breaking the removability the rest of the shell is
/// careful to preserve. A `getItOrNull` guard cannot fix that on its own: an
/// unresolved import fails at compile time, before any lookup happens.
/// Enforced now by `arch_check` rule **R10**.
///
/// The gateway is resolved at call time rather than injected, so this class
/// constructs fine whether or not an auth module is in the build, and no
/// module-initialisation ordering matters.
@LazySingleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  NetworkConfigImpl(this._languageStorage);

  final ILanguageStorage _languageStorage;

  /// Null in a build that composes no auth module.
  IAuthSessionGateway? get _session => getItOrNull<IAuthSessionGateway>();

  /// Whether an auth module is composed — *without* resolving it.
  ///
  /// `ApiClient` reads [onRefreshToken] while `Dio` is being constructed, and
  /// the gateway's own dependency chain (`IAuthRepository` →
  /// `AuthRemoteDataSource`) needs that same `Dio`. Resolving the gateway
  /// here closed the loop: GetIt threw "Circular dependency detected" and
  /// the app booted to an error screen. The lookup itself stays lazy, inside
  /// the callbacks, which run long after construction.
  bool get _hasSession => getIt.isRegistered<IAuthSessionGateway>();

  @override
  String? Function() get getToken =>
      () => _session?.readToken();

  @override
  String? Function() get getLocale =>
      () => _languageStorage.getLanguage().languageCode;

  /// Returning null here is load-bearing: `ApiClient` adds
  /// `RefreshTokenInterceptor` **only** when this is non-null. With no auth
  /// module there is no session to renew, so a 401 should fail outright
  /// rather than pass through an interceptor that can never succeed.
  @override
  Future<String?> Function()? get onRefreshToken =>
      _hasSession ? _refreshSession : null;

  @override
  Future<void> Function()? get onRefreshFailed =>
      _hasSession ? _clearSession : null;

  /// Renews the session and hands the transport layer the refreshed token.
  ///
  /// Persisting the new credentials is the gateway's job, not this class's.
  Future<String?> _refreshSession() async => await _session?.refreshToken();

  /// Ends the session after the server refused to renew it.
  ///
  /// Two steps, because they belong to two owners: the gateway drops the
  /// stored credentials, and the session owner drops to signed-out — which is
  /// what `NavigatorWrapperWidget` listens to and routes to login on. Clearing
  /// storage alone changes nothing anyone observes.
  Future<void> _clearSession() async {
    await _session?.clearSession();
    getItOrNull<IAuthSessionState>()?.onSessionLost();
  }

  @override
  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  }) {
    AppDialogController.show<void>(
      builder: (context) {
        // RetryDialog closes itself before calling back. A second close
        // through AppOverlay would target a different overlay system and
        // could dismiss an unrelated dialog.
        return RetryDialog(onRetry: onRetry, onCancel: onCancel);
      },
    );
  }

  /// SPKI SHA-256 pins applied on staging and production.
  ///
  /// **An empty list disables pinning.** `AppInitializer._setupHttpOverrides`
  /// only installs `HttpSecurityPinningClient` when this is non-empty, so
  /// until it is filled in the app accepts any certificate a device trusts —
  /// including one injected by an intercepting proxy. The initializer logs an
  /// ERROR on non-dev flavors while this stays empty.
  ///
  /// Populate it before shipping. To read the pin for a host:
  /// ```sh
  /// openssl s_client -servername <host> -connect <host>:443 </dev/null \
  ///   | openssl x509 -pubkey -noout \
  ///   | openssl pkey -pubin -outform der \
  ///   | openssl dgst -sha256 -binary \
  ///   | openssl enc -base64
  /// ```
  /// Pin at least two keys — the leaf plus a backup — so certificate rotation
  /// does not lock every installed client out of the API.
  @override
  List<String> get sslPinningHashes => const [];
}
