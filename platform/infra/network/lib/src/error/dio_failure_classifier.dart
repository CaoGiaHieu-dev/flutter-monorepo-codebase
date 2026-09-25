import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// Maps Dio's [DioException] to an [AppFailure] for `ErrorHandler`.
///
/// **Every failure carries a stable code** — an [ErrorCodes] constant for a
/// transport failure, the HTTP status for an error response — and that code
/// is what a UI maps to a translated message. [AppFailure.message] is an
/// English diagnostic (or the server's own text) for logs and crash
/// reports; do not show it as-is.
///
/// The kernel is pure Dart and names no transport, so the Dio rules live
/// here, next to the client that throws them, and reach `ErrorHandler`
/// through [ErrorHandler.registerClassifier].
///
/// **Registration is deterministic:** this is an eager `@singleton` of
/// `core_network`'s DI module whose `@PostConstruct` registers it, so it is
/// in place as soon as the `core` DI group has initialised — before any
/// Dio client exists (every client is lazy) and before any repository runs.
/// [ApiClient] registers it again when constructed (a no-op after the first
/// time), which covers a client built outside DI. Code that throws or
/// classifies `DioException`s without either — a unit test driving a
/// repository — calls [ensureRegistered] itself.
@singleton
final class DioFailureClassifier implements ErrorClassifier {
  const DioFailureClassifier();

  /// Registers a [DioFailureClassifier] with `ErrorHandler`. Idempotent.
  static void ensureRegistered() =>
      ErrorHandler.registerClassifier(const DioFailureClassifier());

  /// Hooks this instance into `ErrorHandler`; run by DI on construction.
  @PostConstruct()
  void register() => ErrorHandler.registerClassifier(this);

  @override
  AppFailure<dynamic>? classify(Object error) {
    if (error is! DioException) return null;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkFailure(
          message: 'Connection timeout',
          code: ErrorCodes.CONNECTION_TIMEOUT,
        );

      case DioExceptionType.badResponse:
        final response = error.response;
        return _failureFromStatusCode(
          response?.statusCode,
          _messageOf(response),
        );

      case DioExceptionType.cancel:
        return const ServerFailure(
          message: 'Request was cancelled',
          code: ErrorCodes.REQUEST_CANCELLED,
        );

      case DioExceptionType.connectionError:
        return const NetworkFailure(
          message: 'Connection error',
          code: ErrorCodes.CONNECTION_ERROR,
        );

      case DioExceptionType.badCertificate:
        return const NetworkFailure(
          message: 'Certificate error',
          code: ErrorCodes.BAD_CERTIFICATE,
        );

      case DioExceptionType.transformTimeout:
        return const NetworkFailure(
          message: 'Transform timeout error',
          code: ErrorCodes.TRANSFORM_TIMEOUT,
        );

      case DioExceptionType.unknown:
        return NetworkFailure(
          message: error.message ?? 'Unknown network error',
          code: ErrorCodes.NETWORK_UNKNOWN,
        );
    }
  }

  /// The failure for an HTTP error response: 401/403 → [AuthFailure],
  /// any other status → [ServerFailure] carrying it, no status →
  /// [ErrorCodes.HTTP_ERROR] — never a made-up 500, so a code in 500–599
  /// always is a real server error.
  static AppFailure<dynamic> _failureFromStatusCode(
    int? statusCode,
    String message,
  ) {
    if (statusCode == null) {
      return ServerFailure(message: message, code: ErrorCodes.HTTP_ERROR);
    }
    if (statusCode == 401 || statusCode == 403) {
      return AuthFailure(message: message, code: statusCode);
    }
    return ServerFailure(message: message, code: statusCode);
  }

  /// The diagnostic message of an error response — the server's own text
  /// when it sent one.
  ///
  /// Backends disagree on the shape of `message`: a plain string, a list of
  /// validation messages (NestJS's `{"message": ["email must be an
  /// email"]}`), an object, a number. Reading it as a `String` threw a
  /// `TypeError` for every shape but the first. Falls back to the HTTP
  /// status message, then to a generic one, when the body carries nothing
  /// usable — a non-map body included.
  static String _messageOf(Response<dynamic>? response) {
    final data = response?.data;
    final fromBody = data is Map ? _textOf(data['message']) : null;
    return fromBody ?? _textOf(response?.statusMessage) ?? 'Server error';
  }

  /// [value] as display text, or `null` when it holds none.
  ///
  /// A list is joined one entry per line, skipping entries with no text;
  /// anything else that is not a string goes through `toString`.
  static String? _textOf(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }
    if (value is Iterable) {
      final lines = value.map(_textOf).whereType<String>();
      return lines.isEmpty ? null : lines.join('\n');
    }
    return _textOf(value.toString());
  }
}
