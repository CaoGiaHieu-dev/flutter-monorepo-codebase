import 'dart:io';
import 'dart:typed_data';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// Records the `Authorization` header each host was sent.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.seen);

  final Map<String, Object?> seen;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen[options.uri.host] = options.headers[HttpHeaders.authorizationHeader];
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

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

        expect(options.headers['language'], equals('EN'));
      },
    );

    test('an empty locale also falls back to the default', () {
      final interceptor = AuthInterceptor(
        getToken: () => null,
        getLocale: () => '',
      );

      final options = RequestOptions(path: '/user');
      interceptor.onRequest(options, RequestInterceptorHandler());

      expect(
        options.headers['language'],
        const LocaleProfile().fallback.toUpperCase(),
      );
    });

    group('the bearer token goes only to the client\'s own API host', () {
      Map<String, dynamic> headersSentTo(
        String url, {
        String baseUrl = 'https://api.example.com/v1',
        Set<String> authorizedHosts = const {},
      }) {
        final interceptor = AuthInterceptor(
          getToken: () => 'SECRET',
          getLocale: () => 'en',
          authorizedHosts: authorizedHosts,
        );
        final options = RequestOptions(path: url, baseUrl: baseUrl);
        interceptor.onRequest(options, RequestInterceptorHandler());
        return options.headers;
      }

      test('a relative path resolves against the base URL: token attached', () {
        expect(
          headersSentTo('/me')[HttpHeaders.authorizationHeader],
          'Bearer SECRET',
        );
      });

      test('an absolute URL on the same host keeps the token, whatever the '
          'case', () {
        expect(
          headersSentTo(
            'https://API.example.com/other',
          )[HttpHeaders.authorizationHeader],
          'Bearer SECRET',
        );
      });

      test('an absolute URL to another host gets no token', () {
        final headers = headersSentTo('https://thirdparty.example/file.png');

        expect(headers[HttpHeaders.authorizationHeader], isNull);
        expect(
          headers['language'],
          'EN',
          reason: 'only the credential is held back',
        );
      });

      test('a look-alike host (suffix or sub-domain) is another host', () {
        for (final url in [
          'https://api.example.com.evil.test/x',
          'https://evilapi.example.com/x',
          'https://x.api.example.com/x',
        ]) {
          expect(
            headersSentTo(url)[HttpHeaders.authorizationHeader],
            isNull,
            reason: url,
          );
        }
      });

      test('https downgraded to http on the same host gets no token', () {
        expect(
          headersSentTo(
            'http://api.example.com/x',
          )[HttpHeaders.authorizationHeader],
          isNull,
        );
      });

      test('a host the app lists in authorizedHosts gets the token', () {
        expect(
          headersSentTo(
            'https://Files.Example.com/x',
            authorizedHosts: {'files.example.com'},
          )[HttpHeaders.authorizationHeader],
          'Bearer SECRET',
        );
        expect(
          headersSentTo(
            'https://other.example.com/x',
            authorizedHosts: {'files.example.com'},
          )[HttpHeaders.authorizationHeader],
          isNull,
        );
      });

      test('a 401 from a host that never saw the token cannot start a '
          'refresh', () {
        final interceptor = AuthInterceptor(
          getToken: () => 'SECRET',
          getLocale: () => 'en',
        );
        final options = RequestOptions(
          path: 'https://thirdparty.example/x',
          baseUrl: 'https://api.example.com',
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        expect(options.extra[NetworkConstants.EXTRA_CAN_REFRESH_TOKEN], false);
      });

      test('through a real Dio: the third-party request carries no '
          'Authorization on the wire', () async {
        final seen = <String, Object?>{};
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
          ..httpClientAdapter = _RecordingAdapter(seen)
          ..interceptors.add(
            AuthInterceptor(getToken: () => 'SECRET', getLocale: () => 'en'),
          );

        await dio.get<dynamic>('/me');
        expect(seen['api.example.com'], 'Bearer SECRET');

        await dio.get<dynamic>('https://thirdparty.example/file');
        expect(seen['thirdparty.example'], isNull);
        expect(seen.containsKey('thirdparty.example'), isTrue);
      });
    });
  });
}
