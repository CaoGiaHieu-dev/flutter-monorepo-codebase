import 'dart:convert';
import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_security_pinning/http_security_pinning.dart';

/// A self-signed P-256 certificate (CN=pin.example.test, valid until 2126),
/// DER, base64 — what the pinning plugin's native side hands back for a host.
/// Made with `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1`.
const _certDerBase64 =
    'MIIBjDCCATOgAwIBAgIUa1BO5r9Lcj8gFL5u+N9xm8hgFqgwCgYIKoZIzj0EAwIwGzEZMBcGA1UEAwwQcGluLmV4YW1wbGUudGVzdDAgFw0yNjEwMDQwODUyMzRaGA8yMTI2MDkxMDA4NTIzNFowGzEZMBcGA1UEAwwQcGluLmV4YW1wbGUudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABHCnpCd4ts9Nc0evg4ZtFbpKfMPpT2Ntk+PEfs+RiOhE4jdLrWNdF0vDcS73eJt173JW0nVxlccyjWv2sbzrtMOjUzBRMB0GA1UdDgQWBBTUL523I6T8/yNXvsBz5h+eQ8UZvTAfBgNVHSMEGDAWgBTUL523I6T8/yNXvsBz5h+eQ8UZvTAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCICBhi55eWpk8+9EwTahVnUu9kNNR8ydCqsb8+2NQR0UiAiBU0C9c5ImepyG3GjdV0ab3dAtZncSFeEzwc5m1Hwtn/A==';

/// `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst
/// -sha256 -binary | base64` of the certificate above: the SPKI pin.
const _certPin = 'd+AvDlc63Q/jq0zPimPv+quotxt4ZC9J1iHcoFNwtT8=';

/// Pins that are well formed (32 bytes, base64) and belong to no key here.
const _otherPin = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const _anotherPin = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=';

const _channel = MethodChannel('http_security_pinning');

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
/// connection to a host whose certificate chain (served by a faked native
/// side) holds, or does not hold, one of the declared pins.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> fetchedFor;
  late HttpOverrides? before;

  setUp(() async {
    before = HttpOverrides.current;
    await getIt.reset();
    AppInitializer.debugResetBeforeRunApp();
    HttpSecurityPinningClient.clearCache();
    fetchedFor = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          expect(call.method, 'fetchHostCertificates');
          final arguments = call.arguments as Map<Object?, Object?>;
          fetchedFor.add(Uri.parse(arguments['url']! as String).host);
          return [base64.decode(_certDerBase64)];
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    HttpOverrides.global = before;
    HttpSecurityPinningClient.clearCache();
    await getIt.reset();
    AppInitializer.debugResetBeforeRunApp();
  });

  HttpClient bootWith(SslPinning decision) {
    AppInitializer.initBeforeRunApp(
      profile: _profile(decision),
      platform: AppPlatform.android,
      flavor: Flavor.prod,
    );
    return HttpOverrides.current!.createHttpClient(null);
  }

  /// Opens a request to [host]; returns what stopped it, `null` when nothing
  /// did. Only the pinning check is under test: a connection that then fails
  /// (the host is not real) is not a pinning failure.
  Future<Object?> open(HttpClient client, String host) async {
    try {
      final request = await client.getUrl(Uri.parse('https://$host/'));
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

  test(
    'a host whose chain holds a declared pin passes the pin check',
    () async {
      final client = bootWith(const SslPinning.pinned(_otherPin, _certPin));

      final stopped = await open(client, 'match.example.test');

      expect(fetchedFor, ['match.example.test'], reason: 'the chain was read');
      expect(stopped, isNot(isA<CertificatePinningException>()));
    },
  );

  test(
    'every declared hash counts, including the ones after the backup',
    () async {
      final client = bootWith(
        const SslPinning.pinned(_otherPin, _anotherPin, [_certPin]),
      );

      final stopped = await open(client, 'more.example.test');

      expect(stopped, isNot(isA<CertificatePinningException>()));
    },
  );

  test('a host whose chain matches none of the declared pins is refused '
      'before any request is sent', () async {
    final client = bootWith(const SslPinning.pinned(_otherPin, _anotherPin));

    final stopped = await open(client, 'mismatch.example.test');

    expect(fetchedFor, ['mismatch.example.test']);
    expect(stopped, isA<NoValidPinsFoundException>());
    expect(
      (stopped! as NoValidPinsFoundException).host,
      'mismatch.example.test',
    );
  });

  test('the pins are checked for every host the client opens, not only the '
      'first', () async {
    final client = bootWith(const SslPinning.pinned(_certPin, _otherPin));

    expect(
      await open(client, 'first.example.test'),
      isNot(isA<CertificatePinningException>()),
    );
    // Same hashes, other host: its chain is read and judged on its own.
    expect(
      await open(client, 'second.example.test'),
      isNot(isA<CertificatePinningException>()),
    );
    expect(fetchedFor, ['first.example.test', 'second.example.test']);
  });

  test('a disabled decision leaves the default client: no pinning client is '
      'installed, nothing reads a chain', () async {
    final client = bootWith(const SslPinning.disabled('test: no pins yet'));

    expect(client, isNot(isA<HttpSecurityPinningClient>()));
    expect(fetchedFor, isEmpty);
  });
}
