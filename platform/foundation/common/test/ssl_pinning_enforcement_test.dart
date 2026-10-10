import 'dart:convert';
import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_security_pinning/http_security_pinning.dart';

/// A self-signed P-256 certificate (CN=pin.example.test, valid until 2126),
/// DER, base64 — the chain a host "presents" in these tests, in the form the
/// plugin's probe hands it to the pin check.
/// Made with `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1`.
const _certDerBase64 =
    'MIIBjDCCATOgAwIBAgIUa1BO5r9Lcj8gFL5u+N9xm8hgFqgwCgYIKoZIzj0EAwIwGzEZMBcGA1UEAwwQcGluLmV4YW1wbGUudGVzdDAgFw0yNjEwMDQwODUyMzRaGA8yMTI2MDkxMDA4NTIzNFowGzEZMBcGA1UEAwwQcGluLmV4YW1wbGUudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABHCnpCd4ts9Nc0evg4ZtFbpKfMPpT2Ntk+PEfs+RiOhE4jdLrWNdF0vDcS73eJt173JW0nVxlccyjWv2sbzrtMOjUzBRMB0GA1UdDgQWBBTUL523I6T8/yNXvsBz5h+eQ8UZvTAfBgNVHSMEGDAWgBTUL523I6T8/yNXvsBz5h+eQ8UZvTAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCICBhi55eWpk8+9EwTahVnUu9kNNR8ydCqsb8+2NQR0UiAiBU0C9c5ImepyG3GjdV0ab3dAtZncSFeEzwc5m1Hwtn/A==';

/// `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst
/// -sha256 -binary | base64` of the certificate above: the SPKI pin.
const _certPin = 'd+AvDlc63Q/jq0zPimPv+quotxt4ZC9J1iHcoFNwtT8=';

/// A second, unrelated self-signed P-256 certificate (CN=other.example.test,
/// valid until 2126), made the same way. Public data: its key was discarded.
const _otherCertDerBase64 =
    'MIIBkjCCATegAwIBAgIUWBp7ru4GAHVeiDtLJeDxvFFt5mEwCgYIKoZIzj0EAwIwHTEbMBkGA1UEAwwSb3RoZXIuZXhhbXBsZS50ZXN0MCAXDTI2MTAxMDExNDIzNFoYDzIxMjYwOTE2MTE0MjM0WjAdMRswGQYDVQQDDBJvdGhlci5leGFtcGxlLnRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARnQG8BrX53H6rPhjZTjzvoIeqaIJ043DjPbV7LELL34WGmBieNzjoxbAUePGP3pTJFodqcNNv9ytviCOVCv2Ndo1MwUTAdBgNVHQ4EFgQUkERBybKV2GOi+9Qxcf+Q+d034egwHwYDVR0jBBgwFoAUkERBybKV2GOi+9Qxcf+Q+d034egwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNJADBGAiEAxMjBUL+ZEVd9pdE5MhYcFGDYtyQG32PTANe3LRBrQNMCIQCS+5SIRnjxq9uqg8TTG5pJmCPLXtER/UDVXfHJdqRH2w==';

/// The SPKI pin of [_otherCertDerBase64], computed like [_certPin].
const _otherCertPin = 'lo/9FLMZSULZBJ5L5NZEjriKzk2m4kATEhJcoZBdN5g=';

/// Pins that are well formed (32 bytes, base64) and belong to no key here.
const _otherPin = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const _anotherPin = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=';

AppProfile _profile(SslPinning decision) => AppProfile(
  facts: AppFacts(
    id: 'enforce',
    name: 'Enforce',
    flavors: Flavor.values.toSet(),
    platforms: {
      for (final platform in AppPlatform.values)
        platform: const PlatformFacts.today(),
    },
    sslPinning: SslPinningPolicy({
      for (final flavor in Flavor.values) flavor: decision,
    }),
  ),
);

/// What the shell's certificate handling actually *does*, not only that an
/// override was installed: the accept-all bypass and the pinning client are
/// both "a new `HttpOverrides`", and a test that only checks for one cannot
/// tell them apart. Here the client the override creates is asked to open a
/// connection to a host whose chain — put where the plugin's own probe would
/// have left it, its chain cache — holds, or does not hold, a declared pin.
/// A refused connection after the pin check is the proof that it passed (the
/// pinned client dialled a closed loopback port); nothing is dialled for a
/// mismatch. No certificate server, no key material, no network.
void main() {
  late HttpOverrides? before;

  setUp(() {
    before = HttpOverrides.current;
    AppInitializer.debugResetBeforeRunApp();
    HttpSecurityPinningClient.clearCache();
  });

  tearDown(() {
    HttpOverrides.global = before;
    HttpSecurityPinningClient.clearCache();
    AppInitializer.debugResetBeforeRunApp();
  });

  /// Boots the shell's certificate handling and returns the client the app
  /// gets from `HttpClient()` afterwards, the way Dio and the image loaders do.
  HttpClient bootWith(
    SslPinning decision, {
    AppPlatform platform = AppPlatform.android,
  }) {
    AppInitializer.initBeforeRunApp(
      profile: _profile(decision),
      platform: platform,
      flavor: Flavor.prod,
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    return client;
  }

  /// A URL on [host] at a loopback port nothing listens on, with [chain]
  /// (DER, base64) already in the plugin's chain cache as the chain that host
  /// presents.
  Future<Uri> presents(String host, List<String> chain) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final url = Uri.parse('https://$host:$port/');
    await CertificateChainCache.shared.getOrFetch(
      CertificateChainCache.keyFor(url),
      () async => [for (final der in chain) base64.decode(der)],
    );
    return url;
  }

  /// What stopped a request to [url]; `null` when nothing did.
  Future<Object?> open(HttpClient client, Uri url) async {
    try {
      final request = await client.getUrl(url);
      await request.close();
      return null;
    } catch (error) {
      return error;
    }
  }

  test('a pinned decision installs the pinning client, not the accept-all '
      'bypass', () {
    final client = bootWith(const SslPinning.pinned(_certPin, _otherPin));

    expect(client, isA<HttpSecurityPinningClient>());
  });

  test('a host whose chain holds a declared pin passes the pin check', () async {
    final client = bootWith(const SslPinning.pinned(_otherPin, _certPin));
    final url = await presents('127.0.0.1', [_certDerBase64]);

    // The pin check passed and a real wrapped client dialled the closed port.
    // The recursion the package guards against would be a stack overflow here.
    expect(await open(client, url), isA<SocketException>());
  });

  test(
    'every declared hash counts, including the ones after the backup',
    () async {
      final client = bootWith(
        const SslPinning.pinned(_otherPin, _anotherPin, [_certPin]),
      );
      final url = await presents('127.0.0.1', [_certDerBase64]);

      expect(await open(client, url), isA<SocketException>());
    },
  );

  test('a host whose chain matches none of the declared pins is refused '
      'before any connection', () async {
    final client = bootWith(const SslPinning.pinned(_otherPin, _anotherPin));
    final url = await presents('127.0.0.1', [_certDerBase64]);

    final stopped = await open(client, url);

    // Not a `SocketException`: nothing was dialled.
    expect(stopped, isA<NoValidPinsFoundException>());
    final refused = stopped! as NoValidPinsFoundException;
    expect(refused.host, '127.0.0.1');
    expect(
      refused.observedPins,
      [_certPin],
      reason: 'the refusal names what the server presented',
    );
    expect(
      CertificateChainCache.shared.contains(CertificateChainCache.keyFor(url)),
      isFalse,
      reason: 'a refused chain is forgotten',
    );
  });

  test('the pins are checked for every host the client opens, not only the '
      'first', () async {
    final client = bootWith(const SslPinning.pinned(_certPin, _otherPin));
    final first = await presents('127.0.0.1', [_certDerBase64]);
    final second = await presents('localhost', [_otherCertDerBase64]);

    expect(await open(client, first), isA<SocketException>());
    // Same hashes, other host, other chain: judged on its own.
    final stopped = await open(client, second);
    expect(stopped, isA<NoValidPinsFoundException>());
    expect(
      (stopped! as NoValidPinsFoundException).observedPins,
      [_otherCertPin],
    );
  });

  test('every platform that can pin enforces the declared pins', () async {
    for (final platform in AppPlatform.values.where((p) => p.canPinTls)) {
      AppInitializer.debugResetBeforeRunApp();
      HttpSecurityPinningClient.clearCache();
      final client = bootWith(
        const SslPinning.pinned(_otherPin, _anotherPin),
        platform: platform,
      );
      final url = await presents('127.0.0.1', [_certDerBase64]);

      expect(
        await open(client, url),
        isA<NoValidPinsFoundException>(),
        reason: platform.name,
      );
    }
  });

  test('a disabled decision leaves the default client: no pinning client is '
      'installed', () {
    final client = bootWith(const SslPinning.disabled('test: no pins yet'));

    expect(client, isNot(isA<HttpSecurityPinningClient>()));
    expect(
      HttpOverrides.current,
      same(before),
      reason: 'nothing installed: neither pinning nor an accept-all bypass',
    );
  });
}
