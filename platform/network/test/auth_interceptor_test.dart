import 'dart:io';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthInterceptor', () {
    late String? mockToken;
    late String? mockLocale;

    setUp(() {
      mockToken = 'test_jwt_token';
      mockLocale = 'vi';
    });

    test(
      'should add Bearer token to authorization header by default',
      () async {
        final interceptor = AuthInterceptor(
          getToken: () => mockToken,
          getLocale: () => mockLocale,
        );

        final dio = Dio();
        dio.interceptors.add(interceptor);

        // Create a mock RequestOptions
        final options = RequestOptions(path: '/user');
        final handler = RequestInterceptorHandler();

        interceptor.onRequest(options, handler);

        expect(
          options.headers[HttpHeaders.authorizationHeader],
          equals('Bearer test_jwt_token'),
        );
        expect(options.headers['language'], equals('VI'));
      },
    );

    test(
      'should NOT add Bearer token when needAuthentication is false',
      () async {
        final interceptor = AuthInterceptor(
          getToken: () => mockToken,
          getLocale: () => mockLocale,
        );

        final options = RequestOptions(
          path: '/public',
          extra: {'needAuthentication': false},
        );
        final handler = RequestInterceptorHandler();

        interceptor.onRequest(options, handler);

        expect(options.headers[HttpHeaders.authorizationHeader], isNull);
        expect(options.headers['language'], equals('VI'));
      },
    );

    test(
      'should fallback to default language code when getLocale returns null',
      () async {
        final interceptor = AuthInterceptor(
          getToken: () => mockToken,
          getLocale: () => null,
          defaultLanguageCode: 'en',
        );

        final options = RequestOptions(path: '/user');
        final handler = RequestInterceptorHandler();

        interceptor.onRequest(options, handler);

        // Should capitalized language header
        expect(options.headers['language'], isNotNull);
      },
    );
  });
}
