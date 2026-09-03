import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:data_auth/data_auth.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../presentation/navigation/app_router.dart';

/// Concrete implementation of NetworkConfig for the main application shell.
///
/// This fulfills dependencies of core_network using core_base_ui for retry
/// overlay dialogs, without creating circular package dependencies.
///
/// Credentials are never read from a shared storage object — this delegates
/// to the actual owners of each value ([AuthLocalDataSource] for the token,
/// [ILanguageStorage] for the locale) so no cross-domain storage key leaks.
///
/// Registered lazily (not eager `@Singleton`) because [AuthLocalDataSource]
/// lives in `data_auth`, whose module is initialized after this app-local DI
/// block runs. Its only consumer, `ApiClient`, is itself `@lazySingleton`,
/// so deferring construction here is safe and avoids a "not registered"
/// error during `configureDependencies()`.
@LazySingleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  /// Constructor – receives the credential owners and [AppRouter] through DI.
  NetworkConfigImpl(
    this._authLocalDataSource,
    this._languageStorage,
    this._refreshTokenUseCase,
  );

  final AuthLocalDataSource _authLocalDataSource;
  final ILanguageStorage _languageStorage;
  final RefreshTokenUseCase _refreshTokenUseCase;

  @override
  String? Function() get getToken => _authLocalDataSource.getUserToken;

  @override
  String? Function() get getLocale =>
      () => _languageStorage.getLanguage().languageCode;

  @override
  Future<String?> Function()? get onRefreshToken => _refreshSession;

  @override
  Future<void> Function()? get onRefreshFailed => _clearSession;

  /// Renews the session and hands the transport layer the refreshed token.
  ///
  /// The use case delegates to the repository, which is what persists the new
  /// credentials; this only re-reads the value from its owner
  /// ([AuthLocalDataSource]) afterwards rather than storing anything itself.
  Future<String?> _refreshSession() async {
    final result = await _refreshTokenUseCase(const NoParams());
    if (!result.isSuccess) return null;

    return _authLocalDataSource.getUserToken();
  }

  /// Drops the local session after an unrecoverable refresh failure.
  ///
  /// Navigation is intentionally left out: clearing the stored credentials is
  /// enough, because the auth shell listener in `NavigatorWrapperWidget`
  /// reacts to the session change and routes to login. Doing it here would
  /// need a `BuildContext`, which the transport layer has no business holding.
  Future<void> _clearSession() async {
    _authLocalDataSource.clearAllAuthData();
  }

  @override
  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  }) {
    AppDialogController.show(
      builder: (context) {
        return RetryDialog(
          onRetry: () {
            AppOverlay.removeDialogOverlay();
            onRetry();
          },
          onCancel: () {
            AppOverlay.removeDialogOverlay();
            onCancel();
          },
        );
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
