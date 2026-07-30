import 'package:dio/dio.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/foundation.dart';

// Keep these flags to easily enable/disable logging for requests and responses
const bool _loggerRequest = kDebugMode;
const bool _loggerResponse = kDebugMode;

class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({this.tag = 'AppClient'});
  final String tag;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_loggerRequest) {
      // Use DynamicLogger to log the RequestOptions object directly.
      // DynamicLogger has built-in support for formatting RequestOptions.
      DynamicLogger.log(
        {
          'request_url': '[${options.method}] ${options.uri}',
          'request_header': options.headers,
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
          'request_header': response.requestOptions.headers,
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
    // Log error details in a structured map for better readability.
    // DynamicLogger will format the nested 'request' and 'response' objects.
    DynamicLogger.log(
      {
        'type': err.type.toString(),
        'message': err.message,
        'error_details': err.error
            ?.toString(), // Include underlying error object info
        'response_data': err.response?.data, // Log response data if available
        'request_options':
            err.requestOptions, // Log the request that caused the error
      },
      tag:
          '$tag - ERROR [${err.requestOptions.method}] ${err.requestOptions.uri}', // More descriptive tag
      level: LogLevel.ERROR,
      stackTrace: err.stackTrace, // Pass the stack trace for better debugging
    );

    super.onError(err, handler);
  }
}
