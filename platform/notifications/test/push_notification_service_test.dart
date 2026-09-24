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
    tearDown(() => service.dispose());

    test('blocking is case-insensitive on both sides', () async {
      await service.addBlockedTypes(['Promo']);

      expect(service.isTypeBlocked('promo'), isTrue);
      expect(service.isTypeBlocked('PROMO'), isTrue);
      expect(service.isTypeBlocked('Promo'), isTrue);
      expect(service.isTypeBlocked('chat'), isFalse);
      expect(service.isTypeBlocked(null), isFalse);
    });

    test('removing a type unblocks it whatever its case', () async {
      await service.addBlockedTypes(['promo']);
      await service.removeBlockedTypes(['PROMO']);

      expect(service.isTypeBlocked('promo'), isFalse);
    });
  });
}
