import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pins implements SslPinningConfig {
  @override
  List<String> get sslPinningHashes => const [
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  ];
}

class _Sentinel extends HttpOverrides {}

/// `runShellApp` installs certificate pinning before the splash is built, so
/// `initBeforeRunApp` must do it synchronously — and `init`, which runs later
/// and calls it again, must not install a second override.
void main() {
  setUp(() async {
    await getIt.reset();
    AppInitializer.debugResetBeforeRunApp();
  });

  tearDown(() async {
    await getIt.reset();
    AppInitializer.debugResetBeforeRunApp();
  });

  test('installs the pinning HttpOverrides synchronously', () {
    getIt.registerSingleton<SslPinningConfig>(_Pins());
    final before = HttpOverrides.current;

    AppInitializer.initBeforeRunApp();

    expect(HttpOverrides.current, isNot(same(before)));
    expect(HttpOverrides.current, isNotNull);
  });

  test('is idempotent: a second call installs nothing', () {
    getIt.registerSingleton<SslPinningConfig>(_Pins());
    AppInitializer.initBeforeRunApp();

    final sentinel = _Sentinel();
    HttpOverrides.global = sentinel;
    AppInitializer.initBeforeRunApp();

    expect(HttpOverrides.current, same(sentinel));
  });

  test('leaves HttpOverrides alone without pins (logs instead)', () {
    final sentinel = _Sentinel();
    HttpOverrides.global = sentinel;

    AppInitializer.initBeforeRunApp();

    expect(HttpOverrides.current, same(sentinel));
  });
}
