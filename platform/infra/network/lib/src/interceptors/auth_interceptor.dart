import 'dart:io';

import 'package:dio/dio.dart';
import 'package:platform_kernel/platform_kernel.dart';

import '../utils/network_constants.dart';

/// Interceptor that adds headers to every request.
///
/// The `language` header goes to every request; the bearer token only to a
/// request whose host is the client's own (the host of its base URL) or one of
/// [authorizedHosts]. An absolute URL to anywhere else — a CDN, a presigned
/// storage link, a "next page" link a server handed back — carries no
/// credential: a token sent to a third party is a leak, and a presigned URL
/// is rejected when it arrives with a second authorisation.
class AuthInterceptor extends Interceptor {
  /// Callback to get the current auth token.
  final String? Function() getToken;

  /// Callback to get the current language/locale code.
  final String? Function() getLocale;

  /// Sent when [getLocale] supplies no language code: the app's
  /// `LocaleProfile.fallback`, or the template's own when none is given.
  final String defaultLanguageCode;

  /// Hosts besides the client's own base-URL host that receive the bearer
  /// token — the app's `NetworkProfile.authorizedHosts`. Compared
  /// case-insensitively, by host only (no scheme or port).
  final Set<String> authorizedHosts;

  AuthInterceptor({
    required this.getToken,
    required this.getLocale,
    String? defaultLanguageCode,
    Set<String> authorizedHosts = const {},
  }) : defaultLanguageCode =
           defaultLanguageCode ?? const LocaleProfile().fallback,
       authorizedHosts = {
         for (final host in authorizedHosts) host.toLowerCase(),
       };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // The app's `NetworkConfig` supplies an already-resolved, supported
    // code (the shell's resolves through `core_base_ui`'s `LanguageSet`).
    // The default covers a client built without one.
    final locale = getLocale();
    final languageCode = locale == null || locale.isEmpty
        ? defaultLanguageCode
        : locale;

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
      if (_isTrustedHost(options)) {
        final token = getToken() ?? '';
        if (token.isNotEmpty) {
          options.headers.addAll({
            HttpHeaders.authorizationHeader:
                '${NetworkConstants.BEARER_PREFIX} $token',
          });
        }
      } else {
        // A `401` from a host that never saw the token says nothing about the
        // session: it must not start a refresh, and a refresh that fails
        // would sign the user out over somebody else's server.
        options.extra[NetworkConstants.EXTRA_CAN_REFRESH_TOKEN] = false;
      }
    }

    // Continue the request.
    super.onRequest(options, handler);
  }

  /// Whether [options] is addressed to the client's own API host — the one in
  /// its base URL — or to one of [authorizedHosts].
  ///
  /// A relative path resolves against the base URL, so it is always the
  /// client's own. An absolute URL is compared to it; `https` → `http` on the
  /// same host is a downgrade that would send the token in clear, so the
  /// scheme must not be weaker than the base URL's.
  bool _isTrustedHost(RequestOptions options) {
    final target = options.uri;
    final host = target.host.toLowerCase();
    if (authorizedHosts.contains(host)) return true;

    final base = Uri.tryParse(options.baseUrl);
    if (base == null) return false;
    if (host != base.host.toLowerCase()) return false;
    return !(base.scheme == 'https' && target.scheme != 'https');
  }
}
