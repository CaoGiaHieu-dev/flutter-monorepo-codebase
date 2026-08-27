import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'handlers/refresh_token_handler.dart';
import 'handlers/retry_handler.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/refresh_token_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'network_config.dart';
import 'utils/network_constants.dart';

/// ApiClient is responsible for creating and configuring Dio HTTP clients.
@lazySingleton
class ApiClient {
  final NetworkConfig _config;

  ApiClient(this._config);

  /// Default base options for Dio.
  BaseOptions get _defaultOptions => BaseOptions(
    baseUrl: EnvConstants.BASE_URL,
    connectTimeout: NetworkConstants.CONNECT_TIMEOUT,
    receiveTimeout: NetworkConstants.RECEIVE_TIMEOUT,
    sendTimeout: NetworkConstants.SEND_TIMEOUT,
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
      dio.interceptors.add(
        AuthInterceptor(
          getToken: _config.getToken,
          getLocale: _config.getLocale,
        ),
      );

      // Renewing an expired session must happen before the retry pass,
      // otherwise a 401 would be replayed with the same stale token.
      // Only wired when the app supplies a refresh callback; without one a
      // 401 surfaces to the caller unchanged.
      final onRefreshToken = _config.onRefreshToken;
      if (onRefreshToken != null) {
        final onRefreshFailed = _config.onRefreshFailed;
        dio.interceptors.add(
          RefreshTokenInterceptor(
            RefreshTokenHandler(
              dio: dio,
              onRefreshToken: onRefreshToken,
              onRefreshFailed: onRefreshFailed ?? () async {},
            ),
          ),
        );
      }

      dio.interceptors.addAll([
        RetryInterceptor(
          handleRetry: retryHandler.handleRetry,
          retryWhen: retryHandler.retryWhen,
        ),
        LoggingInterceptor(tag: NetworkConstants.CLIENT_LOG_TAG),
      ]);
    }

    // Add custom interceptors if any
    if (interceptors != null) {
      dio.interceptors.addAll(interceptors);
    }

    return dio;
  }
}
