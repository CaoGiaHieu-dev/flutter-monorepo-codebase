import 'package:domain_core/domain_core.dart';
import 'package:test/test.dart';

/// `Result<T>` is the return type of every use case and repository. These
/// pin the helpers the Provider and BLoC layers unwrap it with.
void main() {
  const failure = ServerFailure<dynamic>(message: 'down', code: 503);

  group('variants', () {
    test('success carries its data', () {
      const r = Result<int>.success(7);
      expect(r, isA<Success<int>>());
      expect(r.isSuccess, isTrue);
      expect(r.isFailure, isFalse);
      expect(r.dataOrNull, 7);
      expect(r.errorOrNull, isNull);
    });

    test('success may carry no data', () {
      const r = Result<int>.success();
      expect(r.isSuccess, isTrue);
      expect(r.dataOrNull, isNull);
    });

    test('failure carries its AppFailure', () {
      const r = Result<int>.failure(failure);
      expect(r, isA<Failure<int>>());
      expect(r.isFailure, isTrue);
      expect(r.isSuccess, isFalse);
      expect(r.dataOrNull, isNull);
      expect(r.errorOrNull, failure);
    });

    test('none and cancel are neither success nor failure', () {
      for (final r in const [Result<int>.none(), Result<int>.cancel()]) {
        expect(r.isSuccess, isFalse);
        expect(r.isFailure, isFalse);
        expect(r.dataOrNull, isNull);
        expect(r.errorOrNull, isNull);
      }
    });
  });

  group('when', () {
    String describe(Result<int> r) => r.when(
      success: (data) => 'success:$data',
      failure: (error) => 'failure:${error.message}',
      none: () => 'none',
      cancel: () => 'cancel',
    );

    test('dispatches on every variant', () {
      expect(describe(const Result.success(1)), 'success:1');
      expect(describe(const Result.failure(failure)), 'failure:down');
      expect(describe(const Result.none()), 'none');
      expect(describe(const Result.cancel()), 'cancel');
    });

    test('whenAsync awaits the matching branch', () async {
      final out = await const Result<int>.success(2).whenAsync(
        success: (data) async => data! * 10,
        failure: (_) => -1,
        none: () => -2,
        cancel: () => -3,
      );
      expect(out, 20);
    });
  });

  group('mapData', () {
    test('transforms success data', () {
      final r = const Result<int>.success(3).mapData((d) => '${d! + 1}');
      expect(r, const Result<String>.success('4'));
    });

    test('passes a failure through untouched', () {
      var called = false;
      final r = const Result<int>.failure(failure).mapData((d) {
        called = true;
        return d;
      });
      expect(called, isFalse);
      expect(r.errorOrNull, failure);
    });

    test('keeps none and cancel', () {
      expect(const Result<int>.none().mapData((d) => d), isA<None<int?>>());
      expect(
        const Result<int>.cancel().mapData((d) => d),
        isA<Cancel<int?>>(),
      );
    });
  });

  group('flatMap', () {
    test('chains a second result on success', () async {
      final r = await const Result<int>.success(
        2,
      ).flatMap((d) async => Result<String>.success('x' * d!));
      expect(r.dataOrNull, 'xx');
    });

    test('short-circuits on failure', () async {
      final r = await const Result<int>.failure(
        failure,
      ).flatMap((d) async => const Result<String>.success('never'));
      expect(r.isFailure, isTrue);
      expect(r.errorOrNull, failure);
    });
  });

  group('getOrElse / getOrThrow', () {
    test('getOrElse falls back when there is no data', () {
      expect(const Result<int>.success(5).getOrElse(0), 5);
      expect(const Result<int>.success().getOrElse(9), 9);
      expect(const Result<int>.failure(failure).getOrElse(9), 9);
      expect(const Result<int>.none().getOrElse(9), 9);
    });

    test('getOrThrow returns data or throws the failure itself', () {
      expect(const Result<int>.success(5).getOrThrow(), 5);
      expect(
        () => const Result<int>.failure(failure).getOrThrow(),
        throwsA(failure),
      );
      expect(
        () => const Result<int>.cancel().getOrThrow(),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('results compare by value', () {
    expect(const Result<int>.success(1), const Result<int>.success(1));
    expect(const Result<int>.success(1), isNot(const Result<int>.success(2)));
    expect(
      const Result<int>.failure(failure),
      const Result<int>.failure(ServerFailure(message: 'down', code: 503)),
    );
  });
}
