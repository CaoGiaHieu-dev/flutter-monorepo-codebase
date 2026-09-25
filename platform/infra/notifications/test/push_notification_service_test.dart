import 'package:core_notifications/core_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

// Never initialized: the blocked-type bookkeeping touches neither Firebase nor
// the local notifications plugin.
const _options = FirebaseOptions(
  apiKey: 'test',
  appId: 'test',
  messagingSenderId: 'test',
  projectId: 'test',
);

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
}
