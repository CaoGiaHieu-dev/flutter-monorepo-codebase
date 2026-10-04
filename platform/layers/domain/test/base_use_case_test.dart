import 'dart:async';

import 'package:domain_core/domain_core.dart';
import 'package:test/test.dart';

class _Double extends BaseUseCase<int, int> {
  @override
  Result<int> call(int params) => Result.success(params * 2);
}

class _FetchName extends BaseUseCase<String, String> {
  @override
  Future<Result<String>> call(String params) async => params.isEmpty
      ? const Result.failure(ValidationFailure(message: 'empty', code: 1))
      : Result.success('name:$params');
}

/// A use case is a callable object returning a `Result`, synchronously or
/// not; the abstract `call` is the whole contract.
void main() {
  test('a synchronous use case answers with a Result directly', () {
    final result = _Double()(21);

    expect(result, isA<Result<int>>());
    expect(result.dataOrNull, 42);
  });

  test('an asynchronous use case is awaited into a Result', () async {
    final result = await _FetchName()('ada');

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull, 'name:ada');
  });

  test('a failure travels as a value, not as an exception', () async {
    final result = await _FetchName()('');

    expect(result.isFailure, isTrue);
    expect(result.errorOrNull, isA<ValidationFailure<dynamic>>());
    expect(result.errorOrNull!.code, 1);
  });

  test('FutureOr lets a caller treat both the same way', () async {
    final FutureOr<Result<int>> sync = _Double().call(1);
    final FutureOr<Result<String>> async = _FetchName().call('x');

    expect((await sync).dataOrNull, 2);
    expect((await async).dataOrNull, 'name:x');
  });
}
