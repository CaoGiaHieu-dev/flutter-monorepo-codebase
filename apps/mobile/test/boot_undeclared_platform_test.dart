import 'package:core_common/core_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app_hooks.dart';
import 'package:mobile_app/app/app_profile.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

/// Booting this app on a platform its manifest does not declare used to be a
/// permanently blank window with no error (Linux: `Firebase.initializeApp`
/// never returns). Now the boot stops before dependency injection and says
/// what to do — and `ALLOW_UNDECLARED_PLATFORM` is the one way past it.
void main() {
  tearDown(() async {
    debugAppPlatformOverride = null;
    await getIt.reset();
  });

  testWidgets('stops before DI on linux with the manifest-key message', (
    tester,
  ) async {
    debugAppPlatformOverride = AppPlatform.linux;
    var diCalls = 0;

    runShellApp(
      profile: appProfile,
      hooks: appHooks,
      configureDependencies: () async => diCalls++,
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 200; i++) {
        if (find.byType(BootErrorApp).evaluate().isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pump();

    expect(find.byType(BootErrorApp), findsOneWidget);
    expect(diCalls, 0, reason: 'configureDependencies must not run');
    expect(
      find.textContaining(
        '`mobile` is running on linux, which its manifest does not declare '
        '(declared: android, ios)',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('apps/mobile/app_manifest.yaml'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'dart tools/composer/composer.dart sync --app mobile',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('ALLOW_UNDECLARED_PLATFORM=true'),
      findsOneWidget,
    );
    expect(getIt.isRegistered<AppProfile>(), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('ALLOW_UNDECLARED_PLATFORM lets the profile register, as the template '
      'behaved before apps declared platforms', () {
    expect(
      () => registerAppProfile(appProfile, platform: AppPlatform.linux),
      throwsStateError,
    );

    registerAppProfile(
      appProfile,
      platform: AppPlatform.linux,
      allowUndeclaredPlatform: true,
    );

    final facts = getIt<PlatformFacts>();
    expect(facts.splash, SplashMode.dart);
    expect(facts.push, isTrue);
    expect(facts.deepLinks, isTrue);
  });
}
