import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

import 'support/profile_fixtures.dart';

List<String> _codes(List<ProfileProblem> problems) =>
    problems.map((p) => p.code).toList();

void main() {
  group('AppPlatform', () {
    test('only android and ios can pin TLS', () {
      expect(
        AppPlatform.values.where((p) => p.canPinTls),
        [AppPlatform.android, AppPlatform.ios],
      );
    });

    test('windows, macos and linux are the desktop platforms', () {
      expect(
        AppPlatform.values.where((p) => p.isDesktop),
        [AppPlatform.windows, AppPlatform.macos, AppPlatform.linux],
      );
    });
  });

  group('PlatformFacts.today', () {
    test('is the behaviour the template had before apps declared anything', () {
      const today = PlatformFacts.today();
      expect(today.splash, SplashMode.dart);
      expect(today.orientation, OrientationPolicy.phonesPortrait);
      expect(today.deepLinks, isTrue);
      expect(today.push, isTrue);
      expect(today.window, isNull);
    });
  });

  group('AppFacts.platformFor', () {
    test('returns the declared platform and null for the others', () {
      final facts = mobileFacts();
      expect(facts.platformFor(AppPlatform.android), same(androidFacts));
      expect(facts.platformFor(AppPlatform.linux), isNull);
    });
  });

  group('AppProfile.validate', () {
    test('a declared platform and flavor with nothing wrong is clean', () {
      expect(
        mobileProfile().validate(
          platform: AppPlatform.android,
          flavor: Flavor.prod,
        ),
        isEmpty,
      );
    });

    group('P01 platform not declared', () {
      test('names the app, the platform and what is declared', () {
        final problems = mobileProfile().validate(
          platform: AppPlatform.linux,
          flavor: Flavor.dev,
        );

        expect(_codes(problems), ['P01']);
        expect(problems.single.description, contains('`mobile`'));
        expect(problems.single.description, contains('linux'));
        expect(problems.single.description, contains('declared: android, ios'));
        expect(
          problems.single.action,
          allOf(
            contains('apps/mobile/app_manifest.yaml'),
            contains('dart tools/composer/composer.dart sync --app mobile'),
            contains('ALLOW_UNDECLARED_PLATFORM=true'),
          ),
        );
      });

      test('does not add a second problem about the same platform', () {
        // linux cannot pin and would otherwise be inspected for a window.
        final profile = mobileProfile(
          sslPinning: const SslPinningPolicy.none(),
        );
        expect(
          _codes(
            profile.validate(platform: AppPlatform.ios, flavor: Flavor.dev),
          ),
          ['P04'],
        );
        expect(
          _codes(
            profile.validate(platform: AppPlatform.macos, flavor: Flavor.dev),
          ),
          ['P01'],
        );
      });
    });

    group('P02 flavor not declared', () {
      test('names the flavor and what is declared', () {
        final problems = mobileProfile(
          flavors: const {Flavor.dev, Flavor.prod},
        ).validate(platform: AppPlatform.android, flavor: Flavor.staging);

        expect(_codes(problems), ['P02']);
        expect(problems.single.description, contains('`staging`'));
        expect(problems.single.description, contains('declared: dev, prod'));
        expect(problems.single.action, contains('apps/mobile/app_manifest'));
      });

      test('skips the flavor-keyed checks', () {
        final profile = mobileProfile(
          flavors: const {Flavor.dev},
          sslPinning: const SslPinningPolicy.none(),
          env: const [
            EnvRule(
              key: 'BASE_URL',
              value: '',
              requiredIn: {Flavor.staging},
            ),
          ],
        );
        expect(
          _codes(
            profile.validate(
              platform: AppPlatform.android,
              flavor: Flavor.staging,
            ),
          ),
          ['P02'],
        );
      });
    });

    group('P03 required env key empty', () {
      const rules = [
        EnvRule(key: 'BASE_URL', value: '', requiredIn: {Flavor.prod}),
        EnvRule(
          key: 'APP_NAME',
          value: 'Codebase',
          requiredIn: {Flavor.staging, Flavor.prod},
        ),
        EnvRule(key: 'WEB_DOMAIN', value: ''),
      ];

      test('an empty key required in this flavor is a problem', () {
        final problems = mobileProfile(env: rules).validate(
          platform: AppPlatform.android,
          flavor: Flavor.prod,
        );

        expect(_codes(problems), ['P03']);
        expect(problems.single.description, contains('`BASE_URL`'));
        expect(problems.single.description, contains('`prod`'));
        expect(problems.single.action, contains('BASE_URL=<value>'));
      });

      test('a key required only in another flavor is not', () {
        expect(
          mobileProfile(env: rules).validate(
            platform: AppPlatform.android,
            flavor: Flavor.dev,
          ),
          isEmpty,
        );
      });

      test('checkEnv: false skips it', () {
        expect(
          mobileProfile(env: rules).validate(
            platform: AppPlatform.android,
            flavor: Flavor.prod,
            checkEnv: false,
          ),
          isEmpty,
        );
      });

      test('each empty key is its own problem', () {
        final problems = mobileProfile(
          env: const [
            EnvRule(key: 'BASE_URL', value: '', requiredIn: {Flavor.prod}),
            EnvRule(key: 'APP_NAME', value: '', requiredIn: {Flavor.prod}),
          ],
        ).validate(platform: AppPlatform.android, flavor: Flavor.prod);

        expect(_codes(problems), ['P03', 'P03']);
      });
    });

    group('P04 no pin decision where the platform can pin', () {
      final undecided = mobileProfile(
        sslPinning: const SslPinningPolicy({
          Flavor.dev: SslPinning.disabled('development flavor'),
        }),
      );

      test('flavor without a decision on android and ios', () {
        for (final platform in [AppPlatform.android, AppPlatform.ios]) {
          final problems = undecided.validate(
            platform: platform,
            flavor: Flavor.prod,
          );
          expect(_codes(problems), ['P04'], reason: platform.name);
          expect(problems.single.action, contains('flavors.prod.ssl_pinning'));
          expect(problems.single.action, contains('disabled: "<reason>"'));
        }
      });

      test('a flavor with a decision is clean', () {
        expect(
          undecided.validate(platform: AppPlatform.android, flavor: Flavor.dev),
          isEmpty,
        );
      });

      test('a platform that cannot pin needs no decision', () {
        final profile = mobileProfile(
          platforms: const {AppPlatform.linux: linuxFacts},
          sslPinning: const SslPinningPolicy.none(),
        );
        expect(
          profile.validate(platform: AppPlatform.linux, flavor: Flavor.prod),
          isEmpty,
        );
      });

      test('pinned counts as a decision', () {
        final pinned = mobileProfile(
          sslPinning: const SslPinningPolicy({
            Flavor.prod: SslPinning.pinned('leaf', 'backup'),
          }),
        );
        expect(
          pinned.validate(platform: AppPlatform.ios, flavor: Flavor.prod),
          isEmpty,
        );
      });
    });

    group('P05 window declared with no hook', () {
      const windowed = PlatformFacts(
        runner: RunnerKind.scaffold,
        splash: SplashMode.native,
        orientation: OrientationPolicy.free,
        deepLinks: true,
        push: false,
        window: WindowFacts(
          initial: SizeSpec(1280, 800),
          min: SizeSpec(800, 600),
        ),
      );
      final profile = mobileProfile(
        platforms: const {
          AppPlatform.linux: windowed,
          AppPlatform.windows: linuxFacts,
        },
      );

      test('is a problem without a hook', () {
        final problems = profile.validate(
          platform: AppPlatform.linux,
          flavor: Flavor.dev,
        );

        expect(_codes(problems), ['P05']);
        expect(problems.single.description, contains('linux'));
        expect(problems.single.action, contains('platforms.linux'));
      });

      test('is satisfied by a hook', () {
        expect(
          profile.validate(
            platform: AppPlatform.linux,
            flavor: Flavor.dev,
            hasWindowHook: true,
          ),
          isEmpty,
        );
      });

      test('a platform with no window needs no hook', () {
        expect(
          profile.validate(platform: AppPlatform.windows, flavor: Flavor.dev),
          isEmpty,
        );
      });
    });

    test('independent problems are all reported, in code order', () {
      final profile = mobileProfile(
        sslPinning: const SslPinningPolicy.none(),
        env: const [
          EnvRule(key: 'BASE_URL', value: '', requiredIn: {Flavor.prod}),
        ],
      );

      expect(
        _codes(
          profile.validate(platform: AppPlatform.android, flavor: Flavor.prod),
        ),
        ['P03', 'P04'],
      );
    });

    test('an app that declares nothing says so', () {
      const profile = AppProfile(
        facts: AppFacts(
          id: 'empty',
          name: 'Empty',
          flavors: {},
          platforms: {},
          sslPinning: SslPinningPolicy.none(),
        ),
      );

      final problems = profile.validate(
        platform: AppPlatform.android,
        flavor: Flavor.dev,
      );
      expect(_codes(problems), ['P01', 'P02']);
      expect(problems.first.description, contains('declared: none'));
    });
  });

  group('ProfileProblem', () {
    test('toString is Description:/Action:', () {
      const problem = ProfileProblem(
        code: 'P99',
        description: 'something is wrong',
        action: 'fix it',
      );

      expect(
        problem.toString(),
        'Description:\nsomething is wrong\nAction:\nfix it',
      );
    });
  });

  group('AppRuntime', () {
    test('carries what a hook needs to know', () {
      final profile = mobileProfile();
      final runtime = AppRuntime(
        profile: profile,
        flavor: Flavor.dev,
        platform: AppPlatform.ios,
        isDebug: true,
      );

      expect(runtime.profile, same(profile));
      expect(runtime.flavor, Flavor.dev);
      expect(runtime.platform, AppPlatform.ios);
      expect(runtime.isDebug, isTrue);
    });
  });
}
