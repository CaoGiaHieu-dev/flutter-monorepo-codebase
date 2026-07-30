import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';

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
    this.defaultLanguageCode = 'vi',
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Get the language code from the callback.
    String? languageCode = getLocale();

    if (languageCode == null || languageCode.isEmpty) {
      // Get the language code of the device.
      languageCode = PlatformDispatcher.instance.locale.languageCode;
      // Default to Vietnamese if the locale is not Vietnamese or English.
      if (languageCode != 'vi' && languageCode != 'en') {
        languageCode = defaultLanguageCode;
      }
    }

    // Add the language code to the headers.
    options.headers.addAll({'language': languageCode.toUpperCase()});

    // Get the extra request configuration from the options extra map.
    final needAuthentication =
        options.extra['needAuthentication'] as bool? ?? true;

    // If the request requires authentication and the authentication token is not null,
    // add the authentication token to the headers.
    if (needAuthentication) {
      final token = getToken() ?? '';
      if (token.isNotEmpty) {
        options.headers.addAll({
          HttpHeaders.authorizationHeader: 'Bearer $token',
        });
      }
    }

    // Continue the request.
    super.onRequest(options, handler);
  }
}
