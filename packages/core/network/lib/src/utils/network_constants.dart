/// Constants owned exclusively by `core_network`.
///
/// Kept inside this package — not in `core_common` — so transport-level
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
  // Locale fallbacks
  // ---------------------------------------------------------------------------

  /// Language code used when the caller supplies none and the device locale
  /// is outside [SUPPORTED_LANGUAGE_CODES].
  static const String DEFAULT_LANGUAGE_CODE = 'vi';

  /// Device locales accepted as-is before falling back to
  /// [DEFAULT_LANGUAGE_CODE].
  static const List<String> SUPPORTED_LANGUAGE_CODES = ['vi', 'en'];

  // ---------------------------------------------------------------------------
  // RequestOptions.extra flags
  //
  // Read per-request by the interceptors; both default to `true` when absent.
  // ---------------------------------------------------------------------------

  /// Set `false` to stop [AuthInterceptor] attaching the bearer token.
  static const String EXTRA_NEED_AUTHENTICATION = 'needAuthentication';

  /// Set `false` to opt a request out of [RetryInterceptor].
  static const String EXTRA_CAN_RETRY = 'canRetry';

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
  static const String RETRY_LOG_TAG = 'Retry';
}
