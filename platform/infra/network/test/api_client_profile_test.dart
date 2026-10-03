import 'dart:io';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show GetItHelper;
import 'package:platform_kernel/platform_kernel.dart';

/// K16: the timeouts, extra headers and redirect policy of the default `Dio`
/// are the app's `NetworkProfile`, and an empty profile is what `ApiClient`
/// did before an app could say anything.
void main() {
  Dio build([
    NetworkProfile profile = const NetworkProfile(),
    LocaleProfile locale = const LocaleProfile(),
  ]) => ApiClient(
    _Config(),
    profile,
    locale,
  ).createClient(baseUrl: 'https://example.test');

  group('the default profile is what ApiClient did before', () {
    test('20 seconds each for connect, receive and send', () {
      final options = build().options;

      expect(options.connectTimeout, const Duration(seconds: 20));
      expect(options.receiveTimeout, const Duration(seconds: 20));
      expect(options.sendTimeout, const Duration(seconds: 20));
    });

    test('redirects are not followed and the body is JSON', () {
      final options = build().options;

      expect(options.followRedirects, isFalse);
      expect(options.headers, {
        HttpHeaders.contentTypeHeader: ContentType.json.value,
      });
    });
  });

  group('an app value changes the client', () {
    test('the timeouts', () {
      final options = build(
        const NetworkProfile(
          connectTimeout: Duration(seconds: 5),
          receiveTimeout: Duration(seconds: 60),
          sendTimeout: Duration(seconds: 7),
        ),
      ).options;

      expect(options.connectTimeout, const Duration(seconds: 5));
      expect(options.receiveTimeout, const Duration(seconds: 60));
      expect(options.sendTimeout, const Duration(seconds: 7));
    });

    test('the extra headers join the JSON content type', () {
      final options = build(
        const NetworkProfile(headers: {'x-client': 'reports'}),
      ).options;

      expect(options.headers['x-client'], 'reports');
      expect(
        options.headers[HttpHeaders.contentTypeHeader],
        ContentType.json.value,
      );
    });

    test('following redirects', () {
      expect(
        build(const NetworkProfile(followRedirects: true))
            .options
            .followRedirects,
        isTrue,
      );
    });

    test('the language sent when the config supplies none', () {
      final dio = build(
        const NetworkProfile(),
        const LocaleProfile(fallback: 'vi'),
      );
      final auth = dio.interceptors.whereType<AuthInterceptor>().single;

      expect(auth.defaultLanguageCode, 'vi');
    });
  });

  test('a credential header is refused at construction (RULE-66)', () {
    expect(
      () => ApiClient(
        _Config(),
        const NetworkProfile(headers: {'Authorization': 'Bearer leaked'}),
      ),
      throwsArgumentError,
    );
  });

  test('the default Dio the core group builds carries the registered '
      'profile', () async {
    // The graph as `runShellApp` leaves it: the profile registered first, then
    // the package's own module — the way the `before` group builds `Dio`.
    addTearDown(getIt.reset);
    getIt
      ..registerSingleton<NetworkProfile>(
        const NetworkProfile(
          connectTimeout: Duration(seconds: 3),
          headers: {'x-client': 'reports'},
        ),
      )
      ..registerSingleton<LocaleProfile>(const LocaleProfile())
      ..registerSingleton<NetworkConfig>(_Config());

    await CoreNetworkPackageModule().init(GetItHelper(getIt));

    final options = getIt<Dio>().options;
    expect(options.connectTimeout, const Duration(seconds: 3));
    expect(options.headers['x-client'], 'reports');
    expect(options.receiveTimeout, const Duration(seconds: 20));
  });

  test('a bare graph — no profile registered, only the defaults the generated '
      'configureDependencies adds — still builds the default Dio', () async {
    addTearDown(getIt.reset);
    registerProfileDefaults();
    getIt.registerSingleton<NetworkConfig>(_Config());

    await CoreNetworkPackageModule().init(GetItHelper(getIt));

    final options = getIt<Dio>().options;
    expect(options.connectTimeout, const Duration(seconds: 20));
    expect(options.followRedirects, isFalse);
  });

  test('without the sections the graph fails on the first one it needs', () {
    addTearDown(getIt.reset);
    getIt.registerSingleton<NetworkConfig>(_Config());

    expect(() async {
      await CoreNetworkPackageModule().init(GetItHelper(getIt));
      getIt<Dio>();
    }, throwsStateError);
  });
}

class _Config implements NetworkConfig {
  @override
  String? Function() get getToken =>
      () => null;

  @override
  String? Function() get getLocale =>
      () => null;

  @override
  Future<String?> Function()? get onRefreshToken => null;

  @override
  Future<void> Function()? get onRefreshFailed => null;

  @override
  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  }) {}
}
