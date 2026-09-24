import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';

import '../utils/network_constants.dart';

/// Interceptor that adds headers to every request.
class AuthInterceptor extends Interceptor {
  /// Callback to get the current auth token.
  final String? Function() getToken;

  /// Callback to get the current language/locale code.
  final String? Function() getLocale;

  /// Default fallback language code.
  final String defaultLanguageCode;

  AuthInterceptor({
    required this.getToken,
    required this.getLocale,
    this.defaultLanguageCode = NetworkConstants.DEFAULT_LANGUAGE_CODE,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Get the language code from the callback.
    String? languageCode = getLocale();

    if (languageCode == null || languageCode.isEmpty) {
      // Get the language code of the device.
      languageCode = PlatformDispatcher.instance.locale.languageCode;
      // Default to Vietnamese if the locale is not Vietnamese or English.
      if (!NetworkConstants.SUPPORTED_LANGUAGE_CODES.contains(languageCode)) {
        languageCode = defaultLanguageCode;
      }
    }

    // Add the language code to the headers.
    options.headers.addAll({
      NetworkConstants.LANGUAGE_HEADER: languageCode.toUpperCase(),
    });

    // Get the extra request configuration from the options extra map.
    final needAuthentication =
        options.extra[NetworkConstants.EXTRA_NEED_AUTHENTICATION] as bool? ??
        true;

    // If the request requires authentication and the authentication token is not null,
    // add the authentication token to the headers.
    if (needAuthentication) {
      final token = getToken() ?? '';
      if (token.isNotEmpty) {
        options.headers.addAll({
          HttpHeaders.authorizationHeader:
              '${NetworkConstants.BEARER_PREFIX} $token',
        });
      }
    }

    // Continue the request.
    super.onRequest(options, handler);
  }
}
