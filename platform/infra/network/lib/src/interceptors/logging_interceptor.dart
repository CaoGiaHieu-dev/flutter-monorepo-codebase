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
  @visibleForTesting
  static Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
    const redactedKeys = {
      HttpHeaders.authorizationHeader,
      HttpHeaders.cookieHeader,
      HttpHeaders.setCookieHeader,
      HttpHeaders.proxyAuthorizationHeader,
    };

    return {
      for (final entry in headers.entries)
        entry.key: redactedKeys.contains(entry.key.toLowerCase())
            ? _mask
            : entry.value,
    };
  }

  /// Key endings that mark a credential, compared lower-case with `_` and `-`
  /// removed — so `password`, `newPassword`, `confirm_password`,
  /// `access_token`, `refreshToken`, `clientSecret` and `X-Api-Key` all match,
  /// while `tokenType` and `password_hint` (which do not end in one) do not.
  static const _redactedKeyEndings = [
    'password',
    'passwd',
    'passcode',
    'pwd',
    'token',
    'secret',
    'apikey',
    'authorization',
    'privatekey',
    'cardnumber',
  ];

  /// Short credential names, matched whole — as a suffix `pin` would also hit
  /// `shipping` and `mapping` — alone or after one of [_redactedKeyPrefixes]
  /// (`otp`, `newPin`, `cardCvv`).
  static const _redactedWholeKeys = {
    'otp',
    'pin',
    'cvv',
    'cvc',
    'ssn',
    'cardno',
  };

  static const _redactedKeyPrefixes = [
    'new',
    'old',
    'confirm',
    'current',
    'user',
    'card',
  ];

  static const _mask = '***REDACTED***';

  /// Whether [key] names a credential — see [_redactedKeyEndings].
  static bool _isCredentialKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[_\\- ]'), '');
    if (_redactedKeyEndings.any(normalized.endsWith)) return true;
    if (_redactedWholeKeys.contains(normalized)) return true;
    return _redactedKeyPrefixes.any(
      (prefix) =>
          normalized.startsWith(prefix) &&
          _redactedWholeKeys.contains(normalized.substring(prefix.length)),
    );
  }

  /// [uri] as it is safe to print: scheme, host, port and path, with every
  /// query *value* masked and the user-info and fragment dropped. A token or
  /// an e-mail address in a query string (`?token=…`, `?email=…`) would
  /// otherwise reach the console in clear — the request headers and body were
  /// masked, the URL was not.
  @visibleForTesting
  static String redactUri(Uri uri) {
    final base = StringBuffer();
    if (uri.hasScheme) base.write('${uri.scheme}:');
    if (uri.hasAuthority) {
      base.write('//${uri.host}');
      if (uri.hasPort) base.write(':${uri.port}');
    }
    base.write(uri.path);
    if (!uri.hasQuery || uri.query.isEmpty) return base.toString();

    final keys = uri.queryParametersAll.keys;
    return '$base?${keys.map((key) => '$key=***').join('&')}';
  }

  /// Returns [data] with credential values masked, at any depth.
  ///
  /// Headers are not the only carrier: a login request sends the password in
  /// its body and the response returns the token in its body, and both would
  /// otherwise be printed verbatim into the same shared console.
  @visibleForTesting
  static Object? redactBody(Object? data) {
    if (data is Map) {
      return {
        for (final entry in data.entries)
          entry.key: _isCredentialKey(entry.key.toString())
              ? _mask
              : redactBody(entry.value),
      };
    }
    if (data is List) return data.map(redactBody).toList();
    return data;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_loggerRequest) {
      // Use DynamicLogger to log the RequestOptions object directly.
      // DynamicLogger has built-in support for formatting RequestOptions.
      DynamicLogger.log(
        {
          'request_url': '[${options.method}] ${redactUri(options.uri)}',
          'request_header': redactHeaders(options.headers),
          'request_data': redactBody(options.data),
        },
        tag: '$tag - REQUEST', // More descriptive tag
        level: LogLevel.INFO,
      );
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (_loggerResponse) {
      // Log relevant response information in a structured map.
      // This allows DynamicLogger to format the data nicely.
      DynamicLogger.log(
        {
          'request_url':
              '[${response.requestOptions.method}] '
              '${redactUri(response.requestOptions.uri)}',
          'request_header': redactHeaders(response.requestOptions.headers),
          'request_data': redactBody(response.requestOptions.data),
          'status_code': response.statusCode,
          'status_message': response.statusMessage,
          'data': redactBody(response.data),
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
          'response_data': redactBody(err.response?.data),
          // Log the request that caused the error — headers redacted so the
          // bearer token is never printed.
          'request_url':
              '[${err.requestOptions.method}] '
              '${redactUri(err.requestOptions.uri)}',
          'request_header': redactHeaders(err.requestOptions.headers),
          'request_data': redactBody(err.requestOptions.data),
        },
        tag:
            '$tag - ERROR [${err.requestOptions.method}] '
            '${redactUri(err.requestOptions.uri)}', // More descriptive tag
        level: LogLevel.ERROR,
        stackTrace: err.stackTrace, // Pass the stack trace for better debugging
      );
    }

    super.onError(err, handler);
  }
}
