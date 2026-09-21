import 'package:dio/dio.dart';

/// Extension methods for Dio exception types
extension DioExceptionTypeExtension on DioExceptionType {
  /// Returns a user-friendly description of the Dio exception type
  ///
  /// Converts technical Dio exception types into readable descriptions
  /// that can be displayed to users or used in error logging.
  ///
  /// Example:
  /// ```dart
  /// DioExceptionType.connectionTimeout.prettyDescription; // "Connection Timeout"
  /// ```
  String get prettyDescription {
    switch (this) {
      case DioExceptionType.connectionTimeout:
        return 'Connection Timeout';
      case DioExceptionType.sendTimeout:
        return 'Send Timeout';
      case DioExceptionType.receiveTimeout:
        return 'Receive Timeout';
      case DioExceptionType.badCertificate:
        return 'Bad Certificate';
      case DioExceptionType.badResponse:
        return 'Bad Response';
      case DioExceptionType.cancel:
        return 'Request Cancelled';
      case DioExceptionType.connectionError:
        return 'Connection Error';
      case DioExceptionType.unknown:
        return 'Unknown';
      case DioExceptionType.transformTimeout:
        return 'Transform Timeout';
    }
  }
}
