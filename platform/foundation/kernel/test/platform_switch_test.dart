import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

import 'support/profile_fixtures.dart';

void main() {
  tearDown(() async => getIt.reset());

  group('platformSwitchKey', () {
    test('without a registered profile it names the key generically', () {
      expect(
        platformSwitchKey('push'),
        'platforms.<platform>.push in the app manifest',
      );
    });

    test('names the platform, the key and the manifest of the app', () {
      registerAppProfile(mobileProfile(), platform: AppPlatform.ios);

      expect(
        platformSwitchKey('deep_links'),
        'platforms.ios.deep_links in apps/mobile/app_manifest.yaml',
      );
    });
  });
}
