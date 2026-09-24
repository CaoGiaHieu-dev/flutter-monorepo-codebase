import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

/// A deep link must never open a signed-in screen while an auth module says
/// nobody is signed in — and must still route in a build without auth.
void main() {
  group('DeeplinkProvider.canRoute', () {
    test('routes when no auth module is composed', () {
      expect(DeeplinkProvider.canRoute(null), isTrue);
    });

    test('routes while someone is signed in', () {
      expect(
        DeeplinkProvider.canRoute(
          _Session(const AuthPrincipal(id: 'u1')),
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

class _Session implements IAuthSessionState {
  _Session(this.signedInUser);

  @override
  final AuthPrincipal? signedInUser;

  @override
  bool get hasRestoredSession => true;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Stream<AuthPrincipal?> get sessionChanges => const Stream.empty();

  @override
  Stream<AuthSessionFailure> get sessionFailures => const Stream.empty();

  @override
  void onSessionLost() {}
}
