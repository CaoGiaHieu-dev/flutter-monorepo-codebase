import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';

import 'error/dio_failure_classifier.dart';
import 'handlers/refresh_token_handler.dart';
import 'handlers/retry_handler.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/refresh_token_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'network_config.dart';
import 'utils/network_constants.dart';

/// ApiClient is responsible for creating and configuring Dio HTTP clients.
///
/// What an app tunes comes from its [NetworkProfile] (timeouts, extra headers,
/// redirects) and [LocaleProfile] (the language sent when the config supplies
/// none) — `runShellApp` registers both before the graph is built, so the
/// default `Dio` the `core` group builds already carries them. The `const`
/// defaults of the constructor serve a client built by hand only: injectable
/// resolves both sections unconditionally, so a graph needs them registered
/// (`registerAppProfile`, or `registerProfileDefaults` for the template's own
/// values — the generated `configureDependencies` calls the latter).
@lazySingleton
class ApiClient {
  final NetworkConfig _config;
  final NetworkProfile _profile;
  final LocaleProfile _locale;

  ApiClient(
    this._config, [
    this._profile = const NetworkProfile(),
    this._locale = const LocaleProfile(),
  ]) {
    final refused = _profile.refusedHeaders;
    if (refused.isNotEmpty) {
      throw ArgumentError.value(
        refused.join(', '),
        'NetworkProfile.headers',
        'a credential or shell-owned header cannot be set by the app '
            '(RULE-66); the session owner supplies Authorization',
      );
    }
    // Already registered by DI (the classifier is an eager singleton of this
    // package's module); repeated here, idempotently, for a client built
    // outside DI, whose DioExceptions must still classify.
    DioFailureClassifier.ensureRegistered();
  }

  /// Default base options for Dio.
  BaseOptions get _defaultOptions => BaseOptions(
    baseUrl: EnvConstants.BASE_URL,
    connectTimeout: _profile.connectTimeout,
    receiveTimeout: _profile.receiveTimeout,
    sendTimeout: _profile.sendTimeout,
    followRedirects: _profile.followRedirects,
    headers: {
      ..._profile.headers,
      HttpHeaders.contentTypeHeader: ContentType.json.value,
    },
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
        dio,
        onRetryCallback: _config.onRetryCallback,
      );
      dio.interceptors.add(
        AuthInterceptor(
          getToken: _config.getToken,
          getLocale: _config.getLocale,
          defaultLanguageCode: _locale.fallback,
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
              currentToken: _config.getToken,
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
