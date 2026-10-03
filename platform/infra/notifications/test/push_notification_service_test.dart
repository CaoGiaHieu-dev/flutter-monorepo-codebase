import 'package:core_notifications/core_notifications.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_kernel/platform_kernel.dart';

// Never initialized: the blocked-type bookkeeping touches neither Firebase nor
// the local notifications plugin.
const _options = FirebaseOptions(
  apiKey: 'test',
  appId: 'test',
  messagingSenderId: 'test',
  projectId: 'test',
);

/// `DynamicLogger`'s level number for `LogLevel.INFO`.
const _info = 700;

void main() {
  group('PushNotificationService blocked types', () {
    late PushNotificationService service;

    setUp(() => service = PushNotificationService(_options));
    tearDown(() async => service.dispose());

    test('blocking is case-insensitive on both sides', () {
      service.addBlockedTypes(['Promo']);

      expect(service.isTypeBlocked('promo'), isTrue);
      expect(service.isTypeBlocked('PROMO'), isTrue);
      expect(service.isTypeBlocked('Promo'), isTrue);
      expect(service.isTypeBlocked('chat'), isFalse);
      expect(service.isTypeBlocked(null), isFalse);
    });

    test('removing a type unblocks it whatever its case', () {
      service.addBlockedTypes(['promo']);
      service.removeBlockedTypes(['PROMO']);

      expect(service.isTypeBlocked('promo'), isFalse);
    });
  });

  test('dispose closes the streams and can run before init', () async {
    final service = PushNotificationService(_options);
    final done = service.tokenStream.drain<void>();

    await service.dispose();

    await expectLater(done, completes);
  });

  group('platforms.<p>.push', () {
    late List<({int level, String message})> logged;

    setUp(() async {
      await getIt.reset();
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
    });

    tearDown(() async {
      DynamicLogger.reset();
      await getIt.reset();
    });

    const off = PlatformFacts(
      runner: RunnerKind.scaffold,
      splash: SplashMode.native,
      orientation: OrientationPolicy.free,
      deepLinks: true,
      push: false,
    );

    test('the default platform facts keep push on, as before', () {
      expect(const PlatformFacts.today().push, isTrue);
    });

    test(
      'off: init logs one INFO line naming the key and initialises nothing',
      () async {
        registerAppProfile(
          const AppProfile(
            facts: AppFacts(
              id: 'admin',
              name: 'Admin',
              flavors: {Flavor.dev},
              platforms: {AppPlatform.windows: off},
              sslPinning: SslPinningPolicy.none(),
            ),
          ),
          platform: AppPlatform.windows,
        );
        final service = PushNotificationService(_options, off);

        // With push on this would reach `Firebase.initializeApp` and fail in a
        // test; off, it returns before touching Firebase at all.
        await service.init();

        final infos = logged.where((l) => l.level == _info);
        expect(infos, hasLength(1));
        expect(
          infos.single.message,
          allOf(
            contains('platforms.windows.push'),
            contains('apps/admin/app_manifest.yaml'),
          ),
        );
        await service.dispose();
      },
    );

    test('off: every other call does nothing and never throws', () async {
      final service = PushNotificationService(_options, off);

      await service.registerToken();
      await service.requestPermission();
      await service.subscribeToTopic('news');
      await service.unsubscribeFromTopic('news');
      await service.revokeToken();

      expect(service.fcmToken, isNull);
      expect(logged, isEmpty);
      await service.dispose();
    });

    test('on: init does not take the off path', () async {
      final service = PushNotificationService(_options);

      // The first thing the real init does is Firebase.initializeApp, which
      // has no platform channel in a unit test; reaching it proves the off
      // path was not taken.
      await expectLater(service.init(), throwsA(anything));
      expect(
        logged.where((l) => l.message.contains('Push notifications are off')),
        isEmpty,
      );
      await service.dispose();
    });
  });
}
