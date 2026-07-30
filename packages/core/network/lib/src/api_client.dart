import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'handlers/retry_handler.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'network_config.dart';

/// Timeout durations for network requests.
const _connectTimeOut = Duration(seconds: 20);
const _receiveTimeOut = Duration(seconds: 20);
const _sendTimeout = Duration(seconds: 20);

/// ApiClient is responsible for creating and configuring Dio HTTP clients.
@lazySingleton
class ApiClient {
  final NetworkConfig _config;

  ApiClient(this._config);

  /// Default base options for Dio.
  BaseOptions get _defaultOptions => BaseOptions(
    baseUrl: EnvConstants.BASE_URL,
    connectTimeout: _connectTimeOut,
    receiveTimeout: _receiveTimeOut,
    sendTimeout: _sendTimeout,
    followRedirects: false,
    headers: {HttpHeaders.contentTypeHeader: ContentType.json.value},
  );

  /// Creates a new Dio instance with the provided configuration.
  ///
  /// [baseUrl] overrides the default base URL.
  /// [interceptors] adds additional interceptors to the client.
  /// [useDefaultInterceptors] whether to include Auth, Retry, and Logging interceptors.
  /// [options] overrides the default BaseOptions.
  Dio createClient({
    String? baseUrl,
    List<Interceptor>? interceptors,
    bool useDefaultInterceptors = true,
    BaseOptions? options,
  }) {
    // Clone or use default options to avoid mutating shared state
    final dioOptions = options?.copyWith() ?? _defaultOptions;

    if (baseUrl != null) {
      dioOptions.baseUrl = baseUrl;
    }

    final dio = Dio(dioOptions);

    if (useDefaultInterceptors) {
      final retryHandler = RetryHandler(
        dio.options,
        onRetryCallback: _config.onRetryCallback,
      );
      dio.interceptors.addAll([
        AuthInterceptor(
          getToken: _config.getToken,
          getLocale: _config.getLocale,
        ),
        RetryInterceptor(
          handleRetry: retryHandler.handleRetry,
          retryWhen: retryHandler.retryWhen,
        ),
        LoggingInterceptor(tag: 'DioClient'),
      ]);
    }

    // Add custom interceptors if any
    if (interceptors != null) {
      dio.interceptors.addAll(interceptors);
    }

    return dio;
  }
}
