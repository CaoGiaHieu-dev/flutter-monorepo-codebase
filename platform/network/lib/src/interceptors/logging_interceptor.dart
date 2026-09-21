import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/foundation.dart';

import '../utils/network_constants.dart';

// Keep these flags to easily enable/disable logging for requests and responses
const bool _loggerRequest = kDebugMode;
const bool _loggerResponse = kDebugMode;
const bool _loggerError = kDebugMode;

class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({this.tag = NetworkConstants.DEFAULT_LOG_TAG});
  final String tag;

  /// Returns a copy of [headers] with credential-bearing values masked.
  ///
  /// Even in debug builds the logs are written to a shared console (and are
  /// routinely pasted into bug reports), so the bearer token and cookies are
  /// never printed verbatim.
  Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) {
    const redactedKeys = {
      HttpHeaders.authorizationHeader,
      HttpHeaders.cookieHeader,
      HttpHeaders.setCookieHeader,
      HttpHeaders.proxyAuthorizationHeader,
    };

    return {
      for (final entry in headers.entries)
        entry.key: redactedKeys.contains(entry.key.toLowerCase())
            ? '***REDACTED***'
            : entry.value,
    };
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_loggerRequest) {
      // Use DynamicLogger to log the RequestOptions object directly.
      // DynamicLogger has built-in support for formatting RequestOptions.
      DynamicLogger.log(
        {
          'request_url': '[${options.method}] ${options.uri}',
          'request_header': _redactHeaders(options.headers),
          'request_data': options.data,
        },
        tag: '$tag - REQUEST', // More descriptive tag
        level: LogLevel.INFO,
      );
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_loggerResponse) {
      // Log relevant response information in a structured map.
      // This allows DynamicLogger to format the data nicely.
      DynamicLogger.log(
        {
          'request_url':
              '[${response.requestOptions.method}] ${response.requestOptions.uri}',
          'request_header': _redactHeaders(response.requestOptions.headers),
          'request_data': response.requestOptions.data,
          'status_code': response.statusCode,
          'status_message': response.statusMessage,
          'data': response.data, // Let DynamicLogger handle data formatting
        },
        tag: '$tag - RESPONSE', // More descriptive tag
        level: LogLevel.INFO,
      );
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Guarded by `kDebugMode` like onRequest/onResponse: this payload carries
    // the request headers (bearer token) and the raw response body, neither of
    // which may reach a release build's logs.
    if (_loggerError) {
      // Log error details in a structured map for better readability.
      // DynamicLogger will format the nested 'request' and 'response' objects.
      DynamicLogger.log(
        {
          'type': err.type.toString(),
          'message': err.message,
          'error_details': err.error
              ?.toString(), // Include underlying error object info
          'response_data': err.response?.data, // Log response data if available
          // Log the request that caused the error — headers redacted so the
          // bearer token is never printed.
          'request_url':
              '[${err.requestOptions.method}] ${err.requestOptions.uri}',
          'request_header': _redactHeaders(err.requestOptions.headers),
          'request_data': err.requestOptions.data,
        },
        tag:
            '$tag - ERROR [${err.requestOptions.method}] ${err.requestOptions.uri}', // More descriptive tag
        level: LogLevel.ERROR,
        stackTrace: err.stackTrace, // Pass the stack trace for better debugging
      );
    }

    super.onError(err, handler);
  }
}
