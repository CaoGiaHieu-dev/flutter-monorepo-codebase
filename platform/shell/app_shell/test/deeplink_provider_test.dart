import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/profile_fakes.dart';

/// A deep link must never open a signed-in screen while an auth module says
/// nobody is signed in — and must still route in a build without auth.
void main() {
  _deepLinkSwitch();

  group('DeeplinkProvider.canRoute', () {
    test('routes when no auth module is composed', () {
      expect(DeeplinkProvider.canRoute(null), isTrue);
    });

    test('routes while someone is signed in', () {
      expect(
        DeeplinkProvider.canRoute(
          _Session(const SessionPrincipal(id: 'u1')),
        ),
        isTrue,
      );
    });

    test('drops links while signed out, e.g. after a sign-out', () {
      expect(DeeplinkProvider.canRoute(_Session(null)), isFalse);
    });
  });

  group('DeeplinkProvider.locationOf', () {
    test('a web link keeps its path and query', () {
      expect(
        DeeplinkProvider.locationOf(
          Uri.parse('https://example.com/settings?tab=2'),
        ),
        '/settings?tab=2',
      );
    });

    test('a custom-scheme link reads its first segment from the host', () {
      expect(
        DeeplinkProvider.locationOf(Uri.parse('myapp://settings/detail')),
        '/settings/detail',
      );
    });

    test('a bare web link goes to the root', () {
      expect(
        DeeplinkProvider.locationOf(Uri.parse('https://example.com')),
        '/',
      );
    });
  });
}

/// K10 — `platforms.<p>.deep_links` reaches `DeeplinkProvider.initAppLink`.
/// Left on (the default), it subscribes to the `app_links` stream as before;
/// off, it logs one INFO line naming the manifest key and subscribes to
/// nothing.
void _deepLinkSwitch() {
  group('DeeplinkProvider.initAppLink', () {
    var listens = 0;
    late List<({int level, String message})> logged;
    const info = 700;

    setUp(() async {
      listens = 0;
      logged = [];
      await getIt.reset();
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel('com.llfbandit.app_links/events'),
            MockStreamHandler.inline(
              onListen: (arguments, events) => listens++,
            ),
          );
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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel('com.llfbandit.app_links/events'),
            null,
          );
      DynamicLogger.reset();
      await getIt.reset();
    });

    const off = PlatformFacts(
      runner: RunnerKind.scaffold,
      splash: SplashMode.native,
      orientation: OrientationPolicy.free,
      deepLinks: false,
      push: false,
    );

    test('the default platform facts keep deep links on, as before', () async {
      final provider = DeeplinkProvider(AppRouter());

      provider.initAppLink();
      provider.initAppLink();
      await Future<void>.delayed(Duration.zero);

      expect(listens, 1, reason: 'subscribed once, idempotently');
      expect(
        logged.where((l) => l.message.contains('Deep links are off')),
        isEmpty,
      );
      provider.dispose();
    });

    test('off: one INFO line naming the key, nothing subscribed', () async {
      registerAppProfile(
        testProfile(platforms: {AppPlatform.android: off}),
        platform: AppPlatform.android,
        locator: getIt,
      );
      final provider = DeeplinkProvider(AppRouter(), off);

      provider.initAppLink();
      provider.initAppLink();
      await Future<void>.delayed(Duration.zero);

      expect(listens, 0, reason: 'the app_links stream is never listened to');
      final lines = logged.where((l) => l.level == info);
      expect(lines, hasLength(1), reason: 'logged once, however often called');
      expect(
        lines.single.message,
        allOf(
          contains('platforms.android.deep_links'),
          contains('apps/test_app/app_manifest.yaml'),
        ),
      );
      provider.dispose();
    });
  });
}

class _Session implements ISessionState {
  _Session(this.signedInUser);

  @override
  final SessionPrincipal? signedInUser;

  @override
  bool get hasRestoredSession => true;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Stream<SessionPrincipal?> get sessionChanges => const Stream.empty();

  @override
  Stream<SessionFailure> get sessionFailures => const Stream.empty();

  @override
  void onSessionLost() {}
}
