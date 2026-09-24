/// Failure codes `ErrorHandler` and `IBaseRepository` assign when there is no
/// HTTP status to carry.
///
/// A caller that must tell a server's refusal from a transient problem —
/// the auth session gateway deciding whether to keep a session — compares
/// against these instead of guessing from a default code. None of them lies
/// in the HTTP range (100–599), so a `ServerFailure` whose code is `>= 500 &&
/// < 600` is always a real 5xx.
class ErrorCodes {
  ErrorCodes._();

  /// The request was cancelled before an answer arrived
  /// (`DioExceptionType.cancel`).
  static const int REQUEST_CANCELLED = 1004;

  /// The server answered, but `execute`'s `successCondition` rejected the
  /// response — a 200 whose envelope reports failure. The server's verdict,
  /// not a transport problem.
  static const int RESPONSE_REJECTED = 7001;

  /// The server answered with an empty body where a value was required.
  static const int EMPTY_RESPONSE = 7002;

  /// An error nothing more specific recognised.
  static const int UNKNOWN = 9999;
}
