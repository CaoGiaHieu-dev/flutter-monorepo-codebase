/// Constants owned exclusively by `core_network`.
///
/// Kept inside this package — not in `platform_kernel` — so transport-level
/// details (timeouts, header names, request-extra flags, log tags) stay
/// invisible to features and other layers.
class NetworkConstants {
  /// Private constructor to prevent instantiation of this class.
  NetworkConstants._();

  // ---------------------------------------------------------------------------
  // Timeouts
  // ---------------------------------------------------------------------------

  static const Duration CONNECT_TIMEOUT = Duration(seconds: 20);
  static const Duration RECEIVE_TIMEOUT = Duration(seconds: 20);
  static const Duration SEND_TIMEOUT = Duration(seconds: 20);

  // ---------------------------------------------------------------------------
  // Headers
  //
  // `Authorization` and `Content-Type` come from `HttpHeaders` in `dart:io`;
  // only the non-standard ones are declared here.
  // ---------------------------------------------------------------------------

  /// Custom header carrying the upper-cased language code (e.g. `VI`, `EN`).
  static const String LANGUAGE_HEADER = 'language';

  /// Scheme prefix for the bearer token in the `Authorization` header.
  static const String BEARER_PREFIX = 'Bearer';

  // ---------------------------------------------------------------------------
  // Locale fallback
  // ---------------------------------------------------------------------------

  /// Language code sent when the `NetworkConfig` supplies none.
  ///
  /// The same language as `core_base_ui`'s `AppLanguages.fallback` — this
  /// package cannot import it (infra never depends on ui), so keep the two
  /// equal. The shell's `NetworkConfig` always supplies a resolved code, so
  /// in an app this applies only to a client built without one.
  static const String DEFAULT_LANGUAGE_CODE = 'en';

  // ---------------------------------------------------------------------------
  // RequestOptions.extra flags
  //
  // Read per-request by the interceptors; both default to `true` when absent.
  // ---------------------------------------------------------------------------

  /// Set `false` to stop [AuthInterceptor] attaching the bearer token.
  static const String EXTRA_NEED_AUTHENTICATION = 'needAuthentication';

  /// Set `false` to opt a request out of [RetryInterceptor].
  static const String EXTRA_CAN_RETRY = 'canRetry';

  /// Set `false` on a request whose `401` must never start a token refresh —
  /// the login and refresh calls themselves. The bearer token is still
  /// attached; only the refresh reaction is skipped. Without it a `401` from
  /// the refresh call waits on the refresh that is waiting on it.
  static const String EXTRA_CAN_REFRESH_TOKEN = 'canRefreshToken';

  /// Set by [RefreshTokenInterceptor] on a request it has already replayed
  /// after a token refresh. Its presence stops a second `401` on the replayed
  /// request from starting another refresh, which would otherwise recurse.
  static const String EXTRA_TOKEN_REFRESH_ATTEMPTED = 'tokenRefreshAttempted';

  // ---------------------------------------------------------------------------
  // HTTP status codes handled inside the transport layer
  // ---------------------------------------------------------------------------

  /// Triggers the refresh-token flow in [RefreshTokenInterceptor].
  static const int STATUS_UNAUTHORIZED = 401;

  // ---------------------------------------------------------------------------
  // Log tags
  // ---------------------------------------------------------------------------

  static const String DEFAULT_LOG_TAG = 'AppClient';
  static const String CLIENT_LOG_TAG = 'DioClient';
}
