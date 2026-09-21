import 'package:data_core/data_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the wire contract between [ExtraRequest] and `core_network`'s
/// interceptors.
///
/// `data_core` does not depend on `core_network`, so these key strings are the
/// only thing linking the two packages. Without this test, renaming a field
/// would silently stop `AuthInterceptor` / `RetryInterceptor` from seeing the
/// flag — the request would still succeed, just with the opt-out ignored.
///
/// If this test fails, do not "fix" it by editing the expected strings: check
/// `NetworkConstants.EXTRA_NEED_AUTHENTICATION` / `EXTRA_CAN_RETRY` first and
/// keep both sides equal.
void main() {
  group('ExtraRequest wire contract', () {
    test('toExtra uses the exact keys the interceptors read', () {
      final extra = const ExtraRequest().toExtra();

      expect(extra.keys.toSet(), equals({'needAuthentication', 'canRetry'}));
    });

    test('defaults to opting in to both auth and retry', () {
      final extra = const ExtraRequest().toExtra();

      expect(extra['needAuthentication'], isTrue);
      expect(extra['canRetry'], isTrue);
    });

    test('carries an explicit opt-out through to the map', () {
      final extra = const ExtraRequest(
        needAuthentication: false,
        canRetry: false,
      ).toExtra();

      expect(extra['needAuthentication'], isFalse);
      expect(extra['canRetry'], isFalse);
    });

    test('round-trips through json', () {
      const original = ExtraRequest(needAuthentication: false);

      expect(ExtraRequest.fromJson(original.toJson()), equals(original));
    });
  });
}
