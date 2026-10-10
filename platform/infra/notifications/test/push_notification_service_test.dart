import 'package:core_notifications/core_notifications.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

/// A platform with no Android / iOS implementation to ask: what the plugin
/// resolves to on the web or a desktop.
class _NoNotificationsPlatform extends FlutterLocalNotificationsPlatform {}

/// A service whose system prompt answers with [status] (or throws), and whose
/// token registration only counts — no Firebase app is needed.
class _PromptingService extends PushNotificationService {
  _PromptingService(
    this.status, {
    this.throws = false,
    this.localAllows = true,
    PlatformFacts? platform,
  }) : super(_options, platform ?? const PlatformFacts.today());

  final AuthorizationStatus status;
  final bool throws;
  final bool localAllows;
  int prompts = 0;
  int tokenRegistrations = 0;

  @override
  Future<AuthorizationStatus> requestSystemPermission() async {
    prompts++;
    if (throws) throw StateError('the prompt failed');
    return status;
  }

  @override
  Future<bool> requestLocalPermission() async => localAllows;

  @override
  Future<void> registerToken() async => tokenRegistrations++;
}

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

  group('requestPermission', () {
    test('reports true when the user allows notifications', () async {
      for (final status in [
        AuthorizationStatus.authorized,
        AuthorizationStatus.provisional,
      ]) {
        final service = _PromptingService(status);

        expect(await service.requestPermission(), isTrue, reason: '$status');
        expect(service.prompts, 1);
        await service.dispose();
      }
    });

    test('reports false when they refuse or have not decided', () async {
      for (final status in [
        AuthorizationStatus.denied,
        AuthorizationStatus.notDetermined,
      ]) {
        final service = _PromptingService(status);

        expect(await service.requestPermission(), isFalse, reason: '$status');
        await service.dispose();
      }
    });

    test('registers the token afterwards, granted or not', () async {
      final granted = _PromptingService(AuthorizationStatus.authorized);
      final denied = _PromptingService(AuthorizationStatus.denied);

      await granted.requestPermission();
      await denied.requestPermission();

      expect(granted.tokenRegistrations, 1);
      expect(denied.tokenRegistrations, 1);
      await granted.dispose();
      await denied.dispose();
    });

    test('a failing prompt is false, not an exception, and still registers '
        'the token', () async {
      final service = _PromptingService(
        AuthorizationStatus.authorized,
        throws: true,
      );

      expect(await service.requestPermission(), isFalse);
      expect(service.tokenRegistrations, 1);
      await service.dispose();
    });

    test('a refusal at the local plugin (Android 13, iOS) is false even if '
        'Firebase reports authorized', () async {
      final service = _PromptingService(
        AuthorizationStatus.authorized,
        localAllows: false,
      );

      expect(await service.requestPermission(), isFalse);
      await service.dispose();
    });

    test('the local plugin answers null off Android and iOS, which is not a '
        'refusal', () async {
      // Without a platform implementation (the web, a desktop) there is
      // nothing to ask: the base implementation must not throw
      // `UnsupportedError` as `Platform.isAndroid` does in a browser.
      FlutterLocalNotificationsPlatform.instance = _NoNotificationsPlatform();
      final service = PushNotificationService(_options);

      for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          expect(await service.requestLocalPermission(), isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
      await service.dispose();
    });

    test('with push off it asks nothing and reports false', () async {
      const off = PlatformFacts(
        runner: RunnerKind.scaffold,
        splash: SplashMode.native,
        orientation: OrientationPolicy.free,
        deepLinks: true,
        push: false,
      );
      final service = _PromptingService(
        AuthorizationStatus.authorized,
        platform: off,
      );

      expect(await service.requestPermission(), isFalse);
      expect(service.prompts, 0);
      await service.dispose();
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
              sslPinning: SslPinningPolicy({
                Flavor.dev: SslPinning.disabled('test: no pins'),
              }),
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
      expect(await service.requestPermission(), isFalse);
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
