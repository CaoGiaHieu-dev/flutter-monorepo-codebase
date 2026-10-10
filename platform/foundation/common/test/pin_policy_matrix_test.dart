import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_security_pinning/http_security_pinning.dart';

class _Sentinel extends HttpOverrides {}

const _leaf = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const _backup = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const _reason = 'TEMPLATE PLACEHOLDER: no SPKI pins provisioned';

/// What an app's pinning decision for one flavor does at boot, on every
/// platform: `AppInitializer.initBeforeRunApp(profile:, platform:, flavor:)`.
///
/// The decision is the app's (`flavors.<f>.ssl_pinning` in its manifest); the
/// platform decides whether it can apply at all (`AppPlatform.canPinTls`):
///
/// - web: the browser owns TLS — INFO, nothing installed;
/// - every other platform (android, ios, windows, macos, linux): `pinned`
///   installs the pinning client, `disabled` logs its declared reason as a
///   WARNING, and no decision at all is an ERROR.
void main() {
  late List<({int level, String message})> logged;
  late HttpOverrides sentinel;

  setUp(() async {
    await getIt.reset();
    AppInitializer.debugResetBeforeRunApp();
    logged = [];
    DynamicLogger.configure(
      logHandler: (
        message, {
        error,
        level = 0,
        name = '',
        sequenceNumber,
        stackTrace,
        time,
        zone,
      }) => logged.add((level: level, message: message)),
    );
    sentinel = _Sentinel();
    HttpOverrides.global = sentinel;
  });

  tearDown(() async {
    HttpOverrides.global = null;
    DynamicLogger.reset();
    await getIt.reset();
    AppInitializer.debugResetBeforeRunApp();
  });

  AppProfile profileWith(SslPinning? decision) => AppProfile(
    facts: AppFacts(
      id: 'matrix',
      name: 'Matrix',
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

  void boot(SslPinning? decision, AppPlatform platform, Flavor flavor) {
    AppInitializer.initBeforeRunApp(
      profile: profileWith(decision),
      platform: platform,
      flavor: flavor,
    );
  }

  bool logsAt(int level, Pattern text) =>
      logged.any((l) => l.level == level && l.message.contains(text));

  /// Whether the client the global overrides hand out *is* the pinning
  /// client. "Not the sentinel" would also be true of the accept-all bypass
  /// the dev flavor installs, which is the opposite of pinning.
  bool installedPinning() =>
      HttpOverrides.current?.createHttpClient(null)
          is HttpSecurityPinningClient;

  const info = 700;
  const warning = 900;
  const error = 1000;

  const pinned = SslPinning.pinned(_leaf, _backup);
  const disabled = SslPinning.disabled(_reason);

  for (final flavor in Flavor.values) {
    group('flavor ${flavor.name}', () {
      for (final platform in AppPlatform.values) {
        final decisions = <String, SslPinning?>{
          'pinned': pinned,
          'disabled': disabled,
          'undecided': null,
        };
        for (final entry in decisions.entries) {
          final label = '${platform.name} x ${entry.key}';

          if (platform == AppPlatform.web) {
            test('$label: the browser owns TLS, nothing is installed', () {
              boot(entry.value, platform, flavor);

              expect(installedPinning(), isFalse);
              expect(
                HttpOverrides.current,
                same(sentinel),
                reason: 'nothing installed: neither pinning nor a bypass',
              );
              expect(logsAt(info, 'browser validates TLS'), isTrue);
              expect(logsAt(error, 'NOT pinned'), isFalse);
            });
          } else if (entry.key == 'pinned') {
            test('$label: installs the pinning client', () {
              boot(entry.value, platform, flavor);

              expect(installedPinning(), isTrue);
              expect(logsAt(error, 'NOT pinned'), isFalse);
              expect(logsAt(warning, 'NOT pinned'), isFalse);
            });
          } else if (entry.key == 'disabled') {
            test('$label: installs nothing and logs the declared reason', () {
              boot(entry.value, platform, flavor);

              expect(installedPinning(), isFalse);
              expect(
                HttpOverrides.current,
                same(sentinel),
                reason: 'a disabled decision installs nothing: TLS stays on',
              );
              expect(logsAt(warning, _reason), isTrue);
              expect(logsAt(warning, 'flavor ${flavor.name}'), isTrue);
            });
          } else {
            test('$label: no decision is an ERROR naming the manifest key', () {
              boot(entry.value, platform, flavor);

              expect(installedPinning(), isFalse);
              expect(
                HttpOverrides.current,
                same(sentinel),
                reason: 'no decision installs nothing: TLS stays on',
              );
              expect(
                logsAt(error, 'flavors.${flavor.name}.ssl_pinning'),
                isTrue,
              );
            });
          }
        }
      }
    });
  }

  test('the web is the only platform where pinning cannot apply', () {
    expect(
      AppPlatform.values.where((p) => !p.canPinTls),
      [AppPlatform.web],
    );
  });

  test('only the current flavor decides: another flavor pinned changes '
      'nothing', () {
    AppInitializer.initBeforeRunApp(
      profile: AppProfile(
        facts: AppFacts(
          id: 'matrix',
          name: 'Matrix',
          flavors: Flavor.values.toSet(),
          platforms: {
            AppPlatform.android: const PlatformFacts.today(),
          },
          sslPinning: const SslPinningPolicy({
            Flavor.dev: disabled,
            Flavor.prod: pinned,
          }),
        ),
      ),
      platform: AppPlatform.android,
      flavor: Flavor.dev,
    );

    expect(installedPinning(), isFalse);
    expect(logsAt(warning, _reason), isTrue);
  });

  test('reads only the profile: with nothing registered in DI, a pinned '
      'decision is still installed', () {
    expect(getIt.isRegistered<AppProfile>(), isFalse);

    boot(pinned, AppPlatform.android, Flavor.prod);

    expect(installedPinning(), isTrue);
    expect(logsAt(error, 'NOT pinned'), isFalse);
  });
}
