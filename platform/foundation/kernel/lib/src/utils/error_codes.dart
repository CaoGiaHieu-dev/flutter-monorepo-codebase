/// Failure codes `ErrorHandler`, the transport classifiers and
/// `BaseRepository` assign when there is no HTTP status to carry.
///
/// Every non-HTTP code the platform assigns is named here — none is spelled
/// as a literal anywhere else. A caller that must tell a server's refusal
/// from a transient problem — the auth session gateway deciding whether to
/// keep a session — compares against these instead of guessing from a
/// default code. None of them lies in the HTTP range (100–599), so a
/// `ServerFailure` whose code is `>= 500 && < 600` is always a real 5xx.
///
/// Ranges: 1xxx network, 2xxx storage, 3xxx validation, 4xxx parsing,
/// 5xxx cache, 6xxx external service, 7xxx response envelope, 9999 unknown.
class ErrorCodes {
  ErrorCodes._();

  // --- 1xxx network ---------------------------------------------------------

  /// A network failure with no more specific cause
  /// (`ErrorHandler.networkFailure`).
  static const int NETWORK_ERROR = 1000;

  /// No connection at all (`SocketException`).
  static const int NO_INTERNET = 1001;

  /// An HTTP-level failure below the response (`HttpException`).
  static const int HTTP_ERROR = 1002;

  /// Connecting, sending or receiving timed out.
  static const int CONNECTION_TIMEOUT = 1003;

  /// The request was cancelled before an answer arrived
  /// (`DioExceptionType.cancel`).
  static const int REQUEST_CANCELLED = 1004;

  /// The connection could not be established (`DioExceptionType.connectionError`).
  static const int CONNECTION_ERROR = 1005;

  /// The server's certificate was rejected (`DioExceptionType.badCertificate`).
  static const int BAD_CERTIFICATE = 1006;

  /// A transport failure the client could not name (`DioExceptionType.unknown`).
  static const int NETWORK_UNKNOWN = 1007;

  /// Transforming the response timed out (`DioExceptionType.transformTimeout`).
  static const int TRANSFORM_TIMEOUT = 1008;

  // --- 2xxx–6xxx: defaults of the `ErrorHandler` failure factories ----------

  /// A local storage operation failed (`ErrorHandler.storageFailure`).
  static const int STORAGE_ERROR = 2000;

  /// Input failed validation (`ErrorHandler.validationFailure`).
  static const int VALIDATION_ERROR = 3000;

  /// Data could not be parsed (`ErrorHandler.parseFailure`).
  static const int PARSE_ERROR = 4000;

  /// Data arrived in a format it cannot have (`FormatException`).
  static const int INVALID_FORMAT = 4001;

  /// A cache operation failed (`ErrorHandler.cacheFailure`).
  static const int CACHE_ERROR = 5000;

  /// An external service failed (`ErrorHandler.serviceFailure`).
  static const int SERVICE_ERROR = 6000;

  // --- 7xxx response envelope -----------------------------------------------

  /// The server answered, but `execute`'s `successCondition` rejected the
  /// response — a 200 whose envelope reports failure. The server's verdict,
  /// not a transport problem.
  static const int RESPONSE_REJECTED = 7001;

  /// The server answered with an empty body where a value was required.
  static const int EMPTY_RESPONSE = 7002;

  // --- 9999 ------------------------------------------------------------------

  /// An error nothing more specific recognised.
  static const int UNKNOWN = 9999;
}
