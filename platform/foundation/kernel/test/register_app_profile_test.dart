import 'package:get_it/get_it.dart';
import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

import 'support/profile_fixtures.dart';

void main() {
  late GetIt locator;

  setUp(() => locator = GetIt.asNewInstance());
  tearDown(() => locator.reset());

  group('registerAppProfile', () {
    test(
      'registers the profile, the platform, its facts and the pin policy',
      () {
        final profile = mobileProfile();

        registerAppProfile(
          profile,
          platform: AppPlatform.ios,
          locator: locator,
        );

        expect(locator<AppProfile>(), same(profile));
        expect(locator<AppPlatform>(), AppPlatform.ios);
        expect(locator<PlatformFacts>(), same(iosFacts));
        expect(locator<SslPinningPolicy>(), same(profile.facts.sslPinning));
        expect(locator<RouterProfile>(), same(profile.router));
      },
    );

    test('each section is bound under its own exact type', () {
      registerAppProfile(
        mobileProfile(),
        platform: AppPlatform.android,
        locator: locator,
      );

      expect(locator.isRegistered<AppProfile>(), isTrue);
      expect(locator.isRegistered<AppPlatform>(), isTrue);
      expect(locator.isRegistered<PlatformFacts>(), isTrue);
      expect(locator.isRegistered<SslPinningPolicy>(), isTrue);
      expect(locator.isRegistered<RouterProfile>(), isTrue);
      // Nothing else is bound: the facts are read through the profile, and a
      // section a class is not DI-built for (`DisplayProfile`) is handed to
      // it by `runShellApp`.
      expect(locator.isRegistered<AppFacts>(), isFalse);
      expect(locator.isRegistered<DisplayProfile>(), isFalse);
    });

    test('is idempotent: the same profile twice changes nothing', () {
      final profile = mobileProfile();

      registerAppProfile(
        profile,
        platform: AppPlatform.android,
        locator: locator,
      );
      final first = locator<PlatformFacts>();
      registerAppProfile(
        profile,
        platform: AppPlatform.android,
        locator: locator,
      );

      expect(locator<AppProfile>(), same(profile));
      expect(locator<PlatformFacts>(), same(first));
      expect(locator.getAll<AppProfile>(), hasLength(1));
    });

    test('a different profile replaces the earlier registration', () {
      final first = mobileProfile();
      final second = mobileProfile(
        platforms: const {AppPlatform.linux: linuxFacts},
      );

      registerAppProfile(first, platform: AppPlatform.ios, locator: locator);
      registerAppProfile(
        second,
        platform: AppPlatform.linux,
        locator: locator,
      );

      expect(locator<AppProfile>(), same(second));
      expect(locator<PlatformFacts>(), same(linuxFacts));
      expect(locator<SslPinningPolicy>(), same(second.facts.sslPinning));
    });

    test('the same profile on another platform swaps only the facts', () {
      final profile = mobileProfile();

      registerAppProfile(
        profile,
        platform: AppPlatform.android,
        locator: locator,
      );
      registerAppProfile(profile, platform: AppPlatform.ios, locator: locator);

      expect(locator<AppProfile>(), same(profile));
      expect(locator<PlatformFacts>(), same(iosFacts));
    });

    test('an undeclared platform is a StateError that names the fix', () {
      expect(
        () => registerAppProfile(
          mobileProfile(),
          platform: AppPlatform.linux,
          locator: locator,
          allowUndeclaredPlatform: false,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('mobile'),
              contains('linux'),
              contains('apps/mobile/app_manifest.yaml'),
            ),
          ),
        ),
      );
      expect(locator.isRegistered<AppProfile>(), isFalse);
    });

    test('allowUndeclaredPlatform registers the template behaviour', () {
      final profile = mobileProfile();

      registerAppProfile(
        profile,
        platform: AppPlatform.linux,
        locator: locator,
        allowUndeclaredPlatform: true,
      );

      final facts = locator<PlatformFacts>();
      expect(facts.splash, SplashMode.dart);
      expect(facts.deepLinks, isTrue);
      expect(facts.push, isTrue);
      expect(locator<AppProfile>(), same(profile));
    });

    test('without the define, an undeclared platform is refused', () {
      expect(ProfileConstants.ALLOW_UNDECLARED_PLATFORM, isFalse);
      expect(
        () => registerAppProfile(
          mobileProfile(),
          platform: AppPlatform.web,
          locator: locator,
        ),
        throwsStateError,
      );
    });

    test('registers into the global getIt when no locator is given', () {
      addTearDown(getIt.reset);
      final profile = mobileProfile();

      registerAppProfile(profile, platform: AppPlatform.android);

      expect(getIt<AppProfile>(), same(profile));
    });

    test('a section registered before enabling multiple instances wins', () {
      // The shell registers the profile before the generated
      // `configureDependencies`, which then calls
      // `enableRegisteringMultipleInstancesOfOneType()`.
      final profile = mobileProfile();
      registerAppProfile(
        profile,
        platform: AppPlatform.android,
        locator: locator,
      );
      locator
        ..enableRegisteringMultipleInstancesOfOneType()
        ..registerSingleton<AppProfile>(mobileProfile());

      expect(locator<AppProfile>(), same(profile));
    });
  });
}
