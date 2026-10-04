import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_security_pinning/http_security_pinning.dart';

class _Sentinel extends HttpOverrides {}

const _pinned = SslPinning.pinned(
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
);

AppProfile _profile({required SslPinning? decision}) => AppProfile(
  facts: AppFacts(
    id: 'overrides',
    name: 'Overrides',
    flavors: Flavor.values.toSet(),
    platforms: {
      for (final platform in AppPlatform.values)
        platform: const PlatformFacts.today(),
    },
    sslPinning: SslPinningPolicy({
      if (decision != null)
        for (final flavor in Flavor.values) flavor: decision,
    }),
  ),
);

/// `runShellApp` installs certificate pinning before dependency injection
/// starts, so `initBeforeRunApp` must do it synchronously, from the profile
/// alone — and `init`, which runs later and calls it again, must not install
/// a second override.
void main() {
  setUp(() async {
    await getIt.reset();
    AppInitializer.debugResetBeforeRunApp();
  });

  tearDown(() async {
    HttpOverrides.global = null;
    await getIt.reset();
    AppInitializer.debugResetBeforeRunApp();
  });

  test('installs the pinning HttpOverrides synchronously', () {
    final before = HttpOverrides.current;

    AppInitializer.initBeforeRunApp(
      profile: _profile(decision: _pinned),
      platform: AppPlatform.android,
      flavor: Flavor.prod,
    );

    expect(HttpOverrides.current, isNot(same(before)));
    expect(
      HttpOverrides.current?.createHttpClient(null),
      isA<HttpSecurityPinningClient>(),
      reason: 'a new override is not enough: the accept-all bypass is one too',
    );
  });

  test('is idempotent: a second call installs nothing', () {
    final profile = _profile(decision: _pinned);
    AppInitializer.initBeforeRunApp(
      profile: profile,
      platform: AppPlatform.android,
      flavor: Flavor.prod,
    );

    final sentinel = _Sentinel();
    HttpOverrides.global = sentinel;
    AppInitializer.initBeforeRunApp(
      profile: profile,
      platform: AppPlatform.android,
      flavor: Flavor.prod,
    );

    expect(HttpOverrides.current, same(sentinel));
  });

  test('leaves HttpOverrides alone without a pin decision (logs instead)', () {
    final sentinel = _Sentinel();
    HttpOverrides.global = sentinel;

    AppInitializer.initBeforeRunApp(
      profile: _profile(decision: null),
      platform: AppPlatform.android,
      flavor: Flavor.prod,
    );

    expect(HttpOverrides.current, same(sentinel));
  });

  test('installs nothing on the web, even with pins declared', () {
    final sentinel = _Sentinel();
    HttpOverrides.global = sentinel;

    AppInitializer.initBeforeRunApp(
      profile: _profile(decision: _pinned),
      platform: AppPlatform.web,
      flavor: Flavor.prod,
    );

    expect(HttpOverrides.current, same(sentinel));
  });
}
