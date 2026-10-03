import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('SslPinning', () {
    test('pinned keeps its hashes, leaf first', () {
      const pinning = SslPinning.pinned('leaf', 'backup');

      expect(pinning, isA<PinnedSsl>());
      expect((pinning as PinnedSsl).hashes, ['leaf', 'backup']);
    });

    test('pinned accepts further hashes after the backup', () {
      const pinning = SslPinning.pinned('leaf', 'backup', ['intermediate']);

      expect((pinning as PinnedSsl).hashes, ['leaf', 'backup', 'intermediate']);
    });

    test('disabled keeps its reason', () {
      const pinning = SslPinning.disabled('no pins provisioned yet');

      expect(pinning, isA<DisabledSsl>());
      expect((pinning as DisabledSsl).reason, 'no pins provisioned yet');
    });

    // Two pins are a property of the signature — `SslPinning.pinned('only')`
    // does not compile. What an assert can still refuse is an empty or
    // repeated pin; a bad `const` is a compile error, a bad run-time
    // construction goes through the same assert.
    test('an empty pin is refused', () {
      final empty = ''.toString();

      expect(() => PinnedSsl(empty, 'backup'), throwsA(isA<AssertionError>()));
      expect(() => PinnedSsl('leaf', empty), throwsA(isA<AssertionError>()));
      expect(
        () => SslPinning.pinned(empty, empty),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a backup equal to the leaf is refused', () {
      final same = 'same'.toString();

      expect(() => PinnedSsl(same, same), throwsA(isA<AssertionError>()));
    });

    test('disabled with an empty reason is refused', () {
      final empty = ''.toString();

      expect(() => DisabledSsl(empty), throwsA(isA<AssertionError>()));
      expect(
        () => SslPinning.disabled(empty),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a switch over the decision is exhaustive', () {
      String describe(SslPinning pinning) => switch (pinning) {
        PinnedSsl(:final hashes) => 'pinned ${hashes.length}',
        DisabledSsl(:final reason) => 'disabled: $reason',
      };

      expect(describe(const SslPinning.pinned('a', 'b')), 'pinned 2');
      expect(describe(const SslPinning.disabled('why')), 'disabled: why');
    });
  });

  group('SslPinningPolicy', () {
    const policy = SslPinningPolicy({
      Flavor.dev: SslPinning.disabled('development flavor'),
      Flavor.prod: SslPinning.pinned('leaf', 'backup'),
    });

    test('decisionFor returns the declared decision, null otherwise', () {
      expect(policy.decisionFor(Flavor.dev), isA<DisabledSsl>());
      expect(policy.decisionFor(Flavor.prod), isA<PinnedSsl>());
      expect(policy.decisionFor(Flavor.staging), isNull);
    });

    test('hashesFor is the pins only when the flavor pins', () {
      expect(policy.hashesFor(Flavor.prod), ['leaf', 'backup']);
      expect(policy.hashesFor(Flavor.dev), isEmpty);
      expect(policy.hashesFor(Flavor.staging), isEmpty);
    });

    test('none decides nothing and pins nothing', () {
      const none = SslPinningPolicy.none();

      for (final flavor in Flavor.values) {
        expect(none.decisionFor(flavor), isNull);
        expect(none.hashesFor(flavor), isEmpty);
      }
    });
  });

  group('CapabilityExpectation', () {
    test('provided and absent are the two states', () {
      const provided = CapabilityExpectation.provided();
      const absent = CapabilityExpectation.absent('no crash backend chosen');

      expect(provided, isA<ProvidedCapability>());
      expect((absent as AbsentCapability).reason, 'no crash backend chosen');
    });

    test('absent with an empty reason is refused', () {
      final empty = ''.toString();

      expect(
        () => AbsentCapability(empty),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
