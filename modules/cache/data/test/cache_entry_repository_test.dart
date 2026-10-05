import 'package:core_database/core_database.dart';
import 'package:data_cache/data_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// A data source whose every call fails, to prove the repository turns a
/// thrown error into a `Result.failure` instead of letting it reach the UI.
class _ThrowingDataSource implements ICacheEntryLocalDataSource {
  @override
  Future<CacheEntryModel?> getEntry(String key) async =>
      throw StateError('database is closed');

  @override
  Future<void> save(String key, String value) async =>
      throw StateError('database is closed');
}

void main() {
  test('a saved value comes back as a domain entity, a missing key as null',
      () async {
    final database = CacheDatabase.forTesting();
    addTearDown(database.close);
    final repository = CacheEntryRepositoryImpl(
      CacheEntryLocalDataSource(DatabaseHandle<CacheDatabase>(database)),
    );

    await repository.save('greeting', 'hello');
    await repository.save('greeting', 'world');

    final entry = (await repository.getByKey('greeting')).dataOrNull;
    expect(entry?.key, 'greeting');
    expect(entry?.value, 'world');
    final missing = await repository.getByKey('absent');
    expect(missing.isSuccess, isTrue);
    expect(missing.dataOrNull, isNull);
  });

  test('a throwing data source becomes a failure, never an exception', () async {
    final repository = CacheEntryRepositoryImpl(_ThrowingDataSource());

    expect((await repository.getByKey('k')).isFailure, isTrue);
    expect((await repository.save('k', 'v')).isFailure, isTrue);
  });
}
